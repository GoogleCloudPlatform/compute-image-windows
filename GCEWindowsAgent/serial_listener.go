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
	"io/ioutil"
	"os/exec"
	"path"
	"syscall"
	"time"

	"github.com/GoogleCloudPlatform/guest-logging-go/logger"
)

type serialMessage interface{}

// Must match json format
type prepareForSnapshotRequest struct {
	Signature    string
	Version      int
	Operation_id int
}

type prepareForSnapshotResponse struct {
	Signature    string
	Version      int
	Rc           int
	Operation_id int
}

type resumePostSnapshotRequest struct {
	Signature    string
	Version      int
	Operation_id int
}

type resumePostSnapshotResponse struct {
	Signature    string
	Version      int
	Rc           int
	Operation_id int
}

const preSnapshotDir = "/etc/google.d/disks/pre-snapshot/"
const postSnapshotDir = "/etc/google.d/disks/post-snapshot/"

// TODO I don't know what this should be
const scriptTimeout = time.Second * 60

// TODO I don't know what this should be
const serialPort = "5"

var (
	currentMsg []byte
)

func clearCurrentMsg() {
	currentMsg = nil
}

func parseMessage() serialMessage {
	defer clearCurrentMsg()
	var msgJson map[string]interface{}
	err := json.Unmarshal(currentMsg, &msgJson)
	if err != nil {
		logger.Fatalf(err.Error())
	}
	sig, ok := msgJson["signature"]
	if !ok {
		logger.Errorf("message does not have signature")
	}

	switch sig {
	case "PREREQ":
		msg := prepareForSnapshotRequest{}
		err := json.Unmarshal(currentMsg, &msg)
		if err != nil {
			logger.Fatalf(err.Error())
		}
		return msg
	case "POSTREQ":
		msg := resumePostSnapshotRequest{}
		err := json.Unmarshal(currentMsg, &msg)
		if err != nil {
			logger.Fatalf(err.Error())
		}
		return msg
	default:
		logger.Errorf("unable to parse signature %s", sig)
		return nil
	}
}

func runScripts(dir string) int {
	files, err := ioutil.ReadDir(dir)
	if err != nil {
		logger.Errorf("unable to read directory %s", dir)
	}
	for _, f := range files {
		fullpath := path.Join(dir, f.Name())
		logger.Infof("running script at %s", fullpath)
		cmd := exec.Command(fullpath)

		cmd.Start()

		done := make(chan error)
		go func() { done <- cmd.Wait() }()

		// Start timer
		timeout := time.After(scriptTimeout)

		select {
		case <-timeout:
			logger.Warningf("timeout while running %s", fullpath)
			// Exit code of the timeout command when it times out
			return 124
		case err := <-done:
			if err != nil {
				exiterr := err.(*exec.ExitError)
				status := exiterr.Sys().(syscall.WaitStatus)
				logger.Warningf("script at %s return with exit code %d", fullpath, status.ExitStatus())
				return status.ExitStatus()
			}
		}
	}
	return 0
}

func handlePrepareForSnapshotRequest(req prepareForSnapshotRequest) {
	code := runScripts(preSnapshotDir)
	res := prepareForSnapshotResponse{"PRERESP", req.Version, code, req.Operation_id}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Fatalf(err.Error())
	}
	writeSerial(serialPort, out)
}

func handleResumePostSnapshotRequest(req resumePostSnapshotRequest) {
	code := runScripts(postSnapshotDir)
	res := prepareForSnapshotResponse{"POSTRESP", req.Version, code, req.Operation_id}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Fatalf(err.Error())
	}
	writeSerial(serialPort, out)
}

func handleMessage(msg serialMessage) {
	switch v := msg.(type) {
	case prepareForSnapshotRequest:
		handlePrepareForSnapshotRequest(v)
	case resumePostSnapshotRequest:
		handleResumePostSnapshotRequest(v)
	default:
		logger.Fatalf("unknown message type")
	}
}

func parseSerialData(serialData []byte) serialMessage {
	for _, c := range serialData {
		if c == '\n' {
			// Should be the end of the msg
			return parseMessage()
		} else {
			currentMsg = append(currentMsg, c)
		}
	}
	return nil
}

func listenOnSerialPort() error {
	for {
		serialData, err := readSerial(serialPort)
		if err != nil {
			logger.Fatalf(err.Error())
		}
		msg := parseSerialData(serialData)
		if msg != nil {
			handleMessage(msg)
		}
	}
}
