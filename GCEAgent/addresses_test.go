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
