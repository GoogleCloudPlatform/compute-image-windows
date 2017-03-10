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
	"strings"
	"time"

	"../logger"
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

func newPwd() (string, error) {
	// 15 character password with a max of 4 characters from each category.
	pwLgth, limit := 15, 4
	lower := []byte("abcdefghijklmnopqrstuvwxyz")
	upper := []byte("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
	numbers := []byte("0123456789")
	special := []byte(`~!@#$%^&*_-+=|\(){}[]:;<>,.?/`)
	chars := bytes.Join([][]byte{lower, upper, numbers, special}, nil)

	r := make([]byte, len(chars))
	if _, err := rand.Read(r); err != nil {
		return "", err
	}

	var i, l, u, n, s int
	b := make([]byte, pwLgth)
	for _, rb := range r {
		c := chars[int(rb)%len(chars)]
		switch {
		case bytes.Contains(lower, []byte{c}):
			if l >= limit {
				continue
			}
			l++
		case bytes.Contains(upper, []byte{c}):
			if u >= limit {
				continue
			}
			u++
		case bytes.Contains(numbers, []byte{c}):
			if n >= limit {
				continue
			}
			n++
		case bytes.Contains(special, []byte{c}):
			if s >= limit {
				continue
			}
			s++
		}
		b[i] = c
		i++
		if i == pwLgth {
			break
		}
	}
	return string(b), nil
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
}

func (a *accounts) diff() bool {
	return !reflect.DeepEqual(a.newMetadata.Instance.Attributes.WindowsKeys, a.oldMetadata.Instance.Attributes.WindowsKeys)
}

func (a *accounts) disabled() bool {
	d := a.newMetadata.Instance.Attributes.DisableAccountManager
	if d != accountDisabled {
		accountDisabled = d
		logStatus("account", d)
	}

	return d
}

type credsJSON struct {
	ErrorMessage      string `JSON:"errorMessage,omitempty"`
	EncryptedPassword string `JSON:"encryptedPassword,omitempty"`
	UserName          string `JSON:"userName,omitempty"`
	PasswordFound     bool   `JSON:"passwordFound,omitempty"`
	Exponent          string `JSON:"exponent,omitempty"`
	Modulus           string `JSON:"modulus,omitempty"`
}

func printCreds(creds *credsJSON) error {
	data, err := json.Marshal(creds)
	if err != nil {
		return err
	}
	return writeSerial("COM4", append(data, []byte("\n")...))
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
			if !containsString(s, badReg) {
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
			printCreds(creds)
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
		printCreds(creds)
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
