## [Windows](https://cloud.google.com/compute/docs/operating-systems/windows) on [Google Compute Engine](https://cloud.google.com/compute/)
This repository contains Windows agents and scripts for Google Compute Engine.

This repository contains:

+ Latest Windows agent source code and binaries -- For handling user account and address management.
+ Latest version of the metadata scripts source code and binary -- For handling startup and shutdown scripts.
+ Latest sysprep scripts -- For running sysprep on new Windows virtual machines.

## Installation

To install or update the Windows agent and metadata scripts on your virtual machine we recommend recreating your instance with the agent installation script hosted in this repository. With [`gcloud`](https://cloud.google.com/sdk/gcloud/), you can recreate your instance as follows:

    # Delete the instance
    $ gcloud compute instances delete INSTANCE --keep-disks boot

    # Restart the instance with the startup script
    $ gcloud compute instances create NEW-INSTANCE --disk name=DISK boot=yes \
    --metadata windows-startup-script-url=https://raw.githubusercontent.com/GoogleCloudPlatform/compute-image-windows/master/gce/install_agent.ps1

Alternatively, if you prefer not to recreate your instance, you can run the script from within the Windows virtual machine:

1. Log into your Windows virtual machine.
1. Download and save the agent installation script in any directory on your Windows instance.
1. Run powershell as administrator:
  1. Click on the **Start** menu.
  1. Type "powershell" and right click on the first result.
  1. Select **Run as administrator**.
1. In the command-line window, type `Set-ExecutionPolicy Unrestricted` and hit `y` when prompted.
1. Run the agent install script.

For installing the latest sysprep scripts, follow the same instructions above but use the sysprep installation script:

[https://raw.githubusercontent.com/GoogleCloudPlatform/compute-image-windows/master/gce/install_sysprep.ps1](https://raw.githubusercontent.com/GoogleCloudPlatform/compute-image-windows/master/gce/install_sysprep.ps1)

## Contribute

Have a patch that will benefit this project? Awesome! Follow these steps to have it accepted.

1. Please sign our [Contributor License Agreement](CONTRIB.md).
1. Fork this Git repository and make your changes.
1. Create a Pull Request
1. Incorporate review feedback to your changes.
1. Accepted!

## License

All files in this repository are under the [Apache License, Version 2.0](LICENSE) unless noted otherwise.

## Support

If you run into issues, email the Compute Engine team at gc-team@googlegroups.com or email the Compute Engine discussion board at gce-discussion@googlegroups.com.
