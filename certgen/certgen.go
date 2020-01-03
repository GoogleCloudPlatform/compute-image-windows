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

// Generate a self-signed X.509 certificate in PKCS#12 format.
package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"time"

	"github.com/mitchellh/packer/builder/azure/pkcs12"
)

var (
	validFor = flag.Duration("duration", 365*24*time.Hour, "Duration that certificate is valid for")
	outDir   = flag.String("outDir", "", "Directory to create the cert file in.")
	hostname = flag.String("hostname", "", "Hostname to use for the self signed cert.")
)

func main() {
	flag.Parse()

	var hn string
	var err error
	if *hostname != "" {
		hn = *hostname
	} else {
		hn, err = os.Hostname()
		if err != nil {
			log.Fatal(err)
		}
	}

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		log.Fatalf("failed to generate private key: %s", err)
	}

	notBefore := time.Now()
	notAfter := notBefore.Add(*validFor)

	serialNumberLimit := new(big.Int).Lsh(big.NewInt(1), 128)
	serialNumber, err := rand.Int(rand.Reader, serialNumberLimit)
	if err != nil {
		log.Fatalf("failed to generate serial number: %s", err)
	}

	template := x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			CommonName: hn,
		},
		NotBefore: notBefore,
		NotAfter:  notAfter,

		DNSNames:              []string{hn},
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
	}

	derBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &priv.PublicKey, priv)
	if err != nil {
		log.Fatalf("Failed to create certificate: %s", err)
	}

	p12, err := pkcs12.Encode(derBytes, priv, "")
	if err != nil {
		log.Fatal(err)
	}

	out := filepath.Join(*outDir, "cert.p12")
	if err := ioutil.WriteFile(out, p12, 0600); err != nil {
		log.Fatalf("failed to open cert.p12 for writing: %s", err)
	}
	fmt.Println("written", out)
}
