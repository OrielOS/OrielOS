# tests

Automated and manual checks for the image.

## Boot test

`boot-test.sh` installs the image to a 30 GiB disk file with `bootc install to-disk`, boots it headless under QEMU/KVM with Secure Boot firmware and a software TPM, and boots it twice:

1. **First boot.** The disk has no user account, so Plasma Setup, KDE's first-boot wizard, should start. The test checks that it did, takes `first-boot.png`, then finishes setup over SSH the way the wizard does (see [Finishing setup](#finishing-setup)) and restarts the VM.
2. **Second boot.** Plasma Setup must not run again, and SDDM shows the login screen. The test checks the services, starts OrielOS's apps and logs the user that setup created in to the Plasma desktop.

The installation is left to the image's own install configuration, so the test also proves that the root filesystem is Btrfs with zstd compression.

```sh
tests/boot-test.sh                          # tests localhost/orielos:latest
tests/boot-test.sh --archive FILE           # loads an OCI archive from tools/build-image.sh first
tests/boot-test.sh --keep --timeout 300
```

Run `tests/boot-test.sh --help` for all the options. It needs the tools that `tools/check-env.sh` checks for, and runs as root (it uses `sudo` when needed). A run takes about ten minutes, most of it the installation and the two boots. `--timeout` applies to each boot.

It prints PASS or FAIL for fourteen checks, under a "First boot" and a "Second boot" heading, and exits with status 0 only if all fourteen pass.

First boot:

1. Plasma Setup starts on first boot: `plasma-setup.service` ran (`ConditionResult=yes`, `Result=success`), there is no `/etc/plasma-setup-done` and no regular user (`awk -F: '$3>=1000 && $3<60000' /etc/passwd` prints nothing), SDDM logs the `plasma-setup` user in to a `wayland` session within 120 seconds with `kwin_wayland` and the `plasma-setup` wizard running, and `first-boot.png` is not a single flat colour.

Second boot, after finishing setup and restarting:

2. Plasma Setup does not run again: `plasma-setup.service` was skipped by its condition (`ConditionResult=no`), there is no `plasma-setup` process and no Plasma Setup autologin, the only regular user is `orielostest`, and `systemctl is-active sddm` says `active`.
3. Secure Boot was on.
4. The kernel command line has `rootflags=compress=zstd:1`.
5. The root filesystem is Btrfs with zstd compression.
6. `graphical.target` was reached.
7. SDDM is running: it started according to the console, the screen is not a single flat colour, and `systemctl is-active sddm` inside the VM says `active`.
8. NetworkManager is running: it started according to the console, and `systemctl is-active NetworkManager` inside the VM says `active`.
9. OrielOS apps start: `orielos-buildcheck --self-test` inside the VM exits with status 0 and prints its `self-test passed` line.
10. The Plasma Wayland session starts: after the scripted desktop login (below), `loginctl` shows a `wayland` session for `orielostest` within 90 seconds, `plasmashell` and `kwin_wayland` run as that user, and the desktop screenshot is not a single flat colour.
11. Sound services run: `systemctl --user -M orielostest@ is-active pipewire wireplumber` says `active` for both. The VM has an Intel HD Audio sound card with a silent output, so there is a device to drive.
12. The Bluetooth service is enabled: `systemctl is-enabled bluetooth.service` says `enabled`. The VM has no Bluetooth adapter, so the service is skipped by its condition; its state is printed as an INFO line.
13. Server defaults are off: `systemctl is-enabled bootc-fetch-apply-updates.timer sshd.service` says `disabled` for both, and there is no `kexec`, `kdumpctl` or `makedumpfile` binary. Both results are printed as INFO lines too.
14. Kernel modules are signed by Fedora or Universal Blue: `modinfo -F signer nvidia` prints `ublue kernel`; `rpm -q kernel` matches the kernel installed in the image (read with `rpm -q kernel-core` in the container, because the base image's `ostree.linux` label still names the base kernel); and the NVIDIA driver packages (the same set that the image build checks) have exactly one version between them. `rpm -q kernel` and the driver version are printed as INFO lines. The module is not loaded in a VM without an NVIDIA GPU; `modinfo` reads the file, which is what the check needs.

Checks 3 to 14 read the second boot only: before restarting, the test notes how long the serial log is, and afterwards it reads from the new kernel's first line on. Any other unit that failed to start on the second boot is reported as a WARN and does not fail the test. The times from power-on to SDDM and to Plasma Setup's wizard, the time from the restart to SDDM, the time until SSH answered, the output of `systemctl is-system-running` and the list of failed units are printed as INFO lines too.

### Finishing setup

Plasma Setup's wizard has no scripting interface, so the test does over SSH what the wizard does when the user clicks Finish:

1. It creates `orielostest` with `useradd -m -U`, adds it to the groups in `/etc/xdg/plasmasetuprc` (`wheel`) and sets a random password with `chpasswd`.
2. It copies the theme and display scaling chosen in the wizard (`kdeglobals`, `kwinoutputconfig.json` and `kwinrc` from `/run/plasma-setup/.config`, where they exist) to the new user.
3. It removes the wizard's SDDM autologin, `/etc/sddm.conf.d/99-plasma-setup.conf`, which the wizard already removes when it starts.
4. It writes the done marker, `/etc/plasma-setup-done`, with the same "Plasma Setup completed at" line.

The wizard then logs out to the login screen; the test restarts the VM with `systemctl reboot` instead, which also proves that the marker survives a restart.

### Console output

The image boots with `rhgb quiet` for its splash screen, which hides kernel and service messages. Checks 3 to 8 read those messages from the serial console, so the test installs with `systemd.show_status=1` and `ignore_loglevel` after the console arguments, which print them there again. It also adds `plymouth.enable=0`, which turns the boot splash off: while the splash runs, Plymouth takes over the console output, so systemd's status lines never reach the serial console. These arguments are for the test only, so the test does not show the splash.

### Desktop login

On the second boot, after the login screenshot, the test logs the user that setup created in to Plasma the way SDDM would at boot:

1. It writes `/etc/sddm.conf.d/99-boot-test-autologin.conf` with an `[Autologin]` section for that user and the Plasma Wayland session, `plasma.desktop` from `/usr/share/wayland-sessions/`.
2. It restarts SDDM, which logs the user in.
3. It waits up to 90 seconds for the session, then 15 seconds more for the desktop to draw, and takes `desktop.png`.

Restarting SDDM stops it on purpose, so check 7 reads the console only up to the restart.

### Commands inside the VM

On each boot, once SDDM has started, the test logs in to the VM as root over SSH and runs the commands for the checks. The connection goes through a vsock device rather than the network, so the image needs no open port and no password:

- Each run creates a new ed25519 key in its work folder and picks a random vsock guest CID.
- QEMU gets a `vhost-vsock-pci` device with that CID, and the public key as the `ssh.authorized_keys.root` systemd credential through SMBIOS.
- In the VM, systemd's SSH generator makes sshd listen on vsock port 22 with that key, about 20 seconds after boot.
- The test connects with `ssh` through `systemd-ssh-proxy` (with `ProxyUseFdpass=yes`, which the proxy needs) and waits up to 60 seconds for SSH to answer.

The host needs `/dev/vhost-vsock` (the test loads the `vhost_vsock` module when it is missing) and `systemd-ssh-proxy`, which comes with systemd 256 or newer; `tools/check-env.sh` checks both. The SSH server's own service, `sshd.service`, is disabled in the image; the vsock socket starts `sshd` without it. The key and the vsock device stay the same across the restart. If SSH never answers on the first boot, the test cannot finish setup or restart, and every check that needs SSH fails with a hint; the checks based on the console still run.

Results go to `tests/results/<run id>/` (ignored by git), or to the folder given with `--results`. The run id is `<image tag>-<UTC time>`. The folder holds:

- `serial.log`: the VM's console output from both boots, with colour codes removed.
- `install.log`: the output of the installation.
- `first-boot.png`: Plasma Setup's wizard on the first boot.
- `screenshot.png`: the login screen on the second boot, taken after pressing a key so the form is visible.
- `desktop.png`: the Plasma desktop after the scripted login.
- `summary.txt`: the same lines as the test printed.

The disk, the SSH key and the VM's other files live in `/var/lib/orielos/vm/<run id>` while the test runs and are deleted afterwards. With `--keep` they stay, and the test prints how to boot the disk again (setup is finished on it, so it starts at the login screen), with the same vsock device and key so SSH keeps working.

## Update test

`update-test.sh` tests updating and rolling back with `orielos-update` (see `image/README.md`). It installs an old build to a fresh 30 GiB disk the way the boot test does, boots it in the same VM, with Secure Boot firmware, a software TPM and SSH over vsock, and runs every step over SSH:

1. **Install and boot the old build**, wait for SSH and read the running build's digest and version from `bootc status --format=json`.
2. **Create user data.** Setup is finished the way the boot test does it (see [Finishing setup](#finishing-setup)), which creates `orielostest`, and `/var/home/orielostest/keepme.txt` gets random content.
3. **Copy the new build** into the VM over SSH, to `/var/tmp/`, and compare its SHA-256 with the original.
4. **Stage it** with `orielos-update stage`. The running build and the boot must stay the same, and bootc must report the new build as staged, with the manifest digest read from the archive's `index.json` on the host.
5. **Restart.** The new build must run, with its digest, its version label and the version in `/usr/lib/orielos/build-info`, and `keepme.txt` must be unchanged.
6. **Roll back** with `orielos-update rollback`, which must list the new build's digest in `/var/lib/orielos/update/rejected-digests`, and restart. The old build must run again, and `keepme.txt` must be unchanged.
7. **Stage the new build again.** `orielos-update stage` must refuse it with exit status 3, and nothing must be staged.

```sh
tests/update-test.sh --old localhost/orielos:44.20261025 --new /var/lib/orielos/builds/orielos-44.20261026.ociarchive
tests/update-test.sh --old OLD.ociarchive --new NEW.ociarchive --keep
```

`--old` takes an image in Podman or an OCI archive, which is loaded as `localhost/orielos-archive:<file name>` first; `--new` takes an OCI archive from `tools/build-image.sh`. Run `tests/update-test.sh --help` for all the options. It needs the same tools as the boot test and runs as root. A run takes about fifteen minutes: the installation, three boots, copying the archive and importing it.

Each restart is started with `systemctl reboot` over SSH; the VM restarts in place. The test waits for SSH to go away and answer again, then checks that `/proc/sys/kernel/random/boot_id` changed. `--timeout` is how long it waits for SSH after power-on and after each restart.

It prints PASS or FAIL for twelve checks, one or more per step, and exits with status 0 only if all of them pass. If a step fails in a way that the later steps depend on, the test stops there and reports that as a failure too.

Results go to `tests/results/<run id>/`, or to the folder given with `--results`. The run id is `update-<new build's tag>-<UTC time>`. The folder holds:

- `summary.txt`: the same lines as the test printed.
- `install.log` and `serial.log`: the installation's output and the VM's console output from every boot.
- `bootc-status-<step>.json` and `status-<step>.txt`: the output of `bootc status --format=json` and `orielos-update status` after each step (`old`, `staged`, `new`, `rolled-back` and `final`).
- `stage.txt`, `rollback.txt` and `stage-again.txt`: the output of those `orielos-update` commands.

The work folder and `--keep` work as in the boot test.

## Shared VM code

`lib/vm.sh` holds what both tests need: the PASS, FAIL, WARN and INFO lines, installing the image, starting the VM with its firmware, TPM and vsock device, SSH into the VM, finishing setup and cleaning up. Both tests source it. `.shellcheckrc` lets shellcheck follow it.

## Still to come

- Benchmark scripts.
- The real-hardware release checklist.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
