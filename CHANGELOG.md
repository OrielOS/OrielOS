# Changelog

All notable changes to OrielOS are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and OrielOS uses [semantic versioning](https://semver.org/) for its releases; OS image builds are additionally tagged by Fedora release and date.

## [Unreleased]

### Added

- README describing what OrielOS is, its goals, how it will be built and its known limitations.
- Repository layout, with a README in each folder describing what belongs there.
- Licence files: GPL-3.0-or-later for code and configuration, and CC BY-SA 4.0 for documentation and artwork.
- Editor settings, ignore rules and secret-scanning configuration.
- OS image recipe based on Fedora 44 bootc with the Fedora CoreOS stable kernel, NVIDIA's open kernel modules and driver, and a minimal KDE Plasma desktop, with a local build script that pins every upstream input by digest.
