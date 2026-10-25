# tests

Automated and manual checks for the image.

## Boot test

`boot-test.sh` installs the image to a 30 GiB disk file with `bootc install to-disk`, boots it headless under QEMU/KVM with Secure Boot firmware and a software TPM, and checks that it reaches the login screen. It then logs in over SSH to check the services and start OrielOS's apps inside the VM. The installation is left to the image's own install configuration, so the test also proves that the root filesystem is Btrfs with zstd compression.

```sh
tests/boot-test.sh                          # tests localhost/orielos:latest
tests/boot-test.sh --archive FILE           # loads an OCI archive from tools/build-image.sh first
tests/boot-test.sh --keep --timeout 300
```

Run `tests/boot-test.sh --help` for all the options. It needs the tools that `tools/check-env.sh` checks for, and runs as root (it uses `sudo` when needed). A run takes about five minutes, most of it the installation.

It prints PASS or FAIL for seven checks and exits with status 0 only if all seven pass:

1. Secure Boot was on.
2. The kernel command line has `rootflags=compress=zstd:1`.
3. The root filesystem is Btrfs with zstd compression.
4. `graphical.target` was reached.
5. SDDM is running: it started according to the console, the screen is not a single flat colour, and `systemctl is-active sddm` inside the VM says `active`.
6. NetworkManager is running: it started according to the console, and `systemctl is-active NetworkManager` inside the VM says `active`.
7. OrielOS apps start: `orielos-buildcheck --self-test` inside the VM exits with status 0 and prints its `self-test passed` line.

Any other unit that failed to start is reported as a WARN and does not fail the test. The time from power-on to SDDM, the time until SSH answered, the output of `systemctl is-system-running` and the list of failed units are printed as INFO lines too.

### Commands inside the VM

Once the login screen appears, the test logs in to the VM as root over SSH and runs the commands for checks 5 to 7. The connection goes through a vsock device rather than the network, so the image needs no open port and no password:

- Each run creates a new ed25519 key in its work folder and picks a random vsock guest CID.
- QEMU gets a `vhost-vsock-pci` device with that CID, and the public key as the `ssh.authorized_keys.root` systemd credential through SMBIOS.
- In the VM, systemd's SSH generator makes sshd listen on vsock port 22 with that key, about 20 seconds after boot.
- The test connects with `ssh` through `systemd-ssh-proxy` (with `ProxyUseFdpass=yes`, which the proxy needs) and waits up to 60 seconds for SSH to answer.

The host needs `/dev/vhost-vsock` (the test loads the `vhost_vsock` module when it is missing) and `systemd-ssh-proxy`, which comes with systemd 256 or newer; `tools/check-env.sh` checks both. If SSH never answers, checks 5 to 7 fail with a hint, and the checks based on the console still run.

Results go to `tests/results/<run id>/` (ignored by git), or to the folder given with `--results`. The run id is `<image tag>-<UTC time>`. The folder holds:

- `serial.log`: the VM's console output, with colour codes removed.
- `install.log`: the output of the installation.
- `screenshot.png`: the login screen, taken after pressing a key so the form is visible.
- `summary.txt`: the same lines as the test printed.

The disk, the SSH key and the VM's other files live in `/var/lib/orielos/vm/<run id>` while the test runs and are deleted afterwards. With `--keep` they stay, and the test prints how to boot the disk again, with the same vsock device and key so SSH keeps working.

## Still to come

- Update and rollback tests.
- Benchmark scripts.
- The real-hardware release checklist.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
