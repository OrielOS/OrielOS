# Updates and going back

OrielOS updates in the background. A new version is prepared while you keep working, and nothing changes until you restart. If the new version gives you trouble, you go back to the one you had before, and OrielOS doesn't offer that version to you again.

New versions come from OrielOS's own downloads on GitHub (`ghcr.io/orielos/orielos`), and your computer checks each one's signature before preparing it. Which versions it gets depends on its [update channel](#the-update-settings): stable, the default, or testing.

## What stays and what changes

Each OrielOS version is a complete, read-only copy of the system: Fedora, the drivers, the desktop and OrielOS's own apps, all tested together. Updating swaps one copy for another at restart, so an update never leaves the system half-installed.

Your files and your own settings are kept, whichever version you start. They live in `/var` (your home folder is `/var/home/<your name>`), which updates and going back never touch. System settings, such as saved Wi-Fi networks and user accounts, are carried into each new version; going back is the one time they can change (see [What going back keeps](#what-going-back-keeps)). Apps from the Store aren't part of the system copy: they update on their own through the Store, and going back leaves them as they are.

OrielOS keeps two versions: the one you are running and the one before it, for 14 days after an update. You can go back to the previous one in the update settings, and if an update doesn't start, OrielOS goes back by itself.

## How updates arrive

A while after you start the computer, and then about every six hours, OrielOS checks for a new version. When there is one, it downloads it in the background, at low priority, and prepares it for the next restart. Your computer keeps running the version it started with until then.

When a new version is ready, a notification says **Restart to update**:

- **Restart to update** signs you out and restarts the computer into the new version. Save your work first.
- **Pick a time** opens the update settings, where you choose when the computer restarts (see [Choosing when to restart](#choosing-when-to-restart)).
- **Later** closes the notification. The new version still starts the next time you restart, whenever that is.

While the computer restarts into the new version, the screen says **Installing updates…** for a moment as it finishes. Don't turn it off then. After the restart, a notification says which version is running, with **See what's new**.

While a new version is ready, an **OrielOS updates** icon also shows in the system tray, at the right of the taskbar; hover over it to see what's waiting. Click it to open the update settings. Right-clicking it offers **Restart to update** and **Open update settings**. Once you've restarted, or when there's nothing to restart for, the icon goes away; the update settings in Settings show when OrielOS last checked.

OrielOS doesn't download updates over a metered connection, such as a phone hotspot that NetworkManager knows is metered.

## The update settings

**Update** in Settings holds everything about updates. Open it by clicking the **OrielOS updates** tray icon, or press Windows + I and choose **Update**. It shows the version you are running and when OrielOS last checked for updates, and offers:

- **Check for updates**, to check straight away. The page says what the check found when it's done.
- **Restart now**, while a new version is ready, or while going back is waiting for a restart, and **Pick a time** to schedule that restart instead.
- **Pause updates**, for 1 to 5 weeks. While updates are paused, OrielOS doesn't check for or download new versions, and the page shows the date they resume. **Resume updates** ends the pause early.
- **Update channel**:
  - **Stable**, the default, gets versions that people have already used on the testing channel and that have passed checks on real hardware.
  - **Testing** gets new versions sooner, as soon as they pass OrielOS's automatic tests. Something may break now and then; you can always go back. If a testing version turns out to be bad, OrielOS takes it back, and computers on testing return to the earlier version at their next update check.

  Changing the channel asks for an administrator's password, and takes effect at the next check. To see what each version brings, see [What's in each version](#whats-in-each-version).
- **Active hours** and **Restart automatically outside active hours** (see [Choosing when to restart](#choosing-when-to-restart)).
- **Update history**: each version this computer has run, with the date it was installed, and **What's new in this version**, the changes the version you're running brought.
- **Previous version**, while the computer keeps one: the date it's kept until, **Go back to the previous version…** (see [Going back yourself](#going-back-yourself)) and **Remove the previous version…** (see [How long the previous version is kept](#how-long-the-previous-version-is-kept)). Both ask for an administrator's password.

Every option can be used from the keyboard: hold Alt to see each one's underlined letter.

## Choosing when to restart

OrielOS never restarts by itself unless you ask it to:

- **Pick a time**, in the update settings or the notification, chooses a day in the next week and a time. The computer restarts then to finish the update, and the update settings say when, with **Don't restart then** to cancel it. Leave your work saved before then.
- **Active hours** are the hours you usually use the computer, 8:00 to 17:00 until you change them.
- **Restart automatically outside active hours**, off unless you turn it on, makes OrielOS schedule the restart itself once an update is ready: at 3:00 at night, or as your active hours end if 3:00 is within them. It never restarts the computer during your active hours.

Restarting yourself before the scheduled time finishes the update as well, and the scheduled restart no longer happens.

## What's in each version

Every version has notes on [orielos.org's release notes](https://orielos.org/releases/) and on [GitHub's releases page](https://github.com/OrielOS/OrielOS/releases):

- **Testing builds** are marked Testing. Each one lists what's new since the build before it, so if you're on the testing channel you can see what the latest update brought. Each also says which stable version includes it, once there is one. A build that was taken back is marked Withdrawn.
- **Stable versions** list everything that's new since the previous stable version, and which testing builds they bring together.

The download page names the newest testing build when it's newer than the stable version. Testing builds don't appear in the news feed, which follows stable versions only.

## Apps from the Store

Apps you installed from the Store update by themselves too, in the background, a few minutes after you start the computer and then about every six hours. They update quietly and slowly enough not to slow down a game. An app that's open keeps its old version until you close and open it again. When an OrielOS update brings a new NVIDIA driver, games from the Store get the matching graphics driver for apps this way too, without opening the Store.

To turn this off, clear **Update apps automatically** under **Apps from the Store** on the update settings page. The Store's own **Update** button still updates your apps whenever you choose. Apps aren't updated on a metered connection.

## If an update doesn't start

You don't need to do anything. If a new version fails to reach the desktop twice in a row, for example because it stops partway through starting or the screen stays black, the next start uses the previous version instead. Once its desktop is up, OrielOS keeps that version, tells you in a notification that the update was undone, and doesn't offer the version that failed again until a newer one is published. There's no question to answer at startup.

## Going back yourself

If a new version starts but doesn't work well for you, open the update settings and choose **Go back to the previous version…**. OrielOS asks first, then asks for an administrator's password. After that, the page offers **Restart now**, and the tray icon and a notification offer **Restart to go back**. When you restart, the previous version starts again.

Going back is offered for 14 days after an update, until the previous version is removed. It isn't offered for a version you already went back from, or for one that didn't start.

OrielOS remembers the version you went back from and won't prepare it again until a newer version is published. While going back is waiting for a restart, OrielOS doesn't prepare any update.

In a terminal, `sudo orielos-update rollback` does the same. If you are testing and want to try the version you went back from again anyway, `orielos-update status` lists it under "Rejected builds", and

```sh
sudo orielos-update forget sha256:<digest>
```

allows it again.

## What going back keeps

Your files and your own settings stay as they are, whichever version you start: your home folder, your desktop and app settings, and the apps you installed from the Store.

System settings are part of each version, though. Anything you changed at system level since the update goes back to how it was before it: a Wi-Fi network you saved, a printer you added, a new user account or a changed password. Set those again after going back if you need them.

## How long the previous version is kept

OrielOS keeps the previous version for 14 days after an update, so you can go back to it; the update settings show the date. After that it's removed, and going back is no longer offered until the next update. To remove it sooner, choose **Remove the previous version…** in the update settings. It asks first, then asks for an administrator's password, and can't be undone. While an update or going back is waiting for a restart, restart first. In a terminal, run:

```sh
sudo orielos-update remove-previous
```

The two versions share every file that didn't change between them, so the previous version usually takes up much less space than a whole copy of the system.

## The boot menu

When the computer starts, the boot menu stays out of sight. To open it, press Esc once, or hold Shift, just after the computer's own start-up screen. It lists the versions on the computer by name, such as **OrielOS v0.0.7**, with the one that normally starts at the top. Use the arrow keys to choose one and press Enter. Pressing Esc again while the menu is showing closes it and leaves a `grub>` prompt instead; type `reboot` and press Enter to start again.

Choosing a version in the boot menu starts it this once.

On a computer that also has Windows, the boot menu shows for five seconds at every start and lists **Windows** after OrielOS's versions. Choose it with the arrow keys and Enter to start Windows; if you do nothing, OrielOS starts.

The menu appears by itself only if both versions fail to start: after an update was undone, the previous version didn't reach the desktop either. It waits 30 seconds, then starts the highlighted version.

## In a terminal

`orielos-update` does everything the update settings do, and more. It runs as administrator:

```sh
sudo orielos-update status          # versions, channel, pause and the last check
sudo orielos-update check           # check now and wait for it to finish
sudo orielos-update pause 2         # pause updates for 2 weeks (1 to 5)
sudo orielos-update resume          # end a pause
sudo orielos-update channel testing # or stable
sudo orielos-update rollback        # go back to the previous version at the next restart
sudo orielos-update remove-previous # remove the previous version now
sudo orielos-update app-updates off # stop apps from the Store updating by themselves (or on)
sudo orielos-update restart-at 2026-11-02T03:00:00Z  # restart then (UTC) to finish the update
sudo orielos-update restart-at cancel                # drop the scheduled restart
sudo orielos-update active-hours 9 18                # active hours from 9:00 to 18:00
sudo orielos-update auto-restart on                  # restart by itself outside active hours (or off)
```

## Preparing a version yourself

A version can also come as an archive file (`orielos-<version>.ociarchive`), made with `tools/build-image.sh`. Copy it to the computer, then in a terminal run:

```sh
sudo orielos-update stage /path/to/orielos-v0.0.7.ociarchive
```

This prepares the new version for the next restart. It takes a few minutes, and you can keep using the computer meanwhile; the running system isn't changed. Restart when you are ready, and the new version starts.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
