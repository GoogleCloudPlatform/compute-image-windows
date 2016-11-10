## Windows Guest Environment for Google Compute Engine
This repository stores the collection of Windows packages installed on Google 
supported Compute Engine [images](https://cloud.google.com/compute/docs/images).

[GooGet](https://github.com/google/googet) is used for Windows package management.

**Table of Contents**

* [Background](#background)
* [Agent](#Agent)
    * [Account Setup](#account-setup)
    * [IP Forwarding](#ip-forwarding)
* [Instance Setup](#instance-setup)
* [Metadata Scripts](#metadata-scripts)
* [Network Setup](#network-setup)
* [Packaging and Package Distribution](#packaging-andpackage-distribution)
* [Contributing](#contributing)
* [License](#license)

## Background

The Windows guest environment denotes the Google provided configuration and
tooling inside of a [Google Compute Engine](https://cloud.google.com/compute/)
(GCE) virtual machine. The
[metadata server](https://cloud.google.com/compute/docs/metadata) is a
communication channel for transferring information from a client into the guest.
The Windows guest environment includes a set of scripts and binaies that read 
the content of the metadata server to make a virtual machine run properly on our 
platform.

## Agent

#### Account Setup

The agent handles creating user accounts, setting, and resetting passwords.

#### IP Forwarding

The agent uses IP forwarding metadata to setup or remove IP routes in the guest.

*   Only IPv4 IP addresses are currently supported.

## Instance Setup

`instance_setup.ps1` is configured by GCE sysprep to run on VM first boot. The script 
configures the Windows guest environment by performing the following tasks.

*   Setting Hostname
*   Running user provided 'specialize' startup script
*   Activating Windows
*   Seting up RDP and WinRM

## Metadata Scripts

Metadata scripts implement support for running user provided
[startup scripts](https://cloud.google.com/compute/docs/startupscript) and
[shutdown scripts](https://cloud.google.com/compute/docs/shutdownscript).

## Packaging and Package Distribution

The guest code is packaged in [GooGet](https://github.com/google/googet)
packages and published to Google Cloud repositories, if you are creating 
a custom image, you can also use these repositories in your image.

We build the following packages for the Windows guest environment:
  
*   `google-compute-engine-windows` 
    *   Windows agent exe
*   `google-compute-engine-windows-common` 
    *   Windows agent common dll
*   `google-compute-engine-sysprep` 
    *   For running sysprep on new Windows virtual machines.
* `google-compute-engine-metadata-scripts`
    *   GCEMetadataScripts.exe and .cmd files to run startup and shutdown 
        scripts
* `google-compute-engine-powershell` 
    *   PowerShell module for common functions used by other packages
* `google-compute-engine-auto-updater` 
    *   Automatic updater for core Google packages

The package build tools are published in this project.

**To setup GooGet and install packages un the following commands in an elevated 
PowerShell prompt:**

Download and install GooGet:
```
wget https://github.com/google/googet/releases/download/v2.9.1/googet.exe -o $env:temp\googet.exe
$env:temp\googet.exe -root C:\ProgramData\GooGet -noconfirm install -sources https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable googet
rm $env:temp\googet.exe
```

On installation GooGet adds content to the system environment, launch a new PowerShell 
console after installation or provide the full path to googet.exe 
(C:\ProgramData\GooGet\googet.exe).

Add the `google-compute-engine-stable` repo:
```
googet addrepo google-compute-engine-stable https://packages.cloud.google.com/yuck/repos/google-compute-engine-stable
```

Install the core packages `google-compute-engine-windows` and 
`google-compute-engine-sysprep`, `google-compute-engine-sysprep` and 
`google-compute-engine-sysprep` will also be installed as dependencies:
```
googet -noconfirm install google-compute-engine-windows google-compute-engine-sysprep
```

Install optional packages, `google-compute-engine-auto-updater` and 
`google-compute-engine-windows-common`, see above for descriptions:
```
googet -noconfirm install google-compute-engine-auto-updater google-compute-engine-windows-common
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
1.  Create a Pull Request against the
    [development](https://github.com/GoogleCloudPlatform/compute-image-packages/tree/development)
    branch.
1.  Incorporate review feedback to your changes.
1.  Accepted!

## License

All files in this repository are under the
[Apache License, Version 2.0](LICENSE) unless noted otherwise.
