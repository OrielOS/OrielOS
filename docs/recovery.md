# Resetting this PC

If OrielOS isn't working as it should, and going back to the previous version (see [Updates and going back](updates.md#going-back-yourself)) doesn't help, you can reset it. A reset puts the newest version of OrielOS back on the computer, with its own system settings, as if it had just been installed. You choose whether your accounts and files stay.

Open **Settings → System → Recovery**. You can also search Start for "reset".

## The two choices

**Reset and keep files** keeps:

- every account, with its password, picture and sign-in PIN;
- everything in each person's home folder (`/var/home/<name>`): documents, pictures, downloads, games installed from Steam, and each person's own desktop and app settings;
- this PC's name, language, keyboard layout and time zone, the Wi-Fi and other networks it has saved, and the Bluetooth devices paired with it;
- the update channel and whether apps update by themselves.

It removes:

- apps installed from the Store for everyone (Firefox comes back by itself a minute or two after the restart; apps installed just for you stay in your home folder);
- every system setting you changed, such as printers you added or firewall exceptions;
- a pause of updates, and the previous version you could go back to.

**Reset and remove everything** removes every account and every file and app in them. After the restart the computer starts with first-run setup, as after installing OrielOS. Only the update channel is kept, so the computer goes on getting the same versions. Copy anything you want to keep to another drive or online storage first.

Removing everything doesn't securely erase the drive: deleted files could still be recovered from it with special tools. Before giving the computer away, use a tool made for erasing drives.

## What a reset never touches

A reset changes only OrielOS's own part of the drive. It doesn't repartition or format anything, so Windows, its files and its boot files, other drives, and any other partition on this drive stay exactly as they are. The boot menu still offers Windows afterwards.

## How it works

1. Choose **Reset…** or **Remove everything…**, confirm, and enter an administrator's password.
2. OrielOS downloads the newest version on your update channel, about 4 GB, and checks its signature, as it does for updates. The page shows the download's progress. You can keep using the computer meanwhile, and **Cancel the reset** stops it.
3. OrielOS gets the new version ready next to the one you're running. This takes a few minutes. Nothing changes until you restart.
4. When it's ready, choose **Restart now**. The restart takes a little longer than usual. With files kept, you then sign in as before; otherwise first-run setup starts.

Once the sign-in screen or first-run setup appears, OrielOS removes the old system in the background. Until you restart, **Cancel the reset** on the Recovery page undoes everything, and the next restart starts OrielOS as it was.

The reset needs free space for the download and for the new version beside the old one: about 10 GB. If there isn't enough, the page says so before downloading anything. It also needs an internet connection.

## If the reset start fails

If the computer can't reach the desktop after the restart, twice in a row, it starts the system it had before by itself, and puts back anything the reset had moved. The Recovery page then says the reset didn't finish, and you can try again.

## While a reset is ready

Updates wait while a reset is being got ready or is ready: OrielOS doesn't download one, and going back to the previous version or removing it can't be done until then. They go on as usual after the reset or after you cancel it. If an update was already waiting for a restart, the reset sets it aside, because the reset brings the newest version anyway.
