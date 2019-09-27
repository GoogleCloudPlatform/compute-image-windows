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
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"syscall"
	"time"

	"cloud.google.com/go/logging"
	"github.com/GoogleCloudPlatform/compute-image-windows/serialprotocol"
	"github.com/GoogleCloudPlatform/guest-logging-go/logger"
	"github.com/hashicorp/golang-lru"
	"github.com/tarm/serial"
)

const identifier = "329d1643-127b-4096-84a6-ac19f597e51c"
const testPreSnapshotScript = "preSnapshotScript.sh"
const testPostSnapshotScript = "postSnapshotScript.sh"
const serialPort = "/dev/ttyS3"
const serialProtocolVersion = 1

var (
	seenPreSnapshotoperationIds, _  = lru.New(128)
	seenPostSnapshotoperationIds, _ = lru.New(128)
	currentMsg                      []byte
)

func clearCurrentMsg() {
	currentMsg = nil
}

func parseMessage() serialprotocol.SerialRequest {
	defer clearCurrentMsg()
	msg := serialprotocol.SerialRequest{}
	err := json.Unmarshal(currentMsg, &msg)
	if err != nil {
		logger.Errorf(err.Error())
	}
	return msg
}

func handlePrepareForSnapshotRequest(req serialprotocol.SerialRequest) {
	if seenPreSnapshotoperationIds.Contains(req.OperationId) {
		logger.Infof("ignoring pre-snapshot request with operation id %d", req.OperationId)
		return
	}

	seenPreSnapshotoperationIds.Add(req.OperationId, nil)

	config := getSnapshotConfig()
	if _, err := os.Stat(config.PreSnapshotScript); os.IsNotExist(err) {
		logToStackdriver(fmt.Sprintf("pre-snapshot script not found at: %s", config.PreSnapshotScript), logging.Error)
		return
	}
	logger.Infof("running pre-snapshot script")
	code := runScript(config.PreSnapshotScript, req.Disks, config.Timeout)
	res := serialprotocol.SerialResponse{Identifier: identifier, Signature: "PRERESP", Version: req.Version, Rc: code, OperationId: req.OperationId}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Errorf(err.Error())
	}
	writeSerial(serialPort, out)
}

func handleResumePostSnapshotRequest(req serialprotocol.SerialRequest) {
	if seenPostSnapshotoperationIds.Contains(req.OperationId) {
		logger.Infof("ignoring post-snapshot request with operation id %d", req.OperationId)
		return
	}
	seenPostSnapshotoperationIds.Add(req.OperationId, nil)

	config := getSnapshotConfig()
	if _, err := os.Stat(config.PostSnapshotScript); os.IsNotExist(err) {
		logToStackdriver(fmt.Sprintf("post-snapshot script not found at: %s", config.PostSnapshotScript), logging.Error)
		return
	}
	logger.Infof("running post-snapshot script")
	code := runScript(config.PostSnapshotScript, req.Disks, config.Timeout)
	res := serialprotocol.SerialResponse{Identifier: identifier, Signature: "POSTRESP", Version: req.Version, Rc: code, OperationId: req.OperationId}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Errorf(err.Error())
	}
	writeSerial(serialPort, out)
}

func handleMessage(msg serialprotocol.SerialRequest) {
	switch sig := msg.Signature; sig {
	case "PREREQ":
		handlePrepareForSnapshotRequest(msg)
	case "POSTREQ":
		handleResumePostSnapshotRequest(msg)
	default:
		logger.Errorf("unknown message signature %s", msg.Signature)
	}
}

func handleSerialData(serialData []byte) {
	for _, c := range serialData {
		if c == '\n' {
			// Should be the end of the message
			msg := parseMessage()
			switch sig := msg.Signature; sig {
			case "PREREQ":
				handlePrepareForSnapshotRequest(msg)
			case "POSTREQ":
				handleResumePostSnapshotRequest(msg)
			default:
				logger.Errorf("unknown message signature %s", msg.Signature)
			}
		} else if c != '\x00' {
			currentMsg = append(currentMsg, c)
		}
	}
}

func getSnapshotConfig() serialprotocol.SnapshotConfig {
	setConfig()
	var snapshotConfig serialprotocol.SnapshotConfig
	snapshotConfig.Timeout = config.Section("Snapshots").Key("timeout_in_seconds").MustInt(60)
	snapshotConfig.ContinueOnScriptError = config.Section("Snapshots").Key("continue_on_script_error").MustBool(false)
	snapshotConfig.PreSnapshotScript = config.Section("Snapshots").Key("pre_snapshot_script").MustString("")
	snapshotConfig.PostSnapshotScript = config.Section("Snapshots").Key("post_snapshot_script").MustString("")

	if snapshotConfig.PreSnapshotScript == "" && snapshotConfig.PostSnapshotScript == "" {
		logToStackdriver("neither pre or post snapshot script has been configured", logging.Warning)
	}
	return snapshotConfig
}

func runScript(path string, disks string, timeout int) int {
	cmd := exec.Command(path, disks)
	err := cmd.Start()
	if err != nil {
		logger.Errorf("failed to start script at %s: %v", path, err)
	}

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	// Start timer
	timer := time.After(time.Second * time.Duration(timeout))

	select {
	case <-timer:
		logToStackdriver(fmt.Sprintf("timeout while running script at %s", path), logging.Error)
		// Exit code of the timeout command when it times out
		return 124
	case err := <-done:
		if err != nil {
			exiterr := err.(*exec.ExitError)
			status := exiterr.Sys().(syscall.WaitStatus)
			logToStackdriver(fmt.Sprintf("error while running script at %s, return with exit code %d", path, status.ExitStatus()), logging.Error)
			return status.ExitStatus()
		}
	}
	return 0
}

func listenOnSerialPort() {
	ready, err := json.Marshal(serialprotocol.AgentReady{Identifier: identifier, Signature: "READY", Version: serialProtocolVersion})
	if err != nil {
		logger.Errorf(err.Error())
	}
	writeSerial(serialPort, ready)

	serialChan := make(chan []byte)
	go func() {
		c := &serial.Config{Name: serialPort, Baud: 115200}
		s, err := serial.OpenPort(c)
		if err != nil {
			logger.Errorf("error opening serial port %s", serialPort)
		}

		defer closer(s)

		for {
			buf := make([]byte, 128)
			_, err = s.Read(buf)
			if err != nil {
				logger.Errorf("error reading from serial port %s", serialPort)
			}
			serialChan <- buf
		}
	}()
	go func() {
		for {
			serialData := <-serialChan
			handleSerialData(serialData)
		}
	}()
}

func sendAgentShuttingDownMessage() {
	logger.Infof("shutting down, sending shutdown message on serial port")
	shutdown, err := json.Marshal(serialprotocol.AgentShutdown{Identifier: identifier, Signature: "SHUTDOWN", Version: serialProtocolVersion})
	if err != nil {
		logger.Errorf(err.Error())
	}
	writeSerial(serialPort, shutdown)
}
