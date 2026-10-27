# installer

OrielOS's network installer, `OrielOS.iso` (about 1.2 GB). It's Fedora's installer, Anaconda, built with lorax under the OrielOS name with generic logos. It boots with Secure Boot through Fedora's signed shim, asks for language, keyboard, time zone, network and disk, then downloads the current OrielOS build of a channel (`stable` by default) from `ghcr.io/ncjsvr/orielos` and installs it with Anaconda's `ostreecontainer`, after checking its cosign signature. Plasma Setup creates the account on first boot, so the installer creates none. The user guide is [docs/install.md](../docs/install.md).

Because it downloads OrielOS while it installs, the ISO is rebuilt only when the installer changes: a fix here, a new Fedora release, newer hardware support in the installer environment, or new Secure Boot boot files.

## Files

- `build-iso.sh`: builds `OrielOS.iso` and `SHA256SUMS`. `--channel testing` makes an installer that installs testing builds, for trying the installer before a stable release exists; `--keep-lorax` reuses the installer environment from the last build and only remakes the kickstart and updates image. Runs lorax and mkksiso in the pinned Fedora container (`BUILDER_IMAGE` in `image/pins.env`). The installer and its boot menu show the version the channel's image carries when the ISO is built (its `org.opencontainers.image.version` label, such as v0.0.5), through the updates image's `.buildstamp` and mkksiso's `--replace`; `--version` sets another, and a channel with no image yet is named instead.
- `orielos.ks.in`: the kickstart. Besides the image, it:
  - removes an earlier install's boot files (`EFI/fedora`) from the EFI system partition before installing (`%pre-install`); otherwise ostree finds their `grub.cfg` and the install fails on a reinstall next to Windows;
  - adds Btrfs compression to the root file system's kernel arguments, which bootc's own install configuration would add;
  - removes the `/` line Anaconda writes to fstab: the root is a read-only composefs overlay, and `systemd-remount-fs` fails on it;
  - names the firmware boot entry OrielOS instead of Fedora.
- `updates/`: files laid over the installer environment through an updates image:
  - `etc/anaconda/profile.d/orielos.conf`: the `orielos` profile (selected with `inst.profile=orielos`), Fedora's defaults (Btrfs with zstd) without the account pages;
  - `etc/containers/policy.json` and `registries.d/orielos.yaml`: OrielOS's image must carry a sigstore signature made with `image/keys/orielos-cosign.pub`, which the build adds;
  - `etc/NetworkManager/conf.d/90-orielos-dns.conf`: the installer environment points `/etc/resolv.conf` at systemd-resolved, which it doesn't run, so NetworkManager writes the name servers itself.
- `patch-anaconda.py`: patches the installer's own copy of Anaconda, and stops if any code it changes has changed:
  - the deploy step shows nothing while it downloads, so it reports the download's progress and time left;
  - Anaconda cuts versions to two parts (v0.0) and writes them in capitals, so OrielOS's is shown whole;
  - a storage check warns when a drive that stays is encrypted with BitLocker, since Windows may then ask for its recovery key.
- `fedora.repo`: the Fedora repositories lorax installs from.

## CI

`.github/workflows/installer.yml` builds the ISO on pull requests that change this folder, and on merges, runs by hand and new releases attaches `OrielOS.iso` and `SHA256SUMS` to the latest release, then rebuilds the website, whose download section links the ISO from there. The Promote workflow starts it after creating a release.

## Testing

Before merging a change here, install from the new ISO in a virtual machine with Secure Boot on, next to a disk laid out like Windows 11 with free space after it, and check that:

- the boot menu and the installer's welcome page name the channel's current version;
- the installer starts, connects to the network and installs into the free space only, warning about a BitLocker partition if the disk has one;
- the installed system boots with Secure Boot to Plasma Setup, with Windows in the boot menu, `rootflags=…compress=zstd:1` on its command line, no failed units apart from `systemd-modules-load` before the key is enrolled, and a firmware entry named OrielOS;
- reinstalling over that install, deleting only its two partitions with "Free up space", works too;
- an installer whose policy trusts a different key refuses the image.
