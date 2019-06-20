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
	osuser "os/user"
	"path"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/GoogleCloudPlatform/guest-logging-go/logger"
)

var (
	accountRegKey   = "PublicKeys"
	googleUsersFile = "/var/lib/google/google_users"
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
	// If any have changed OR if any have expired!
	return true
}

func (a *linuxAccountsMgr) timeout() bool {
	return false
}

func (a *linuxAccountsMgr) disabled() (disabled bool) {
	return config.Section("Daemons").Key("accounts_daemon").MustBool(true)
}

// sshKeys is a cache of what we have added to each managed users' authorized
// keys file. Avoids necessity of re-reading all files on every change.
var sshKeys map[string][]string

func (a *linuxAccountsMgr) set() error {
	// TODO: oslogin
	// TODO: expiring SSH keys - remove from list, will appear as a diff
	if sshKeys == nil {
		sshKeys = make(map[string][]string)
	}
	createSudoersFile()

	mdkeys := newMetadata.Instance.Attributes.SshKeys
	if !newMetadata.Instance.Attributes.BlockProjectKeys {
		mdkeys = append(mdkeys, newMetadata.Project.Attributes.SshKeys...)
	}

	mdkeys = removeExpiredKeys(mdkeys)

	mdKeyMap := make(map[string][]string)
	for _, key := range mdkeys {
		idx := strings.Index(key, ":")
		if idx == -1 {
			continue
		}
		user := key[:idx]
		userKeys := mdKeyMap[user]
		userKeys = append(userKeys, key)
		mdKeyMap[user] = userKeys
	}
	fmt.Printf("found %d users in metadata\n", len(mdKeyMap))

	// Update SSH keys for users, creating as needed.
	var changed bool
	for user, userKeys := range mdKeyMap {
		passwd, err := getPasswd(user)
		if err != nil {
			fmt.Printf("creating user %s\n", user)
			if err = createUser(user); err != nil {
				continue
			}
			changed = true
		}
		if passwd.Shell == "/sbin/nologin" {
			continue
		}
		if !compareStringSlice(userKeys, sshKeys[user]) {
			fmt.Printf("Updating authorized keys file for %s\n", user)
			if err := updateAuthorizedKeysFile(user, userKeys); err != nil {
				continue
			}
			sshKeys[user] = userKeys
		}
	}

	// Remove Google users not found in metadata.
	gUsers, _ := ioutil.ReadFile(googleUsersFile)
	for _, user := range strings.Split(string(gUsers), "\n") {
		if _, ok := mdKeyMap[user]; !ok && user != "" {
			fmt.Printf("removing user %s\n", user)
			removeUser(user)
			sshKeys[user] = nil
			changed = true
		}
	}

	if changed {
		fmt.Printf("updating google_users file\n")
		gfile, err := os.OpenFile(googleUsersFile, os.O_CREATE|os.O_WRONLY, 0600)
		if err == nil {
			defer gfile.Close()
			for user := range sshKeys {
				if user == "" {
					continue
				}
				fmt.Fprintf(gfile, "%s\n", user)
			}
		}
	}

	return nil
}

type linuxKey windowsKey

func (k linuxKey) expired() bool {
	t, err := time.Parse("2006-01-02T15:04:05-0700", k.ExpireOn)
	if err != nil {
		if !containsString(k.ExpireOn, badExpire) {
			logger.Errorf("Error parsing time: %s", err)
			badExpire = append(badExpire, k.ExpireOn)
		}
		return true
	}
	return t.Before(time.Now())
}

func removeExpiredKeys(keys []string) []string {
	var res []string
	for i := 0; i < len(keys); i++ {
		key := strings.Trim(keys[i], " ")
		fields := strings.SplitN(key, " ", 4)
		if fields[2] != "google-ssh" {
			res = append(res, key)
			continue
		}
		lkjson := fields[len(fields)-1]
		lk := linuxKey{}
		if err := json.Unmarshal([]byte(lkjson), &lk); err != nil {
			continue
		}
		if !lk.expired() {
			res = append(res, key)
		}
	}
	return res
}

func removeUser(user string) error {
	if config.Section("Accounts").Key("deprovision_remove").MustBool(true) {
		exec.Command("userdel", "-r", user).Run()
	} else {
		updateAuthorizedKeysFile(user, []string{})
		exec.Command("gpasswd", "-a", user, "google-sudoers").Run()
	}
	return nil
}

// compareStringSlice returns true if two string slices are equal, false
// otherwise. Does not modify the slices.
func compareStringSlice(first, second []string) bool {
	if len(first) != len(second) {
		return false
	}
	for _, list := range [][]string{first, second} {
		sortfunc := func(i, j int) bool { return list[i] < list[j] }
		list = append([]string{}, list...)
		sort.Slice(list, sortfunc)
	}
	for idx := range first {
		if first[idx] != second[idx] {
			return false
		}
	}
	return true
}

// createSudoersFile creates the google_sudoers configuration file if it does
// not exist and specifies the group 'google-sudoers' should have all
// permissions.
func createSudoersFile() error {
	sudoFile, err := os.OpenFile("/etc/sudoers.d/google_sudoers", os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0440)
	if err != nil {
		return err
	}
	defer sudoFile.Close()
	fmt.Fprintf(sudoFile, "%%google-sudoers ALL=(ALL:ALL) NOPASSWD:ALL\n")
	return nil
}

// createUser creates a Google managed user account.
func createUser(user string) error {
	_, err := getPasswd(user)
	if err == nil {
		return fmt.Errorf("user %s already exists", user)
	}
	if err := exec.Command("useradd", "-m", "-s", "/bin/bash", "-p", "*", user).Run(); err != nil {
		return err
	}
	if _, err := osuser.LookupGroup("google-sudoers"); err != nil {
		if err = exec.Command("groupadd", "google-sudoers").Run(); err != nil {
			return err
		}
	}
	groups := config.Section("Accounts").Key("groups").MustString("adm,dip,docker,lxd,plugdev,video")
	exec.Command("usermod", "-G", groups, user).Run()
	exec.Command("gpasswd", "-a", user, "google-sudoers").Run()

	return nil
}

// User is a user.User with omitted passwd fields restored.
type User struct {
	osuser.User
	Passwd, Shell string
}

// getPasswd returns a User from the local passwd database. Code adapted from os/user
// TODO: cache passwd file for at least one set of consecutive runs..
func getPasswd(user string) (*User, error) {
	prefix := []byte(user + ":")
	colon := []byte{':'}

	parse := func(line []byte) (*User, error) {
		if !bytes.Contains(line, prefix) || bytes.Count(line, colon) < 6 {
			return nil, nil
		}
		// kevin:x:1005:1006::/home/kevin:/usr/bin/zsh
		parts := strings.SplitN(string(line), ":", 7)
		if _, err := strconv.Atoi(parts[2]); err != nil {
			return nil, fmt.Errorf("Invalid passwd entry for %s", user)
		}
		if _, err := strconv.Atoi(parts[3]); err != nil {
			return nil, fmt.Errorf("Invalid passwd entry for %s", user)
		}
		u := &User{
			osuser.User{
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
// AuthorizedKeys file. The file and containing directory are created if it
// does not exist. Uses a temporary file to avoid partial updates in case of
// errors.
func updateAuthorizedKeysFile(user string, keys []string) error {
	gcomment := "# Added by Google"

	passwd, err := getPasswd(user)
	if err != nil {
		return fmt.Errorf("error getting user %s: %v", user, err)
	}
	uid, err := strconv.Atoi(passwd.Uid)
	if err != nil {
		return err
	}
	gid, err := strconv.Atoi(passwd.Gid)
	if err != nil {
		return err
	}
	if passwd.HomeDir == "" {
		return fmt.Errorf("user %s has no homedir set", user)
	}
	if passwd.Shell == "/sbin/nologin" {
		return nil
	}

	sshpath := path.Join(passwd.HomeDir, ".ssh")
	if _, err := os.Stat(sshpath); err != nil {
		if os.IsNotExist(err) {
			if err = os.Mkdir(sshpath, 0700); err != nil {
				return err
			}
			if err = os.Chown(sshpath, uid, gid); err != nil {
				return err
			}
		} else {
			return err
		}
	}
	akpath := path.Join(sshpath, "authorized_keys")
	tempPath := akpath + ".google"
	akcontents, err := ioutil.ReadFile(akpath)
	if err != nil {
		return err
	}

	var isgoogle bool
	var userKeys []string
	for _, key := range strings.Split(string(akcontents), "\n") {
		if key == "" {
			continue
		}
		if isgoogle {
			isgoogle = false
			continue
		}
		if key == gcomment {
			isgoogle = true
			continue
		}
		userKeys = append(userKeys, key)
	}

	newfile, err := os.OpenFile(tempPath, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer newfile.Close()

	for _, key := range userKeys {
		fmt.Fprintf(newfile, "%s\n", key)
	}
	for _, key := range keys {
		fmt.Fprintf(newfile, "%s\n%s\n", gcomment, key)
	}
	err = os.Chown(tempPath, uid, gid)
	if err != nil {
		os.Remove(tempPath)
		return err
	}
	return os.Rename(tempPath, akpath)
}
