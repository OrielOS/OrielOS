# Real-hardware checklist

What a build has to pass on a real PC before it's promoted to `stable`, on top of the automated
tests. Copy the table, fill in each result with the date, and note anything that fails with what
was tried. A failure blocks the release unless it's recorded as a known limitation.

Build: ______  PC: ______  Graphics card and driver: ______  Date: ______

| Area | Check | Result |
|---|---|---|
| **Start-up** | The PC starts OrielOS with Secure Boot on; the boot menu stays hidden | |
| | Settings › Privacy & security › Device security shows every requirement met (Secure Boot, TPM, lockdown, IOMMU, signed drivers) | |
| | Start-up to the sign-in screen within 20 s; sign-in to a usable desktop within 5 s (`tests/benchmark/system.sh`) | |
| | Memory in use after signing in, idle: under 2.5 GB | |
| **Graphics** | The NVIDIA driver is in use (`nvidia-smi` lists the card; Settings › System › NVIDIA settings opens) | |
| | HDR turns on in Settings › System › Display and an HDR video or game shows it | |
| | Variable refresh rate (adaptive sync) on a VRR screen: no tearing in a game | |
| | Two screens: arranged, each at its own scale and refresh rate; windows move between them | |
| **Power** | Sleep and wake from Start, from the lid (laptops) and from the power button; the desktop comes back as it was | |
| | On battery (laptops): energy saver turns on at 20 % | |
| **Sound** | Speakers, headphones (switching when plugged in), a USB or Bluetooth headset and its microphone | |
| **Controllers** | An Xbox controller, a DualShock 4 and a DualSense, each over a USB cable and over Bluetooth, paired from Settings without a terminal; each works in Steam | |
| **Games** | A Steam game through GE-Proton | |
| | A game from a store's launcher installed with Run this app | |
| | A game with anti-cheat that Will it run? says works | |
| | The FPS overlay with Windows + G in a game | |
| | The benchmark set (`tests/benchmark/`), three runs each, within 5 % of Windows on average FPS and 1% lows | |
| **Apps** | Discord screen sharing shows a window and the whole screen | |
| | OBS Studio records with the NVIDIA encoder (NVENC) | |
| | Installing and uninstalling an app from the Store and from Settings › Apps › Installed apps | |
| **Updates** | Updating to the build from the one before it, and going back (Settings › Update › Go back) | |

Keep the filled-in checklist with the release's records.
