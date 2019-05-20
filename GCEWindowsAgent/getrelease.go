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
	"io/ioutil"
	"runtime"
	"strconv"
	"strings"
)

type ver struct {
	major, minor, patch *int
}

type release struct {
	os      string
	version ver
}

func (v ver) String() string {
	if v.major == nil {
		return ""
	}
	ret := fmt.Sprintf("%d", *v.major)
	if v.minor != nil {
		ret = fmt.Sprintf("%s.%d", ret, *v.minor)
	}
	if v.patch != nil {
		ret = fmt.Sprintf("%s.%d", ret, *v.patch)
	}
	return ret
}

func parseOSRelease(osRelease string) release {
	var ret release
	for _, line := range strings.Split(osRelease, "\n") {
		var id = line
		if id = strings.TrimPrefix(line, "ID="); id != line {
			if len(id) > 0 && id[0] == '"' {
				id = id[1:]
			}
			if len(id) > 0 && id[len(id)-1] == '"' {
				id = id[:len(id)-1]
			}
			ret.os = parseID(id)
		}
		if id = strings.TrimPrefix(line, "VERSION_ID="); id != line {
			if len(id) > 0 && id[0] == '"' {
				id = id[1:]
			}
			if len(id) > 0 && id[len(id)-1] == '"' {
				id = id[:len(id)-1]
			}
			ret.version = parseVersion(id)
		}
	}
	return ret
}

func parseSystemRelease(systemRelease string) release {
	var ret release
	var key = " release "
	idx := strings.Index(systemRelease, key)
	if idx == -1 {
		return ret
	}
	ret.os = parseID(systemRelease[:idx])

	var version string
	version = strings.Split(systemRelease[idx+len(key):], " ")[0]
	ret.version = parseVersion(version)
	return ret
}

func parseVersion(version string) ver {
	var ret ver
	var versionsl []string
	versionsl = strings.Split(version, ".")

	vernum, err := strconv.Atoi(versionsl[0])
	if err != nil {
		fmt.Println("error on versionsl[0]:", err)
		return ret
	}

	ret.major = &vernum
	if len(versionsl) > 1 {
		vernum, err := strconv.Atoi(versionsl[1])
		if err == nil {
			ret.minor = &vernum
		}
	}
	if len(versionsl) > 2 {
		vernum, err := strconv.Atoi(versionsl[2])
		if err == nil {
			ret.patch = &vernum
		}
	}
	return ret
}

func parseID(id string) string {
	switch id {
	case "Red Hat Enterprise Linux Server":
		return "rhel"
	case "CentOS", "CentOS Linux":
		return "centos"
	default:
		return id
	}
}

func getRelease() release {
	switch runtime.GOOS {
	case "freebsd":
		return release{os: "freebsd"}
	case "linux":
		releaseFile, err := ioutil.ReadFile("/etc/os-release")
		if err == nil {
			return parseOSRelease(string(releaseFile))
		}
		releaseFile, err = ioutil.ReadFile("/etc/system-release")
		if err == nil {
			return parseSystemRelease(string(releaseFile))
		}
		return release{}
	default:
		return release{}
	}
}
