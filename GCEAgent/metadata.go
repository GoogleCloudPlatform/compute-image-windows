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
	"context"
	"encoding/json"
	"io/ioutil"
	"net/http"
	"time"
)

const metadataServer = "http://metadata.google.internal/computeMetadata/v1"
const metadataHang = "/?recursive=true&alt=json&wait_for_change=true&timeout_sec=60&last_etag="
const defaultEtag = "NONE"

var (
	defaultTimeout = 70 * time.Second
	etag           = defaultEtag
)

type metadataJSON struct {
	Instance instanceJSON
	Project  projectJSON
}

type instanceJSON struct {
	Attributes        attributesJSON
	NetworkInterfaces []networkInterfacesJSON
}

type networkInterfacesJSON struct {
	ForwardedIps []string
	Mac          string
}

type projectJSON struct {
	Attributes attributesJSON
}

type attributesJSON struct {
	WindowsKeys           string `json:"windows-keys"`
	DisableAddressManager bool   `json:"disable-address-manager,string"`
	DisableAgentUpdates   bool   `json:"disable-agent-updates,string"`
	DisableAccountManager bool   `json:"disable-account-manager,string"`
	EnableWSFC            bool   `json:"enable-wsfc,string"`
	WSFCAddresses         string `json:"wsfc-addrs"`
}

func updateEtag(resp *http.Response) {
	etag = resp.Header.Get("etag")
	if etag == "" {
		etag = defaultEtag
	}
}

func watchMetadata(ctx context.Context) (*metadataJSON, error) {
	client := &http.Client{
		Timeout: defaultTimeout,
	}

	req, err := http.NewRequest("GET", metadataServer+metadataHang+etag, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Add("Metadata-Flavor", "Google")
	req = req.WithContext(ctx)

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}

	updateEtag(resp)

	md, err := ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		return nil, err
	}
	var metadata metadataJSON
	writeSerial("COM1", md)
	return &metadata, json.Unmarshal(md, &metadata)
}
