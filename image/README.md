# image

The OS image recipe. The image is built from Fedora's `fedora-bootc` base with rootful Podman.

## What is in the recipe

- `Containerfile`: the recipe. Its build context is the repository root, so it can build the apps from `apps/` and `plasma/` with the artwork they install from `artwork/`; `.containerignore` in the root keeps the context small. It runs one small script per feature from `build/`, bind-mounted from the build context so the scripts do not end up in the image. The version tag (`IMAGE_VERSION`) comes last: the final layer refuses an unversioned build, writes the version to `/usr/lib/orielos/build-info` (`VERSION=<tag>`) for `orielos-update` and the Settings app, and the labels follow it. Two builds of the same commit with different date tags therefore share every layer but that one.
- The `app-builder` stage: builds OrielOS's own apps on the pinned Fedora image (`BUILDER_IMAGE`), using `build/apps-builder.sh`. It copies in only `CMakeLists.txt`, `VERSION`, `apps/`, `plasma/` and `artwork/`, then configures, builds, runs the tests with `ctest`, runs `qmllint` over every QML module and installs to `/out`. A failing test or a `qmllint` warning fails the build. The final image copies in `/out/usr`, so no compiler, header or build tool reaches it. `tools/test-apps.sh` builds only this stage.
- `build/10-kernel.sh`: replaces the base kernel with the Fedora CoreOS stable kernel, locks its version, and adds the signed xone, xpadneo, OpenRazer and v4l2loopback drivers.
- `build/15-server-defaults.sh`: removes the parts of fedora-bootc that only make sense on servers and switches off its server behaviour (see [Server defaults](#server-defaults)). It installs nothing.
- `build/20-desktop.sh`: installs the desktop from `packages/desktop.txt` without weak dependencies, makes Flathub the only Flatpak source, enables Plasma Setup for the first boot and SDDM for every boot, makes `graphical.target` the default, makes OrielOS's look-and-feel the default (see [The taskbar](#the-taskbar)) and sets the Plymouth theme.
- `packages/desktop.txt`: the desktop package list, one package per line, grouped under comment headings (see [The desktop](#the-desktop)). It is bind-mounted into the build like the scripts.
- `build/25-store.sh`: turns Discover into the Store (see [The Store](#the-store)), removes its firmware backend and makes Firefox the default browser. It fails the build if a Discover desktop entry or the default-browser file is missing, or if any backend but Flatpak is left.
- `build/26-shortcuts.sh`: the Windows keyboard shortcuts for apps and the Windows names of the system tools (see [Keyboard shortcuts](#keyboard-shortcuts)). It fails the build if a desktop entry it changes is missing or no longer has the shortcuts or name it expects, if a Plasma default that OrielOS relies on has moved, or if two desktop entries share a shortcut.
- `build/desktop-entry.sh`: helpers sourced by `25-store.sh` and `26-shortcuts.sh`: `die`, and `rename_entry`, which renames a desktop entry, sets its `GenericName` and drops its translated names.
- `build/30-nvidia.sh`: NVIDIA's open kernel modules and the matching driver. It checks that the modules were built for the installed kernel and that the driver packages carry negativo17's signature.
- `build/40-apps.sh`: the runtime libraries the apps need (Qt Quick, Kirigami, KI18n, KCoreAddons). Plasma already pulls them in; listing them keeps the dependency explicit. It also installs `tar` and `jq`, which `orielos-update` uses.
- `build/80-repos.sh`: disables every repository that is not Fedora's own.
- `build/85-check-modules.sh`: runs after every package is installed and fails the build unless:
  - every kernel module (`*.ko`, `*.ko.xz`, `*.ko.zst`) has a signer listed in `module-signers.txt`; the failure lists the offending modules and their signers, which may be none;
  - exactly one kernel is installed, and the NVIDIA modules were built for it;
  - every NVIDIA driver package, whatever its architecture, has the same version and release as `kmod-nvidia`; `nvidia-gpu-firmware`, `nvidia-driver-selinux`, `ublue-os-nvidia-addons` and `libva-nvidia-driver` are not driver components and are left out;
  - the 32-bit libraries Steam needs are installed: `nvidia-driver-libs.i686`, `nvidia-driver-cuda-libs.i686` and `libnvidia-fbc.i686`.

  On success it prints the kernel and driver versions and the number of modules per signer. It is bind-mounted with the whole `image/` folder so it can read the signers file.
- `build/86-check-boot-security.sh`: runs after the module check and fails the build unless every boot will be in the anti-cheat mode (see [Anti-cheat boot mode](#anti-cheat-boot-mode)):
  - every `kargs.d` file has exactly one `kargs = [...]` line, `20-orielos-anticheat.toml` sets `lockdown=integrity`, `intel_iommu=on` and `iommu.passthrough=0`, and no file sets `lsm=`;
  - `kexec-tools` is not installed and `60-orielos-kexec.conf` sets `kernel.kexec_load_disabled = 1`;
  - the kernel's config (`/usr/lib/modules/<version>/config`) has `CONFIG_BPF_LSM=y` and `bpf` in its default LSM list, `CONFIG_LSM`;
  - `50-orielos.conf` switches hibernation, suspend-then-hibernate and hybrid sleep off.

  On success it prints the kernel, its default LSM list and the kernel arguments.
- `module-signers.txt`: the allowed module signers, one per line: `Fedora kernel signing key` and `ublue kernel` (Universal Blue's). OrielOS never builds or signs kernel modules itself and never ships one signed by another key, which keeps it eligible for anti-cheat systems that check the module signing chain.
- `build/90-finalise.sh`: fails the build if any `-devel` package, `gcc`, `gcc-c++`, `cmake` or `extra-cmake-modules` is installed, or if the first boot would not run Plasma Setup (see [First boot](#first-boot)), enables `orielos-flatpak-setup.service` (and fails if its stamp file exists) and `orielos-secure-boot-key.service` (and fails if its parts are missing; see [Secure Boot](#secure-boot)), fails if new users would not get the taskbar (see [The taskbar](#the-taskbar)), refreshes the `hicolor` icon cache, then rebuilds the initramfs with Plymouth in it, cleans up and lints the image.
- `system/`: files copied into the image as they are, laid out like the filesystem. It holds:
  - `usr/bin/orielos-update`: the update command (see [Updates](#updates)).
  - `usr/libexec/orielos/flatpak-setup` and `usr/lib/systemd/system/orielos-flatpak-setup.service`: the first-boot install of Firefox from Flathub (see [The Store](#the-store)).
  - `usr/libexec/orielos/secure-boot-key`, `usr/lib/systemd/system/orielos-secure-boot-key.service`, `usr/libexec/orielos/secure-boot-notify` and `etc/xdg/autostart/orielos-secure-boot-notify.desktop`: the Secure Boot key step (see [Secure Boot](#secure-boot)). The Containerfile copies `system/etc/` to `/etc`, which bootc keeps as the default configuration.
  - `etc/skel/.config/kglobalshortcutsrc`: the KWin shortcuts every new user starts with (see [Keyboard shortcuts](#keyboard-shortcuts)).
  - `etc/xdg/dolphinrc`: Files (Dolphin) opens a fresh window on the Home folder instead of restoring the last session's tabs.
  - `usr/lib/bootc/install/00-orielos.toml`: the install configuration, which makes every installation use a Btrfs root filesystem with zstd compression.
  - `usr/lib/bootc/kargs.d/10-orielos-splash.toml`: the kernel arguments for the boot splash, `rhgb quiet`.
  - `usr/lib/bootc/kargs.d/20-orielos-anticheat.toml`, `usr/lib/sysctl.d/60-orielos-kexec.conf` and `usr/lib/systemd/sleep.conf.d/50-orielos.conf`: the anti-cheat boot mode (see [Anti-cheat boot mode](#anti-cheat-boot-mode)).
  - `usr/lib/systemd/system-preset/80-orielos.preset`: keeps the server services listed below disabled whenever systemd applies its presets.
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

## The taskbar

New users get a Windows 11-style taskbar: the Start button and pinned apps (Files, Firefox and Store) in the centre of a panel along the bottom of the screen, and the system tray, the clock with the date and the show-desktop sliver at the right. Notifications appear at the bottom right, next to the tray. It comes from OrielOS's look-and-feel package, built from `plasma/` with the apps; [plasma/README.md](../plasma/README.md) describes the package, its layout script and the update scripts for existing users.

- `build/20-desktop.sh` sets `LookAndFeelPackage=org.orielos.desktop` in the `[KDE]` group of `/etc/xdg/kdeglobals`. `/etc/xdg` comes before Fedora's `kde-settings` profile (`/usr/share/kde-settings/kde-profile/default/xdg`) on `XDG_CONFIG_DIRS`, which still sets Fedora's look-and-feel there, so OrielOS's wins without changing Fedora's files. `build/25-store.sh` adds the default browser to the same file.
- Plasma runs the package's layout script when a user logs in for the first time, so it applies to every account created after installation, including the first one from Plasma Setup.
- Plasma Setup's Dark Theme switch applies Fedora's dark look-and-feel, which the wizard passes on to the new account. That account's first desktop then starts from Fedora's layout, and OrielOS's update script `orielos-taskbar-1.js` moves its panel into the taskbar order straight away, with the OrielOS Start icon, but the panel keeps Fedora's floating style, the pager and the default pinned apps. An OrielOS dark look-and-feel will replace this.
- SDDM's login screen keeps Fedora's Breeze theme, and the lock screen is Breeze's, until OrielOS has its own.
- The image's files all have the same timestamp, so icon loaders would trust Fedora's `hicolor` icon cache and miss the Start button's icon; `build/90-finalise.sh` rebuilds the cache with `gtk-update-icon-cache`, and fails the build if the setting, the package or the icon is missing.

`tests/boot-test.sh` checks the new user's taskbar.

## Keyboard shortcuts

The Windows keyboard shortcuts work for every new user, and open the tools that play the Windows tools' parts. Most are already Plasma 6.7's defaults; OrielOS changes only the rest. [docs/keyboard-shortcuts.md](../docs/keyboard-shortcuts.md) lists them for users.

| Shortcut | Plasma 6.7's default | OrielOS |
|---|---|---|
| Win | Start (Kickoff), from `kwinrc`'s `ModifierOnlyShortcuts` | unchanged |
| Win+E | Dolphin (`X-KDE-Shortcuts=Meta+E`) | unchanged; Dolphin is named Files |
| Win+R | Spectacle's region recording (`Meta+Shift+R,Meta+R`); KRunner is on `Alt+Space,Alt+F2,Search` | KRunner (Run) gets `Meta+R`; region recording keeps `Meta+Shift+R` |
| Win+L | Lock Session (ksmserver) | unchanged |
| Win+D | Show Desktop (KWin) | unchanged |
| Win+Tab | KWin's Walk Through Windows, together with Alt+Tab (and Win+Shift+Tab with Alt+Shift+Tab for the reverse) | KWin's Overview, which a second press closes, and which keeps Win+W; Walk Through Windows keeps Alt+Tab and Alt+Shift+Tab only |
| Win+I | System Settings (`Tools,Meta+I`) | unchanged |
| Win+Shift+S | Spectacle (`Print,Meta+Shift+S`), which starts with a rectangular region | unchanged; Spectacle is named Snipping Tool |
| Win+V | Klipper's clipboard history at the mouse pointer (`show-on-mouse-pos`) | unchanged |
| Win+. | Emoji picker (`Meta+.,Meta+Ctrl+Alt+Shift+Space`) | unchanged |
| Ctrl+Shift+Esc | nothing; System Monitor is on `Meta+Esc` | System Monitor (Task Manager), on both |
| Win+Left/Right | KWin's Quick Tile Left/Right | unchanged |
| Win+Up/Down | KWin's Quick Tile Top/Bottom | KWin's Maximise and Minimise, which keep Win+PgUp/PgDown; Quick Tile Top/Bottom have no shortcut |
| Win+PrtSc | Spectacle's active window capture | a new Spectacle action, `spectacle --background --fullscreen`, which saves the whole desktop to Pictures/Screenshots without opening Spectacle's window; the active window moves to Alt+PrtSc, as on Windows |

- **App shortcuts.** kglobalaccel reads app shortcuts from the `X-KDE-Shortcuts` keys of the desktop entries in `/usr/share/kglobalaccel` (some are links to the entries in `/usr/share/applications`), and the key `X-KDE-Shortcuts` of each `[Desktop Action ...]` group. `build/26-shortcuts.sh` changes those keys in place, like the Store rename. System Monitor's entry in `/usr/share/kglobalaccel` was a hard link to its menu entry, which editing would split, so the script replaces it with a symbolic link, as Dolphin's and Spectacle's already are.
- **KWin shortcuts.** kglobalaccel keeps the other global shortcuts in each user's `~/.config/kglobalshortcutsrc`, so `system/etc/skel/.config/kglobalshortcutsrc` gives every new account (created by Plasma Setup or `useradd -m`) the `[kwin]` entries for Win+Tab and Win+Up/Down, and takes those keys off the actions that had them by default. Each value is the active shortcut, Plasma's default and the action's name; every other shortcut keeps Plasma's default, and the user can change any of them in System Settings. Accounts created before this change keep their shortcuts.
- **Names.** `build/26-shortcuts.sh` uses `rename_entry` from `build/desktop-entry.sh` to name System Monitor **Task Manager** (`GenericName=System monitor`), Spectacle **Snipping Tool** (`GenericName=Screenshot tool`) and Dolphin **Files** (`GenericName=File manager`, as on the taskbar), and deletes their translated names. The apps' own windows still show their KDE names. KRunner keeps its name; it has no menu entry.
- **No clashes.** The script fails the build if two desktop entries share a shortcut. It does not see KWin's or Plasma's built-in shortcuts, which the boot test checks in the new user's `kglobalshortcutsrc`.

`tests/boot-test.sh` asks the new user's kglobalaccel which action each shortcut runs, fails if two actions in the user's `kglobalshortcutsrc` share a shortcut, presses Win+E and expects Files to start, and checks the names.

## The Store

OrielOS's app store is KDE Discover under another name, like Windows' Microsoft Store. Apps come only from Flathub, and users cannot add Fedora packages to the OS.

- **Name.** `build/25-store.sh` sets `Name=Store` and `GenericName=App store` in Discover's desktop entries (`org.kde.discover.desktop`, `.urlhandler`, `.notifier` and `.flatpak` in `/usr/share/applications`, and the notifier's entry in `/etc/xdg/autostart`) and deletes their translated `Name[..]` and `GenericName[..]` lines, which would still say Discover in other languages. The build fails if one of those files is missing or no longer says `Name=Discover`, so a package change cannot undo it silently. Discover's window title and in-app text still say Discover for now; they are in the program, not the desktop entries.
- **One source.** Discover's backends are plugins in `/usr/lib64/qt6/plugins/discover/`. Only `plasma-discover-flatpak` is installed, and neither PackageKit's Discover backend nor rpm-ostree's is present. The firmware backend, `fwupd-backend.so`, comes with `plasma-discover-libs`, so the build deletes it. `build/25-store.sh` fails unless the Flatpak backend and its notifier are the only plugins left. Flathub is the only remote (see [The desktop](#the-desktop)).
- **Firefox on first boot.** Firefox is the one preinstalled third-party app, and it comes from Flathub, not from Fedora. `orielos-flatpak-setup.service` (enabled by `80-orielos.preset`, and by `build/90-finalise.sh` because presets are not applied while the image builds) runs `/usr/libexec/orielos/flatpak-setup`, which makes sure the `flathub` remote exists (`flatpak remote-add --if-not-exists --system`), installs `org.mozilla.firefox` system-wide without prompts and then writes `/var/lib/orielos/flatpak-setup.done`. The service starts after `network-online.target` and is skipped once the stamp exists. It is a plain service, not a oneshot, so a slow download never holds up the login screen. If it fails, for example offline, `Restart=on-failure` with `RestartSec=5min` and no start limit runs it again every five minutes until it succeeds. `RuntimeMaxSec=1h` turns a stalled download into a failure that is retried. Flatpak keeps what it already downloaded.
- **Default browser.** `build/25-store.sh` sets `org.mozilla.firefox.desktop` for `text/html`, `x-scheme-handler/http` and `x-scheme-handler/https` in `/usr/share/applications/mimeapps.list`, which exists before any user does, and `BrowserApplication=org.mozilla.firefox.desktop` in `/etc/xdg/kdeglobals`. Flatpak exports Firefox's desktop file to `/var/lib/flatpak/exports/share/applications`, which is on `XDG_DATA_DIRS`. Until Firefox is installed, links have nothing to open them. [docs/apps.md](../docs/apps.md) explains this for users, and `tests/boot-test.sh` checks the Store and the Firefox install.

## First boot

The image has no user account, and installing it with `bootc install` creates none. On first boot KDE's Plasma Setup wizard asks for the language, keyboard layout, network, time zone and the first user account, which becomes an administrator, then opens the login screen. Fedora sets up its KDE editions the same way, and OrielOS wires it up the way Fedora does:

- `plasma-setup.service` is enabled, by `build/20-desktop.sh` and by `80-orielos.preset` (Fedora's own `90-default.preset` enables it too). It runs before SDDM on every boot until `/etc/plasma-setup-done` exists.
- When it runs, it writes `/etc/sddm.conf.d/99-plasma-setup.conf`, which makes SDDM log in the `plasma-setup` system user (created from `sysusers.d`, with its home in `/run/plasma-setup`) to a Plasma session that starts only the wizard.
- The wizard removes that autologin when it starts. When the user clicks Finish, it creates the account with a password and its own group, adds it to the groups in `/etc/xdg/plasmasetuprc` (`wheel`), copies the theme and display scaling chosen in the wizard to it, writes `/etc/plasma-setup-done` and logs out to the login screen.
- It offers to create an account only when there is no regular user (UID 1000 to 60000) yet, and never runs again once the done marker exists.

`build/90-finalise.sh` fails the build if `plasma-setup.service` is not enabled, if `/etc/plasma-setup-done` exists or if the image has a regular user. Plasma Setup looks as KDE and Fedora ship it for now; OrielOS's own styling will follow. `tests/boot-test.sh` checks both boots.

## Secure Boot

OrielOS boots with Secure Boot. Its kernel is signed by Fedora, but its NVIDIA, xone, xpadneo, OpenRazer and v4l2loopback modules are signed by Universal Blue's key, `/etc/pki/akmods/certs/akmods-ublue.der` ("ublue kernel"), and the kernel refuses them (`Loading of module with unavailable key is rejected`) until that key is in shim's Machine Owner Key (MOK) list. Enrolling it takes the user's confirmation on shim's MOK manager screen at boot, once; [docs/secure-boot.md](../docs/secure-boot.md) explains the steps for users.

- `orielos-secure-boot-key.service` (enabled by `80-orielos.preset` and by `build/90-finalise.sh`) is a oneshot that runs on every boot after `local-fs.target` and before the display manager. It runs `/usr/libexec/orielos/secure-boot-key`, which writes `/var/lib/orielos/secure-boot/state` (`key=value` lines, readable by everyone):
  - Secure Boot off (`mokutil --sb-state`): `key=not-needed`, and nothing else is done.
  - `mokutil --test-key` says the key is already enrolled: `key=enrolled`.
  - It says the key is already in the enrolment request: `key=pending`.
  - Otherwise it writes the hash of the one-time password `orielos` (`mokutil --generate-hash=orielos`) to a root-only temporary file in `/run`, runs `mokutil --import /etc/pki/akmods/certs/akmods-ublue.der --hash-file <file>`, deletes the file and records `key=pending` with the time in `requested=`. If a later boot finds the key neither enrolled nor queued, for example because shim dropped the request, it is queued again with a new time.
  - It also records `ca2023=present` or `ca2023=missing`, depending on whether `mokutil --db` lists Microsoft UEFI CA 2023 in the firmware's db. Microsoft's 2011 UEFI CA expired in June 2026, and newer shims are signed by the 2023 CA.
- The key path is fixed in the script: it imports Universal Blue's key and nothing else. OrielOS never generates or enrols a key of its own, which keeps it eligible for anti-cheat systems that check the module signing chain.
- In the Plasma session, the autostart entry `/etc/xdg/autostart/orielos-secure-boot-notify.desktop` runs `/usr/libexec/orielos/secure-boot-notify`, which reads the state and shows, with `notify-send` from `libnotify`: "Finish setting up your graphics driver" with the steps on shim's screen and a **Restart now** button while the key is pending, and "Your PC needs a firmware update" when `ca2023=missing`. Each is shown once per state change (a new request counts as one), remembered in `~/.local/state/orielos/secure-boot-notified`. These texts are the source strings for translation.

`build/90-finalise.sh` fails the build if the service is not enabled, if the scripts are not executable, if the key, the autostart entry, `mokutil` or `notify-send` is missing, or if the state folder is in the image. The VM tests enrol the key in the VM's firmware beforehand, and `tests/secure-boot-key-test.sh` tests the user's steps on shim's screen (see [tests/README.md](../tests/README.md)).

## Anti-cheat boot mode

Every OrielOS boot meets Easy Anti-Cheat's published Linux requirements. There is one boot entry, and it is always in this mode:

- Secure Boot (see [Secure Boot](#secure-boot)), with only modules signed by Fedora or Universal Blue (`module-signers.txt`).
- Kernel lockdown in integrity mode and the IOMMU on without passthrough: `system/usr/lib/bootc/kargs.d/20-orielos-anticheat.toml` adds `lockdown=integrity intel_iommu=on iommu.passthrough=0`. bootc applies `kargs.d` files when it installs the image and on every update. AMD processors turn their IOMMU on by default, so they need no argument of their own.
- The BPF LSM: Fedora's kernel lists `bpf` in its built-in default LSM list, so there is no `lsm=` argument, which would replace that list.
- kexec disabled from early boot: `system/usr/lib/sysctl.d/60-orielos-kexec.conf` sets `kernel.kexec_load_disabled = 1`, which `systemd-sysctl` applies early and which cannot be unset until the next restart. `kexec-tools` is removed with the server defaults.
- No hibernation, because kernel lockdown rules it out: `system/usr/lib/systemd/sleep.conf.d/50-orielos.conf` sets `AllowHibernation=no`, `AllowSuspendThenHibernate=no` and `AllowHybridSleep=no`. logind's `CanHibernate` is then not `yes`, so Plasma and SDDM do not offer Hibernate. Sleep still works.

`build/86-check-boot-security.sh` checks all of this while the image builds, and `tests/boot-test.sh` checks it in the running system. [docs/anti-cheat.md](../docs/anti-cheat.md) explains it for users.

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
