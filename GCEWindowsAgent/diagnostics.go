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
	diagnosticsDisabled = false
)

type diagnosticsKeyJSON struct {
	SignedUrl string
	ExpireOn  string
	TraceFlag bool
}

func (k diagnosticsKeyJSON) expired() bool {
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
	return !reflect.DeepEqual(a.newMetadata.Instance.Attributes.DiagnosticsKeys, a.oldMetadata.Instance.Attributes.DiagnosticsKeys)
}

func (a *diagnostics) disabled() (disabled bool) {
	defer func() {
		if disabled != diagnosticsDisabled {
			diagnosticsDisabled = disabled
			logStatus("diagnostics", disabled)
		}
	}()

	var err error
	disabled, err = strconv.ParseBool(a.config.Section("diagnostics").Key("disable").String())
	if err == nil {
		return disabled
	}
	disabled, err = strconv.ParseBool(a.newMetadata.Instance.Attributes.DisableDiagnostics)
	if err == nil {
		return disabled
	}
	disabled, err = strconv.ParseBool(a.newMetadata.Project.Attributes.DisableDiagnostics)
	if err == nil {
		return disabled
	}
	return diagnosticsDisabled
}

var diagnosticsKeys []string

func (a *diagnostics) set() error {
	var key diagnosticsKeyJSON
	strKey := a.newMetadata.Instance.Attributes.DiagnosticsKeys
	if containsString(strKey, diagnosticsKeys) {
		return nil
	}

	diagnosticsKeys = append(diagnosticsKeys, strKey)
	if err := json.Unmarshal([]byte(strKey), &key); err != nil {
		logger.Error(err)
		return nil
	}
	if key.SignedUrl == "" || key.expired() {
		return nil
	}

	args := []string{
		"-signedUrl",
		key.SignedUrl,
	}
	if key.TraceFlag {
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
