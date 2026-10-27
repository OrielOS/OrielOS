// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QList>
#include <QMap>
#include <QString>
#include <QStringList>

#include <optional>

// What Run this app does, apart from its window: names each Windows program's prefix, finds where a
// download came from, builds the umu-launcher command, reads the shortcuts an installer makes and
// writes Start entries for them.
namespace OrielOSRunApp {

// The prefix name for a downloaded file: its words in lower case, joined with "-", without the
// extension, version numbers and packaging words such as "setup" or "x64", so that every version
// of the same program shares one prefix. "SteamSetup.exe" gives "steam"; a name with no words
// left gives "app".
QString prefixName(const QString &fileName);

// Whether the file looks like an installer: an .msi, or a name with a word such as "setup" or
// "installer" in it.
bool looksLikeInstaller(const QString &fileName);

// Where a program's prefix, the folder Wine keeps it in, lives: under dataHome (normally
// ~/.local/share), at orielos/windows-apps/<name>/prefix.
QString prefixDir(const QString &dataHome, const QString &name);

// Where the output of a program's runs is kept: under stateHome (normally ~/.local/state).
QString logFile(const QString &stateHome, const QString &name);

// Where a download came from, from the user.xdg.origin.url attribute browsers and KDE set on it,
// or user.xdg.referrer.url. Empty when the file has neither.
struct DownloadSource
{
    QString url;
    QString host;
};
DownloadSource downloadSource(const QString &filePath);

// How to run a Windows program: umu-launcher, which downloads GE-Proton the first time, with the
// program's own prefix. An .msi is installed with msiexec.
struct Command
{
    QString program;
    QStringList arguments;
    QMap<QString, QString> environment;
};
Command command(const QString &prefix, const QString &filePath, const QStringList &arguments = { });

// Whether umu-launcher still has to download GE-Proton or its runtime: true when dataHome has no
// Steam/compatibilitytools.d/GE-Proton* and no umu folder.
bool needsFirstDownload(const QString &dataHome);

// The target of a Windows shortcut (.lnk): an absolute Windows path, or a path relative to the
// shortcut, and its arguments.
struct LinkTarget
{
    QString windowsPath;
    QString relativePath;
    QString arguments;
};
std::optional<LinkTarget> readShortcut(const QByteArray &data);

// The Linux path of a Windows path in a prefix: C:\ is the prefix's drive_c, Z:\ is /.
QString linuxPath(const QString &prefix, const QString &windowsPath);

// Splits Windows command-line arguments, honouring double quotes.
QStringList splitArguments(const QString &arguments);

// A program an installer put in the Start menu or on the desktop.
struct Shortcut
{
    QString name;
    QString target;
    QStringList arguments;
};

// The programs a prefix's installers made shortcuts for, in its Start menu folders and on its
// desktops, without uninstallers, non-programs and targets that don't exist, each target once.
QList<Shortcut> findShortcuts(const QString &prefix);

// One argument of a desktop entry's Exec key, quoted and escaped as the Desktop Entry
// Specification asks.
QString execArgument(const QString &argument);

// Writes a Start entry for a shortcut, in applicationsDir (normally ~/.local/share/applications),
// that starts it with orielos-run-app --launch, and returns the file's path. Writing the same
// program again replaces its entry.
QString writeStartEntry(const QString &applicationsDir, const QString &name, const Shortcut &shortcut);

} // namespace OrielOSRunApp
