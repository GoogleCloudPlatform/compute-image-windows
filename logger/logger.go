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
// Events are logged to the serial console as well as the event log.
package logger

import (
	"fmt"
	"log"
	"path/filepath"
	"runtime"
	"strings"

	"github.com/tarm/serial"
	"golang.org/x/sys/windows/svc/eventlog"
)

var (
	// Log is the serial logger's log.Logger.
	Log         *log.Logger
	slInfo      *log.Logger
	slError     *log.Logger
	slFatal     *log.Logger
	initialized bool
	logger      string
)

// Init sets up logging and should be called before log functions, usually in
// the callers main(). Log functions can be called before Init(), but log
// output will go to COM1.
func Init(name, port string) {
	logger = name
	out := &serialPort{port}
	// Split logging to the serial port and event log so processes like the
	// metadata script runnner can log to serial output but not the event log.
	Log = log.New(out, "", log.Ldate|log.Ltime)
	if err := slSetup(name); err != nil {
		log.Fatal(err)
	}
	initialized = true
}

type severity int

const (
	sInfo = iota
	sError
	sFatal
)

type writer struct {
	pri severity
	src string
	el  *eventlog.Log
}

// Write sends a log message to the Event Log.
func (w *writer) Write(b []byte) (int, error) {
	switch w.pri {
	case sInfo:
		return len(b), w.el.Info(1, string(b))
	case sError:
		return len(b), w.el.Error(2, string(b))
	}
	return 0, fmt.Errorf("unrecognized severity: %v", w.pri)
}

func newW(pri severity, src string) (*writer, error) {
	if err := eventlog.InstallAsEventCreate(src, eventlog.Info|eventlog.Error); err != nil {
		if !strings.Contains(err.Error(), "registry key already exists") {
			return nil, err
		}
	}
	el, err := eventlog.Open(src)
	if err != nil {
		return nil, err
	}
	return &writer{
		pri: pri,
		src: src,
		el:  el,
	}, nil
}

func slSetup(src string) error {
	flags := log.Ldate | log.Lmicroseconds | log.Lshortfile
	infoL, err := newW(sInfo, src)
	if err != nil {
		return err
	}
	slInfo = log.New(infoL, "INFO: ", flags)
	errL, err := newW(sError, src)
	if err != nil {
		return err
	}
	slError = log.New(errL, "ERROR: ", flags)
	slFatal = log.New(errL, "FATAL: ", flags)
	return nil
}

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
		msg := fmt.Sprintf("%s: %s", logger, txt)
		Log.Output(3, msg)
		slInfo.Output(3, msg)
	case sError:
		msg := fmt.Sprintf("%s: ERROR %s: %s", logger, caller(), txt)
		Log.Output(3, msg)
		slError.Output(3, msg)
	case sFatal:
		msg := fmt.Sprintf("%s: FATAL %s: %s", logger, caller(), txt)
		Log.Output(3, msg)
		slFatal.Output(3, msg)
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
}

// Fatalln logs with the Fatal severity, and ends with os.Exit(1).
// Arguments are handled in the manner of fmt.Println.
func Fatalln(v ...interface{}) {
	output(sFatal, fmt.Sprintln(v...))
}

// Fatalf logs with the Fatal severity, and ends with os.Exit(1).
// Arguments are handled in the manner of fmt.Printf.
func Fatalf(format string, v ...interface{}) {
	output(sFatal, fmt.Sprintf(format, v...))
}
