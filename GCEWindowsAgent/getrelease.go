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

func parseOSRelease(osRelease string) (release, error) {
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
			version, err := parseVersion(id)
			if err != nil {
				return ret, err
			}
			ret.version = version
		}
	}
	return ret, nil
}

func parseSystemRelease(systemRelease string) (release, error) {
	var ret release
	var key = " release "
	idx := strings.Index(systemRelease, key)
	if idx == -1 {
		return ret, fmt.Errorf("SystemRelease does not match format")
	}
	ret.os = parseID(systemRelease[:idx])

	versionFromRelease := strings.Split(systemRelease[idx+len(key):], " ")[0]
	version, err := parseVersion(versionFromRelease)
	if err != nil {
		return ret, err
	}
	ret.version = version
	return ret, nil
}

func parseVersion(version string) (ver, error) {
	var ret ver
	var versionsl []string
	versionsl = strings.Split(version, ".")

	vernum, err := strconv.Atoi(versionsl[0])
	if err != nil {
		return ret, err
	}

	ret.major = &vernum
	if len(versionsl) > 1 {
		vernum, err := strconv.Atoi(versionsl[1])
		if err != nil {
			return ret, err
		}
		ret.minor = &vernum
	}
	if len(versionsl) > 2 {
		vernum, err := strconv.Atoi(versionsl[2])
		if err != nil {
			return ret, err
		}
		ret.patch = &vernum
	}
	return ret, nil
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

func getRelease() (release, error) {
	if runtime.GOOS == "linux" {
		releaseFile, err := ioutil.ReadFile("/etc/os-release")
		if err == nil {
			return parseOSRelease(string(releaseFile))
		}
		releaseFile, err = ioutil.ReadFile("/etc/system-release")
		if err == nil {
			return parseSystemRelease(string(releaseFile))
		}
	}
	return release{}, fmt.Errorf("%s is a supported platform", runtime.GOOS)
}
