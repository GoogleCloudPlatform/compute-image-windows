//  Copyright 2019 Google Inc. All Rights Reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.

package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"syscall"
	"time"

	"cloud.google.com/go/logging"
	"github.com/GoogleCloudPlatform/guest-logging-go/logger"
	"github.com/hashicorp/golang-lru"
	pb "github.com/maxnelso/compute-image-windows/GCEWindowsAgent/protos"
	"google.golang.org/grpc"
)

const testPreSnapshotScript = "preSnapshotScript.sh"
const testPostSnapshotScript = "postSnapshotScript.sh"
const testIp = "169.254.0.1"
const prodAddress = "169.254.169.254:8081"

var (
	seenPreSnapshotoperationIds, _  = lru.New(128)
	seenPostSnapshotoperationIds, _ = lru.New(128)
)

type SnapshotConfig struct {
	Timeout               int // seconds
	ContinueOnScriptError bool
	PreSnapshotScriptUrl  string
	PostSnapshotScriptUrl string
	Enabled               bool
}

type scriptsTimeoutError struct {
	path string
}

func (e *scriptsTimeoutError) Error() string {
	return fmt.Sprintf("script timed out at: %s", e.path)
}

type invalidSnapshotConfig struct {
	msg string
}

func (e *invalidSnapshotConfig) Error() string {
	return fmt.Sprintf("invalid config: %s", e.msg)
}

func getSnapshotConfig() (SnapshotConfig, error) {
	setConfig()
	var snapshotConfig SnapshotConfig
	snapshotConfig.Timeout = config.Section("Snapshots").Key("timeout_in_seconds").MustInt(60)
	snapshotConfig.ContinueOnScriptError = config.Section("Snapshots").Key("continue_on_script_error").MustBool(false)
	snapshotConfig.PreSnapshotScriptUrl = config.Section("Snapshots").Key("pre_snapshot_script").MustString("")
	snapshotConfig.PostSnapshotScriptUrl = config.Section("Snapshots").Key("post_snapshot_script").MustString("")

	if snapshotConfig.PreSnapshotScriptUrl == "" && snapshotConfig.PostSnapshotScriptUrl == "" {
		msg := "neither pre or post snapshot script has been configured"
		logToStackdriver(msg, logging.Warning)
		return snapshotConfig, &invalidSnapshotConfig{msg}
	}

	return snapshotConfig, nil
}

func runScript(path string, disks string, timeout int) (int, error) {
	logger.Infof("running script at: %s", path)
	cmd := exec.Command(path, disks)
	err := cmd.Start()
	if err != nil {
		logger.Errorf("failed to start script at %s: %v", path, err)
		return 0, err
	}

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	// Start timer
	timer := time.After(time.Second * time.Duration(timeout))

	select {
	case <-timer:
		logToStackdriver(fmt.Sprintf("timeout while running script at %s", path), logging.Error)
		// Exit code of the timeout command when it times out
		return 124, &scriptsTimeoutError{path}
	case err := <-done:
		if err != nil {
			exiterr := err.(*exec.ExitError)
			status := exiterr.Sys().(syscall.WaitStatus)
			logToStackdriver(fmt.Sprintf("error while running script at %s, return with exit code %d", path, status.ExitStatus()), logging.Error)
			return status.ExitStatus(), nil
		}
	}
	return 0, nil
}

func handleRequest(config SnapshotConfig, path string, disks string) (pb.AgentErrorCode, int) {
	ec, err := runScript(path, disks, config.Timeout)
	if os.IsNotExist(err) {
		logger.Infof("script not found at %s: ", path)
		logToStackdriver(fmt.Sprintf("script not found at %s: ", path), logging.Error)
		return pb.AgentErrorCode_SCRIPT_NOT_FOUND, 0
	}

	if _, ok := err.(*scriptsTimeoutError); ok {
		logger.Infof("script at: %s timed out", path)
		return pb.AgentErrorCode_SCRIPT_TIMED_OUT, ec
	}

	if !config.ContinueOnScriptError && ec != 0 {
		logger.Infof("script at: %s failed with error code %d", path, ec)
		return pb.AgentErrorCode_UNHANDLED_SCRIPT_ERROR, ec
	}

	return pb.AgentErrorCode_NO_ERROR, ec
}

func listenForSnapshotRequests(address string, requestChan chan *pb.GuestMessage) {
	for {
		// Start hanging connection on server that feeds to channel
		logger.Infof("attempting to connect to snapshot service at %s", address)
		conn, err := grpc.Dial(address, grpc.WithInsecure())
		if err != nil {
			logger.Errorf("failed to connect: %v", err)
			continue
		}

		c := pb.NewSnapshotServiceClient(conn)
		ctx, cancel := context.WithCancel(context.Background())
		guestReady := pb.GuestReady{
			RequestServerInfo: false,
		}
		r, err := c.CreateConnection(ctx, &guestReady)
		if err != nil {
			logger.Errorf("error creating connection: %v", err)
			continue
		}
		logger.Infof("created hanging connection with snapshot service")
		for {
			request, err := r.Recv()
			if err != nil {
				logger.Errorf("error reading request: %v", err)
				break
			}
			logger.Infof("received snapshot request")
			requestChan <- request
		}
		cancel()
	}
}

func getSnapshotResponse(guestMessage *pb.GuestMessage) *pb.SnapshotResponse {
	switch request := guestMessage.Msg.(type) {
	case *pb.GuestMessage_SnapshotRequest:
		response := &pb.SnapshotResponse{
			OperationId: request.SnapshotRequest.GetOperationId(),
			Type:        request.SnapshotRequest.GetType(),
		}

		config, err := getSnapshotConfig()
		if err != nil {
			response.AgentReturnCode = pb.AgentErrorCode_INVALID_CONFIG
			return response

		}

		var url string
		switch request.SnapshotRequest.GetType() {
		case pb.OperationType_PRE_SNAPSHOT:
			logger.Infof("handling pre snapshot request")
			if seenPreSnapshotoperationIds.Contains(request.SnapshotRequest.GetOperationId()) {
				logger.Infof("duplicate pre snapshot request operation id %d", request.SnapshotRequest.GetOperationId())
				return nil
			}
			seenPreSnapshotoperationIds.Add(request.SnapshotRequest.GetOperationId(), nil)
			url = config.PreSnapshotScriptUrl
		case pb.OperationType_POST_SNAPSHOT:
			logger.Infof("handling post snapshot request")
			if seenPostSnapshotoperationIds.Contains(request.SnapshotRequest.GetOperationId()) {
				logger.Infof("duplicate post snapshot request operation id %d", request.SnapshotRequest.GetOperationId())
				return nil
			}
			seenPostSnapshotoperationIds.Add(request.SnapshotRequest.GetOperationId(), nil)
			url = config.PostSnapshotScriptUrl
		default:
			logger.Errorf("unhandled operation type %d", request.SnapshotRequest.GetType())
			return nil
		}

		agentErrorCode, scriptsReturnCode := handleRequest(config, url, request.SnapshotRequest.GetDiskList())
		response.ScriptsReturnCode = int32(scriptsReturnCode)
		response.AgentReturnCode = agentErrorCode

		return response
	case *pb.GuestMessage_ServerInfo:
	}
	return nil
}

func handleSnapshotRequests(address string, requestChan chan *pb.GuestMessage) {
	for {
		conn, err := grpc.Dial(address, grpc.WithInsecure(), grpc.WithBlock())
		if err != nil {
			logger.Errorf("failed to connect: %v", err)
			continue
		}
		for {
			// Listen on channel and respond
			guestMessage := <-requestChan
			response := getSnapshotResponse(guestMessage)
			for {
				c := pb.NewSnapshotServiceClient(conn)
				ctx, cancel := context.WithCancel(context.Background())
				_, err = c.HandleResponsesFromGuest(ctx, response)
				if err == nil {
					cancel()
					break
				}
				logger.Errorf("error sending response: %v", err)
			}
		}
	}

}

func startSnapshotListener(testMode bool, testSnapshotPort int) {
	requestChan := make(chan *pb.GuestMessage)
	var address string
	if testMode {
		address = testIp + ":" + strconv.Itoa(testSnapshotPort)
	} else {
		address = prodAddress
	}
	go listenForSnapshotRequests(address, requestChan)
	go handleSnapshotRequests(address, requestChan)
}
