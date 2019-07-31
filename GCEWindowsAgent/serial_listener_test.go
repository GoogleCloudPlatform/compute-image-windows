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
	"fmt"
	"testing"
)

func TestParseSerialDataPrepareForSnapshotRequest(t *testing.T) {
	version := 1
	operation_id := 3
	json := fmt.Sprintf("{\"signature\":\"PREREQ\", \"version\":%d, \"operation_id\":%d}\n", version, operation_id)
	msg := parseSerialData([]byte(json)).(prepareForSnapshotRequest)
	if msg.Version != version {
		t.Errorf("returned version unexpected, got: %d, want %d", msg.Version, version)
	}
	if msg.Operation_id != operation_id {
		t.Errorf("returned operation_id unexpected, got: %d, want %d", msg.Operation_id, operation_id)
	}
}

func TestParseSerialDataResumePostSnapshotRequest(t *testing.T) {
	version := 1
	operation_id := 3
	json := fmt.Sprintf("{\"signature\":\"POSTREQ\", \"version\":%d, \"operation_id\":%d}\n", version, operation_id)
	msg := parseSerialData([]byte(json)).(resumePostSnapshotRequest)
	if msg.Version != version {
		t.Errorf("returned version unexpected, got: %d, want %d", msg.Version, version)
	}
	if msg.Operation_id != operation_id {
		t.Errorf("returned operation_id unexpected, got: %d, want %d", msg.Operation_id, operation_id)
	}
}
