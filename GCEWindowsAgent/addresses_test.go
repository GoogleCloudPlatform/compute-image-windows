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
	"encoding/json"
	"reflect"
	"testing"

	"github.com/go-ini/ini"
)

func TestCompareIPs(t *testing.T) {
	var tests = []struct {
		forwarded, metadata, wantAdd, wantRm []string
	}{
		// These should return toAdd:
		// In Md, not present
		{nil, []string{"1.2.3.4"}, []string{"1.2.3.4"}, nil},
		{nil, []string{"1.2.3.4", "5.6.7.8"}, []string{"1.2.3.4", "5.6.7.8"}, nil},

		// These should return toRm:
		// Present, not in Md
		{[]string{"1.2.3.4"}, nil, nil, []string{"1.2.3.4"}},
		{[]string{"1.2.3.4", "5.6.7.8"}, []string{"5.6.7.8"}, nil, []string{"1.2.3.4"}},

		// These should return nil, nil:
		// Present, in Md
		{[]string{"1.2.3.4"}, []string{"1.2.3.4"}, nil, nil},
		{[]string{"1.2.3.4", "5.6.7.8"}, []string{"1.2.3.4", "5.6.7.8"}, nil, nil},
	}

	for idx, tt := range tests {
		toAdd, toRm := compareIPs(tt.forwarded, tt.metadata)
		if !reflect.DeepEqual(tt.wantAdd, toAdd) {
			t.Errorf("case %d: toAdd does not match expected: forwarded: %q, metadata: %q, got: %q, want: %q", idx, tt.forwarded, tt.metadata, toAdd, tt.wantAdd)
		}
		if !reflect.DeepEqual(tt.wantRm, toRm) {
			t.Errorf("case %d: toRm does not match expected: forwarded: %q, metadata: %q, got: %q, want: %q", idx, tt.forwarded, tt.metadata, toRm, tt.wantRm)
		}
	}
}

func TestAddressDisabled(t *testing.T) {
	var tests = []struct {
		name string
		data []byte
		md   *metadataJSON
		want bool
	}{
		{"not explicitly disabled", []byte(""), &metadataJSON{}, false},
		{"enabled in cfg only", []byte("[addressManager]\ndisable=false"), &metadataJSON{}, false},
		{"disabled in cfg only", []byte("[addressManager]\ndisable=true"), &metadataJSON{}, true},
		{"disabled in cfg, enabled in instance metadata", []byte("[addressManager]\ndisable=true"), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(false)}}}, true},
		{"enabled in cfg, disabled in instance metadata", []byte("[addressManager]\ndisable=false"), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(true)}}}, false},
		{"enabled in instance metadata only", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(false)}}}, false},
		{"enabled in project metadata only", []byte(""), &metadataJSON{Project: projectJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(false)}}}, false},
		{"disabled in instance metadata only", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(true)}}}, true},
		{"enabled in instance metadata, disabled in project metadata", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(false)}}, Project: projectJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(true)}}}, false},
		{"disabled in project metadata only", []byte(""), &metadataJSON{Project: projectJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(true)}}}, true},
	}

	for _, tt := range tests {
		cfg, err := ini.InsensitiveLoad(tt.data)
		if err != nil {
			t.Errorf("test case %q: error parsing config: %v", tt.name, err)
			continue
		}
		if cfg == nil {
			cfg = &ini.File{}
		}
		newMetadata = tt.md
		config = cfg
		got := (&addressMgr{}).disabled()
		if got != tt.want {
			t.Errorf("test case %q, disabled? got: %t, want: %t", tt.name, got, tt.want)
		}
	}
}

func TestAddressDiff(t *testing.T) {
	var tests = []struct {
		name string
		data []byte
		md   *metadataJSON
		want bool
	}{
		{"not set", []byte(""), &metadataJSON{}, false},
		{"enabled in cfg only", []byte("[wsfc]\nenable=true"), &metadataJSON{}, true},
		{"disabled in cfg only", []byte("[wsfc]\nenable=false"), &metadataJSON{}, false},
		{"disabled in cfg, enabled in instance metadata", []byte("[wsfc]\nenable=false"), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{EnableWSFC: mkptr(true)}}}, false},
		{"enabled in cfg, disabled in instance metadata", []byte("[wsfc]\nenable=true"), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{EnableWSFC: mkptr(false)}}}, true},
		{"enabled in instance metadata only", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{EnableWSFC: mkptr(true)}}}, true},
		{"enabled in project metadata only", []byte(""), &metadataJSON{Project: projectJSON{Attributes: attributesJSON{EnableWSFC: mkptr(true)}}}, true},
		{"disabled in instance metadata only", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{EnableWSFC: mkptr(false)}}}, false},
		{"enabled in instance metadata, disabled in project metadata", []byte(""), &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{EnableWSFC: mkptr(true)}}, Project: projectJSON{Attributes: attributesJSON{EnableWSFC: mkptr(false)}}}, true},
		{"disabled in project metadata only", []byte(""), &metadataJSON{Project: projectJSON{Attributes: attributesJSON{EnableWSFC: mkptr(false)}}}, false},
	}

	for _, tt := range tests {
		cfg, err := ini.InsensitiveLoad(tt.data)
		if err != nil {
			t.Errorf("test case %q: error parsing config: %v", tt.name, err)
			continue
		}
		if cfg == nil {
			cfg = &ini.File{}
		}
		oldWSFCEnable = false
		oldMetadata = &metadataJSON{}
		newMetadata = tt.md
		config = cfg
		got := (&addressMgr{}).diff()
		if got != tt.want {
			t.Errorf("test case %q, addresses.diff() got: %t, want: %t", tt.name, got, tt.want)
		}
	}
}

func TestWsfcFilter(t *testing.T) {
	var tests = []struct {
		metaData    []byte
		expectedIps []string
	}{
		// signle nic with enable-wsfc set to true
		{[]byte(`{"instance":{"attributes":{"enable-wsfc":"true"}, "networkInterfaces":[{"forwardedIps":["192.168.0.0", "192.168.0.1"]}]}}`), []string{}},
		// multi nic with enable-wsfc set to true
		{[]byte(`{"instance":{"attributes":{"enable-wsfc":"true"}, "networkInterfaces":[{"forwardedIps":["192.168.0.0", "192.168.0.1"]},{"forwardedIps":["192.168.0.2"]}]}}`), []string{}},
		// filter with wsfc-addrs
		{[]byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0.1"}, "networkInterfaces":[{"forwardedIps":["192.168.0.0", "192.168.0.1"]}]}}`), []string{"192.168.0.0"}},
		// filter with both wsfc-addrs and enable-wsfc flag
		{[]byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0.1", "enable-wsfc":"true"}, "networkInterfaces":[{"forwardedIps":["192.168.0.0", "192.168.0.1"]}]}}`), []string{"192.168.0.0"}},
		// filter with invalid wsfc-addrs
		{[]byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0"}, "networkInterfaces":[{"forwardedIps":["192.168.0.0", "192.168.0.1"]}]}}`), []string{"192.168.0.0", "192.168.0.1"}},
	}

	config = ini.Empty()
	for _, tt := range tests {
		var metadata metadataJSON
		if err := json.Unmarshal(tt.metaData, &metadata); err != nil {
			t.Error("invalid test case:", tt, err)
		}

		newMetadata = &metadata
		testAddress := addressMgr{}
		testAddress.applyWSFCFilter()

		forwardedIps := []string{}
		for _, ni := range newMetadata.Instance.NetworkInterfaces {
			forwardedIps = append(forwardedIps, ni.ForwardedIps...)
		}

		if !reflect.DeepEqual(forwardedIps, tt.expectedIps) {
			t.Errorf("wsfc filter failed: expect - %q, actual - %q", tt.expectedIps, forwardedIps)
		}
	}
}

func TestWsfcFlagTriggerAddressDiff(t *testing.T) {
	var tests = []struct {
		newMetadata, oldMetadata *metadataJSON
	}{
		// trigger diff on wsfc-addrs
		{&metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.1"}}}, &metadataJSON{}},
		{&metadataJSON{Project: projectJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.1"}}}, &metadataJSON{}},
		{&metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.1"}}}, &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.2"}}}},
		{&metadataJSON{Project: projectJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.1"}}}, &metadataJSON{Project: projectJSON{Attributes: attributesJSON{WSFCAddresses: "192.168.0.2"}}}},
	}

	config = ini.Empty()
	for _, tt := range tests {
		oldWSFCAddresses = tt.oldMetadata.Instance.Attributes.WSFCAddresses
		newMetadata = tt.newMetadata
		oldMetadata = tt.oldMetadata
		testAddress := addressMgr{}
		if !testAddress.diff() {
			t.Errorf("old: %v new: %v doesn't trigger diff.", tt.oldMetadata, tt.newMetadata)
		}
	}
}

func TestAddressLogStatus(t *testing.T) {
	// Disable it.
	addressDisabled = false
	newMetadata = &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(true)}}}
	config = ini.Empty()
	disabled := (&addressMgr{}).disabled()
	if !disabled {
		t.Fatal("expected true but got", disabled)
	}

	// Enable it.
	newMetadata = &metadataJSON{Instance: instanceJSON{Attributes: attributesJSON{DisableAddressManager: mkptr(false)}}}
	disabled = (&addressMgr{}).disabled()
	if disabled {
		t.Fatal("expected false but got", disabled)
	}
}
