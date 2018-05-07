//  Copyright 2018 Google Inc. All Rights Reserved.
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
	"os/exec"
	"reflect"
	"strconv"
	"time"

	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
	"github.com/go-ini/ini"
)

const diagnosticsCmd = `C:\Program Files\Google\Compute Engine\diagnostics\diagnostics.exe`

var (
	diagnosticsDisabled = true
)

type diagnosticsEntryJSON struct {
	SignedUrl string
	ExpireOn  string
	TraceFlag bool
}

func (k diagnosticsEntryJSON) expired() bool {
	t, err := time.Parse(time.RFC3339, k.ExpireOn)
	if err != nil {
		if !containsString(k.ExpireOn, badExpire) {
			logger.Errorln("Error parsing time:", err)
			badExpire = append(badExpire, k.ExpireOn)
		}
		return true
	}
	return t.Before(time.Now())
}

type diagnostics struct {
	newMetadata, oldMetadata *metadataJSON
	config                   *ini.File
}

func (a *diagnostics) diff() bool {
	return !reflect.DeepEqual(a.newMetadata.Instance.Attributes.Diagnostics, a.oldMetadata.Instance.Attributes.Diagnostics)
}

func (a *diagnostics) disabled() (disabled bool) {
	defer func() {
		if disabled != diagnosticsDisabled {
			diagnosticsDisabled = disabled
			logStatus("diagnostics", disabled)
		}
	}()

	// Diagnostics are opt-in and disabled by default.
	var err error
	var enabled bool
	enabled, err = strconv.ParseBool(a.config.Section("diagnostics").Key("enable").String())
	if err == nil {
		return !enabled
	}
	enabled, err = strconv.ParseBool(a.newMetadata.Instance.Attributes.EnableDiagnostics)
	if err == nil {
		return !enabled
	}
	enabled, err = strconv.ParseBool(a.newMetadata.Project.Attributes.EnableDiagnostics)
	if err == nil {
		return !enabled
	}
	return diagnosticsDisabled
}

var diagnosticsEntries []string

func (a *diagnostics) set() error {
	var entry diagnosticsEntryJSON
	strEntry := a.newMetadata.Instance.Attributes.Diagnostics
	if containsString(strEntry, diagnosticsEntries) {
		return nil
	}

	diagnosticsEntries = append(diagnosticsEntries, strEntry)
	if err := json.Unmarshal([]byte(strEntry), &entry); err != nil {
		return err
	}
	if entry.SignedUrl == "" || entry.expired() {
		return nil
	}

	args := []string{
		"-signedUrl",
		entry.SignedUrl,
	}
	if entry.TraceFlag {
		args = append(args, "-trace")
	}

	cmd := exec.Command(diagnosticsCmd, args...)
	go func() {
		logger.Info("Collecting logs from the system:")
		out, err := cmd.CombinedOutput()
		logger.Info(string(out[:]))
		if err != nil {
			logger.Infof("Error collecting logs: %v", err)
		}
	}()

	return nil
}
