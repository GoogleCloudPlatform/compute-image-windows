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
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"encoding/base64"
	"math/big"
	"reflect"
	"testing"
	"time"
	"unicode"
)

func TestExpired(t *testing.T) {
	var tests = []struct {
		sTime string
		e     bool
	}{
		{time.Now().Add(5 * time.Minute).Format(time.RFC3339), false},
		{time.Now().Add(-5 * time.Minute).Format(time.RFC3339), true},
		{"some bad time", true},
	}

	for _, tt := range tests {
		k := windowsKeyJSON{ExpireOn: tt.sTime}
		if tt.e != k.expired() {
			t.Errorf("windowsKeyJSON.expired() with ExpiredOn %q should return %t", k.ExpireOn, tt.e)
		}
	}
}

func TestNewPwd(t *testing.T) {
	for i := 0; i < 1000; i++ {
		pwd, err := newPwd()
		if err != nil {
			t.Fatal(err)
		}
		if len(pwd) != 15 {
			t.Fatalf("Password is not 15 characters: len(%s)=%d", pwd, len(pwd))
		}
		var l, u, n, s bool
		for _, r := range pwd {
			switch {
			case unicode.IsLower(r):
				l = true
			case unicode.IsUpper(r):
				u = true
			case unicode.IsDigit(r):
				n = true
			case unicode.IsPunct(r) || unicode.IsSymbol(r):
				s = true
			}
		}
		if !l || !u || !n || !s {
			t.Fatalf("Password does not have at least one character from each category: %s", pwd)
		}
	}
}

func TestCreatecredsJSON(t *testing.T) {
	pwd := "password"
	prv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("error generating key: %v", err)
	}
	k := windowsKeyJSON{
		Email:    "email",
		ExpireOn: "expire",
		Exponent: base64.StdEncoding.EncodeToString(new(big.Int).SetInt64(int64(prv.PublicKey.E)).Bytes()),
		Modulus:  base64.StdEncoding.EncodeToString(prv.PublicKey.N.Bytes()),
		UserName: "username",
	}

	c, err := createcredsJSON(k, pwd)
	if err != nil {
		t.Fatalf("error running createcredsJSON: %v", err)
	}

	bPwd, err := base64.StdEncoding.DecodeString(c.EncryptedPassword)
	if err != nil {
		t.Fatalf("error base64 decoding encoded pwd: %v", err)
	}
	decPwd, err := rsa.DecryptOAEP(sha1.New(), rand.Reader, prv, bPwd, nil)
	if err != nil {
		t.Fatalf("error decrypting password: %v", err)
	}
	if pwd != string(decPwd) {
		t.Errorf("decrypted password does not match expected, got: %s, want: %s", string(decPwd), pwd)
	}
	if k.UserName != c.UserName {
		t.Errorf("returned credsJSON UserName field unexpected, got: %s, want: %s", c.UserName, k.UserName)
	}
	if !c.PasswordFound {
		t.Error("returned credsJSON PasswordFound field is not true")
	}
}

func TestCompareAccounts(t *testing.T) {
	var tests = []struct {
		newKeys    []windowsKeyJSON
		oldStrKeys []string
		wantAdd    []windowsKeyJSON
	}{
		// These should return toAdd:
		// In MD, not Reg
		{[]windowsKeyJSON{windowsKeyJSON{UserName: "foo"}}, nil, []windowsKeyJSON{windowsKeyJSON{UserName: "foo"}}},
		{[]windowsKeyJSON{windowsKeyJSON{UserName: "foo"}}, []string{`{"UserName":"bar"}`}, []windowsKeyJSON{windowsKeyJSON{UserName: "foo"}}},

		// These should return nothing:
		// In Reg and Md
		{[]windowsKeyJSON{windowsKeyJSON{UserName: "foo"}}, []string{`{"UserName":"foo"}`}, nil},
		// In Md, not Reg
		{nil, []string{`{UserName":"foo"}`}, nil},
	}

	for _, tt := range tests {
		toAdd := compareAccounts(tt.newKeys, tt.oldStrKeys)
		if !reflect.DeepEqual(tt.wantAdd, toAdd) {
			t.Errorf("toAdd does not match expected: newKeys: %q, oldStrKeys: %q, got: %q, want: %q", tt.newKeys, tt.oldStrKeys, toAdd, tt.wantAdd)
		}
	}
}
