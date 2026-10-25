# image

The OS image recipe. The image is built from Fedora's `fedora-bootc` base with rootful Podman.

## What is in the recipe

- `Containerfile`: the recipe. Its build context is the repository root, so it can build the apps from `apps/` and `plasma/`; `.containerignore` in the root keeps the context small. It runs one small script per feature from `build/`, bind-mounted from the build context so the scripts do not end up in the image. The version tag (`IMAGE_VERSION`) comes last: the final layer refuses an unversioned build, writes the version to `/usr/lib/orielos/build-info` (`VERSION=<tag>`) for `orielos-update` and the Settings app, and the labels follow it. Two builds of the same commit with different date tags therefore share every layer but that one.
- The `app-builder` stage: builds OrielOS's own apps on the pinned Fedora image (`BUILDER_IMAGE`), using `build/apps-builder.sh`. It copies in only `CMakeLists.txt`, `VERSION`, `apps/` and `plasma/`, then configures, builds, runs the tests with `ctest`, runs `qmllint` over every QML module and installs to `/out`. A failing test or a `qmllint` warning fails the build. The final image copies in `/out/usr`, so no compiler, header or build tool reaches it. `tools/test-apps.sh` builds only this stage.
- `build/10-kernel.sh`: replaces the base kernel with the Fedora CoreOS stable kernel, locks its version, and adds the signed xone, xpadneo, OpenRazer and v4l2loopback drivers.
- `build/15-server-defaults.sh`: removes the parts of fedora-bootc that only make sense on servers and switches off its server behaviour (see [Server defaults](#server-defaults)). It installs nothing.
- `build/20-desktop.sh`: installs the desktop from `packages/desktop.txt` without weak dependencies, makes Flathub the only Flatpak source, enables Plasma Setup for the first boot and SDDM for every boot, makes `graphical.target` the default and sets the Plymouth theme.
- `packages/desktop.txt`: the desktop package list, one package per line, grouped under comment headings (see [The desktop](#the-desktop)). It is bind-mounted into the build like the scripts.
- `build/30-nvidia.sh`: NVIDIA's open kernel modules and the matching driver. It checks that the modules were built for the installed kernel and that the driver packages carry negativo17's signature.
- `build/40-apps.sh`: the runtime libraries the apps need (Qt Quick, Kirigami, KI18n, KCoreAddons). Plasma already pulls them in; listing them keeps the dependency explicit. It also installs `tar` and `jq`, which `orielos-update` uses.
- `build/80-repos.sh`: disables every repository that is not Fedora's own.
- `build/85-check-modules.sh`: runs after every package is installed and fails the build unless:
  - every kernel module (`*.ko`, `*.ko.xz`, `*.ko.zst`) has a signer listed in `module-signers.txt`; the failure lists the offending modules and their signers, which may be none;
  - exactly one kernel is installed, and the NVIDIA modules were built for it;
  - every NVIDIA driver package, whatever its architecture, has the same version and release as `kmod-nvidia`; `nvidia-gpu-firmware`, `nvidia-driver-selinux`, `ublue-os-nvidia-addons` and `libva-nvidia-driver` are not driver components and are left out;
  - the 32-bit libraries Steam needs are installed: `nvidia-driver-libs.i686`, `nvidia-driver-cuda-libs.i686` and `libnvidia-fbc.i686`.

  On success it prints the kernel and driver versions and the number of modules per signer. It is bind-mounted with the whole `image/` folder so it can read the signers file.
- `module-signers.txt`: the allowed module signers, one per line: `Fedora kernel signing key` and `ublue kernel` (Universal Blue's). OrielOS never builds or signs kernel modules itself and never ships one signed by another key, which keeps it eligible for anti-cheat systems that check the module signing chain.
- `build/90-finalise.sh`: fails the build if any `-devel` package, `gcc`, `gcc-c++`, `cmake` or `extra-cmake-modules` is installed, or if the first boot would not run Plasma Setup (see [First boot](#first-boot)), then rebuilds the initramfs with Plymouth in it, cleans up and lints the image.
- `system/`: files copied into the image as they are, laid out like the filesystem. It holds:
  - `usr/bin/orielos-update`: the update command (see [Updates](#updates)).
  - `usr/lib/bootc/install/00-orielos.toml`: the install configuration, which makes every installation use a Btrfs root filesystem with zstd compression.
  - `usr/lib/bootc/kargs.d/10-orielos-splash.toml`: the kernel arguments for the boot splash, `rhgb quiet`.
  - `usr/lib/systemd/system-preset/80-orielos.preset`: keeps the server services listed below disabled, and Plasma Setup enabled, whenever systemd applies its presets.
- `keys/`: public keys used to verify packages during the build.
- `pins.env`: the upstream inputs, each pinned by digest.

More system configuration (sysctl settings, udev rules, systemd units) will be added to `system/` as it is needed.

## The desktop

`packages/desktop.txt` lists everything the desktop needs from Fedora's repositories. It is installed without weak dependencies, so the image holds only what is listed and what those packages strictly require; if something stops working because a recommended package is missing, add that package to the list. The list covers:

- KDE Plasma on Wayland with KWin, Xwayland for X11 apps, and Fedora's Plasma defaults.
- SDDM with the Breeze theme on a Wayland greeter, and its settings page.
- Plasma Setup, the first-boot wizard, with the Fedora look-and-feel and wallpapers it needs.
- System Settings, power management, display, disk health, Thunderbolt, firewall, printing, Bluetooth, sound and network settings, including Wi-Fi, mobile broadband and the common VPN types.
- The system tools that play the parts of Windows' built-in ones: Dolphin (File Explorer), Konsole (Terminal), Spectacle (Snipping Tool), Plasma System Monitor (Task Manager), Klipper (clipboard history, part of Plasma), System Settings, Discover, KInfoCenter and Ark (archive support in Dolphin).
- Discover with only its Flatpak backend. Flathub is the only source: Fedora's own Flatpak remote is never added, and Flathub's remote file from `fedora-flathub-remote` is installed in `/usr/share/flatpak/remotes.d` without Fedora's filter, so all of Flathub is available. Discover cannot add Fedora packages to the OS.
- NetworkManager, PipeWire (with PulseAudio, ALSA and JACK compatibility) and WirePlumber, BlueZ, CUPS with its filters, firewalld and Flatpak.
- Breeze icons, cursors and GTK theme, and the Noto fonts, with CJK and colour emoji.
- Mesa's OpenGL, Vulkan and VA-API drivers, Intel's video decoding driver, and the GStreamer plugins for basic playback.
- Guest support for QEMU/KVM and VMware (qemu-guest-agent, spice-vdagent, open-vm-tools-desktop), which does nothing on real hardware.

Apps that Flathub provides are not preinstalled: no text editor, document or image viewer, music player, mail client, games or office apps. Nothing in the image comes from Microsoft.

## First boot

The image has no user account, and installing it with `bootc install` creates none. On first boot KDE's Plasma Setup wizard asks for the language, keyboard layout, network, time zone and the first user account, which becomes an administrator, then opens the login screen. Fedora sets up its KDE editions the same way, and OrielOS wires it up the way Fedora does:

- `plasma-setup.service` is enabled, by `build/20-desktop.sh` and by `80-orielos.preset` (Fedora's own `90-default.preset` enables it too). It runs before SDDM on every boot until `/etc/plasma-setup-done` exists.
- When it runs, it writes `/etc/sddm.conf.d/99-plasma-setup.conf`, which makes SDDM log in the `plasma-setup` system user (created from `sysusers.d`, with its home in `/run/plasma-setup`) to a Plasma session that starts only the wizard.
- The wizard removes that autologin when it starts. When the user clicks Finish, it creates the account with a password and its own group, adds it to the groups in `/etc/xdg/plasmasetuprc` (`wheel`), copies the theme and display scaling chosen in the wizard to it, writes `/etc/plasma-setup-done` and logs out to the login screen.
- It offers to create an account only when there is no regular user (UID 1000 to 60000) yet, and never runs again once the done marker exists.

`build/90-finalise.sh` fails the build if `plasma-setup.service` is not enabled, if `/etc/plasma-setup-done` exists or if the image has a regular user. Plasma Setup looks as KDE and Fedora ship it for now; OrielOS's own styling will follow. `tests/boot-test.sh` checks both boots.

## Server defaults

fedora-bootc is set up for servers. `build/15-server-defaults.sh` changes that:

- Automatic updates are off: `bootc-fetch-apply-updates.timer`, which downloads updates and reboots into them by itself, is disabled. OrielOS will stage updates and ask before restarting.
- The SSH server is off: `sshd.service` is disabled, so a desktop does not listen for SSH. `openssh-server` stays installed because systemd's vsock SSH socket, which `tests/boot-test.sh` uses, runs `sshd` without `sshd.service`.
- These packages are removed, freeing about 300 MB:
  - `kexec-tools`, `kdump-utils` and `makedumpfile`: crash dumps through kexec, which will be disabled at boot.
  - `NetworkManager-cloud-setup`, `WALinuxAgent-udev` and `cloud-utils-growpart`: network set-up from cloud metadata, Azure's agent rules and growing the root partition of cloud images.
  - `sos` with `python3-boto3`, `python3-botocore` and `python3-s3transfer`: server support reports and their upload libraries (about 120 MB).
  - `stalld`: a CPU stall monitor for real-time servers.
  - `qemu-user-static` and its per-architecture packages: emulators for running containers built for other processors, about 190 MB.
  - `nfs-utils`, `quota` and `quota-nls`: the NFS server and disk quotas. Mounting NFS shares still works through `nfs-client-utils`.
  - `iptables-services`: static firewall rules; firewalld manages the firewall instead.
  - `console-login-helper-messages` and its two subpackages: text-console banners that show the machine's addresses and SSH host keys.

Both services are also disabled in `system/usr/lib/systemd/system-preset/80-orielos.preset`, together with `flatpak-add-fedora-repos.service`, so they stay off when systemd applies its presets.

## Updates

OrielOS updates with bootc. A new build is staged for the next boot while the running system stays as it is; at the restart the staged build starts, and the build that was running becomes the rollback build, also listed in the boot menu. `/var`, which holds home folders and system state, is kept across updates and rollbacks. Images aren't published to a registry yet, so builds reach a machine as OCI archives from `tools/build-image.sh`.

`orielos-update` (in `system/usr/bin/`) is the command-line front end. It runs as root:

- `orielos-update status`: the running build, the build staged for the next restart and the rollback build, each with its image reference, version and digest, read from `bootc status --format=json` (`status.booted`, `status.staged` and `status.rollback`; in each, `image.image.transport` and `image.image.image`, `image.version`, which bootc takes from the `org.opencontainers.image.version` label, and `image.imageDigest`). It falls back to `/usr/lib/orielos/build-info` for the running build's version. It also says when a rollback is queued (`status.rollbackQueued`) and lists the rejected builds.
- `orielos-update stage FILE.ociarchive`: reads the build's manifest digest and version label from the archive's `index.json`, manifest and configuration with `tar` and `jq`, without importing it. It refuses a rejected build with exit status 3, does nothing if the build is already running or already staged, and otherwise runs `bootc switch --transport oci-archive FILE`, which imports the build and stages it for the next boot. Without `--apply`, bootc does not restart.
- `orielos-update rollback`: refuses if there is no rollback build. Otherwise it adds the running build's digest to the rejected builds and runs `bootc rollback`, which makes the previous build start at the next restart. Running it again while that rollback is queued changes nothing.
- `orielos-update forget DIGEST`: removes a digest from the rejected builds, for testers.

The rejected builds are kept in `/var/lib/orielos/update/rejected-digests`, one digest per line followed by a comment with the time it was rejected and its version. Exit status 1 means an error and 2 wrong usage. `tests/update-test.sh` tests the whole cycle in a VM, and [docs/updates.md](../docs/updates.md) explains it for users. The graphical update service will build on the same steps.

## Boot splash

Plymouth shows a splash screen while the system starts, with Fedora's `bgrt` theme: the firmware's own logo with a spinner. `build/20-desktop.sh` sets the theme, `build/90-finalise.sh` adds Plymouth to the initramfs, and `system/usr/lib/bootc/kargs.d/10-orielos-splash.toml` adds the `rhgb quiet` kernel arguments, which hide kernel and service messages behind the splash.

## Building

```sh
tools/build-image.sh
```

This checks that the kernel and NVIDIA inputs match, builds `localhost/orielos:<release>.<date>`, prints the kernel and driver versions, and exports a compressed OCI archive to `/var/lib/orielos/builds`. Run `tools/build-image.sh --help` for the options. The build needs rootful Podman; `tools/check-env.sh` checks the machine.

## Pins

`pins.env` holds the base image, the kernel image, the NVIDIA image and the Fedora image the apps are built on, each by digest, so two builds from the same commit use the same inputs. To update them, run `tools/update-pins.sh` to see what has changed, `tools/update-pins.sh --write` to apply it, review the kernel and NVIDIA versions it prints, build, boot-test and commit.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
