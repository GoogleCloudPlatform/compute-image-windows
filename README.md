## Windows Guest Environment for Google Compute Engine
This repository stores the collection of Windows packages installed on Google
supported Compute Engine [images](https://cloud.google.com/compute/docs/images).

**Table of Contents**

* [Background](#background)
* [Agent](#agent)
    * [Configuring](#configuring)
    * [Account Setup](#account-setup)
    * [IP Forwarding](#ip-forwarding)
    * [Windows Failover Cluster Support](#windows-failover-cluster-support)
* [Instance Setup](#instance-setup)
* [Metadata Scripts](#metadata-scripts)
* [Packaging and Package Distribution](#packaging-and-package-distribution)
* [Contributing](#contributing)
* [License](#license)

## Background

The Windows guest environment is the Google provided configuration and
tooling inside of a [Google Compute Engine](https://cloud.google.com/compute/)
(GCE) virtual machine. The
[metadata server](https://cloud.google.com/compute/docs/metadata) is a
communication channel for transferring information from a client into the guest.
The Windows guest environment includes a set of scripts and binaries that read
the content of the metadata server to make a virtual machine run properly on
Google Compute Engine.

## Agent

### Configuring

The agent is configurable through
[metadata or a local config file](https://cloud.google.com/compute/docs/instances/windows/creating-managing-windows-instances#configure-windows-features).

#### Account Setup

The agent handles [creating user accounts and setting/resetting passwords](https://cloud.google.com/compute/docs/instances/windows/creating-passwords-for-windows-instances).

#### IP Forwarding

The agent uses IP forwarding metadata to setup or remove IP routes.

*   Only IPv4 IP addresses are currently supported.

#### Windows Failover Cluster Support

The agent can monitor the active node in the [Windows Failover Cluster](https://technet.microsoft.com/en-us/library/cc770737(v=ws.11).aspx) and coordinate with GCP [Internal Load Balancer](https://cloud.google.com/compute/docs/load-balancing/internal/) to forward all cluster traffic to the expected node.

The following fields on instance metadata or instance_configs.cfg can control the behavior:

* `enable-wsfc`: If set to true, all IP forwarding info will be ignored and agent will start responding to the health check port. Default false.
* `wsfc-agent-port`: The port which the agent will respond to health checks. Default 59998.
* `wsfc-addrs`: A comma separated list of IP address. This is an advanced setting to enable user have both normal forwarding IPs and cluster IPs on the same instance. If set, agent will only skip-auto configuring IPs in the list. Default empty. 

Main code can be found here: [wsfc.go](GCEWindowsAgent/wsfc.go)

## Instance Setup

`instance_setup.ps1` is configured by GCE sysprep to run on VM first boot.
The script performs the following tasks:

*   Set the hostname to the instance name.
*   Runs user provided 'specialize' startup script.
*   Activates Windows using a KMS server.
*   Sets up RDP and WinRM to allow remote login.

## Metadata Scripts

Metadata scripts implement support for running user provided
[startup scripts](https://cloud.google.com/compute/docs/startupscript) and
[shutdown scripts](https://cloud.google.com/compute/docs/shutdownscript).

## Packaging and Package Distribution

The guest code is packaged in [GooGet](https://github.com/google/googet)
packages and published to Google Cloud repositories.

We build and install the following packages for the Windows guest environment:

*   `google-compute-engine-windows` - Windows agent executable.
*   `google-compute-engine-sysprep` - Utilities for running sysprep on new
    Windows virtual machines.
*   `google-compute-engine-metadata-scripts` - Windows `exe` and `cmd` files
    to run startup and shutdown scripts.
*   `google-compute-engine-powershell` - PowerShell module for common functions
    used by other packages.
*   `google-compute-engine-auto-updater` - Automatic updater for core Google
    packages.
*   `google-compute-engine-vss` - Google Compute Engine VSS agent and provider

The package build specs are published in this project.

**To setup GooGet and install packages run the following commands in an elevated
PowerShell prompt:**

Download and install GooGet:
```
Invoke-WebRequest https://github.com/google/googet/releases/download/v2.9.1/googet.exe -OutFile $env:temp\googet.exe
& "$env:temp\googet.exe" -root C:\ProgramData\GooGet -noconfirm install -sources https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable googet
Remove-Item "$env:temp\googet.exe"
```

On installation GooGet adds content to the system environment, launch a new PowerShell
console after installation or provide the full path to googet.exe
(C:\ProgramData\GooGet\googet.exe).

Add the `google-compute-engine-stable` repo, **_this must be done in a new console if you just installed GooGet_**:
```
googet addrepo google-compute-engine-stable https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable
```

Install the core packages `google-compute-engine-windows`, 
`google-compute-engine-metadata-scripts`,`google-compute-engine-sysprep`,
and `google-compute-engine-vss`.
```
googet -noconfirm install google-compute-engine-windows google-compute-engine-sysprep google-compute-engine-metadata-scripts google-compute-engine-vss
```

Install optional packages, `google-compute-engine-auto-updater`:
```
googet -noconfirm install google-compute-engine-auto-updater
```

You can view available packages using the `googet available` and installed
packages using the `googet installed` command. Running `googet update` will
update to the latest versions available. To view additional commands run
`googet help`.

## Contributing

Have a patch that will benefit this project? Awesome! Follow these steps to have
it accepted.

1.  Please sign our [Contributor License Agreement](CONTRIB.md).
1.  Fork this Git repository and make your changes.
1.  Create a Pull Request.
1.  Incorporate review feedback to your changes.
1.  Accepted!

## License

All files in this repository are under the
[Apache License, Version 2.0](LICENSE) unless noted otherwise.
