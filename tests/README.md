# tests

Automated and manual checks for the image.

## Boot test

`boot-test.sh` installs the image to a 30 GiB disk file with `bootc install to-disk`, boots it headless under QEMU/KVM with Secure Boot firmware and a software TPM, and boots it twice:

1. **First boot.** The disk has no user account, so Plasma Setup, KDE's first-boot wizard, should start. The test checks that it did, takes `first-boot.png`, then finishes setup over SSH the way the wizard does (see [Finishing setup](#finishing-setup)) and restarts the VM.
2. **Second boot.** Plasma Setup must not run again, and SDDM shows the login screen. The test checks the services, starts OrielOS's apps and logs the user that setup created in to the Plasma desktop.
3. **Third boot.** Last, the test drives OrielOS's Start menu with the keyboard and pins an app, then restarts the VM once more to check that the pin is kept, takes screenshots of the rest of the menu and unpins the app (see [Start menu](#start-menu)).

The installation is left to the image's own install configuration, so the test also proves that the root filesystem is Btrfs with zstd compression.

```sh
tests/boot-test.sh                          # tests localhost/orielos:latest
tests/boot-test.sh --archive FILE           # loads an OCI archive from tools/build-image.sh first
tests/boot-test.sh --keep --timeout 300
```

Run `tests/boot-test.sh --help` for all the options. It needs the tools that `tools/check-env.sh` checks for, and runs as root (it uses `sudo` when needed). A run takes about ten minutes, most of it the installation and the two boots. `--timeout` applies to each boot. If SDDM has started but `graphical.target` isn't in the serial log a minute later, the wait for that boot ends there: on some builds, once agetty takes the serial console, systemd's later status lines are missing from it.

It prints PASS or FAIL for thirty-two checks, under a "First boot", a "Second boot", a "Store and Firefox", a "Visual check", a "Start menu" and an "Anti-cheat boot mode" heading, and exits with status 0 only if all thirty-two pass.

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
14. Gaming defaults are set: `lsmod` lists `ntsync` and `/dev/ntsync` exists; `sysctl` gives `vm.max_map_count` 1048576 and `kernel.split_lock_mitigate` 0; transparent hugepages are `[madvise]`; `swapon` shows a zram device; and `ananicy-cpp` is not installed.
15. Gaming system pieces are installed: `gamemode`, `umu-launcher`, `steam-devices`, `solaar-udev`, `libratbag-ratbagd`, `openrgb-udev-rules` and `zram-generator-defaults` are installed, `umu-run` is on the path, `modinfo -F signer` gives `ublue kernel` for `xone_gip` and `hid_xpadneo` and a signer for the kernel's own `hid_playstation`, and the PlayStation touchpad rule, `70-orielos-playstation-touchpad.rules`, is in `/usr/lib/udev/rules.d`.
16. Fedora's countme reporting is off: no file in `/etc/yum.repos.d` sets `countme=1`, and `systemctl is-enabled rpm-ostree-countme.timer` says `disabled`.
17. Kernel modules are signed by Fedora or Universal Blue: `modinfo -F signer nvidia` prints `ublue kernel`; `rpm -q kernel` matches the kernel installed in the image (read with `rpm -q kernel-core` in the container, because the base image's `ostree.linux` label still names the base kernel); and the NVIDIA driver packages (the same set that the image build checks) have exactly one version between them. `rpm -q kernel` and the driver version are printed as INFO lines. The module is not loaded in a VM without an NVIDIA GPU; `modinfo` reads the file, which is what the check needs.
18. Universal Blue's key is trusted: `mokutil --test-key /etc/pki/akmods/certs/akmods-ublue.der` says the key is already enrolled, `/var/lib/orielos/secure-boot/state` says `key=enrolled`, the kernel log has no `Loading of module with unavailable key is rejected` line, `lsmod` lists `v4l2loopback` (signed by Universal Blue and loaded at every boot) and `systemctl is-active systemd-modules-load.service` says `active`. The VM's firmware has the key in shim's MokList from the start (see [Universal Blue's key](#universal-blues-key)). With `--no-mok` the check expects the opposite: `key=pending`, and `mokutil --list-new` showing one key, `ublue kernel`.
19. The OrielOS taskbar is set up: after the scripted desktop login, `orielostest`'s `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, which Plasma wrote from OrielOS's layout script because the user is brand new, has exactly one panel (`plugin=org.kde.panel`), at the bottom (`location=4`). Its widgets, in the panel's `AppletOrder`, are a panel spacer, OrielOS's Start menu, the icons-only task manager, a panel spacer, the system tray, the digital clock and show desktop; and the task manager's `launchers` include `org.kde.dolphin.desktop`, `org.mozilla.firefox.desktop` and `org.kde.discover.desktop`. The file is saved as `plasma-appletsrc` in the results. Look at `desktop.png` too: it should show the Start button, three blue panes over an amber bar, and the pinned apps in the centre of the taskbar, and the tray and clock at the right.
20. Taskbar: Start is OrielOS's Start menu: in the same file, the panel holds `org.orielos.startmenu` and none of Plasma's launchers (Kickoff, Kicker or the application dashboard), and the Start menu's `icon` is `orielos-start`, the Start button icon from `artwork/icons/orielos-start.svg`.
21. The OrielOS wallpaper is set: in the same file, the desktop (the containment with an `activityId`; panels have none) has `Image=file:///usr/share/wallpapers/OrielOS/` in its `[Wallpaper][org.kde.image][General]` group, and `/usr/share/wallpapers/OrielOS/contents/images/3840x2160.jpg` exists in the VM. `desktop.png` should show Daybreak, the light image: a pale blue sky through a glass bay window above a warm sill.
22. Windows shortcuts are set: in `orielostest`'s session, the test asks kglobalaccel over the user's D-Bus (`busctl --user -M orielostest@ call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel action i <key code>`, or `globalShortcutsByKey` if `action` gives nothing) which action each shortcut in [docs/keyboard-shortcuts.md](../docs/keyboard-shortcuts.md) runs, and expects the component and action listed in `SHORTCUT_TABLE` in the script, for example `kwin` `Overview` for Win+Tab and `org.kde.plasma-systemmonitor.desktop` `_launch` for Ctrl+Shift+Esc. `kreadconfig6 --file kwinrc --group ModifierOnlyShortcuts --key Meta`, run as the user, must be empty (Plasma's default, Start) or name Plasma's `activateLauncherMenu`, and no shortcut may be the active one of two actions in the user's `~/.config/kglobalshortcutsrc`. The test then presses Win+E with QMP `send-key` and expects a `dolphin` process for the user within 20 s, and the menu entries of System Monitor, Spectacle and Dolphin must be named Process Manager, Screenshot and Files, and OrielOS's clipboard entry, `org.orielos.ClipboardHistory.desktop`, Clipboard history. The user's `~/.config/kglobalshortcutsrc` is saved as `kglobalshortcutsrc` in the results.

Checks 3 to 22 read the second boot only: before restarting, the test notes how long the serial log is, and afterwards it reads from the new kernel's first line on, up to where the Start menu checks restart the VM again. Any other unit that failed to start on the second boot is reported as a WARN and does not fail the test. The times from power-on to SDDM and to Plasma Setup's wizard, the time from the restart to SDDM, the time until SSH answered, the output of `systemctl is-system-running` and the list of failed units are printed as INFO lines too.

Store and Firefox, after the second boot:

23. Store is Discover with Flathub only: `flatpak remotes --system` lists only `flathub`, `/usr/share/applications/org.kde.discover.desktop` has `Name=Store`, and `/usr/lib64/qt6/plugins/discover/` holds only `flatpak-backend.so`, so Discover has no system-package, image or firmware backend.
24. Firefox is installed on first boot: `/var/lib/orielos/flatpak-setup.done` exists (the test waits up to 10 minutes for it), `flatpak list --system --app --columns=application` contains `org.mozilla.firefox`, and `xdg-mime query default x-scheme-handler/https`, run as `orielostest` in a login shell, prints `org.mozilla.firefox.desktop`. The VM has user-mode networking with internet access through the host, so the download is real. It starts on the first boot, so the install is timed from the first power-on; the time and Firefox's version are printed as INFO lines. The test waits for it last, after the other checks, so the download runs alongside them. If the wait runs out, the last lines of the service's journal are printed.

Visual check, once Firefox is installed (see [Visual check](#visual-check)):

25. Visual check: the desktop matches its reference: `visual-desktop.png` matches `references/desktop.png`.
26. Visual check: the Start menu matches its reference: `visual-start.png` matches `references/start.png`.

Start menu, after every other second-boot check, because it restarts the VM (see [Start menu](#start-menu)):

27. Start menu: typing a search runs nothing: after Win and `f`, `i`, `l`, no `dolphin` process starts for `orielostest` within 5 seconds. The menu is saved as `start-search.png`.
28. Start menu: Enter opens the first result: Enter then starts `dolphin` for `orielostest` within 20 seconds.
29. Start menu: pinning saves the app: after Win, `a`, `r`, `k`, the Menu key and Enter, the `favorites` key in the Start menu's `[Containments][N][Applets][M][Configuration][General]` group of `orielostest`'s `~/.config/plasma-org.kde.plasma.desktop-appletsrc` contains `org.kde.ark.desktop` within 30 seconds. The file is saved as `start-appletsrc`, and the open context menu as `start-pin-menu.png`. The test presses QEMU's `compose` key, which is a PC keyboard's Menu key.
30. Start menu: pins survive a restart: after restarting the VM and SDDM's autologin, the same key still contains `org.kde.ark.desktop`. The file is saved as `start-appletsrc-restart`, and the open menu as `start-pinned.png`, which should show Ark among the pinned apps.
31. Start menu: unpinning removes the app: after Win, `a`, `r`, `k`, the Menu key and Enter on the pinned Ark, the same key no longer contains `org.kde.ark.desktop` within 30 seconds. The file is saved as `start-appletsrc-unpinned`, and the open context menu, with "Unpin from Start" highlighted, as `start-unpin-menu.png`.

Anti-cheat boot mode, on the second boot (see `image/README.md`):

32. The boot is anti-cheat ready: `/proc/cmdline` contains `lockdown=integrity`, `intel_iommu=on` and `iommu.passthrough=0`; `/sys/kernel/security/lockdown` shows `[integrity]`; `/proc/sys/kernel/kexec_load_disabled` is `1`; `/sys/kernel/security/lsm` includes `bpf`; logind's `CanHibernate` (`busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager CanHibernate`) is not `yes`; and every module in `/proc/modules` has a `modinfo -F signer` value listed in `image/module-signers.txt`, which the test reads on the host. The lockdown state, the active LSMs and the number of loaded modules checked are printed as INFO lines, and a failure names the unsigned or unexpected modules. The VM has no virtual IOMMU, so `intel_iommu=on` finds no DMAR table there, which is harmless; the check reads the argument, not the hardware.

### Finishing setup

Plasma Setup's wizard has no scripting interface, so the test does over SSH what the wizard does when the user clicks Finish:

1. It creates `orielostest` with `useradd -m -U`, adds it to the groups in `/etc/xdg/plasmasetuprc` (`wheel`) and sets a random password with `chpasswd`.
2. It copies the theme and display scaling chosen in the wizard (`kdeglobals`, `kwinoutputconfig.json` and `kwinrc` from `/run/plasma-setup/.config`, where they exist) to the new user.
3. It removes the wizard's SDDM autologin, `/etc/sddm.conf.d/99-plasma-setup.conf`, which the wizard already removes when it starts.
4. It writes the done marker, `/etc/plasma-setup-done`, with the same "Plasma Setup completed at" line.

The wizard then logs out to the login screen; the test restarts the VM with `systemctl reboot` instead, which also proves that the marker survives a restart.

### Universal Blue's key

OrielOS's NVIDIA, xone, xpadneo, OpenRazer and v4l2loopback modules are signed by Universal Blue's key, which a new PC asks the user to confirm once on shim's blue screen (see [docs/secure-boot.md](../docs/secure-boot.md)). So that the VM tests boot like a PC where that is done, `lib/vm.sh` reads the key from the image (`podman run --rm <image> cat /etc/pki/akmods/certs/akmods-ublue.der`) and adds it to shim's MokList in the VM's copy of the firmware variables with `virt-fw-vars --add-mok`, from the `python3-virt-firmware` package. The boot test and the update test both get it. `tests/boot-test.sh --no-mok` leaves it out, and `secure-boot-key-test.sh` tests the user's steps.

### Console output

The image boots with `rhgb quiet` for its splash screen, which hides kernel and service messages. Checks 3 to 8 read those messages from the serial console, so the test installs with `systemd.show_status=1` and `ignore_loglevel` after the console arguments, which print them there again. It also adds `plymouth.enable=0`, which turns the boot splash off: while the splash runs, Plymouth takes over the console output, so systemd's status lines never reach the serial console. These arguments are for the test only, so the test does not show the splash.

### Desktop login

On the second boot, after the login screenshot, the test logs the user that setup created in to Plasma the way SDDM would at boot:

1. It writes `/etc/sddm.conf.d/99-boot-test-autologin.conf` with an `[Autologin]` section for that user and the Plasma Wayland session, `plasma.desktop` from `/usr/share/wayland-sessions/`.
2. It restarts SDDM, which logs the user in.
3. It waits up to 90 seconds for the session, then 15 seconds more for the desktop to draw, and takes `desktop.png`.
4. It copies the user's Plasma layout, `~/.config/plasma-org.kde.plasma.desktop-appletsrc`, for checks 19 to 21.

Restarting SDDM stops it on purpose, so check 7 reads the console only up to the restart.

### Start menu

After the other checks on the second boot, the test uses OrielOS's Start menu the way a person would, with keys sent over QMP `send-key`:

1. It stops the `dolphin` that Win+E started (`pkill -u orielostest -x dolphin`) and waits for it to go.
2. It presses Win alone, waits 2 seconds, types `f`, `i`, `l` about 0.3 seconds apart, waits 3 seconds and takes `start-search.png`. For check 27, no `dolphin` may start in the next 5 seconds: typing only lists results.
3. It presses Enter, which runs the first result, Files, and waits up to 20 seconds for `dolphin` (check 28), then stops it again.
4. It opens the menu again and types `ark`. Ark is not pinned by default. The Menu key opens the result's context menu with "Pin to Start" highlighted, so Enter pins it, and Escape closes the menu. Plasma saves widget settings a few seconds after they change, so the test reads the layout file for up to 30 seconds (check 29).
5. It restarts the VM. The autologin written for the desktop login stays in `/etc/sddm.conf.d`, so SDDM logs `orielostest` straight back in; the test waits up to `--timeout` seconds for the session, reads the layout file again (check 30), opens the menu and takes `start-pinned.png`.
6. It writes `~/Documents/orielos-notes.txt` and tells the session's activity manager that an editor accessed it (`RegisterResourceEvent` on `org.kde.ActivityManager.Resources`, event 0), as KIO does when it opens a file in an app. It opens the menu and takes `start-recommended.png`, which should list the file under Recommended. Firefox isn't listed there as recently added: Plasma counts an app as new only when it appears after the session first lists the apps, and the first boot installs Firefox before the test user's first session.
7. It presses Tab six times, taking `start-tab-1.png` to `start-tab-6.png`: the focus should go from the search field to All apps, the pinned apps, Recommended, the account button and the power button, then back to the search field.
8. It opens the menu, presses Shift+Tab, which goes round to the power button, and Enter, and takes `start-power-menu.png`, which should offer Sleep, Restart and Shut down and no hibernation. Two Shift+Tabs and Enter give `start-account-menu.png`, with Account settings, Lock, Switch user and Sign out.
9. It types `ark` again. Ark is pinned now, so the Menu key offers "Unpin from Start" first, and Enter unpins it (check 31).

If a step cannot be done, because the VM stopped, SSH did not answer or the session did not start, the remaining Start menu checks fail with the reason. The other checks keep reading the second boot: the test puts back its SSH state and its part of the serial log after the restart.

### Visual check

Once Firefox is installed, the test closes the Dolphin that Win+E started, waits 10 seconds for the desktop to settle, takes `visual-desktop.png`, presses Win and takes `visual-start.png` 4 seconds later. Checks 25 and 26 compare them with the reference images in `references/`, using `lib/screens.py`, which needs Pillow:

- A pixel counts as changed when any colour channel differs by more than 32 out of 255, which absorbs anti-aliasing and font rendering differences.
- The areas in `references/desktop.mask` and `references/start.mask` are ignored: one `x y width height` rectangle per line, in pixels of the VM's 1280×800 screen. Both masks leave out the system tray, the clock and Show desktop. The Start menu's mask also leaves out Recommended's list: Firefox shows there as recently added when its installation ends after the session first lists the apps, which depends on how fast the download is.
- A screenshot matches when at most 1 in 100 of the other pixels changed. That catches a moved panel, a missing taskbar, a different wallpaper or theme, or a Start menu laid out differently, but not one app more or less among the pinned ones, which the Start menu checks cover.

When a check fails, `visual-desktop-diff.png` or `visual-start-diff.png` shows the screenshot dimmed, with the changed pixels in red and the ignored areas in blue.

When a change to the desktop is intended, look at the new screenshots, then replace the references with them and commit the images with the change:

```sh
tests/update-references.sh tests/results/<run id>
tests/update-references.sh tests/results/<run id> --only start
```

The script prints how much each new image differs from the one it replaces. It is the only way the references should change.

### Commands inside the VM

On each boot, once SDDM has started, the test logs in to the VM as root over SSH and runs the commands for the checks. The connection goes through a vsock device rather than the network, so the image needs no open port and no password:

- Each run creates a new ed25519 key in its work folder and picks a random vsock guest CID.
- QEMU gets a `vhost-vsock-pci` device with that CID, and the public key as the `ssh.authorized_keys.root` systemd credential through SMBIOS.
- In the VM, systemd's SSH generator makes sshd listen on vsock port 22 with that key, about 20 seconds after boot.
- The test connects with `ssh` through `systemd-ssh-proxy` (with `ProxyUseFdpass=yes`, which the proxy needs) and waits up to 60 seconds for SSH to answer.

The host needs `/dev/vhost-vsock` (the test loads the `vhost_vsock` module when it is missing) and `systemd-ssh-proxy`, which comes with systemd 256 or newer; `tools/check-env.sh` checks both. The SSH server's own service, `sshd.service`, is disabled in the image; the vsock socket starts `sshd` without it. The key and the vsock device stay the same across the restart. If SSH never answers on the first boot, the test cannot finish setup or restart, and every check that needs SSH fails with a hint; the checks based on the console still run.

Results go to `tests/results/<run id>/` (ignored by git), or to the folder given with `--results`. The run id is `<image tag>-<UTC time>`. The folder holds:

- `serial.log`: the VM's console output from every boot, with colour codes removed.
- `install.log`: the output of the installation.
- `first-boot.png`: Plasma Setup's wizard on the first boot.
- `screenshot.png`: the login screen on the second boot, taken after pressing a key so the form is visible.
- `desktop.png`: the Plasma desktop after the scripted login.
- `plasma-appletsrc`: the test user's Plasma layout, read after the scripted login.
- `start-search.png`: the Start menu listing the results for "fil".
- `start-appletsrc` and `start-appletsrc-restart`: the test user's Plasma layout after pinning Ark, and again after the last restart.
- `start-pinned.png`: the Start menu after the last restart, with Ark pinned.
- `start-recommended.png`, `start-tab-1.png` to `start-tab-6.png`, `start-power-menu.png`, `start-account-menu.png` and `start-unpin-menu.png`: Recommended, the Tab order, the two menus and unpinning, for reading by eye. `start-appletsrc-unpinned` is the layout after unpinning.
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

Then it tests the background update service, which normally gets builds from a registry:

8. **A local update source.**
   - In the VM, `skopeo copy` puts the new build into an OCI directory, `/var/lib/orielos/test-source`, tagged `testing`. `/etc/orielos/update.conf` points `source=` at it.
   - The stable channel has no build there, so `orielos-update check` must stage nothing and report `unreachable`.
9. **Channels and pause.**
   - `orielos-update channel testing`, then a check: it must skip the new build, which step 6 rolled back, and report `rejected`.
   - `orielos-update forget` that build and `orielos-update pause 1`, then a check: it must stage nothing and report `paused`.
   - `orielos-update resume`.
10. **The desktop.**
    - SDDM's autologin logs `orielostest` in to Plasma, and the update notifier must start there with a tray icon on the session bus.
    - `systemctl start orielos-update-check.service`, the unit the timer starts, must stage the new build.
    - The notifier's tray icon must turn Active. `update-ready.png` shows the screen, with the notification.
11. **Restart to update.**
    - The notifier's "Restart to update" menu item is clicked over the session bus, through the tray icon's `com.canonical.dbusmenu` interface, as the tray does.
    - The VM must restart into the new build, and this boot's `state.json` must say `up-to-date` with nothing staged.
    - `keepme.txt` must be unchanged.

Then it uses the Update settings page, goes back from there and checks the boot menu:

12. **Settings → Update.** The test drives the page with the keyboard over QMP: every button and option has an Alt mnemonic, and the test types the password into polkit's prompt and presses Enter.
    - `orielostest` gets a known password, because changing the channel and going back need an administrator and polkit asks for theirs.
    - The notifier's menu must offer only "Open update settings" (and restarting, when there's something to restart for): no pause, channel, going back or checking.
    - The test clicks the tray icon itself, calling `Activate` on its `org.kde.StatusNotifierItem` interface as the tray does. Settings must start with `orielos-settings kcm_orielos_update` within 60 s (`settings-page.png`).
    - The test then closes Settings and opens the same page with `kcmshell6 kcm_orielos_update`, through `systemd-run --user` in `orielostest`'s session (`settings-window.png`). There the page is alone in its window, so no other control takes the keys: in System Settings, any letter no shortcut claims goes to the sidebar's search field.
    - Alt+U, **Check for updates**: `state.json`'s `checkedAt` must change (`settings-checked.png`).
    - Alt+P, **Pause updates** with the first choice: `pausedUntil` must be 7 days ahead (`settings-paused.png`). Alt+R, **Resume updates**: it must be `null` again.
    - Alt+S, **Stable**, and the password (`channel-password.png`): the channel must be `stable` (`settings-stable.png`). Alt+T, **Testing**: it must be `testing` again; polkit may keep the authorisation, so the test types the password only if the channel hasn't changed after 10 s.
    - Alt+A, **Update apps automatically**, once no `orielos-update` is running (the page disables its controls until then): `state.json` must say `appUpdates` false, with no password asked (`settings-apps-off.png`); Alt+A again turns it back on.
    - Alt+G, **Go back to the previous version…**. The question's default is Cancel, so the test presses Alt+B for **Go back**, then types the password. `go-back-question.png` and `go-back-password.png` show both. `state.json` must then say `rollbackQueued`, and the new build must be in `rejected-digests`.
    - The tray icon must be Active and offer "Restart to go back" (`go-back-ready.png`). The test presses Alt+N, **Restart now** on the page, and the VM must restart into the old build, with `keepme.txt` unchanged.
13. **The boot menu.** The firmware copies GRUB's screen to the serial console, so the test reads it there. For each restart it watches the serial log from `systemctl reboot` until the kernel prints `Linux version`.
    - `/boot/grub2/grub.cfg` must include `12_orielos-menu.cfg`, and the boot entries must be `OrielOS <old version> (ostree:0)` and `OrielOS <new version> (ostree:1)`.
    - Within 120 s of the desktop starting, `orielos_boot_ok` must be `1` in `EFI/fedora/orielos-boot.env` on the EFI system partition.
    - After a restart, the menu must stay hidden.
    - With `multi-user.target` as the default, so the display manager never starts, the next boot must leave the flag at `0`. The test then sets `graphical.target` back. Nothing was on trial, so the restart after that must show no menu and start the old build as usual.
    - At the next restart the test presses Esc once, as soon as the firmware starts GRUB. The menu must appear (`boot-menu-esc.png`), highlighting the old build, and Enter must start it. The test reads the menu from the serial console, where GRUB marks the highlighted entry with `*`. A second Esc would close the menu again and leave GRUB at a `grub>` prompt, so the test presses it only once.
14. **An update that doesn't start is undone.**
    - The test forgets the new build's rejection, and `orielos-update check` stages it again. The flags must then say `orielos_trial=1`.
    - The test makes the new build fail to reach the desktop. It sets `multi-user.target` as the old build's default before the restart, so the new build's `/etc` gets it too. Once the new build is running, it sets the old build's own default back on disk.
    - The new build starts once and fails, then starts again, with `orielos_fails=1`, and fails again. No menu may appear.
    - At the third restart, the old build must start, with no menu. `state.json` must say `went-back` with nothing queued, and the new build must be rejected.
    - The desktop must start, with the notifier, and `update-undone.png` shows the notification. The next restart must start the old build again.
15. **The last resort, and removing the previous build.**
    - The test sets the flags as they'd be if the kept build failed too (`orielos_boot_ok=0`, `orielos_trial=kept`). The next start must show the menu by itself, listing both builds and highlighting the old one (`boot-menu-last-resort.png`), and Enter must start the old build.
    - The test moves the running build's first start, in `/var/lib/orielos/update/running`, 15 days back and runs a check. The previous build must then be gone: bootc reports none, one boot entry is left, and `state.json` has no previous build.
16. **Removing the previous version from Settings → Update.**
    - The test forgets the new build's rejection, stages it with a check and restarts into it, so the old build is the previous one again, kept until a date 14 days on.
    - The tray icon opens the page (`settings-previous.png`), and `state.json` must name the old build with its removal date. The test opens the page in `kcmshell6` again (`settings-previous-window.png`).
    - Alt+M, **Remove the previous version…**, then Alt+E for **Remove** in the question, and the password (`remove-question.png`, `remove-password.png`). Within 180 s `state.json` must have no previous build, bootc must report none, and one boot entry must be left (`settings-removed.png`).
17. **Apps from the Store update by themselves.**
    - The test waits for the first boot's Firefox install, then moves Firefox back to the version before the newest: `flatpak update --commit` with the `Parent` that `flatpak remote-info` gives for the newest.
    - With `orielos-update app-updates off`, `orielos-app-update.service` must leave Firefox as it is.
    - With app updates on again, the service must bring Firefox to the newest commit, and `state.json` must say when, in `appsUpdatedAt`.

```sh
tests/update-test.sh --old localhost/orielos:44.20261025 --new /var/lib/orielos/builds/orielos-44.20261026.ociarchive
tests/update-test.sh --old OLD.ociarchive --new NEW.ociarchive --keep
```

`--old` takes an image in Podman or an OCI archive, which is loaded as `localhost/orielos-archive:<file name>` first; `--new` takes an OCI archive from `tools/build-image.sh`. Run `tests/update-test.sh --help` for all the options. It needs the same tools as the boot test and runs as root. A run takes about an hour and a quarter: the installation, about sixteen restarts, copying the archive, importing it three times and several desktop logins.

Each restart is started with `systemctl reboot` over SSH; the VM restarts in place. The test waits for SSH to go away and answer again, then checks that `/proc/sys/kernel/random/boot_id` changed. `--timeout` is how long it waits for SSH after power-on and after each restart.

It prints PASS or FAIL for fifty-three checks, one or more per step, and exits with status 0 only if all of them pass. If a step fails in a way that the later steps depend on, the test stops there and reports that as a failure too.

Results go to `tests/results/<run id>/`, or to the folder given with `--results`. The run id is `update-<new build's tag>-<UTC time>`. The folder holds:

- `summary.txt`: the same lines as the test printed.
- `install.log` and `serial.log`: the installation's output and the VM's console output from every boot.
- `bootc-status-<step>.json` and `status-<step>.txt`: the output of `bootc status --format=json` and `orielos-update status` after each step (`old`, `staged`, `new`, `rolled-back` and `final`).
- `stage.txt`, `rollback.txt` and `stage-again.txt`: the output of those `orielos-update` commands.
- `service.txt`: the output of the `orielos-update` commands in steps 8 to 10, and `bootc-status-service-<step>.json` and `status-service-<step>.txt` after them.
- `state-staged.json` and `state-updated.json`: `/var/lib/orielos/update/state.json` once the check service has staged the build, and after the restart.
- `update-ready.png`: the desktop once the update is staged.
- `notifier.txt`: the test user's processes and the journal's lines about the notifier, when it didn't start.
- `settings-page.png`, `settings-window.png`, `settings-checked.png`, `settings-paused.png`, `channel-password.png` and `settings-stable.png`: the Update settings page as step 12 uses it, and polkit's prompt. `settings-resume.png` and `settings-testing.png` exist only if resuming or switching back failed. `settings.txt`: the test user's processes and the journal's lines about System Settings, when the page didn't open.
- `go-back-question.png`, `go-back-password.png` and `go-back-ready.png`: the question, polkit's prompt, and the desktop once going back is queued. `bootc-status-go-back.json`, `bootc-status-went-back.json` and their `status-*.txt` files are taken after the prompt and after the restart.
- `settings-previous.png`, `settings-previous-window.png`, `remove-question.png`, `remove-password.png` and `settings-removed.png`: step 16's page, question, prompt and the page once the previous version is removed.
- `boot-menu-esc.png` and `boot-menu-last-resort.png`: the boot menu after Esc, and when it appears by itself. `update-undone.png`: the desktop after an update was undone. `boot-menu-unexpected.png` exists only if the menu appeared when it shouldn't have. `boot-entries.txt` lists the boot entries' titles and version keys at the start of step 13 and before each of its restarts. `bootc-status-boot-menu.json` and `bootc-status-boot-menu-esc.json` show which build started.
- `settings-apps-off.png`: the page with app updates turned off. `apps.txt`: the output of step 17's commands and the app update service's journal.
- `boot-success.txt`: the journal of the units that mark a boot as good, when the flag wasn't set.

The work folder and `--keep` work as in the boot test.

## Rollback test

`rollback-test.sh` checks that an update which can't reach the desktop is undone without asking, as a new user would meet it: no boot menu, no prompt, and the computer back on the version that worked. The update test covers the same path among its other steps; this test does only that, in about half an hour. It uses the same VM as the boot test, with SSH over vsock:

1. **Build A.** It installs build A, finishes setup (see [Finishing setup](#finishing-setup)) and turns on SDDM's autologin for `orielostest`. After the restart, A must run and the desktop must mark the boot as good (`orielos_boot_ok=1` in the boot menu's flags on the EFI system partition) within 120 seconds.
2. **Stage build B.** It copies B's archive into the VM and stages it with `orielos-update stage`. bootc must report B as staged, with the manifest digest read from the archive, and the flags must put B on trial (`orielos_trial=1`). The test then sets `multi-user.target` as A's default, so B, whose `/etc` is merged from A's at the restart, never starts the display manager.
3. **B fails twice.** B must start first, with no boot menu. Once it's running, the test puts A's own default back to `graphical.target` on disk. B must then start once more, with no menu and `orielos_fails=1`, and fail again.
4. **A by itself.** The third start must be A, with no menu or prompt. `state.json` must say `went-back` with nothing queued, and B's digest must be in `rejected-digests`. A's desktop must mark the boot as good again, and the next restart must start A once more.

For each restart the test watches the serial console, where the firmware copies GRUB's screen, from `systemctl reboot` until the kernel prints `Linux version`. If GRUB's menu appears, the test saves `boot-menu-unexpected.png` and the check fails.

```sh
tests/rollback-test.sh --old localhost/orielos:44.20261025 --new /var/lib/orielos/builds/orielos-44.20261026.ociarchive
```

`--old` and `--new` take the same as in the update test. It prints PASS or FAIL for eight checks and stops at the first step that fails. Results go to `tests/results/rollback-<B's tag>-<UTC time>/`, or to the folder given with `--results`: `summary.txt`, `install.log`, `serial.log`, `stage.txt`, and `bootc-status-<step>.json` and `status-<step>.txt` after each start (`a`, `staged`, `b-first`, `b-second`, `undone` and `after`). The work folder and `--keep` work as in the boot test.

## Unit tests

`unit/` holds quick tests for the shell tools that need no root, VM or network. `tools/lint.sh` runs every `unit/*-test.sh`, so CI runs them on every pull request.

- `unit/orielos-update-test.sh` runs the real `orielos-update` against a scratch directory (`ORIELOS_UPDATE_ROOT`), with a fixed clock (`ORIELOS_UPDATE_NOW`). Stand-ins for `bootc`, `skopeo`, `busctl`, `systemctl` and `flatpak` sit first on `PATH`, record their arguments and return prepared answers. It covers:
  - pausing for 1 and 5 weeks, refusing other lengths, checks while paused, a pause that has ended, and resuming;
  - the default channel, switching channel, keeping a pause when switching, and refusing unknown channels;
  - up-to-date, newer, already staged and rejected builds, an unreachable source, and metered connections;
  - a failed stage, the registry and OCI directory sources, a channel that moves while staging, an unsupported source, and `check-now`;
  - the state file's fields, types and permissions, and `refresh` before any check, after a check and after restarting into an update;
  - the previous build and whether it was rejected, `rollback` with and without a previous build, a check while going back is queued, and `refresh` after restarting into the previous build;
  - putting a staged build on trial, and taking it off when going back;
  - undoing an update after the boot loader fell back, at boot and through `undo-update`, and only then;
  - automatic app updates: on by default, turning them off and on, keeping the setting when pausing or changing channel, updating apps with `flatpak` and recording when, doing nothing while they're off or the connection is metered, a failed update, and wrong usage;
  - when the previous build is removed: after 14 days, by the check only and even while paused, not while an update is staged or going back is queued, and through `remove-previous`.
- `unit/first-run-power-test.sh` runs the first-run setup's power helper in a scratch root folder (`ORIELOS_FIRST_RUN_ROOT`), with a stand-in for `kwriteconfig6`. It covers the settings written for sleep and the screen with a time or never, a second choice replacing the first, the longest wait, refusing once the setup has finished, and wrong arguments.
- `unit/boot-flags-test.sh` runs the boot menu's flag helper on a plain file (`ORIELOS_BOOT_FLAGS_FILE`), with stand-ins for `grub2-editenv` and `orielos-update`. It covers each command's effect on the flags, keeping the previous build after a fallback (and what's left when that fails), `status`, and wrong usage.

## Secure Boot key test

`secure-boot-key-test.sh` tests enrolling Universal Blue's key the way a user does. It installs the image the way the boot test does and boots it with the stock Microsoft firmware variables, so shim's MokList is empty, like on a new PC:

1. **First boot.** Over SSH it waits for `orielos-secure-boot-key.service`, then checks that `/var/lib/orielos/secure-boot/state` says `key=pending` and `ca2023=present`, that `mokutil --list-new` shows exactly one key, `CN=ublue kernel`, and that `v4l2loopback` is not loaded, because the kernel refuses it.
2. **shim's MOK manager.** It restarts the VM over SSH. A QMP client waits for the guest's `RESET` event, then takes screendumps until more than half the screen is the firmware console's blue, and saves `mok-1.png`. It then presses the keys in `MOK_STEPS` with QMP `send-key`: a key to start MOK management, Down and Enter for **Enroll MOK**, Down and Enter for **Continue**, Down and Enter for **Yes**, the password `orielos` and Enter, and Enter for **Reboot**, with a screenshot after each step (`mok-2.png` to `mok-7.png`). shim waits only 10 seconds for the first key.
3. **After the restart.** It checks that `mokutil --list-enrolled` contains `CN=ublue kernel` and `mokutil --test-key` says it is enrolled, that `mokutil --sb-state` says `SecureBoot enabled`, that the state file says `key=enrolled` and that `v4l2loopback` is loaded.

```sh
tests/secure-boot-key-test.sh
tests/secure-boot-key-test.sh --archive FILE --keep
```

It needs the same tools as the boot test and runs as root. A run takes about eight minutes. Results go to `tests/results/secure-boot-<image tag>-<UTC time>/`: `summary.txt`, `install.log`, `serial.log`, the screenshots, `mok-steps.txt` (when the blue screen appeared, and how much of each screenshot is blue) and `queued.txt` and `enrolled.txt`, what the VM reported before and after.

## Screenshot tour

`screenshot-tour.sh` is not a test: it shows what OrielOS looks like. It installs the image the way the boot test does, but keeps the boot splash, and boots it with a 1920×1080 screen and a USB tablet. It catches the splash, clicks through Plasma Setup, saving each of its pages as `03-setup-<n>.png`, and types an account (`alex`) on its user page (saved again as `03-setup-<n>-account.png`), restarts, signs in at the login screen once Firefox is installed, and then opens Start, Start search (for an app, and for a setting, which Enter opens in Settings), Files (with Win+Z's snap layouts, then Files snapped into the right half), Store, Process Manager, Settings (with its Accent colour, Accessory apps, Taskbar, Device security and Power mode pages), Firefox, Screenshot, the overview, the lock screen (idle and unlocking), the dark theme and the dark lock screen with the same keys a person would use, sent with QMP `send-key`. Between screenshots it closes the windows over SSH. If a step cannot be driven, it prints a WARN line and goes on: if the wizard does not create the account, setup is finished over SSH as in the boot test, and if typing the password does not sign in, SDDM's autologin is used. The numbered screenshots go to `tests/results/tour-<image tag>-<UTC time>/`, with `00-contact-sheet.png` when Pillow or ImageMagick is installed. It takes about fifteen minutes; `--image` and `--keep` work as in the boot test.

```sh
tests/screenshot-tour.sh
```

## Smoke test

`smoke-test.sh` is the short check that CI runs on each build before it's signed and published (see `image/README.md`); the boot test and the update test run locally before a change merges. It installs the image like the boot test, finishes setup over SSH on the first boot (so Plasma Setup's wizard is skipped), restarts, and checks:

1. The first boot answers over SSH.
2. The second boot reaches the sign-in screen: SDDM started and `graphical.target` was reached, read from the serial console (`signin.png`).
3. The boot is anti-cheat ready: the same kernel arguments, lockdown, kexec, BPF LSM and hibernation checks as the boot test.
4. Every loaded module has an allowed signer from `image/module-signers.txt`.
5. Universal Blue's key is trusted (`mokutil --test-key`).
6. No systemd unit failed.

```sh
tests/smoke-test.sh --image localhost/orielos:44.20261026
```

It uses 4 GiB of memory by default and takes about ten minutes. `probe.txt` in the results holds what the VM reported. `--image`, `--archive`, `--results` and `--keep` work as in the boot test.

## Shared VM code

`lib/vm.sh` holds what the VM scripts need: the PASS, FAIL, WARN and INFO lines, installing the image, starting the VM with its firmware, TPM and vsock device, SSH into the VM, pressing keys, clicking and taking screenshots over QMP, finishing setup and cleaning up. They all source it. `.shellcheckrc` lets shellcheck follow it. SSH goes through `systemd-ssh-proxy`, or through `socat`'s `VSOCK-CONNECT` where systemd is older than 256, as on GitHub's Ubuntu 24.04 runners.

## Still to come

- Benchmark scripts.
- The real-hardware release checklist.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
