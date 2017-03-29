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
)

func TestCompareIPs(t *testing.T) {
	var tests = []struct {
		regFwdIPs, mdFwdIPs, cfgIPs, wantAdd, wantRm []string
	}{
		// These should return toAdd:
		// In MD, not Reg or config
		{nil, []string{"1.2.3.4"}, nil, []string{"1.2.3.4"}, nil},
		// In MD and in Reg, not config
		{[]string{"1.2.3.4"}, []string{"1.2.3.4"}, nil, []string{"1.2.3.4"}, nil},

		// These should return toRm:
		// In Reg and config, not Md
		{[]string{"1.2.3.4"}, nil, []string{"1.2.3.4"}, nil, []string{"1.2.3.4"}},

		// These should return nil, nil:
		// In Reg, Md and config
		{[]string{"1.2.3.4"}, []string{"1.2.3.4"}, []string{"1.2.3.4"}, nil, nil},
		// In Md and config, not Reg
		{nil, []string{"1.2.3.4"}, []string{"1.2.3.4"}, nil, nil},
		// Only in Reg
		{[]string{"1.2.3.4"}, nil, nil, nil, nil},
		// Only in config
		{nil, nil, []string{"1.2.3.4"}, nil, nil},
	}

	for _, tt := range tests {
		toAdd, toRm := compareIPs(tt.regFwdIPs, tt.mdFwdIPs, tt.cfgIPs)
		if !reflect.DeepEqual(tt.wantAdd, toAdd) {
			t.Errorf("toAdd does not match expected: regFwdIPs: %q, mdFwdIPs: %q, cfgIPs: %q, got: %q, want: %q", tt.regFwdIPs, tt.mdFwdIPs, tt.cfgIPs, toAdd, tt.wantAdd)
		}
		if !reflect.DeepEqual(tt.wantRm, toRm) {
			t.Errorf("toRm does not match expected: regFwdIPs: %q, mdFwdIPs: %q, cfgIPs: %q, got: %q, want: %q", tt.regFwdIPs, tt.mdFwdIPs, tt.cfgIPs, toRm, tt.wantRm)
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

	for _, tt := range tests {
		var metadata metadataJSON
		if err := json.Unmarshal(tt.metaData, &metadata); err != nil {
			t.Error("invalid test case:", tt, err)
		}

		testAddress := addresses{&metadata, nil}
		testAddress.applyWSFCFilter()

		forwardedIps := []string{}
		for _, ni := range testAddress.newMetadata.Instance.NetworkInterfaces {
			forwardedIps = append(forwardedIps, ni.ForwardedIps...)
		}

		if !reflect.DeepEqual(forwardedIps, tt.expectedIps) {
			t.Errorf("wsfc filter failed: expect - %q, actual - %q", tt.expectedIps, forwardedIps)
		}
	}
}

func TestWsfcFlagTriggerAddressDiff(t *testing.T) {
	var tests = []struct {
		newMetadata, oldMetadata []byte
	}{
		// trigger diff on enable-wsfc
		{[]byte(`{"instance":{"attributes":{"enable-wsfc":"true"}}}`), nil},
		// trigger diff on enable-wsfc
		{[]byte(`{"instance":{"attributes":{"enable-wsfc":"false"}}}`), []byte(`{"instance":{"attributes":{"enable-wsfc":"true"}}}`)},
		// trigger diff on wsfc-addrs
		{[]byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0.1"}}}`), []byte(`{"instance":{"attributes":{}}}`)},
		// trigger diff on wsfc-addrs
		{[]byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0.1"}}}`), []byte(`{"instance":{"attributes":{"wsfc-addrs":"192.168.0.2"}}}`)},
	}

	for _, tt := range tests {
		var newMetadata metadataJSON
		var oldMetadata metadataJSON
		json.Unmarshal(tt.newMetadata, &newMetadata)
		json.Unmarshal(tt.oldMetadata, &oldMetadata)

		testAddress := addresses{&newMetadata, &oldMetadata}

		if !testAddress.diff() {
			t.Errorf("old: %q new: %q does't tirgger diff.", tt.oldMetadata, tt.newMetadata)
		}
	}
}
