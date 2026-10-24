# image

The OS image recipe. The image is built from Fedora's `fedora-bootc` base with rootful Podman.

## What is in the recipe

- `Containerfile`: the recipe. It runs one small script per feature from `build/`, bind-mounted from the build context so the scripts do not end up in the image.
- `build/10-kernel.sh`: replaces the base kernel with the Fedora CoreOS stable kernel, locks its version, and adds the signed xone, xpadneo, OpenRazer and v4l2loopback drivers.
- `build/20-desktop.sh`: an interim minimal KDE Plasma desktop with SDDM.
- `build/30-nvidia.sh`: NVIDIA's open kernel modules and the matching driver. It checks that the modules were built for the installed kernel and that the driver packages carry negativo17's signature.
- `build/80-repos.sh`: disables every repository that is not Fedora's own.
- `build/90-finalise.sh`: rebuilds the initramfs, cleans up and lints the image.
- `system/`: files copied into the image as they are, laid out like the filesystem. It holds the install configuration (`usr/lib/bootc/install/00-orielos.toml`), which makes every installation use a Btrfs root filesystem with zstd compression.
- `keys/`: public keys used to verify packages during the build.
- `pins.env`: the upstream inputs, each pinned by digest.

More system configuration (sysctl settings, udev rules, systemd units) will be added to `system/` as it is needed.

## Building

```sh
tools/build-image.sh
```

This checks that the kernel and NVIDIA inputs match, builds `localhost/orielos:<release>.<date>`, prints the kernel and driver versions, and exports a compressed OCI archive to `/var/lib/orielos/builds`. Run `tools/build-image.sh --help` for the options. The build needs rootful Podman; `tools/check-env.sh` checks the machine.

## Pins

`pins.env` holds the base image, the kernel image and the NVIDIA image, each by digest, so two builds from the same commit use the same inputs. To update them, run `tools/update-pins.sh` to see what has changed, `tools/update-pins.sh --write` to apply it, review the kernel and NVIDIA versions it prints, build, boot-test and commit.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
