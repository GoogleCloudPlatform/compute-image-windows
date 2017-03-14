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

// WriteToSerial is a simple serial port writer.
package main

import (
	"log"
	"os"

	"github.com/tarm/serial"
)

func writeSerial(port string, msg []byte) error {
	c := &serial.Config{Name: port, Baud: 115200}
	s, err := serial.OpenPort(c)
	if err != nil {
		return err
	}
	defer s.Close()

	_, err = s.Write(msg)
	return err
}

func main() {
	if err := writeSerial(os.Args[1], []byte(os.Args[2])); err != nil {
		log.Fatal(err)
	}
}
