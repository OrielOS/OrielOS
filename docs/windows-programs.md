# Windows programs

> Run this app is in testing builds of OrielOS. It arrives on the stable channel with the next stable release; to try it now, switch to testing in Settings → Update.

Many Windows programs run on OrielOS. Double-click a Windows program (a file ending in `.exe` or `.msi`) and **Run this app** opens. It shows you the file and asks before doing anything, then runs the program through GE-Proton, the same compatibility layer OrielOS uses for games.

Before you reach for a Windows program, check the Store: many apps, such as Discord, Spotify and Steam, have a Linux version there that works better. For games, install Steam from the Store, or a store's own launcher, such as the Epic Games Launcher or GOG Galaxy, with Run this app (see [Games and controllers](games-and-controllers.md)).

## Running a program

1. Double-click the `.exe` or `.msi` file, for example in your Downloads folder.
2. Run this app shows the file's name, its size and the website it was downloaded from, when your browser recorded it. If you don't know where the file came from, or don't trust it, choose **Cancel**: Windows programs can see your files.
3. Choose **Run** (or **Install** for an `.msi` file). The program starts in its own window.

The first time you run a Windows program, OrielOS downloads GE-Proton and what it needs to run, about 1 GB. That takes a few minutes; after that, programs start straight away.

## Programs Run this app knows

Run this app knows some programs by their download's name, from a list OrielOS keeps up to date online (with a copy on the computer for when it's offline):

- **Apps the Store has**, such as Discord, Spotify, Steam, OBS Studio, VLC, Chrome, Zoom and Visual Studio Code: the dialog offers **Get it from the Store** first. The Store's version is made for OrielOS and updates by itself. You can still run the Windows version.
- **Game stores' launchers**: the Epic Games Launcher, GOG Galaxy, Battle.net, the EA app, Ubisoft Connect and the Rockstar Games Launcher install as usual, with a note on what to expect. Their games appear in Start as you install them.
- **Microsoft Store packages** (`.msix` and `.appx` files, and setup programs that only fetch one, such as Claude's): these need Windows' own app-package service, which OrielOS doesn't have, so the dialog says so before anything runs and offers the app's web version where there is one.

## Start entries

When a program's installer creates Start menu or desktop shortcuts, Run this app adds them to Start, under the names the installer gave them, while the installer runs and when it closes. Open the program from Start after that.

When you run a program that isn't an installer, Run this app offers **Add to Start** once it closes, so you can start it from Start next time.

## Where programs are kept

Each program gets a folder of its own, a separate Windows set-up with its own settings, so programs can't upset each other: `~/.local/share/orielos/windows-apps/<name>`, where the name comes from the file's name (`SteamSetup.exe` gives `steam`). Running the same program again, or a newer version of it, uses the same folder.

If a program doesn't start or closes with an error, Run this app offers **Open the Log**. The log is `~/.local/state/orielos/windows-apps/<name>.log`.

## Removing a program

1. Delete the program's folder, `~/.local/share/orielos/windows-apps/<name>`.
2. Delete its Start entries: the files named `orielos-windows-<name>-…` in `~/.local/share/applications`.

## What doesn't work

- **Programs that need special drivers or deep access to Windows**, such as some anti-virus and system tools, and games whose anti-cheat blocks Linux (see [Games with anti-cheat](anti-cheat.md)).
- **Microsoft 365 and Adobe apps** don't run; use their web versions or Linux alternatives from the Store.
- Run this app is new and has been tried with only a few programs. If one doesn't work, see [Getting help](help.md).

Licence: CC BY-SA 4.0 (see `LICENSE` in this folder).
