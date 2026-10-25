# Updates and going back

OrielOS updates the way Windows Update does. A new version is prepared in the background while you keep working, and nothing changes until you restart. If the new version gives you trouble, you go back to the one you had before, and OrielOS doesn't offer that version to you again.

This page describes how it works today, in development builds. The graphical update service, with "Restart to update" and a one-click way back in Settings, comes later.

## What stays and what changes

Each OrielOS version is a complete, read-only copy of the system. Updating swaps one copy for another at restart, so an update never leaves the system half-installed.

Your files, your accounts and your settings are kept, whichever version you start. They live in `/var` (your home folder is `/var/home/<your name>`), which updates and going back never touch. Apps from the Store are kept too.

OrielOS keeps two versions: the one you are running and the one before it. You can also pick the previous version from the boot menu when the computer starts.

## Updating

Development builds don't download updates by themselves yet. A new version comes as an archive file (`orielos-<version>.ociarchive`), made with `tools/build-image.sh`. Copy it to the computer, then in a terminal run:

```sh
sudo orielos-update stage /path/to/orielos-44.20261026.ociarchive
```

This prepares the new version for the next restart. It takes a few minutes, and you can keep using the computer meanwhile; the running system isn't changed. Restart when you are ready, and the new version starts.

To see which version you are running, which one is prepared for the next restart and which one you can go back to, run:

```sh
sudo orielos-update status
```

## Going back

If the new version doesn't work well for you, run:

```sh
sudo orielos-update rollback
```

and restart. The previous version starts again, with your files and settings as you left them.

OrielOS remembers the version you went back from and won't prepare it again: `orielos-update stage` refuses it. If you are testing and want to try that version again anyway, `orielos-update status` lists it under "Rejected builds", and

```sh
sudo orielos-update forget sha256:<digest>
```

allows it again.

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
