# Changelog

All notable changes to OrielOS are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and every published OrielOS build has its own version, `vMAJOR.MINOR.PATCH`, one more than the build before. Versions before v0.0.1 were named by Fedora release and date.

## [Unreleased]

### Added

- Run this app: double-clicking a Windows program (`.exe` or `.msi`) shows the file and the website it came from and asks first, then runs it through GE-Proton in a Windows set-up of its own. The shortcuts its installer makes appear in Start, and a program that isn't an installer can be added to Start. [Windows programs](docs/windows-programs.md) explains it.
- GE-Proton is the default for Windows games in Steam from the Store: OrielOS installs it next to Steam and, the next time Steam is closed, makes it Steam's default, once, without changing a default you chose. A game's own compatibility setting in Steam still wins. [Games and controllers](docs/games-and-controllers.md#ge-proton-for-windows-games-in-steam) explains it.
- The sign-in screen shows your account and the password box over the OrielOS wallpaper as soon as it appears, with the time and date above, and stays that way until you sign in. It offers Sleep, Restart and Shut down.
- A [Status](docs/status.md) page in the user docs lists what works today, what doesn't work yet and what's planned. The updates guide no longer says that no versions are published.
- orielos.org describes OrielOS to search engines as a free Linux desktop for gaming and development: the home page, the download page and a new FAQ, with structured data for the software and the questions. The sitemap dates a page when git can see the commit that last changed it. A news post covers v0.0.7, the first release with an installer.
- orielos.org has more pages, still with no JavaScript, cookies or trackers:
  - **Download**, with the installer's checksum, `SHA256SUMS` and how to check the download on Windows, macOS and Linux;
  - **Guides**, every user guide from `docs/`, with screenshots, and "Find a topic", an A to Z list of every topic in them;
  - **News**, with an Atom feed of the posts and every release, starting with "Introducing OrielOS";
  - **Release notes** for every release, **Press**, with a fact sheet, the logo and screenshots, and **Credits** for the projects OrielOS is built on and its artwork.
- The home page's "Where it stands" shows the roadmap, from the first builds to version 1 and beyond, and the newest news.
- Two new guides: [The desktop](docs/desktop.md) (the taskbar, the system tray, snapping windows, Files, screenshots and Process Manager) and [Getting help](docs/help.md). The install, Secure Boot, Start, apps, Settings and anti-cheat guides show screenshots.
- [Status](docs/status.md#hardware-verified) lists the hardware OrielOS has been verified on: so far, an NVIDIA GeForce RTX 4050 Laptop GPU.
- Every testing build has its own release notes, on GitHub and on orielos.org, saying what's new since the build before it and, once there is one, which stable version includes it. Each stable version's notes name the testing builds it brings together, a build that was taken back is marked Withdrawn, and the download page names the newest testing build. [What's in each version](docs/updates.md#whats-in-each-version) explains it.

### Changed

- The taskbar has a new look and new buttons, like Windows 11's:
  - **Start** opens in the middle of the screen above the taskbar, floating with rounded corners, with two rows of pinned apps a page (dots turn the pages), a **More** page for Recommended, and Downloads, Files and Settings next to the power button.
  - **Search** and **Task View** buttons follow Start, and a thin strip at the far right shows the desktop.
  - **Quick Settings**, one button with the network, volume and battery icons, opens tiles for Wi-Fi, Bluetooth, airplane mode, energy saver, night light and accessibility, brightness and volume sliders and the battery, with what's playing on a card above. The Wi-Fi and Bluetooth tiles' arrows list networks and paired devices to connect to, and the headphones button switches the sound output and sets each app's volume. Edit unpins tiles, adds them back and puts them in a new order. The tray's own network, sound, Bluetooth, battery and media icons move among the hidden icons.
  - **The clock** shows the time over the date, with a bell that counts new notifications. Either opens your notifications, newest first, with Do not disturb and Clear all, over the month's calendar with a focus session: Do not disturb for a length you choose, with a countdown.
  - Pop-ups float a little above the taskbar, and an open button is lit by a rounded highlight.
- Windows have new frames: a flat title bar with the app's icon and title, wide minimise, maximise and close buttons (close turns red), rounded corners and a soft shadow. Resting the pointer on maximise shows snap layouts under it, and Windows + Z shows the same six layouts.
- Alt + Tab dims the screen and shows the windows' thumbnails, each with its app's icon and title; Delete closes the selected window. Only this desktop's windows show.
- Notifications pop up at the bottom right, above the clock, and the volume keys change the volume by 2 %.
- The Bin is on the desktop, at the top left, and files on the desktop line up in columns from there. Right-clicking the desktop gives View, Sort by, Refresh, New, Display settings, Personalise, Open in Terminal and Show more options.
- Ctrl + Alt + Del shows a full screen with Lock, Switch user, Sign out, Change a password, Process Manager and Cancel, and a power button at the bottom right. Shut down, Restart and Sign out from Start happen at once, without a confirmation screen; apps with unsaved work still ask first.
- Alt + F4 on the desktop asks what the computer should do, with Shut down chosen, as Windows does; in a window it still closes the window.
- Files lays out its toolbar like Explorer's: back, forward, up and refresh, then New, Cut, Copy, Paste, Rename, Delete, Sort, View and search, with the address bar on its own row. Folders open in the Details view with Name, Date modified, Type and Size, and Downloads lists the newest first, grouped by date. Its window is titled Files, and the Bin is called Bin in its places and in Move to Bin.
- Windows + X, or right-clicking Start, opens the quick links menu: Installed apps, Power options, System, Device Manager, Network connections, Terminal, Process Manager, Settings, Files, Search, Run, Shut down or sign out, and Desktop, each with an underlined letter to press.
- Quick Settings, Start and the desktop menu open the matching page of Settings instead of separate settings windows.
- Windows + P chooses how the screens are used, PC screen only, Duplicate, Extend or Second screen only, from a panel above the taskbar; pressing it again moves down the list.
- New shortcuts: Windows + Pause opens About, Windows + U opens Accessibility, Windows + N opens your notifications and Ctrl + Esc opens Start. Accounts made before them get them at their next sign-in, unless they changed those keys.
- The lock screen and the sign-in screen have a new look. Locked, the screen shows a large clock and the date at the top; press a key or click and they slide away to the sign-in: your picture (or your initial) and name and a rounded password box over the blurred wallpaper. The sign-in screen lists every account at the bottom left, with Other for typing a name, and keeps the keyboard layout, the on-screen keyboard and the power menu at the bottom right.
- The locked screen shows, at the bottom right, the apps that sent notifications while it was locked, each with how many, and the network and battery. After you sign in, a Welcome screen with your picture and name carries on from the sign-in screen until the desktop is ready.
- The locked screen also shows the next item in your calendar within the week, such as a public holiday in the regions you chose. After five wrong passwords in a row, the lock and sign-in screens ask you to type some shown characters, then wait 30 seconds before taking a password again, twice as long each time after that. An option asks for Ctrl + Alt + Delete before the sign-in shows. A short startup sound plays when the sign-in screen first appears after the computer starts. Dynamic lock locks the computer about a minute after your paired phone goes out of Bluetooth range.
- Sign in with a PIN, as with Windows Hello: set one up in Settings → Accounts → Sign-in options, and the sign-in screen, the lock screen and administrator prompts take it, signing in as soon as the last digit is typed. The password always works too. The PIN works only on that computer (it is sealed to its TPM where it has one), and after five wrong PINs OrielOS waits before taking another. Sign-in options also sets up fingerprints, dynamic lock, whether waking from sleep asks you to sign in, Ctrl + Alt + Delete before signing in, and the startup sound.
- The taskbar: clicking an app with several windows shows their thumbnails to choose from, and resting on a thumbnail shows just that window. Right-clicking empty taskbar space offers Process Manager and Taskbar settings. Windows + A opens Quick Settings and Windows + B the hidden icons. Settings → Personalisation → Taskbar can show each window as its own button, turn off the Search and Task View buttons and show seconds in the clock. Quick Settings has Mobile hotspot, Project and Keyboard layout tiles to add, on further pages turned with dots.
- The notification centre groups an app's notifications under its name, with a button to clear them; while Do not disturb or a focus session is on, the taskbar's apps don't show badges or progress.
- Batteries show in the taskbar, Quick Settings, the lock screen and the power settings, for laptops and for wireless mice, keyboards and controllers. Fingerprint readers and the built-in cameras of many recent Intel laptops work.
- OrielOS is dark by default: new accounts start with OrielOS Dark's colours, dark icons and the Nightfall wallpaper, and the sign-in screen shows Nightfall too. Light is still one switch away in Settings → Personalisation.
- The desktop is now OrielOS's own: the taskbar, Start and the lock screen run in OrielOS's shell, which will take over more of the desktop in coming versions. Your pinned apps in Start and on the taskbar and your wallpaper carry over the first time it starts, and going back to an earlier version brings back your earlier desktop as you left it.
- Games come the way they do on Windows: Steam from the Store, and other stores through their own launchers, such as the Epic Games Launcher or GOG Galaxy, installed with Run this app. Start no longer suggests Heroic Games Launcher or Lutris, which stay in the Store for anyone who wants them, and the guides no longer point to them.
- The install guide says which graphics cards OrielOS needs, how to check the download on macOS, which tools write the USB stick on Windows, macOS and Linux, and which firmware settings to check if the stick isn't offered.
- The website's download says it's the stable version, which updates itself, and how to switch to the testing channel; its "How to install" link opens the install guide. Each stable release's notes start with how to get it: the installer for new installs, or nothing to do on a computer that already runs OrielOS.
- The installer and its start menu name the OrielOS version that was current when the ISO was made, such as "OrielOS v0.0.5", instead of "OrielOS 44", the Fedora release it's built from. When a drive is encrypted with BitLocker, the installer warns that Windows may ask for its recovery key afterwards.
- Right-clicking an app on the taskbar offers **Pin to taskbar** and **Unpin from taskbar**, the same words as Start, instead of "Pin to Task Manager", and **Configure Taskbar…**; the taskbar's widget is called Taskbar. This applies when the desktop's language is English; a list of languages chosen in Settings → Region & Language brings back Plasma's wording.

### Fixed

- A stable release's notes list only what that version contains: changes merged after the version was built stay under Unreleased for the next one.

## [0.0.7] - 2026-10-27

### Added

- An installer: `OrielOS.iso`, about 1.2 GB, on each release. It starts with Secure Boot on, asks for language, keyboard, time zone, network (Wi-Fi or cable) and where to install, then downloads the current stable version of OrielOS, checks its signature and installs it, showing how much is left and how long it will take. Next to Windows it uses the space you freed in Windows' Disk Management and keeps Windows in the start menu. The account is created when OrielOS first starts. [Install OrielOS](docs/install.md) shows each step.
- Wi-Fi and Bluetooth work with every common card from the first start: OrielOS includes the firmware for Intel cards from the oldest to Wi-Fi 7 and Intel Bluetooth, Qualcomm and Atheros, MediaTek, Realtek, Broadcom, NXP and Marvell, TI and older USB sticks, as well as Intel laptop cameras and TV tuners.
- On a PC that also has Windows, the boot menu lists Windows and shows for five seconds at every start. On other PCs it stays hidden as before.
- OrielOS has its own sounds: soft glass chimes for signing in and out, notifications, questions, warnings and errors, plugging in devices and power, low battery and the volume keys. Any other sound comes from Plasma's Ocean theme.
- Snap layouts: Windows + Z shows layouts for the window you're using (halves, thirds, two thirds beside one third, and quarters) and moves it into the area you click or choose with the arrow keys and Enter.
- A "Known limitations" page lists what OrielOS can't do yet, such as running on real hardware or games whose publishers block Linux, and what it won't do by design, such as Hibernate.
- The sign-in screen opens on the time over the OrielOS wallpaper, like a locked screen. Press a key or click, and the sign-in slides up into the middle; after a minute without input the time comes back. It offers Sleep, Restart and Shut down.
- The boot splash shows the OrielOS logo on a black screen, with a spinner below it.
- OrielOS has its own colours: OrielOS Light, the default, and OrielOS Dark, built from OrielOS's palette with Oriel Blue for selections, focus and links. The OrielOS Dark global theme keeps the OrielOS taskbar, and Plasma's Day-Night Cycle switches between the two.
- Start suggests apps to get started with under Recommended: Steam, Heroic Games Launcher, Discord, Spotify, OBS Studio and Lutris. Each opens its page in the Store, leaves the list once installed, and the suggestions can be hidden from an entry's menu.
- Clipboard history is in Start, under that name: it shows what you copied recently, as Windows + V does. Files always shows its tab bar.
- The first-run setup asks what OrielOS needs, in this order: language, keyboard layout, network, time zone, power and your account.
  - A new power page sets when the computer sleeps and when the screen turns off if it isn't being used, starting from sleep after 15 minutes and the screen off after 10. Your choice becomes the power settings every new account starts with.
  - On a computer without Wi-Fi, the network page shows whether the cable connection reaches the internet, instead of being skipped.
  - The setup no longer asks for screen scaling, a dark theme or the computer's name. The dark theme switch gave the new account Fedora's dark desktop instead of OrielOS's.
  - The last page shows the OrielOS logo.
- OrielOS builds are published when changes merge.
  - Each change that affects the system is built on GitHub, started in a VM to check it reaches the sign-in screen in the mode anti-cheat needs with only signed drivers, signed, and published to ghcr.io as the new testing build.
  - A build is published only if Flathub has the NVIDIA driver extension that Store apps need for it.
  - Stable moves to a tested build by hand, without rebuilding it, with a release on GitHub.
  - Once OrielOS's signing key is in place, computers check the signature of every update before preparing it.
  - The pinned Fedora and driver images are refreshed every week, which is how Fedora's updates reach OrielOS.
- Apps from the Store update by themselves, in the background, a few minutes after start-up and about every six hours, at low priority so they don't slow down a game.
  - After an OrielOS update with a new NVIDIA driver, the matching graphics driver for Store apps arrives the same way, without opening the Store.
  - **Update apps automatically** on the update settings page turns this off; the Store's Update button works either way. Apps aren't updated on a metered connection.
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
  - OrielOS starts in the Performance power mode, on mains and on battery, and keeps whichever mode you choose instead.
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

- OrielOS has one version number for everything, starting at v0.0.1: every published build is the next one, rolling over from v0.0.10 to v0.1.0. About this System, the boot menu, Settings → Update and the apps' About dialogs show it, as in "OrielOS v0.0.7", in place of names such as "OrielOS 44.20261026". A stable release is named after the build it is.
- Window titles sit on the left of the title bar, next to the app's icon, as on Windows.
- OrielOS no longer sends Fedora's anonymous weekly package count ("countme") when it checks repositories.

- Pull requests that don't change the apps, such as documentation or website changes, no longer wait about two minutes for the app build and tests; the `apps` check still reports and passes. The Discord bot's tests run after a merge only when the bot changed.

### Fixed

- Updates from the testing channel are prepared again. Once update signatures were checked, every update stopped with "containers-policy.json specifies a default of insecureAcceptAnything", because the system's container policy accepted unsigned images by default. It now refuses them by default, except where each tool accepted them before, and OrielOS's own updates must carry OrielOS's signature.
- About this System shows the OrielOS logo and the whole version, such as 44.20261026, instead of Fedora's logo.
- The firewall settings page no longer asks for a password as soon as it opens. Anyone can see the firewall's settings, and administrators change them without a password, as on Fedora's KDE edition.
- A new installation names the computer `orielos` instead of `fedora`, on the network and in the terminal.
- A unit no longer fails at every start (`efi.automount`, the EFI system partition's automount), which made `systemctl is-system-running` report `degraded`.
- The credits line on orielos.org names only the upstream projects OrielOS builds on.
- The Discord bot no longer cuts an emoji in half when it shortens a long title or release note.

