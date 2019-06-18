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
	"bufio"
	"bytes"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha1"
	"crypto/sha256"
	"crypto/sha512"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"hash"
	"io/ioutil"
	"math/big"
	"os"
	"os/exec"
	"os/user"
	"path"
	"reflect"
	"strconv"
	"strings"
	"time"

	"github.com/GoogleCloudPlatform/guest-logging-go/logger"
)

var (
	accountRegKey   = "PublicKeys"
	accountDisabled = false
)

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

type credsJSON struct {
	ErrorMessage      string `json:"errorMessage,omitempty"`
	EncryptedPassword string `json:"encryptedPassword,omitempty"`
	UserName          string `json:"userName,omitempty"`
	PasswordFound     bool   `json:"passwordFound,omitempty"`
	Exponent          string `json:"exponent,omitempty"`
	Modulus           string `json:"modulus,omitempty"`
	HashFunction      string `json:"hashFunction,omitempty"`
}

func printCreds(creds *credsJSON) error {
	data, err := json.Marshal(creds)
	if err != nil {
		return err
	}
	return writeSerial("COM4", append(data, []byte("\n")...))
}

var badExpire []string

func (k windowsKey) expired() bool {
	t, err := time.Parse(time.RFC3339, k.ExpireOn)
	if err != nil {
		if !containsString(k.ExpireOn, badExpire) {
			logger.Errorf("Error parsing time: %s", err)
			badExpire = append(badExpire, k.ExpireOn)
		}
		return true
	}
	return t.Before(time.Now())
}

func (k windowsKey) createOrResetPwd() (*credsJSON, error) {
	pwd, err := newPwd()
	if err != nil {
		return nil, fmt.Errorf("error creating password: %v", err)
	}
	if _, err := userExists(k.UserName); err == nil {
		logger.Infof("Resetting password for user %s", k.UserName)
		if err := resetPwd(k.UserName, pwd); err != nil {
			return nil, fmt.Errorf("error running resetPwd: %v", err)
		}
	} else {
		logger.Infof("Creating user %s", k.UserName)
		if err := createAdminUser(k.UserName, pwd); err != nil {
			return nil, fmt.Errorf("error running createAdminUser: %v", err)
		}
	}

	return createcredsJSON(k, pwd)
}

func createcredsJSON(k windowsKey, pwd string) (*credsJSON, error) {
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

	if k.HashFunction == "" {
		k.HashFunction = "sha1"
	}

	var hashFunc hash.Hash
	switch k.HashFunction {
	case "sha1":
		hashFunc = sha1.New()
	case "sha256":
		hashFunc = sha256.New()
	case "sha512":
		hashFunc = sha512.New()
	default:
		return nil, fmt.Errorf("unknown hash function requested: %q", k.HashFunction)
	}

	encPwd, err := rsa.EncryptOAEP(hashFunc, rand.Reader, key, []byte(pwd), nil)
	if err != nil {
		return nil, fmt.Errorf("error encrypting password: %v", err)
	}

	return &credsJSON{
		PasswordFound:     true,
		Exponent:          k.Exponent,
		Modulus:           k.Modulus,
		UserName:          k.UserName,
		HashFunction:      k.HashFunction,
		EncryptedPassword: base64.StdEncoding.EncodeToString(encPwd),
	}, nil
}

type winAccountsMgr struct{}

func (a *winAccountsMgr) diff() bool {
	return !reflect.DeepEqual(newMetadata.Instance.Attributes.WindowsKeys, oldMetadata.Instance.Attributes.WindowsKeys)
}

func (a *winAccountsMgr) timeout() bool {
	return false
}

func (a *winAccountsMgr) disabled() (disabled bool) {
	defer func() {
		if disabled != accountDisabled {
			accountDisabled = disabled
			logStatus("account", disabled)
		}
	}()

	var err error
	disabled, err = strconv.ParseBool(config.Section("accountManager").Key("disable").String())
	if err == nil {
		return disabled
	}
	if newMetadata.Instance.Attributes.DisableAccountManager != nil {
		disabled = *newMetadata.Instance.Attributes.DisableAccountManager
		return disabled
	}
	if newMetadata.Project.Attributes.DisableAccountManager != nil {
		disabled = *newMetadata.Project.Attributes.DisableAccountManager
		return disabled
	}
	return accountDisabled
}

var badKeys []string

func (a *winAccountsMgr) set() error {
	newKeys := newMetadata.Instance.Attributes.WindowsKeys
	regKeys, err := readRegMultiString(regKeyBase, accountRegKey)
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
		logger.Errorf("Error setting password: %s", err)
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
			logger.Errorf("Failed to marshal windows key to JSON: %s", err)
			continue
		}
		jsonKeys = append(jsonKeys, string(jsn))
	}
	return writeRegMultiString(regKeyBase, accountRegKey, jsonKeys)
}

var badReg []string

func compareAccounts(newKeys windowsKeys, oldStrKeys []string) windowsKeys {
	if len(newKeys) == 0 {
		return nil
	}
	if len(oldStrKeys) == 0 {
		return newKeys
	}

	var oldKeys windowsKeys
	for _, s := range oldStrKeys {
		var key windowsKey
		if err := json.Unmarshal([]byte(s), &key); err != nil {
			if !containsString(s, badReg) {
				logger.Errorf("Bad windows key from registry: %s", err)
				badReg = append(badReg, s)
			}
			continue
		}
		oldKeys = append(oldKeys, key)
	}

	var toAdd windowsKeys
	for _, key := range newKeys {
		if func(key windowsKey, oldKeys windowsKeys) bool {
			for _, oldKey := range oldKeys {
				if oldKey.UserName == key.UserName &&
					oldKey.Modulus == key.Modulus &&
					oldKey.ExpireOn == key.ExpireOn {
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

// Linux code.

type linuxAccountsMgr struct{}

func (a *linuxAccountsMgr) diff() bool {
	return true
}

func (a *linuxAccountsMgr) timeout() bool {
	return false
}

func (a *linuxAccountsMgr) disabled() (disabled bool) {
	w := &winAccountsMgr{}
	return w.disabled()
}

// In-memory cache of keys for a user so we don't have to read or write the
// file on every run.
var sshKeys map[string][]string

func (a *linuxAccountsMgr) set() error {
	if sshKeys == nil {
		sshKeys = make(map[string][]string)
	}
	usersFile, err := ioutil.ReadFile("/var/lib/google/google_users")
	if err != nil {
		return err
	}
	localUsers := strings.Split(string(usersFile), "\n")

	isin := func(list []string, entry string) bool {
		for _, lEntry := range list {
			if entry == lEntry {
				return true
			}
		}
		return false
	}

	keys := newMetadata.Instance.Attributes.SshKeys
	if !newMetadata.Instance.Attributes.BlockProjectKeys {
		keys = append(keys, newMetadata.Project.Attributes.SshKeys...)
	}

	keysToAdd := make(map[string][]string)
	for _, key := range keys {
		idx := strings.Index(key, ":")
		if idx == -1 {
			continue
		}
		user := key[:idx]
		if !isin(localUsers, user) {
			if err := createUser(user); err != nil {
				continue
			}
			localUsers = append(localUsers, user)
		}
		if isin(sshKeys[user], key) {
			continue
		}
		keysToAddForUser := keysToAdd[user]
		keysToAddForUser = append(keysToAddForUser, key)
		keysToAdd[user] = keysToAddForUser
	}

	for user, keysToAddForUser := range keysToAdd {
		if err := updateAuthorizedKeysFile(user, keysToAddForUser); err != nil {
			continue
		}
		keys := sshKeys[user]
		keys = append(keys, keysToAddForUser...)
		sshKeys[user] = keys
	}

	//	newKeys := newMetadata.Instance.Attributes.WindowsKeys
	// if enable oslogin:
	//   do what the script does today
	// else add local users:
	//   get local users (from google_users file)
	//   get md users
	//   add user (if needed)
	//   mkhomedir
	//   add ssh key
	//   update google_users file
	// remove users/keys as well
	return nil
}

func createUser(userName string) error {
	_, err := getPasswd(userName)
	if err == nil {
		return fmt.Errorf("user %s already exists", userName)
	}
	// TODO: get this and other commands from config.
	if err := exec.Command("useradd", "-m", "-s", "/bin/bash", "-p", "*", userName).Run(); err != nil {
		return err
	}
	if _, err := user.LookupGroup("google-sudoers"); err != nil {
		if err = exec.Command("groupadd", "google-sudoers").Run(); err != nil {
			return err
		}
	}
	if err = exec.Command("gpasswd", "-a", userName, "google-sudoers").Run(); err != nil {
		return err
	}
	if _, err := os.Stat("/etc/sudoers.d/google_sudoers"); err != nil {
		var file *os.File
		file, err = os.OpenFile("/etc/sudoers.d/google_sudoers", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0440)
		if err != nil {
			return err
		}
		defer file.Close()
		fmt.Fprintf(file, "google-sudoers ALL=(ALL:ALL) NOPASSWD:ALL")
	}

	// TODO: use groups from 'Accounts->groups'

	return nil
}

// User is user.User with omitted passwd fields restored.
type User struct {
	user.User
	Passwd, Shell string
}

// getPasswd returns a User from the local passwd database. Code adapted from os/user
func getPasswd(userName string) (*User, error) {
	prefix := []byte(userName + ":")
	colon := []byte{':'}

	parse := func(line []byte) (*User, error) {
		if !bytes.Contains(line, prefix) || bytes.Count(line, colon) < 6 {
			return nil, nil
		}
		// kevin:x:1005:1006::/home/kevin:/usr/bin/zsh
		parts := strings.SplitN(string(line), ":", 7)
		if _, err := strconv.Atoi(parts[2]); err != nil {
			return nil, fmt.Errorf("Invalid passwd entry for %s", userName)
		}
		if _, err := strconv.Atoi(parts[3]); err != nil {
			return nil, fmt.Errorf("Invalid passwd entry for %s", userName)
		}
		u := &User{
			user.User{
				Username: parts[0],
				Uid:      parts[2],
				Gid:      parts[3],
				Name:     parts[4],
				HomeDir:  parts[5],
			},
			parts[1],
			parts[6],
		}
		return u, nil
	}

	passwd, err := os.Open("/etc/passwd")
	if err != nil {
		return nil, err
	}
	bs := bufio.NewScanner(passwd)
	for bs.Scan() {
		line := bs.Bytes()
		// There's no spec for /etc/passwd or /etc/group, but we try to follow
		// the same rules as the glibc parser, which allows comments and blank
		// space at the beginning of a line.
		line = bytes.TrimSpace(line)
		if len(line) == 0 || line[0] == '#' {
			continue
		}
		v, err := parse(line)
		if v != nil || err != nil {
			return v, err
		}
	}
	return nil, fmt.Errorf("User not found")
}

// updateAuthorizedKeysFile appends a set of keys to the user's SSH
// AuthorizedKeys file. The file is created if it does not exist. Uses a
// temporary file to avoid partial updates in case of errors.
func updateAuthorizedKeysFile(userName string, keys []string) error {
	gcomment := "# Added by Google"

	// The os/user functions don't return login shell so we use getent.
	// TODO: is getent safe? Should we read /etc/passwd?
	user, err := getPasswd(userName)
	if err != nil {
		return fmt.Errorf("error getting user %s: %v", userName, err)
	}
	if user.HomeDir == "" {
		return fmt.Errorf("user %s has no homedir set", userName)
	}
	if user.Shell == "/sbin/nologin" {
		return nil
	}

	akpath := path.Join(user.HomeDir, ".ssh", "authorized_keys")
	var akcontents []byte
	akfile, err := os.Open(akpath)
	if err == nil {
		defer akfile.Close()
		var ierr error
		akcontents, ierr = ioutil.ReadAll(akfile)
		if ierr != nil {
			return ierr
		}
	} else if !os.IsNotExist(err) {
		return err
	}

	var isgline bool
	var glines []string
	var userlines []string
	for _, line := range strings.Split(string(akcontents), "\n") {
		if isgline {
			glines = append(glines, line)
			isgline = false
			continue
		}
		if line == gcomment {
			isgline = true
		} else {
			userlines = append(userlines, line)
		}
	}
	glines = append(glines, keys...)

	newfile, err := os.OpenFile(akpath+".google", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer newfile.Close()

	for _, line := range userlines {
		fmt.Fprintf(newfile, line)
	}
	for _, line := range glines {
		fmt.Fprintf(newfile, "%s\n%s", gcomment, line)
	}

	return os.Rename(akpath+".google", akpath)
}
