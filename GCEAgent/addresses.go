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
	"net"
	"reflect"
	"strings"

	"../logger"
)

var addressDisabled = false
var addressKey = regKeyBase + `\ForwardedIps`

type addresses struct {
	newMetadata, oldMetadata *metadataJSON
}

func (a *addresses) diff() bool {
	return !reflect.DeepEqual(a.newMetadata.Instance.NetworkInterfaces, a.oldMetadata.Instance.NetworkInterfaces)
}

func (a *addresses) disabled() bool {
	d := a.newMetadata.Instance.Attributes.DisableAddressManager
	if d != addressDisabled {
		addressDisabled = d
		logStatus("address", d)
	}

	return d
}

func compareIPs(regFwdIPs, mdFwdIPs, cfgIPs []string) (toAdd []string, toRm []string) {
	for _, mdIP := range mdFwdIPs {
		if !containsString(mdIP, cfgIPs) {
			toAdd = append(toAdd, mdIP)
		}
	}

	for _, cfgIP := range cfgIPs {
		if containsString(cfgIP, regFwdIPs) && !containsString(cfgIP, mdFwdIPs) {
			toRm = append(toRm, cfgIP)
		}
	}

	return
}

var badMAC []string

func (a *addresses) set() error {
	ifs, err := net.Interfaces()
	if err != nil {
		return err
	}
	for _, ni := range a.newMetadata.Instance.NetworkInterfaces {
		mac, err := net.ParseMAC(ni.Mac)
		if err != nil {
			if !containsString(ni.Mac, badMAC) {
				logger.Error(err)
				badMAC = append(badMAC, ni.Mac)
			}
			continue
		}

		regFwdIPs, err := readRegMultiString(addressKey, mac.String())
		if err != nil && err != errRegNotExist {
			logger.Error(err)
			continue
		} else if err != nil && err == errRegNotExist {
			regFwdIPs = nil
		}

		var iface net.Interface
		for _, i := range ifs {
			if i.HardwareAddr.String() == mac.String() {
				iface = i
			}
		}

		if reflect.DeepEqual(net.Interface{}, iface) {
			if !containsString(ni.Mac, badMAC) {
				logger.Errorf("no interface with mac %s exists on system", mac)
				badMAC = append(badMAC, ni.Mac)
			}
			continue
		}

		addrs, err := iface.Addrs()
		if err != nil {
			logger.Error(err)
			continue
		}

		var cfgIPs []string
		for _, addr := range addrs {
			cfgIPs = append(cfgIPs, strings.TrimSuffix(addr.String(), "/32"))
		}

		toAdd, toRm := compareIPs(regFwdIPs, ni.ForwardedIps, cfgIPs)
		if len(toAdd) != 0 || len(toRm) != 0 {
			logger.Infof("Changing forwarded IPs for %s from %q to %q by adding %q and removing %q.", mac, regFwdIPs, ni.ForwardedIps, toAdd, toRm)
		}

		reg := ni.ForwardedIps
		for _, ip := range toAdd {
			if err := addIPAddress(net.ParseIP(ip), net.ParseIP("255.255.255.255"), iface.Index); err != nil {
				logger.Error(err)
				for i, rIP := range reg {
					if rIP == ip {
						reg = append(regFwdIPs[:i], regFwdIPs[i+1:]...)
						break
					}
				}
			}
		}

		for _, ip := range toRm {
			if err := deleteIPAddress(net.ParseIP(ip)); err != nil {
				logger.Error(err)
				reg = append(reg, ip)
			}
		}

		if err := writeRegMultiString(addressKey, mac.String(), reg); err != nil {
			logger.Error(err)
		}
	}

	return nil
}
