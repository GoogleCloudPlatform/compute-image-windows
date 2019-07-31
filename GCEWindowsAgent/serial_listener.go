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
	"encoding/json"
	"fmt"
	"io"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"regexp"
	"syscall"
	"time"

	"cloud.google.com/go/storage"
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

	storageURL = "storage.googleapis.com"

	bucket = `([a-z0-9][-_.a-z0-9]*)`
	object = `(.+)`
	// Many of the Google Storage URLs are supported below.
	// It is preferred that customers specify their object using
	// its gs://<bucket>/<object> URL.
	bucketRegex = regexp.MustCompile(fmt.Sprintf(`^gs://%s/?$`, bucket))
	gsRegex     = regexp.MustCompile(fmt.Sprintf(`^gs://%s/%s$`, bucket, object))
	// Check for the Google Storage URLs:
	// http://<bucket>.storage.googleapis.com/<object>
	// https://<bucket>.storage.googleapis.com/<object>
	gsHTTPRegex1 = regexp.MustCompile(fmt.Sprintf(`^http[s]?://%s\.storage\.googleapis\.com/%s$`, bucket, object))
	// http://storage.cloud.google.com/<bucket>/<object>
	// https://storage.cloud.google.com/<bucket>/<object>
	gsHTTPRegex2 = regexp.MustCompile(fmt.Sprintf(`^http[s]?://storage\.cloud\.google\.com/%s/%s$`, bucket, object))
	// Check for the other possible Google Storage URLs:
	// http://storage.googleapis.com/<bucket>/<object>
	// https://storage.googleapis.com/<bucket>/<object>
	//
	// The following are deprecated but checked:
	// http://commondatastorage.googleapis.com/<bucket>/<object>
	// https://commondatastorage.googleapis.com/<bucket>/<object>
	gsHTTPRegex3 = regexp.MustCompile(fmt.Sprintf(`^http[s]?://(?:commondata)?storage\.googleapis\.com/%s/%s$`, bucket, object))
)

func clearCurrentMsg() {
	currentMsg = nil
}

func parseMessage() serialprotocol.SerialRequest {
	defer clearCurrentMsg()
	msg := serialprotocol.SerialRequest{}
	err := json.Unmarshal(currentMsg, &msg)
	if err != nil {
		logger.Fatalf(err.Error())
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
	if !config.Enabled {
		logger.Infof("snapshot handling disabled, not running pre-snapshot script")
		return
	}
	logger.Infof("running pre-snapshot script")
	code := runScript(config.PreSnapshotScriptUrl, config.Timeout)
	res := serialprotocol.SerialResponse{identifier, "PRERESP", req.Version, code, req.OperationId}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Fatalf(err.Error())
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
	if !config.Enabled {
		logger.Infof("snapshot handling disabled, not running post-snapshot script")
		return
	}
	logger.Infof("running post-snapshot script")
	code := runScript(config.PostSnapshotScriptUrl, config.Timeout)
	res := serialprotocol.SerialResponse{identifier, "POSTRESP", req.Version, code, req.OperationId}
	out, err := json.Marshal(res)
	if err != nil {
		logger.Fatalf(err.Error())
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
		logger.Fatalf("unknown message signature %s", msg.Signature)
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
				logger.Fatalf("unknown message signature %s", msg.Signature)
			}
		} else if c != '\x00' {
			currentMsg = append(currentMsg, c)
		}
	}
}

func createTestSnapshotConfig() serialprotocol.SnapshotConfig {
	var config serialprotocol.SnapshotConfig
	config.Timeout = 5
	config.ContinueOnScriptError = true
	config.PreSnapshotScriptUrl = testPreSnapshotScript
	config.PostSnapshotScriptUrl = testPostSnapshotScript
	config.Enabled = true
	return config

}

func createDefaultSnapshotConfig() serialprotocol.SnapshotConfig {
	var config serialprotocol.SnapshotConfig
	config.Timeout = 60
	config.ContinueOnScriptError = true
	config.PreSnapshotScriptUrl = ""
	config.PostSnapshotScriptUrl = ""
	config.Enabled = false
	return config
}

func getSnapshotConfig() serialprotocol.SnapshotConfig {
	if snapshotTestMode {
		return createTestSnapshotConfig()
	}
	config := createDefaultSnapshotConfig()

	if newMetadata.Instance.Attributes.SnapshotTimeout != 0 {
		config.Timeout = newMetadata.Instance.Attributes.SnapshotTimeout
	} else if newMetadata.Project.Attributes.SnapshotTimeout != 0 {
		config.Timeout = newMetadata.Project.Attributes.SnapshotTimeout
	}

	if newMetadata.Instance.Attributes.SnapshotContinueOnScriptError != false {
		config.ContinueOnScriptError = newMetadata.Instance.Attributes.SnapshotContinueOnScriptError
	} else if newMetadata.Project.Attributes.SnapshotContinueOnScriptError != false {
		config.ContinueOnScriptError = newMetadata.Project.Attributes.SnapshotContinueOnScriptError
	}

	if newMetadata.Instance.Attributes.PreSnapshotScriptUrl != "" {
		config.PreSnapshotScriptUrl = newMetadata.Instance.Attributes.PreSnapshotScriptUrl
	} else if newMetadata.Project.Attributes.PreSnapshotScriptUrl != "" {
		config.PreSnapshotScriptUrl = newMetadata.Project.Attributes.PreSnapshotScriptUrl
	}

	if newMetadata.Instance.Attributes.PostSnapshotScriptUrl != "" {
		config.PostSnapshotScriptUrl = newMetadata.Instance.Attributes.PostSnapshotScriptUrl
	} else if newMetadata.Project.Attributes.PostSnapshotScriptUrl != "" {
		config.PostSnapshotScriptUrl = newMetadata.Project.Attributes.PostSnapshotScriptUrl
	}

	if newMetadata.Instance.Attributes.SnapshotEnabled != false {
		config.Enabled = newMetadata.Instance.Attributes.SnapshotEnabled
	} else if newMetadata.Project.Attributes.SnapshotEnabled != false {
		config.Enabled = newMetadata.Project.Attributes.SnapshotEnabled
	}

	return config
}

func downloadGSURL(ctx context.Context, bucket, object string, file *os.File) error {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return fmt.Errorf("failed to create storage client: %v", err)
	}
	defer client.Close()

	r, err := client.Bucket(bucket).Object(object).NewReader(ctx)
	if err != nil {
		return fmt.Errorf("error reading object %q: %v", object, err)
	}
	defer r.Close()

	_, err = io.Copy(file, r)
	return err
}

func downloadURL(url string, file *os.File) error {
	// Retry up to 3 times, only wait 1 second between retries.
	var res *http.Response
	var err error
	for i := 1; ; i++ {
		res, err = http.Get(url)
		if err != nil && i > 3 {
			return err
		}
		if err == nil {
			break
		}
		time.Sleep(1 * time.Second)
	}
	defer res.Body.Close()

	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("GET %q, bad status: %s", url, res.Status)
	}

	_, err = io.Copy(file, res.Body)
	return err
}

func downloadScript(path string, file *os.File) error {
	ctx := context.Background()
	bucket, object := findMatch(path)
	if bucket != "" && object != "" {
		// Retry up to 3 times, only wait 1 second between retries.
		for i := 1; ; i++ {
			err := downloadGSURL(ctx, bucket, object, file)
			if err == nil {
				return nil
			}
			if err != nil && i > 3 {
				logger.Infof("Failed to download GCS path: %v", err)
				break
			}
			time.Sleep(1 * time.Second)
		}
		logger.Infof("trying unauthenticated download")
		return downloadURL(fmt.Sprintf("https://%s/%s/%s", storageURL, bucket, object), file)
	}

	// Fall back to an HTTP GET of the URL.
	return downloadURL(path, file)
}

func findMatch(path string) (string, string) {
	for _, re := range []*regexp.Regexp{gsRegex, gsHTTPRegex1, gsHTTPRegex2, gsHTTPRegex3} {
		match := re.FindStringSubmatch(path)
		if len(match) == 3 {
			return match[1], match[2]
		}
	}
	return "", ""
}

func runScript(url string, timeout int) int {
	dir, err := ioutil.TempDir("", "snapshot-scripts")
	if err != nil {
		logger.Errorf("failed to create temporary directory")
	}

	defer os.RemoveAll(dir)

	tmpfile, err := ioutil.TempFile(dir, "snapshot-script")
	if err != nil {
		logger.Errorf("failed to create temporary file")
	}

	if snapshotTestMode {
		data, err := ioutil.ReadFile(url)
		if err != nil {
			logger.Errorf("failed to read test script at %s", url)
		}
		err = ioutil.WriteFile(tmpfile.Name(), data, 0644)
		if err != nil {
			logger.Errorf("failed to copy script at %s to temp file %s", url, tmpfile.Name())
		}
	} else {
		err = downloadScript(url, tmpfile)
		if err != nil {
			logger.Errorf("failed to download script at %s", url)
		}
	}

	logger.Infof("running script at %s", tmpfile.Name())

	if err := os.Chmod(tmpfile.Name(), 0700); err != nil {
		logger.Errorf("%v", err)
	}

	tmpfile.Close()

	cmd := exec.Command(tmpfile.Name())
	cmd.Start()

	done := make(chan error)
	go func() { done <- cmd.Wait() }()

	// Start timer
	timer := time.After(time.Second * time.Duration(timeout))

	select {
	case <-timer:
		logger.Warningf("timeout while running %s", url)
		// Exit code of the timeout command when it times out
		return 124
	case err := <-done:
		if err != nil {
			exiterr := err.(*exec.ExitError)
			status := exiterr.Sys().(syscall.WaitStatus)
			logger.Warningf("script at %s return with exit code %d", url, status.ExitStatus())
			return status.ExitStatus()
		}
	}
	return 0
}

func listenOnSerialPort() {
	logger.Infof("running in test mode: %t", snapshotTestMode)
	ready, err := json.Marshal(serialprotocol.AgentReady{identifier, "READY", serialProtocolVersion})
	if err != nil {
		logger.Fatalf(err.Error())
	}
	writeSerial(serialPort, ready)

	serialChan := make(chan []byte)
	go func() {
		c := &serial.Config{Name: serialPort, Baud: 115200}
		s, err := serial.OpenPort(c)
		if err != nil {
			logger.Errorf("error opening serial port at port %s", serialPort)
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
	shutdown, err := json.Marshal(serialprotocol.AgentShutdown{identifier, "SHUTDOWN", serialProtocolVersion})
	if err != nil {
		logger.Fatalf(err.Error())
	}
	writeSerial(serialPort, shutdown)
}
