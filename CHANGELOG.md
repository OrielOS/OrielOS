# Changelog

All notable changes to OrielOS are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and OrielOS uses [semantic versioning](https://semver.org/) for its releases; OS image builds are additionally tagged by Fedora release and date.

## [Unreleased]

### Added

- Settings, OrielOS's own settings app, opens with Windows + I and replaces System Settings in Start.
  - Categories in the order Windows uses: System, Bluetooth & devices, Network & internet, Personalisation, Apps, Accounts, Time & language and Update, each with its pages.
  - Search finds pages by name and by the words people know from Windows, such as "wifi", "default apps" or "windows update".
  - The update tray icon opens Update in Settings.
  - Settings found by Start's search, or KRunner's, open in Settings. Settings that Settings has no page for yet still open in System Settings.
  - Accent colour, under Personalisation, sets the colour of highlights and selected items, which stays when you switch between light and dark mode.
  - Accessory apps, under Bluetooth & devices, opens Solaar, Piper and OpenRGB, or their pages in the Store if they aren't installed.
  - Start, under Personalisation, turns recently added apps and recent files in Start's Recommended section on and off.
  - Taskbar, under Personalisation, centres the taskbar or aligns it to the left, and hides it automatically.
  - Privacy & security, with Device security: a check that the PC meets what games with anti-cheat require (Secure Boot, the TPM, kernel lockdown, the BPF security module, no kernel switching, the IOMMU and signed drivers), saying what to change for anything that isn't met. It also has Firewall, App permissions, Activity history, and Diagnostics & feedback.
  - Accessibility: Screen reader and keyboard, Zoom and colour filters, and On-screen keyboard.
  - Power mode, under System: Performance, Balanced or Power saver, as in the tray's power icon.
- OrielOS Update, a page in System Settings under System, holds everything about updates. Clicking the OrielOS updates icon in the system tray opens it.
  - It shows the version you're running and when OrielOS last checked for updates, and "Check for updates" checks straight away and shows what it found.
  - It pauses updates for one to five weeks or resumes them, and switches between the Stable and Testing channels.
  - It shows until when the previous version is kept, and goes back to it or removes it now, after asking first.
  - Changing the channel, going back and removing the previous version need an administrator's password. Every option works from the keyboard.
  - The OrielOS updates icon now only tells you about updates: its menu offers restarting when there's something to restart for, and opening the page.
- The system pieces games and gaming gear need, while the games and launchers themselves come from the Store.
  - Windows games run through Proton can use NTSYNC, and the system allows the memory maps some games need and doesn't slow down older games that split locks.
  - GameMode, umu-launcher and Fedora's compressed memory swap (zram) are included.
  - Steam from the Store reaches Xbox and PlayStation 4 and 5 controllers. The PlayStation touchpad doesn't move the desktop's pointer.
  - Solaar, Piper and OpenRGB from the Store can reach Logitech devices, gaming mice and RGB lighting.
  - A new "Games and controllers" page explains pairing controllers over Bluetooth.
- Going back to the previous version, and updates that undo themselves if they don't start.
  - If a new version fails to reach the desktop twice, the next start uses the previous version, keeps it and says so in a notification. There's no question to answer at startup.
  - OrielOS Update offers "Go back to the previous version…". After you confirm and enter an administrator's password, "Restart to go back" starts the previous version, and the version you left isn't offered again.
  - The previous version is kept for 14 days after an update, then removed; "Remove the previous version…" in OrielOS Update, or `orielos-update remove-previous`, removes it sooner.
  - The boot menu stays hidden. Esc or Shift opens it at any start, and it appears by itself only if both versions fail to start.
  - Boot menu entries are named after OrielOS versions, such as "OrielOS 44.20261026", and the system now calls itself OrielOS, with links to OrielOS's website, discussions and issue tracker.
- Updates now arrive by themselves.
  - OrielOS checks for a new version a while after start-up and then about every six hours, downloads it in the background and prepares it for the next restart. It never restarts on its own.
  - When a version is ready, a notification and the OrielOS updates icon in the system tray offer "Restart to update" and "Later".
  - Updates are skipped on metered connections, and a version you went back from isn't offered again.
- orielos.org's footer shows OrielOS's OpenSSF Best Practices and OpenSSF Baseline badges, loaded live from bestpractices.dev so they always show the current levels.
- orielos.org has "Share OrielOS" links for X, Bluesky, Reddit, Facebook and email, which contact those sites only when clicked, and every image on the page has alt text.
- orielos.org tells search engines and link previews what it is: a clearer page title, the OrielOS name and logo as structured data, a sitemap, a short summary for AI tools, and a notice to search engines whenever a page changes. Every crawler is welcome, and the site still has no cookies, analytics or scripts.
- On the OrielOS Discord server, members can react 🟢 or 🔴 on the about message to get the NVIDIA or AMD role and show which graphics card they have. Removing the reaction takes the role away.
- OrielOS's own Start menu replaces Plasma's launcher on the taskbar.
  - Search at the top lists apps, settings, files and Store results as you type, but opens nothing until you press Enter or click.
  - Below it are your pinned apps, an All apps list, and recommendations: recently added apps and recently opened files.
  - At the bottom are your account and the power button, with Sleep, Restart and Shut down.
  - Pins are kept across restarts and updates, the whole menu works from the keyboard, and existing users' taskbars switch to it automatically.
- The OrielOS Discord bot also posts new issues, discussions and pull requests, good first issues, answered questions, first contributions and star milestones to the Discord server's feed channel. Test builds ping members who react 🧪 for the Testers role.
- Pull requests from anyone but the maintainer that change the project's workflows, code owners, Discord bot, image signing keys and pins, licences or policy documents are closed automatically, as the contributing guide explains.
- orielos.org has "Join the discussion on GitHub" and "Join Discord" buttons in GitHub's and Discord's own colours, at the top of the page and under "Made in the open".
- The official OrielOS Discord server, https://discord.gg/RnpZYaKbHA, for live chat and quick help, linked from the README, the support and contributing guides, the user documentation and orielos.org. It's the only official OrielOS Discord server.
- A Discord bot, run by GitHub Actions, that posts releases and merges to the OrielOS Discord server (pinging everyone for full releases only) and gives members who link their GitHub account the Maintainer and Contributor roles.
- A wiki on GitHub that mirrors the user documentation in `docs/`, regenerated whenever the documentation changes.
- The orielos.org website: one page with OrielOS's goals, status, download and contributors, built from `website/` and published to GitHub Pages. Its download section links straight to the newest release's installer, with its size and SHA-256 checksum.
- The lock screen shows the time and date under the orange sill of the OrielOS wallpaper, in dark text on Daybreak and white on Nightfall, and hides them while you type your password.
- A Sponsor button on the repository, for supporting OrielOS through GitHub Sponsors.
- Contribution guidelines, a code of conduct, a security policy, support and governance notes, issue and pull request templates, and a GitHub Discussions form for questions.
- OrielOS has its own logo, Start button icon and wallpapers. Daybreak (light) and Nightfall (dark) are the default on the desktop and the lock screen, and the plainer Horizon is in the wallpaper picker.
- Every boot meets Easy Anti-Cheat's Linux requirements: kernel lockdown, IOMMU on, the BPF LSM, kexec disabled and only signed drivers. Hibernation is not offered.
- Windows keyboard shortcuts work out of the box, including Win+R for Run, Win+Tab for the task overview, Ctrl+Shift+Esc for Process Manager and Win+PrtSc to save a screenshot, and the system tools appear in Start as Process Manager, Screenshot and Files.
- First boot queues Universal Blue's driver-signing key for enrolment and explains the one-time Secure Boot step; a warning appears if the firmware lacks Microsoft's 2023 UEFI CA.
- A familiar taskbar for new users: Start button and pinned apps in the centre, system tray, clock and notifications at the right.
- Discover appears as Store, with Flathub as its only source of apps. Firefox is installed from Flathub on first boot, retrying until it succeeds, and is the default web browser.
- README describing what OrielOS is, its goals, how it will be built and its known limitations.
- Repository layout, with a README in each folder describing what belongs there.
- Licence files: GPL-3.0-or-later for code and configuration, and CC BY-SA 4.0 for documentation and artwork.
- Editor settings, ignore rules and secret-scanning configuration.
- OS image recipe based on Fedora 44 bootc with the Fedora CoreOS stable kernel, NVIDIA's open kernel modules and driver, and a minimal KDE Plasma desktop, with a local build script that pins every upstream input by digest.
- The complete KDE Plasma desktop on Wayland, with Discover for apps from Flathub, sound, Bluetooth, printing and a boot splash, and with the server features that a desktop doesn't need switched off: automatic update reboots, the SSH server, crash dumps and cloud tools.
- Plasma Setup on first boot: a new installation has no user account, and KDE's setup wizard asks for the language, keyboard layout, network, time zone and the first account, then opens the login screen. It doesn't run again once setup is finished, and the boot test checks both.
- Virtual machine disks for QEMU (qcow2) and VMware (VMDK) from one command, a tool that creates and boot-checks a VMware Workstation VM from the VMDK, and a guide to trying OrielOS in a virtual machine.
- A command-line update tool that stages a new build for the next restart and rolls back to the previous build; rolled-back builds are not offered again.

### Changed

- OrielOS no longer sends Fedora's anonymous weekly package count ("countme") when it checks repositories.

- Pull requests that don't change the apps, such as documentation or website changes, no longer wait about two minutes for the app build and tests; the `apps` check still reports and passes. The Discord bot's tests run after a merge only when the bot changed.

### Fixed

- The credits line on orielos.org names only the upstream projects OrielOS builds on.
- The Discord bot no longer cuts an emoji in half when it shortens a long title or release note.
