# keys

Public keys vendored into the repository so that the image build can verify packages without trusting a download made during the build.

## RPM-GPG-KEY-negativo17

Signs the NVIDIA driver packages from negativo17. `image/build/30-nvidia.sh` imports it and checks the signature of every NVIDIA userspace package.

- Source: <https://negativo17.org/repos/RPM-GPG-KEY-slaanesh>, the `gpgkey=` of the `fedora-nvidia` repository file installed by `ublue-os-nvidia-addons`.
- Downloaded: 2026-10-24.
- Fingerprint: `0C5D 0F47 0484 AE2F C40A  9B65 97F3 0089 93E8 909B` (Simone Caronni, negativo17.org; RSA 4096, expires 2029-08-31).

Check it with `gpg --show-keys --with-fingerprint image/keys/RPM-GPG-KEY-negativo17`.
