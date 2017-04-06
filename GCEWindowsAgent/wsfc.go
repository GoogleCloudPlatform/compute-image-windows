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
	"net"
	"strings"
	"sync"
	"time"

	"github.com/GoogleCloudPlatform/compute-image-windows/logger"
)

const wsfcDefaultAgentPort = "59998"

type agentState int

// Enum for agentState
const (
	running agentState = iota
	stopped
)

var (
	once          sync.Once
	agentInstance *wsfcAgent
)

type wsfcManager struct {
	agentNewState agentState
	agentNewPort  string
	agent         healthAgent
}

// Create new wsfcManager based on metadata
// agent request state will be set to running if one of the following is true:
// - EnableWSFC is set
// - WSFCAddresses is set (As an advanced setting, it will always override EnableWSFC flag)
func newWsfcManager(newMetadata *metadataJSON) *wsfcManager {
	newState := stopped
	if newMetadata.Instance.Attributes.EnableWSFC ||
		len(newMetadata.Instance.Attributes.WSFCAddresses) > 0 {
		newState = running
	}

	newPort := wsfcDefaultAgentPort
	if len(newMetadata.Instance.Attributes.WSFCAgentPort) > 0 {
		newPort = newMetadata.Instance.Attributes.WSFCAgentPort
	}

	return &wsfcManager{agentNewState: newState, agentNewPort: newPort, agent: getWsfcAgentInstance()}
}

// Implement manager.diff()
func (m *wsfcManager) diff() bool {
	return m.agentNewState != m.agent.getState() || m.agentNewPort != m.agent.getPort()
}

// Implement manager.disabled().
// wsfc manager is always enabled. The manager is just a broker which manages the state of wsfcAgent. User
// can disable the wsfc feature by setting the metadata. If the manager is disabled, the agent will become
// an orphan goroutine if it is currently running and no one can talk to it.
func (m *wsfcManager) disabled() bool {
	return false
}

// Diff will always be called before set. So in set, only two cases are possible:
// - state changed: start or stop the wsfc agent accordingly
// - port changed: restart the agent if it is running
func (m *wsfcManager) set() error {
	m.agent.setPort(m.agentNewPort)

	// if state changes
	if m.agentNewState != m.agent.getState() {
		if m.agentNewState == running {
			return m.startAgent()
		}

		return m.stopAgent()
	}

	// If port changed
	if m.agent.getState() == running {
		if err := m.stopAgent(); err != nil {
			return err
		}

		return m.startAgent()
	}

	return nil
}

// Start health agent in goroutine
func (m *wsfcManager) startAgent() error {
	startChan := make(chan error)
	go m.agent.run(startChan)
	if err := <-startChan; err != nil {
		return err
	}

	return nil
}

// Stop health agent
func (m *wsfcManager) stopAgent() error {
	if err := m.agent.stop(); err != nil {
		return err
	}

	return nil
}

// interface for agent answering health check ping
type healthAgent interface {
	getState() agentState
	getPort() string
	setPort(string)
	run(errc chan error)
	stop() error
}

// Windows failover cluster agent, implements healthAgent interface
type wsfcAgent struct {
	state     agentState
	port      string
	waitGroup *sync.WaitGroup
	closing   chan chan error
}

// Start agent and taking tcp request
func (a *wsfcAgent) run(errc chan error) {
	if a.state == running {
		logger.Infoln("wsfc agent is already running")
		errc <- nil
		return
	}

	logger.Info("Starting wsfc agent...")
	listenerAddr, err := net.ResolveTCPAddr("tcp", ":"+a.port)
	if err != nil {
		errc <- err
		return
	}

	listener, err := net.ListenTCP("tcp", listenerAddr)
	if err != nil {
		errc <- err
		return
	}

	logger.Infoln("wsfc agent stared. Listening on port:", a.port)
	a.state = running
	errc <- nil

	for {
		select {
		case closeChan := <-a.closing:
			// close listener first to avoid taking additional request
			err = listener.Close()
			// wait for exiting request to finish
			a.waitGroup.Wait()
			a.state = stopped
			closeChan <- err
			logger.Info("wsfc agent stopped.")
			return
		default:
			listener.SetDeadline(time.Now().Add(time.Second))
			conn, err := listener.Accept()
			if err != nil {
				// if err is not due to time out, log it
				if opErr, ok := err.(*net.OpError); !ok || !opErr.Timeout() {
					logger.Errorln("error on accepting request: ", err)
				}
				continue
			}
			a.waitGroup.Add(1)
			go a.handleHealthCheckRequest(conn)
		}
	}

}

// Handle health check request.
// The request payload is WSFC ip address.
// Sendback 1 if ipaddress is found locally and 0 otherwise.
func (a *wsfcAgent) handleHealthCheckRequest(conn net.Conn) {
	defer conn.Close()
	defer a.waitGroup.Done()
	conn.SetDeadline(time.Now().Add(time.Second))

	buf := make([]byte, 1024)
	// Read the incoming connection into the buffer.
	reqLen, err := conn.Read(buf)
	if err != nil {
		logger.Errorln("error on processing request:", err)
		return
	}

	wsfcIP := strings.TrimSpace(string(buf[:reqLen]))
	reply, err := checkIPExist(wsfcIP)
	if err != nil {
		logger.Errorln("error on checking local ip:", err)
	}
	conn.Write([]byte(reply))
}

// Stop agent. Will wait for all existing request to be completed.
func (a *wsfcAgent) stop() error {
	if a.state == stopped {
		logger.Info("wsfc agent already stopped.")
		return nil
	}

	logger.Info("Stopping wsfc agent...")
	errc := make(chan error)
	a.closing <- errc
	return <-errc
}

func (a *wsfcAgent) getState() agentState {
	return a.state
}

func (a *wsfcAgent) getPort() string {
	return a.port
}

func (a *wsfcAgent) setPort(newPort string) {
	if newPort != a.port {
		logger.Infof("update wsfc agent from port %v to %v", a.port, newPort)
		a.port = newPort
	}
}

// Create wsfc agent only once
func getWsfcAgentInstance() *wsfcAgent {
	once.Do(func() {
		agentInstance = &wsfcAgent{
			state:     stopped,
			port:      wsfcDefaultAgentPort,
			waitGroup: &sync.WaitGroup{},
			closing:   make(chan chan error),
		}
	})

	return agentInstance
}

// help func to check whether the ip exists on local host.
func checkIPExist(ip string) (string, error) {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return "0", err
	}

	for _, address := range addrs {
		if ipnet, ok := address.(*net.IPNet); ok && !ipnet.IP.IsLoopback() {
			ipString := ipnet.IP.To4().String()
			if ip == ipString {
				return "1", nil
			}
		}
	}

	return "0", nil
}
