# Switching back to stock Fedora

OrielOS is built on Fedora's atomic desktops, so a computer running it can switch to plain Fedora Kinoite, Fedora's own KDE Plasma desktop, without reinstalling. Your files, your apps from the Store and your account stay. You can switch back to OrielOS the same way.

## Switch to Fedora Kinoite

1. Save your work and open **Terminal**.
2. Switch to Fedora Kinoite 44:

   ```sh
   sudo bootc switch quay.io/fedora-ostree-desktops/kinoite:44
   ```

   It downloads Kinoite in the background, like an update, and asks for your password first.
3. Restart. The computer starts Fedora Kinoite, with Plasma's own desktop in place of OrielOS's.

Until you remove it, OrielOS stays on the computer as the previous version: if something isn't right, choose it in the boot menu (hold **Shift** as the computer starts), or run `sudo bootc rollback` and restart.

## What changes and what stays

- **Stays:** everything in your home folder, your apps from the Store (Flatpaks), your Wi-Fi networks and your account.
- **Goes:** OrielOS's own parts: its desktop shell, Settings app, Run this app, Game Settings, the update tray icon and OrielOS's updates. Fedora Kinoite updates itself in its own way (Discover and `rpm-ostree`).
- **The NVIDIA driver:** Fedora Kinoite doesn't include it. Install it the way Fedora's documentation describes, or use [Universal Blue's Kinoite images](https://universal-blue.org/), which include it.
- **Universal Blue's key**, which you told your PC to trust for OrielOS's drivers (see [Secure Boot and your drivers](secure-boot.md)), stays trusted. It's harmless, and Universal Blue's Kinoite images use it too. To remove it, copy `/etc/pki/akmods/certs/akmods-ublue.der` somewhere safe while OrielOS is still running, then after switching run `sudo mokutil --delete akmods-ublue.der` on that copy, set a one-time password, restart and choose **Delete MOK** on the blue screen.
- **Programs you added to Start with Run this app** stay in your home folder, but need umu-launcher, which Kinoite doesn't have, to start.

## Switch back to OrielOS

```sh
sudo bootc switch ghcr.io/orielos/orielos:stable
```

Then restart. OrielOS's first sign-in sets up its desktop again.
