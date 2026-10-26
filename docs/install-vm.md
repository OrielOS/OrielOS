# Try OrielOS in a virtual machine

You can try OrielOS without touching your PC's own system by running it in a virtual machine. This guide shows how to build OrielOS, turn it into a virtual machine disk, and start it in QEMU on Linux or in VMware Workstation on Windows.

OrielOS is in early development, so there is no download yet: you build the system yourself from the source code. It takes about half an hour the first time. [Known limitations](known-limitations.md) lists what it can't do yet.

## What you need

- A PC with a 64-bit Intel or AMD processor with virtualisation turned on in the firmware settings, at least 16 GB of memory and about 60 GB of free disk space.
- Linux, or Windows 11 with WSL2 (the Windows Subsystem for Linux). The commands below run in a Linux terminal, or in a WSL2 terminal on Windows.
- Podman, QEMU's `qemu-img` tool and, for QEMU, QEMU itself with UEFI firmware. `tools/check-env.sh` in the source code checks what is missing and tells you how to install it.
- For VMware: VMware Workstation on Windows (tested with version 25).

The commands need administrator rights and ask for your password through `sudo`.

## 1. Build OrielOS

Get the source code from GitHub, then build the system image:

```sh
git clone https://github.com/ncjsvr/OrielOS.git
cd OrielOS
tools/check-env.sh
tools/build-image.sh --no-archive
```

The build downloads Fedora and the NVIDIA driver, and prints the image's name at the end, for example `localhost/orielos:44.20261025`. The same image is also called `localhost/orielos:latest`.

## 2. Make a virtual machine disk

```sh
tools/make-vm-disk.sh
```

This installs OrielOS to a 64 GB virtual disk and saves it in two formats in `/var/lib/orielos/vm-disks`:

- `orielos-<version>.qcow2` for QEMU, virt-manager and GNOME Boxes;
- `orielos-<version>.vmdk` for VMware Workstation.

The files only take up the space that is in use: about 4 GB for the `.qcow2` file, which is compressed, and about 8 GB for the `.vmdk` file. Useful options:

- `--formats qcow2` or `--formats vmdk` makes only one of them.
- `--size 128` makes a bigger disk (in GB).
- `--output DIR` saves the disks somewhere else.
- `--serial-console` shows the start-up messages on the virtual machine's serial port instead of the OrielOS splash screen. It is meant for testing and fault-finding.

Run `tools/make-vm-disk.sh --help` for all the options.

## 3a. Start it in QEMU

QEMU needs UEFI firmware with Secure Boot, as on a real PC. On Ubuntu and Debian it comes in the `ovmf` package; on Fedora, in `edk2-ovmf`, where the files are in `/usr/share/edk2/ovmf/` and are called `OVMF_CODE.secboot.fd` and `OVMF_VARS.secboot.fd`.

First make a copy of the firmware's settings file for this virtual machine, then start it:

```sh
cp /usr/share/OVMF/OVMF_VARS_4M.ms.fd orielos-vars.fd
qemu-system-x86_64 -accel kvm -machine q35,smm=on -cpu host -m 6144 -smp 4 \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive if=pflash,format=raw,unit=0,file=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd,readonly=on \
    -drive if=pflash,format=raw,unit=1,file=orielos-vars.fd \
    -drive file=/var/lib/orielos/vm-disks/orielos-44.20261025.qcow2,format=qcow2,if=virtio \
    -device virtio-vga -display gtk \
    -audiodev pa,id=snd0 -device ich9-intel-hda -device hda-output,audiodev=snd0 \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0
```

Use your own disk's file name. The disk belongs to root, so either run QEMU with `sudo` or copy the disk to your home folder and take ownership of it first.

With virt-manager instead: choose **Import existing disk image**, pick the `.qcow2` file and **Fedora 44** as the operating system, give it 6 GB of memory and 4 processors, and tick **Customise configuration before install**. Under **Overview**, set **Firmware** to the UEFI firmware whose name ends in `secboot.fd`, then start it.

## 3b. Start it in VMware Workstation

On Windows with WSL2, `tools/vmware-vm.sh` sets the virtual machine up for you. VMware can only use files on the Windows drive, so give it a Windows folder:

```sh
tools/vmware-vm.sh create --vmdk /var/lib/orielos/vm-disks/orielos-44.20261025.vmdk --dir 'C:\VMs'
```

It copies the disk to `C:\VMs\orielos-44.20261025` and creates a virtual machine there with UEFI and Secure Boot, 6 GB of memory, 4 processors, networking and sound. Open the `.vmx` file in that folder with VMware Workstation and press **Power on this virtual machine**.

To set it up by hand instead:

1. Copy the `.vmdk` file to a folder on the Windows drive.
2. In VMware Workstation, choose **File > New Virtual Machine**, then **Custom**, then **I will install the operating system later**.
3. Choose **Linux** and **Fedora 64-bit**, and choose **UEFI** with **Secure Boot** when asked for the firmware type.
4. Give it 4 processors and 6 GB of memory, and choose **NAT** networking.
5. For the disk, choose **NVMe**, then **Use an existing virtual disk**, and pick the `.vmdk` file. If Workstation offers to convert the disk to a newer format, either answer works.
6. Finish, then power on the virtual machine.

To check that Secure Boot is on, open the virtual machine's **Settings > Options > Advanced**. A virtual TPM is not needed.

## What happens on first boot

The first start takes under a minute. Then the setup opens over the OrielOS wallpaper, with a "Welcome to Plasma Desktop" page. Click **Begin Setup**, and it asks, one page at a time, for:

1. your language;
2. your keyboard layout;
3. a network: a list of Wi-Fi networks if your PC has Wi-Fi, or otherwise whether its cable connection reaches the internet (a virtual machine is usually connected already);
4. your time zone;
5. when the computer goes to sleep and when the screen turns off, if you don't use it. It starts with sleep after 15 minutes and the screen off after 10;
6. your name, a user name and a password. This account is an administrator.

When you click **Finish**, Plasma Setup creates your account and shows the login screen. Log in with the password you chose. Plasma Setup does not appear again on later starts.

## Graphics in a virtual machine

OrielOS includes NVIDIA's driver, which only works with a real NVIDIA graphics card. In a virtual machine the desktop uses the virtual machine's basic graphics instead. Everything works, but animations can be slower and games will not run as they would on real hardware, so a virtual machine is for trying OrielOS out, not for judging gaming performance.

## Removing the virtual machine

- QEMU: delete the `.qcow2` file and `orielos-vars.fd`.
- VMware Workstation: right-click the virtual machine and choose **Manage > Delete from Disk**, or run `tools/vmware-vm.sh delete --vmx 'C:\VMs\orielos-44.20261025\orielos-44.20261025.vmx'`.
- The disks made in step 2 stay in `/var/lib/orielos/vm-disks` until you delete them.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
