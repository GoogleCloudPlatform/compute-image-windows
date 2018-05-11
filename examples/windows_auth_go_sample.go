//  Copyright 2018 Google Inc. All Rights Reserved.
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
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"log"
	"strings"
	"time"

	daisyCompute "github.com/GoogleCloudPlatform/compute-image-tools/daisy/compute"
	"google.golang.org/api/compute/v1"
)

var (
	instance = flag.String("instance", "", "instance to reset password on")
	zone     = flag.String("zone", "", "zone instance is in")
	project  = flag.String("project", "", "project instance is in")
	user     = flag.String("user", "", "user to reset password for")
)

func getInstanceMetadata(client daisyCompute.Client, i, z, p string) (*compute.Metadata, error) {
	ins, err := client.GetInstance(p, z, i)
	if err != nil {
		return nil, fmt.Errorf("error getting instance: %v", err)
	}

	return ins.Metadata, nil
}

type windowsKeyJSON struct {
	ExpireOn string
	Exponent string
	Modulus  string
	UserName string
}

func generateKey(priv *rsa.PublicKey, u string) (*windowsKeyJSON, error) {
	bs := make([]byte, 4)
	binary.BigEndian.PutUint32(bs, uint32(priv.E))

	return &windowsKeyJSON{
		ExpireOn: time.Now().Add(5 * time.Minute).Format(time.RFC3339),
		Exponent: base64.StdEncoding.EncodeToString(bs),
		Modulus:  base64.StdEncoding.EncodeToString(priv.N.Bytes()),
		UserName: u,
	}, nil
}

type credsJSON struct {
	ErrorMessage      string `json:"errorMessage,omitempty"`
	EncryptedPassword string `json:"encryptedPassword,omitempty"`
	Modulus           string `json:"modulus,omitempty"`
}

func getEncryptedPassword(client daisyCompute.Client, i, z, p, mod string) (string, error) {
	out, err := client.GetSerialPortOutput(p, z, i, 4, 0)
	if err != nil {
		return "", err
	}

	for _, line := range strings.Split(out.Contents, "\n") {
		var creds credsJSON
		if err := json.Unmarshal([]byte(line), &creds); err != nil {
			continue
		}
		if creds.Modulus == mod {
			if creds.ErrorMessage != "" {
				return "", fmt.Errorf("error from agent: %s", creds.ErrorMessage)
			}
			return creds.EncryptedPassword, nil
		}
	}
	return "", errors.New("password not found in serial output")
}

func decryptPassword(priv *rsa.PrivateKey, ep string) (string, error) {
	bp, err := base64.StdEncoding.DecodeString(ep)
	if err != nil {
		return "", fmt.Errorf("error decoding password: %v", err)
	}
	pwd, err := rsa.DecryptOAEP(sha1.New(), rand.Reader, priv, bp, nil)
	if err != nil {
		return "", fmt.Errorf("error decrypting password: %v", err)
	}
	return string(pwd), nil
}

func resetPassword(client daisyCompute.Client, i, z, p, u string) (string, error) {
	md, err := getInstanceMetadata(client, *instance, *zone, *project)
	if err != nil {
		return "", fmt.Errorf("error getting instance metadata: %v", err)
	}

	fmt.Println("Generating public/private key pair")
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return "", err
	}

	winKey, err := generateKey(&key.PublicKey, u)
	if err != nil {
		return "", err
	}

	data, err := json.Marshal(winKey)
	if err != nil {
		return "", err
	}

	winKeys := string(data)
	var found bool
	for _, mdi := range md.Items {
		if mdi.Key == "windows-keys" {
			val := fmt.Sprintf("%s\n%s", *mdi.Value, winKeys)
			mdi.Value = &val
			found = true
			break
		}
	}
	if !found {
		md.Items = append(md.Items, &compute.MetadataItems{Key: "windows-keys", Value: &winKeys})
	}

	fmt.Println("Setting new 'windows-keys' metadata")
	if err := client.SetInstanceMetadata(p, z, i, md); err != nil {
		return "", err
	}

	fmt.Println("Fetching encrypted password")
	var trys int
	var ep string
	for {
		time.Sleep(1 * time.Second)
		ep, err = getEncryptedPassword(client, i, z, p, winKey.Modulus)
		if err == nil {
			break
		}
		if trys > 10 {
			return "", err
		}
		trys++
	}

	fmt.Println("Decrypting password")
	return decryptPassword(key, ep)
}

func main() {
	flag.Parse()
	if *instance == "" {
		log.Fatal("-instance flag required")
	}
	if *zone == "" {
		log.Fatal("-zone flag required")
	}
	if *project == "" {
		log.Fatal("-project flag required")
	}
	if *user == "" {
		log.Fatal("-user flag required")
	}

	ctx := context.Background()
	client, err := daisyCompute.NewClient(ctx)
	if err != nil {
		log.Fatalf("Error creating compute service: %v", err)
	}

	fmt.Printf("Resetting password on instance %q for user %q\n", *instance, *user)
	pw, err := resetPassword(client, *instance, *zone, *project, *user)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Printf("- Username: %s\n- Password: %s\n", *user, pw)
}
