# Writing code on OrielOS

OrielOS is ready for development on the same PC you game on. The system itself stays read-only and updates as one piece, so the tools you work with live in your home folder, in apps from the Store, and in containers, where they can't break the system and survive every update.

## What's already there

- **Terminal** (Konsole), in Start, or Windows + X › Terminal.
- **Git**, for version control and the tools that expect it.
- **Podman**, which runs containers without an administrator, and accepts the same commands as Docker.
- **Toolbx** and **Distrobox**, which make a container that feels like a normal Linux system with your home folder in it: install compilers, SDKs and anything else there, with the package manager you know, without touching OrielOS.

## A container for your tools

Open Terminal and make a Fedora container, then enter it:

```sh
toolbox create
toolbox enter
```

Inside it, `sudo dnf install` installs what you need, such as `gcc`, `nodejs`, `python3-pip` or `rust cargo`. Your home folder is the same inside and outside, so your projects are where you left them. To work with another distribution's packages, Distrobox makes one, such as `distrobox create --name ubuntu --image ubuntu:24.04` then `distrobox enter ubuntu`.

## An editor

Install **Visual Studio Code** (or another editor, such as Kate or Zed) from the Store. To use the compilers and tools in your container from Visual Studio Code's terminal, start it with:

```sh
flatpak-spawn --host toolbox enter
```

Visual Studio Code's Dev Containers extension works with Podman: in its settings, set **Dev › Containers: Docker Path** to `podman`.

## Command-line tools for your account

Tools that install for one user, such as AI coding assistants, go into your home folder and need no administrator: follow their own Linux instructions. For example, Claude Code's native installer puts it in `~/.local/bin`, which is on your path. Tools that need Node.js or Python can also go inside a container.

## Why not install packages onto the system?

OrielOS updates the whole system at once and can go back to the previous version, which only works because nothing is installed onto it piece by piece. Containers give you the same freedom without that risk; see [Updates and going back](updates.md).
