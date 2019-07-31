package serialprotocol

type SnapshotConfig struct {
	Timeout               int // seconds
	ContinueOnScriptError bool
	PreSnapshotScriptUrl  string
	PostSnapshotScriptUrl string
	Enabled               bool
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
