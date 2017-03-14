//  Copyright 2017 Google Inc. All Rights Reserved.
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

// GCEWindowsAgent is the Google Compute Engine Windows agent executable.
package main

import (
	"context"
	"os"
	"sync"
	"time"

	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
	"github.com/tarm/serial"
)

const regKeyBase = `SOFTWARE\Google\ComputeEngine`

func writeSerial(port string, msg []byte) error {
	c := &serial.Config{Name: port, Baud: 115200}
	s, err := serial.OpenPort(c)
	if err != nil {
		return err
	}
	defer s.Close()

	_, err = s.Write(msg)
	if err != nil {
		return err
	}
	return nil
}

type manager interface {
	diff() bool
	disabled() bool
	set() error
}

func logStatus(name string, disabled bool) {
	var status string
	switch disabled {
	case false:
		status = "enabled"
	case true:
		status = "disabled"
	}
	logger.Infof("GCE %s manager status: %s", name, status)
}

func runUpdate(newMetadata, oldMetadata *metadataJSON) {
	var wg sync.WaitGroup
	addressMgr := &addresses{
		oldMetadata: oldMetadata,
		newMetadata: newMetadata,
	}
	acctMgr := &accounts{
		oldMetadata: oldMetadata,
		newMetadata: newMetadata,
	}
	for _, mgr := range []manager{addressMgr, acctMgr} {
		wg.Add(1)
		go func(mgr manager) {
			defer wg.Done()
			if mgr.disabled() || !mgr.diff() {
				return
			}
			if err := mgr.set(); err != nil {
				logger.Error(err)
			}
		}(mgr)
	}
	wg.Wait()
}

func run(ctx context.Context) {
	logger.Info("GCE Agent Started")

	go func() {
		var oldMetadata metadataJSON
		printWebException := true
		for {
			newMetadata, err := watchMetadata(ctx)
			if err != nil {
				if printWebException {
					logger.Error(err)
					printWebException = false
				}
				time.Sleep(5 * time.Second)
				continue
			}
			runUpdate(newMetadata, &oldMetadata)
			oldMetadata = *newMetadata
			printWebException = true
		}
	}()

	<-ctx.Done()
	logger.Info("GCE Agent Stopped")
}

func containsString(s string, ss []string) bool {
	for _, a := range ss {
		if a == s {
			return true
		}
	}
	return false
}

func main() {
	ctx := context.Background()
	logger.Init("GCEWindowsAgent", "COM1")

	var action string
	if len(os.Args) < 2 {
		action = "run"
	} else {
		action = os.Args[1]
	}
	if action == "noservice" {
		run(ctx)
		os.Exit(0)
	}
	if err := register(ctx, "GCEAgent", "GCEAgent", "", run, action); err != nil {
		logger.Fatal(err)
	}
}
