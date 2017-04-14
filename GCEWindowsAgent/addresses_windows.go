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
	"bytes"
	"encoding/binary"
	"fmt"
	"net"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

var (
	ipHlpAPI            = windows.NewLazySystemDLL("iphlpapi.dll")
	procAddIPAddress    = ipHlpAPI.NewProc("AddIPAddress")
	procDeleteIPAddress = ipHlpAPI.NewProc("DeleteIPAddress")
)

func addIPAddress(ip, mask net.IP, index int) error {
	ip = ip.To4()
	mask = mask.To4()
	var nteC int
	var nteI int

	ret, _, _ := procAddIPAddress.Call(
		uintptr(binary.LittleEndian.Uint32(ip)),
		uintptr(binary.LittleEndian.Uint32(mask)),
		uintptr(index),
		uintptr(unsafe.Pointer(&nteC)),
		uintptr(unsafe.Pointer(&nteI)))
	if ret != 0 {
		return fmt.Errorf("nonzero return code from AddIPAddress: %d", ret)
	}
	return nil
}

func deleteIPAddress(ip net.IP) error {
	ip = ip.To4()
	b := make([]byte, 1)
	ai := (*syscall.IpAdapterInfo)(unsafe.Pointer(&b[0]))
	l := uint32(0)
	syscall.GetAdaptersInfo(ai, &l)

	b = make([]byte, int32(l))
	ai = (*syscall.IpAdapterInfo)(unsafe.Pointer(&b[0]))
	if err := syscall.GetAdaptersInfo(ai, &l); err != nil {
		return err
	}

	for ; ai != nil; ai = ai.Next {
		for ipl := &ai.IpAddressList; ipl != nil; ipl = ipl.Next {
			ipb := bytes.Trim(ipl.IpAddress.String[:], "\x00")
			if string(ipb) != ip.String() {
				continue
			}
			nteC := ipl.Context
			ret, _, _ := procDeleteIPAddress.Call(uintptr(nteC))
			if ret != 0 {
				return fmt.Errorf("nonzero return code from DeleteIPAddress: %d", ret)
			}
			return nil
		}
	}
	return fmt.Errorf("did not find address %s on system", ip)
}
