# Updates and going back

OrielOS updates in the background. A new version is prepared while you keep working, and nothing changes until you restart. If the new version gives you trouble, you go back to the one you had before, and OrielOS doesn't offer that version to you again.

OrielOS isn't publishing versions for download yet, so for now your computer finds no updates on its own. To try a new version, prepare it yourself as described in [Preparing a version yourself](#preparing-a-version-yourself).

## What stays and what changes

Each OrielOS version is a complete, read-only copy of the system: Fedora, the drivers, the desktop and OrielOS's own apps, all tested together. Updating swaps one copy for another at restart, so an update never leaves the system half-installed.

Your files, your accounts and your settings are kept, whichever version you start. They live in `/var` (your home folder is `/var/home/<your name>`), which updates and going back never touch. Apps from the Store aren't part of the system copy: they update on their own through the Store, and going back leaves them as they are.

OrielOS keeps two versions: the one you are running and the one before it. You can also pick the previous version from the boot menu when the computer starts.

## How updates arrive

A while after you start the computer, and then about every six hours, OrielOS checks for a new version. When there is one, it downloads it in the background, at low priority, and prepares it for the next restart. Your computer keeps running the version it started with until then.

When a new version is ready, a notification says **Restart to update**:

- **Restart to update** signs you out and restarts the computer into the new version. Save your work first.
- **Later** closes the notification. The new version still starts the next time you restart, whenever that is.

The **OrielOS updates** icon in the system tray, at the right of the taskbar, shows the same. It's in the tray's hidden icons (the arrow) until an update is ready. Right-click it for these options:

- **Restart to update**, while a new version is ready.
- **Check for updates**, to check straight away.
- **Pause updates**, for 1 to 5 weeks. While updates are paused, OrielOS doesn't check for or download new versions, and the menu shows the date they resume. **Resume updates** ends the pause early.
- **Update channel**:
  - **Stable**, the default, gets versions that have also passed checks on real hardware.
  - **Testing** gets new versions sooner, as soon as they pass OrielOS's automatic tests.

  Changing the channel asks for an administrator's password, and takes effect at the next check.

OrielOS doesn't download updates over a metered connection, such as a phone hotspot that NetworkManager knows is metered.

## Going back

If the new version doesn't work well for you, run:

```sh
sudo orielos-update rollback
```

and restart. The previous version starts again, with your files and settings as you left them.

OrielOS remembers the version you went back from and won't prepare it again, until a newer version is published. If you are testing and want to try that version again anyway, `orielos-update status` lists it under "Rejected builds", and

```sh
sudo orielos-update forget sha256:<digest>
```

allows it again.

## In a terminal

`orielos-update` does everything the tray icon does, and more. It runs as administrator:

```sh
sudo orielos-update status          # versions, channel, pause and the last check
sudo orielos-update check           # check now and wait for it to finish
sudo orielos-update pause 2         # pause updates for 2 weeks (1 to 5)
sudo orielos-update resume          # end a pause
sudo orielos-update channel testing # or stable
```

## Preparing a version yourself

A version can also come as an archive file (`orielos-<version>.ociarchive`), made with `tools/build-image.sh`. Copy it to the computer, then in a terminal run:

```sh
sudo orielos-update stage /path/to/orielos-44.20261026.ociarchive
```

This prepares the new version for the next restart. It takes a few minutes, and you can keep using the computer meanwhile; the running system isn't changed. Restart when you are ready, and the new version starts.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
