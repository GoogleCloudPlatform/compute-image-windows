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

// GCEMetadataScripts handles the running of metadata scripts on Google Compute
// Engine Windows instances.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"time"

	"cloud.google.com/go/storage"
	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
)

var (
	metadataServer = "http://metadata.google.internal/computeMetadata/v1/instance/attributes"
	metadataHang   = "/?recursive=true&alt=json&timeout_sec=10&last_etag=NONE"
	defaultTimeout = 20 * time.Second
	commands       = []string{"specialize", "startup", "shutdown"}
	scripts        = map[metadataScriptType]string{
		ps1: "%s-script-ps1",
		cmd: "%s-script-cmd",
		bat: "%s-script-bat",
		url: "%s-script-url",
	}
)

const (
	ps1 metadataScriptType = iota
	cmd
	bat
	url
)

type metadataScriptType int
type metadataScript struct {
	Type             metadataScriptType
	Script, Metadata string
}

func (ms *metadataScript) run(ctx context.Context) error {
	sType := ms.Metadata[len(ms.Metadata)-3 : len(ms.Metadata)]
	switch ms.Type {
	case ps1:
		return runPs1(ms)
	case cmd:
		return runBat(ms)
	case bat:
		return runBat(ms)
	case url:
		var st metadataScriptType
		switch sType {
		case "ps1":
			st = ps1
		case "cmd":
			st = cmd
		case "bat":
			st = bat
		default:
			return fmt.Errorf("error getting script type from url path, unknown script type: %q", ms.Metadata)
		}
		script, err := downloadScript(ctx, ms.Script)
		if err != nil {
			return err
		}
		ms = &metadataScript{st, script, ms.Metadata}
		return ms.run(ctx)
	default:
		return fmt.Errorf("unknown script type: %s", sType)
	}
}

func getMetadata() (map[string]string, error) {
	client := &http.Client{
		Timeout: defaultTimeout,
	}

	req, err := http.NewRequest("GET", metadataServer+metadataHang, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Add("Metadata-Flavor", "Google")

	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}

	md, err := ioutil.ReadAll(resp.Body)
	resp.Body.Close()
	if err != nil {
		return nil, err
	}
	var att map[string]string
	return att, json.Unmarshal(md, &att)
}

func validateArgs(args []string) (map[metadataScriptType]string, error) {
	if len(args) != 2 {
		return nil, fmt.Errorf("No valid arguments specified. Options: %s", commands)
	}
	for _, command := range commands {
		if command == args[1] {
			mdsm := map[metadataScriptType]string{}
			if command == "specialize" {
				command = "sysprep-" + command
			} else {
				command = "windows-" + command
			}
			for st, script := range scripts {
				mdsm[st] = fmt.Sprintf(script, command)
			}
			return mdsm, nil
		}
	}
	return nil, fmt.Errorf("No valid arguments specified. Options: %s", commands)
}

func parseMetadata(mdsm map[metadataScriptType]string, md map[string]string) []metadataScript {
	var mdss []metadataScript
	// Sort so we run scripts in order.
	var keys []int
	for k := range mdsm {
		keys = append(keys, int(k))
	}
	sort.Ints(keys)
	for _, k := range keys {
		st := metadataScriptType(k)
		name := mdsm[st]
		script, ok := md[name]
		if !ok || script == "" {
			continue
		}
		mdss = append(mdss, metadataScript{st, script, name})
	}
	return mdss
}

func getScripts(mdsm map[metadataScriptType]string) ([]metadataScript, error) {
	md, err := getMetadata()
	if err != nil {
		return nil, err
	}
	return parseMetadata(mdsm, md), nil
}

func tempFile(name, content string) (string, error) {
	dir, err := ioutil.TempDir("", "metadata-scripts")
	if err != nil {
		return "", err
	}

	tmpFile := filepath.Join(dir, name)
	return tmpFile, ioutil.WriteFile(tmpFile, []byte(content), 0666)
}

func runCmd(c *exec.Cmd, name string) error {
	pr, pw, err := os.Pipe()
	if err != nil {
		return err
	}
	defer pr.Close()

	c.Stdout = pw
	c.Stderr = pw

	if err := c.Start(); err != nil {
		return err
	}
	pw.Close()

	in := bufio.NewScanner(pr)
	for in.Scan() {
		logger.Log.Output(3, name+": "+in.Text())
	}

	return c.Wait()
}

func runBat(ms *metadataScript) error {
	tmpFile, err := tempFile(ms.Metadata+".bat", ms.Script)
	if err != nil {
		return err
	}
	defer os.RemoveAll(filepath.Dir(tmpFile))

	return runCmd(exec.Command(tmpFile), ms.Metadata)
}

func runPs1(ms *metadataScript) error {
	tmpFile, err := tempFile(ms.Metadata+".ps1", ms.Script)
	if err != nil {
		return err
	}
	defer os.RemoveAll(filepath.Dir(tmpFile))

	c := exec.Command("powershell.exe", "-NoProfile", "-NoLogo", "-ExecutionPolicy", "Unrestricted", "-File", tmpFile)
	return runCmd(c, ms.Metadata)
}

func downloadGSURL(ctx context.Context, bucket, object string) (string, error) {
	client, err := storage.NewClient(ctx)
	if err != nil {
		return "", fmt.Errorf("failed to create client: %v", err)
	}
	defer client.Close()

	bkt := client.Bucket(bucket)
	obj := bkt.Object(object)
	r, err := obj.NewReader(ctx)
	if err != nil {
		return "", err
	}
	defer r.Close()

	var buf bytes.Buffer
	if _, err := buf.ReadFrom(r); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func downloadURL(p string) (string, error) {
	res, err := http.Get(p)
	if err != nil {
		return "", err
	}
	data, err := ioutil.ReadAll(res.Body)
	res.Body.Close()
	if err != nil {
		return "", err
	}
	return string(data), nil
}

var (
	bucket = `([a-z0-9][-_.a-z0-9]*)`
	object = `(.+)`
	// Many of the Google Storage URLs are supported below.
	// It is preferred that customers specify their object using
	// its gs://<bucket>/<object> URL.
	gsRegex = regexp.MustCompile(fmt.Sprintf(`gs://%s/%s`, bucket, object))
	// Check for the Google Storage URLs:
	// http://<bucket>.storage.googleapis.com/<object>
	// https://<bucket>.storage.googleapis.com/<object>
	urlRegex = regexp.MustCompile(fmt.Sprintf(`http[s]?://%s\.storage\.googleapis\.com/%s`, bucket, object))
	// Check for the other possible Google Storage URLs:
	// http://storage.googleapis.com/<bucket>/<object>
	// https://storage.googleapis.com/<bucket>/<object>
	//
	// The following are deprecated but checked:
	// http://commondatastorage.googleapis.com/<bucket>/<object>
	// https://commondatastorage.googleapis.com/<bucket>/<object>
	url2Regex = regexp.MustCompile(fmt.Sprintf(`http[s]?://(?:commondata)?storage\.googleapis\.com/%s/%s`, bucket, object))
)

func findMatch(path string) (string, string) {
	for _, re := range []*regexp.Regexp{gsRegex, urlRegex, url2Regex} {
		match := re.FindStringSubmatch(path)
		if len(match) == 3 {
			return match[1], match[2]
		}
	}
	return "", ""
}

func downloadScript(ctx context.Context, path string) (string, error) {
	bucket, object := findMatch(path)
	if bucket != "" && object != "" {
		return downloadGSURL(ctx, bucket, object)
	}

	// Fall back to unauthenticated download of the object.
	return downloadURL(path)
}

func runScripts(ctx context.Context, scripts []metadataScript) {
	for _, script := range scripts {
		logger.Infoln("Found", script.Metadata, "in metadata.")
		err := script.run(ctx)
		if _, ok := err.(*exec.ExitError); ok {
			logger.Infoln(script.Metadata, err)
			continue
		}
		if err == nil {
			logger.Infoln(script.Metadata, "exit status 0")
			continue
		}
		logger.Error(err)
	}
}

func main() {
	logger.Init("GCEMetadataScripts", "COM1")
	metadata, err := validateArgs(os.Args)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	logger.Infof("Starting %s scripts.", os.Args[1])

	scripts, err := getScripts(metadata)
	if err != nil {
		fmt.Println(err)
		logger.Fatal(err)
	}

	if len(scripts) == 0 {
		logger.Infof("No %s scripts to run.", os.Args[1])
		os.Exit(0)
	}

	ctx := context.Background()
	runScripts(ctx, scripts)
	logger.Infof("Finished running %s scripts.", os.Args[1])
}
