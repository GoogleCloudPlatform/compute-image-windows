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
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"math/big"
	"os/user"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
	"github.com/go-ini/ini"
)

var (
	regName         = "PublicKeys"
	accountDisabled = false
)

type windowsKeyJSON struct {
	Email    string
	ExpireOn string
	Exponent string
	Modulus  string
	UserName string
}

var badExpire []string

func (k windowsKeyJSON) expired() bool {
	t, err := time.Parse(time.RFC3339, k.ExpireOn)
	if err != nil {
		if !containsString(k.ExpireOn, badExpire) {
			logger.Errorln("Error parsing time:", err)
			badExpire = append(badExpire, k.ExpireOn)
		}
		return true
	}
	return t.Before(time.Now())
}

// newPwd will generate a random password that meets Windows complexity
// requirements: https://technet.microsoft.com/en-us/library/cc786468.
// Characters that are difficult for users to type on a command line (quotes,
// non english characters) are not used.
func newPwd() (string, error) {
	pwLgth := 15
	lower := []byte("abcdefghijklmnopqrstuvwxyz")
	upper := []byte("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	numbers := []byte("0123456789")
	special := []byte(`~!@#$%^&*_-+=|\(){}[]:;<>,.?/`)
	chars := bytes.Join([][]byte{lower, upper, numbers, special}, nil)

	for {
		b := make([]byte, pwLgth)
		for i := range b {
			ci, err := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
			if err != nil {
				return "", err
			}
			b[i] = chars[ci.Int64()]
		}

		var l, u, n, s int
		if bytes.ContainsAny(lower, string(b)) {
			l = 1
		}
		if bytes.ContainsAny(upper, string(b)) {
			u = 1
		}
		if bytes.ContainsAny(numbers, string(b)) {
			n = 1
		}
		if bytes.ContainsAny(special, string(b)) {
			s = 1
		}
		// If the password does not meet Windows complexity requirements, try again.
		// https://technet.microsoft.com/en-us/library/cc786468
		if l+u+n+s >= 3 {
			return string(b), nil
		}
	}
}

func (k windowsKeyJSON) createOrResetPwd() (*credsJSON, error) {
	pwd, err := newPwd()
	if err != nil {
		return nil, fmt.Errorf("error creating password: %v", err)
	}
	if _, err := user.Lookup(k.UserName); err == nil {
		logger.Infoln("Resetting password for user", k.UserName)
		if err := resetPwd(k.UserName, pwd); err != nil {
			return nil, fmt.Errorf("error running resetPwd: %v", err)
		}
	} else {
		logger.Infoln("Creating user", k.UserName)
		if err := createAdminUser(k.UserName, pwd); err != nil {
			return nil, fmt.Errorf("error running createUser: %v", err)
		}
	}

	return createcredsJSON(k, pwd)
}

func createcredsJSON(k windowsKeyJSON, pwd string) (*credsJSON, error) {
	mod, err := base64.StdEncoding.DecodeString(k.Modulus)
	if err != nil {
		return nil, fmt.Errorf("error decoding modulus: %v", err)
	}
	exp, err := base64.StdEncoding.DecodeString(k.Exponent)
	if err != nil {
		return nil, fmt.Errorf("error decoding exponent: %v", err)
	}

	key := &rsa.PublicKey{
		N: new(big.Int).SetBytes(mod),
		E: int(new(big.Int).SetBytes(exp).Int64()),
	}

	encPwd, err := rsa.EncryptOAEP(sha1.New(), rand.Reader, key, []byte(pwd), nil)
	if err != nil {
		return nil, fmt.Errorf("error encrypting password: %v", err)
	}

	return &credsJSON{
		PasswordFound:     true,
		Exponent:          k.Exponent,
		Modulus:           k.Modulus,
		UserName:          k.UserName,
		EncryptedPassword: base64.StdEncoding.EncodeToString(encPwd),
	}, nil
}

type accounts struct {
	newMetadata, oldMetadata *metadataJSON
	config                   *ini.File
}

func (a *accounts) diff() bool {
	return !reflect.DeepEqual(a.newMetadata.Instance.Attributes.WindowsKeys, a.oldMetadata.Instance.Attributes.WindowsKeys)
}

func (a *accounts) disabled() (disabled bool) {
	defer func() {
		if disabled != accountDisabled {
			accountDisabled = disabled
			logStatus("account", disabled)
		}
	}()

	var err error
	disabled, err = strconv.ParseBool(a.config.Section("accountManager").Key("disable").String())
	if err == nil {
		return disabled
	}
	disabled, err = strconv.ParseBool(a.newMetadata.Instance.Attributes.DisableAccountManager)
	if err == nil {
		return disabled
	}
	disabled, err = strconv.ParseBool(a.newMetadata.Project.Attributes.DisableAccountManager)
	if err == nil {
		return disabled
	}
	return accountDisabled
}

type credsJSON struct {
	ErrorMessage      string `json:"errorMessage,omitempty"`
	EncryptedPassword string `json:"encryptedPassword,omitempty"`
	UserName          string `json:"userName,omitempty"`
	PasswordFound     bool   `json:"passwordFound,omitempty"`
	Exponent          string `json:"exponent,omitempty"`
	Modulus           string `json:"modulus,omitempty"`
}

func (a *accounts) parseSerialPort() string {
	port := a.config.Section("accountManager").Key("serialPort").String()
	if len(port) > 0 {
		return port
	}
	return "COM4"
}

func (a *accounts) printCreds(creds *credsJSON) error {
	data, err := json.Marshal(creds)
	if err != nil {
		return err
	}
	return writeSerial(a.parseSerialPort(), append(data, []byte("\n")...))
}

var badReg []string

func compareAccounts(newKeys []windowsKeyJSON, oldStrKeys []string) []windowsKeyJSON {
	if len(newKeys) == 0 {
		return nil
	}
	if len(oldStrKeys) == 0 {
		return newKeys
	}

	var oldKeys []windowsKeyJSON
	for _, s := range oldStrKeys {
		var key windowsKeyJSON
		if err := json.Unmarshal([]byte(s), &key); err != nil {
			if !containsString(s, badReg) {
				logger.Error(err)
				badReg = append(badReg, s)
			}
			continue
		}
		oldKeys = append(oldKeys, key)
	}

	var toAdd []windowsKeyJSON
	for _, key := range newKeys {
		if func(key windowsKeyJSON, oldKeys []windowsKeyJSON) bool {
			for _, oldKey := range oldKeys {
				if reflect.DeepEqual(oldKey, key) {
					return false
				}
			}
			return true
		}(key, oldKeys) {
			toAdd = append(toAdd, key)
		}
	}
	return toAdd
}

var badKeys []string

func (a *accounts) set() error {
	var newKeys []windowsKeyJSON
	for _, s := range strings.Split(a.newMetadata.Instance.Attributes.WindowsKeys, "\n") {
		var key windowsKeyJSON
		if err := json.Unmarshal([]byte(s), &key); err != nil {
			if !containsString(s, badKeys) {
				logger.Error(err)
				badKeys = append(badKeys, s)
			}
			continue
		}
		if key.Exponent != "" && key.Modulus != "" && key.UserName != "" && !key.expired() {
			newKeys = append(newKeys, key)
		}
	}

	regKeys, err := readRegMultiString(regKeyBase, regName)
	if err != nil && err != errRegNotExist {
		return err
	}

	toAdd := compareAccounts(newKeys, regKeys)

	for _, key := range toAdd {
		creds, err := key.createOrResetPwd()
		if err == nil {
			a.printCreds(creds)
			continue
		}
		logger.Error(err)
		creds = &credsJSON{
			PasswordFound: false,
			Exponent:      key.Exponent,
			Modulus:       key.Modulus,
			UserName:      key.UserName,
			ErrorMessage:  err.Error(),
		}
		a.printCreds(creds)
	}

	var jsonKeys []string
	for _, key := range newKeys {
		jsn, err := json.Marshal(key)
		if err != nil {
			// This *should* never happen as each key was just Unmarshalled above.
			logger.Error(err)
			continue
		}
		jsonKeys = append(jsonKeys, string(jsn))
	}
	return writeRegMultiString(regKeyBase, regName, jsonKeys)
}
