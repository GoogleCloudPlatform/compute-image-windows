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
	"io/ioutil"
	"os"
	"sync"
	"time"

	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
	"github.com/go-ini/ini"
	"github.com/tarm/serial"
)

var version string

const (
	configPath = `C:\Program Files\Google\Compute Engine\instance_configs.cfg`
	regKeyBase = `SOFTWARE\Google\ComputeEngine`
)

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

func parseConfig(file string) (*ini.File, error) {
	d, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}
	return ini.InsensitiveLoad(d)
}

func runUpdate(newMetadata, oldMetadata *metadataJSON) {
	cfg, err := parseConfig(configPath)
	if err != nil && err != os.ErrNotExist {
		logger.Error(err)
	}
	if cfg == nil {
		cfg = &ini.File{}
	}

	var wg sync.WaitGroup
	addressMgr := &addresses{
		oldMetadata: oldMetadata,
		newMetadata: newMetadata,
		config:      cfg,
	}
	acctMgr := &accounts{
		oldMetadata: oldMetadata,
		newMetadata: newMetadata,
		config:      cfg,
	}
	wsfcMgr := newWsfcManager(newMetadata, cfg)

	for _, mgr := range []manager{addressMgr, acctMgr, wsfcMgr} {
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
	logger.Infof("GCE Agent Started (version %s)", version)

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
			select {
			case <-ctx.Done():
				return
			default:
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
