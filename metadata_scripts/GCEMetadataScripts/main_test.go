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

package main

import (
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"testing"
)

func TestValidateArgs(t *testing.T) {
	validateTests := []struct {
		arg  string
		want map[metadataScriptType]string
	}{
		{"specialize", map[metadataScriptType]string{
			bat: "sysprep-specialize-script-bat",
			cmd: "sysprep-specialize-script-cmd",
			ps1: "sysprep-specialize-script-ps1",
			url: "sysprep-specialize-script-url"},
		},
		{"startup", map[metadataScriptType]string{
			bat: "windows-startup-script-bat",
			cmd: "windows-startup-script-cmd",
			ps1: "windows-startup-script-ps1",
			url: "windows-startup-script-url"},
		},
		{"shutdown", map[metadataScriptType]string{
			bat: "windows-shutdown-script-bat",
			cmd: "windows-shutdown-script-cmd",
			ps1: "windows-shutdown-script-ps1",
			url: "windows-shutdown-script-url"},
		},
	}

	for _, tt := range validateTests {
		got, err := validateArgs([]string{"", tt.arg})
		if err != nil {
			t.Fatalf("validateArgs returned error: %v", err)
		}
		if !reflect.DeepEqual(got, tt.want) {
			t.Errorf("returned map does not match expected one: got %v, want %v", got, tt.want)
		}
	}
}

func TestParseMetadata(t *testing.T) {
	mdsm := map[metadataScriptType]string{
		bat: "sysprep-specialize-script-bat",
		cmd: "sysprep-specialize-script-cmd",
		ps1: "sysprep-specialize-script-ps1",
		url: "sysprep-specialize-script-url",
	}
	md := map[string]string{
		"sysprep-specialize-script-cmd": "cmd",
		"startup-script-cmd":            "cmd",
		"shutdown-script-ps1":           "ps1",
		"key": "value",
		"sysprep-specialize-script-url": "url",
		"sysprep-specialize-script-ps1": "ps1",
		"sysprep-specialize-script-bat": "bat",
	}

	want := []metadataScript{
		{Type: ps1, Script: "ps1", Metadata: "sysprep-specialize-script-ps1"},
		{Type: cmd, Script: "cmd", Metadata: "sysprep-specialize-script-cmd"},
		{Type: bat, Script: "bat", Metadata: "sysprep-specialize-script-bat"},
		{Type: url, Script: "url", Metadata: "sysprep-specialize-script-url"},
	}
	got := parseMetadata(mdsm, md)
	if !reflect.DeepEqual(got, want) {
		t.Errorf("parsed metadata does not match expectation, got: %v, want: %v", got, want)
	}
}

func TestFindMatch(t *testing.T) {
	matchTests := []struct {
		path, bucket, object string
	}{
		{"gs://bucket/object", "bucket", "object"},
		{"gs://bucket/some/object", "bucket", "some/object"},
		{"http://bucket.storage.googleapis.com/object", "bucket", "object"},
		{"https://bucket.storage.googleapis.com/object", "bucket", "object"},
		{"https://bucket.storage.googleapis.com/some/object", "bucket", "some/object"},
		{"http://storage.googleapis.com/bucket/object", "bucket", "object"},
		{"http://commondatastorage.googleapis.com/bucket/object", "bucket", "object"},
		{"https://storage.googleapis.com/bucket/object", "bucket", "object"},
		{"https://commondatastorage.googleapis.com/bucket/object", "bucket", "object"},
		{"https://storage.googleapis.com/bucket/some/object", "bucket", "some/object"},
		{"https://commondatastorage.googleapis.com/bucket/some/object", "bucket", "some/object"},
	}

	for _, tt := range matchTests {
		bucket, object := findMatch(tt.path)
		if bucket != tt.bucket {
			t.Errorf("returned bucket does not match expected one for %q:\n  got %q, want: %q", tt.path, bucket, tt.bucket)
		}
		if object != tt.object {
			t.Errorf("returned object does not match expected one for %q\n:  got %q, want: %q", tt.path, object, tt.object)
		}
	}
}

func TestGetMetadata(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, `{"key1":"value1","key2":"value2"}`)
	}))
	defer ts.Close()

	metadataURL = ts.URL
	metadataHang = ""

	want := map[string]string{"key1": "value1", "key2": "value2"}
	got, err := getMetadata()
	if err != nil {
		t.Fatalf("error running getMetadata: %v", err)
	}

	if !reflect.DeepEqual(got, want) {
		t.Errorf("metadata does not match expectation, got: %q, want: %q", got, want)
	}
}
