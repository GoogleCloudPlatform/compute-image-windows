package serialprotocol

type SnapshotConfig struct {
	Enabled               bool
	Timeout               int // seconds
	ContinueOnScriptError bool
	PreSnapshotScript     string
	PostSnapshotScript    string
}

type AgentReady struct {
	Identifier string `json:"identifier"`
	Signature  string `json:"signature"`
	Version    int    `json:"version"`
}

type AgentShutdown struct {
	Identifier string `json:"identifier"`
	Signature  string `json:"signature"`
	Version    int    `json:"version"`
}

type SerialRequest struct {
	Identifier  string `json:"identifier"`
	Signature   string `json:"signature"`
	Version     int    `json:"version"`
	OperationId int    `json:"operation_id"`
	AllDisks    bool   `json:"all_disks"`
	Disks       string `json:"disks"`
}

type SerialResponse struct {
	Identifier  string `json:"identifier"`
	Signature   string `json:"signature"`
	Version     int    `json:"version"`
	Rc          int    `json:"rc"`
	OperationId int    `json:"operation_id"`
}
