# image

The OS image recipe. The image is built from Fedora's `fedora-bootc` base with rootful Podman.

Will contain:

- The Containerfile.
- Small per-feature build scripts.
- System configuration copied into the image: sysctl settings, kernel arguments, udev rules and systemd units.

Licence: GPL-3.0-or-later (see `LICENSE` in the repository root).
