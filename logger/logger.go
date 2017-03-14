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

// Package logger offers simple logging on GCE.
package logger

import (
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime"

	"github.com/tarm/serial"
)

var (
	// Log is the logger's log.Logger.
	Log         *log.Logger
	initialized bool
	logger      string
)

type serialPort struct {
	Port string
}

func (s *serialPort) Write(b []byte) (int, error) {
	c := &serial.Config{Name: s.Port, Baud: 115200}
	p, err := serial.OpenPort(c)
	if err != nil {
		return 0, err
	}
	defer p.Close()

	return p.Write(b)
}

// Init sets up logging and should be called before log functions, usually in
// the callers main(). Log functions can be called before Init(), but log
// output will go to COM1.
func Init(name, port string) {
	logger = name
	out := &serialPort{port}
	Log = log.New(out, "", log.Ldate|log.Ltime)
	initialized = true
}

type severity int

const (
	sInfo = iota
	sError
	sFatal
)

func caller() string {
	_, file, line, ok := runtime.Caller(3)
	if !ok {
		file = "???"
		line = 0
	}
	return fmt.Sprintf("%s:%d", filepath.Base(file), line)
}

func output(s severity, txt string) {
	if !initialized {
		Init("logger", "COM1")
	}

	switch s {
	case sInfo:
		Log.Output(3, fmt.Sprintf("%s: %s", logger, txt))
	case sError:
		Log.Output(3, fmt.Sprintf("%s: ERROR %s: %s", logger, caller(), txt))
	case sFatal:
		Log.Output(3, fmt.Sprintf("%s: FATAL %s: %s", logger, caller(), txt))
	default:
		panic(fmt.Sprintln("unrecognized severity:", s))
	}
}

// Info logs with the INFO severity.
// Arguments are handled in the manner of fmt.Print.
func Info(v ...interface{}) {
	output(sInfo, fmt.Sprint(v...))
}

// Infoln logs with the INFO severity.
// Arguments are handled in the manner of fmt.Println.
func Infoln(v ...interface{}) {
	output(sInfo, fmt.Sprintln(v...))
}

// Infof logs with the INFO severity.
// Arguments are handled in the manner of fmt.Printf.
func Infof(format string, v ...interface{}) {
	output(sInfo, fmt.Sprintf(format, v...))
}

// Error logs with the ERROR severity.
// Arguments are handled in the manner of fmt.Print.
func Error(v ...interface{}) {
	output(sError, fmt.Sprint(v...))
}

// Errorln logs with the ERROR severity.
// Arguments are handled in the manner of fmt.Println.
func Errorln(v ...interface{}) {
	output(sError, fmt.Sprintln(v...))
}

// Errorf logs with the Error severity.
// Arguments are handled in the manner of fmt.Printf.
func Errorf(format string, v ...interface{}) {
	output(sError, fmt.Sprintf(format, v...))
}

// Fatal logs with the Fatal severity, and ends with os.Exit(1).
// Arguments are handled in the manner of fmt.Print.
func Fatal(v ...interface{}) {
	output(sFatal, fmt.Sprint(v...))
	os.Exit(1)
}

// Fatalln logs with the Fatal severity, and ends with os.Exit(1).
// Arguments are handled in the manner of fmt.Println.
func Fatalln(v ...interface{}) {
	output(sFatal, fmt.Sprintln(v...))
	os.Exit(1)
}

// Fatalf logs with the Fatal severity, and ends with os.Exit(1).
// Arguments are handled in the manner of fmt.Printf.
func Fatalf(format string, v ...interface{}) {
	output(sFatal, fmt.Sprintf(format, v...))
	os.Exit(1)
}
