# tests

Automated and manual checks for the image.

## Boot test

`boot-test.sh` installs the image to a 30 GiB disk file with `bootc install to-disk`, boots it headless under QEMU/KVM with Secure Boot firmware and a software TPM, and checks that it reaches the login screen. The installation is left to the image's own install configuration, so the test also proves that the root filesystem is Btrfs with zstd compression.

```sh
tests/boot-test.sh                          # tests localhost/orielos:latest
tests/boot-test.sh --archive FILE           # loads an OCI archive from tools/build-image.sh first
tests/boot-test.sh --keep --timeout 300
```

Run `tests/boot-test.sh --help` for all the options. It needs the tools that `tools/check-env.sh` checks for, and runs as root (it uses `sudo` when needed). A run takes about five minutes, most of it the installation.

It prints PASS or FAIL for six checks and exits with status 0 only if all six pass:

1. Secure Boot was on.
2. The kernel command line has `rootflags=compress=zstd:1`.
3. The root filesystem is Btrfs with zstd compression.
4. `graphical.target` was reached.
5. SDDM is running, and the screen is not a single flat colour.
6. NetworkManager is running.

Any other unit that failed to start is reported as a WARN and does not fail the test. The time from power-on to SDDM is printed too.

Results go to `tests/results/<run id>/` (ignored by git), or to the folder given with `--results`. The run id is `<image tag>-<UTC time>`. The folder holds:

- `serial.log`: the VM's console output, with colour codes removed.
- `install.log`: the output of the installation.
- `screenshot.png`: the login screen, taken after pressing a key so the form is visible.
- `summary.txt`: the same lines as the test printed.

The disk and the VM's other files live in `/var/lib/orielos/vm/<run id>` while the test runs and are deleted afterwards. With `--keep` they stay, and the test prints how to boot the disk again.

## Still to come

- Update and rollback tests.
- Benchmark scripts.
- The real-hardware release checklist.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
