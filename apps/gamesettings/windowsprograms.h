// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

namespace OrielOSGames {

// A Windows program installed with Run this app, by the prefix its Start entries share (a game
// store's launcher and the games it installs share one).
struct WindowsProgram
{
    QString prefix;
    QString name;
    QString icon;
};

// The programs in Start that Run this app added: desktop entries in applicationsDir with
// X-OrielOS-WindowsPrefix, one per prefix, by name.
QList<WindowsProgram> windowsPrograms(const QString &applicationsDir);
// A program's launch options, which Run this app applies when it starts it (see
// launchOptionsFile in Run this app), in dataHome/orielos/windows-apps/<prefix>/launch-options.
QString windowsLaunchOptions(const QString &dataHome, const QString &prefix);
// Writes them, or with nothing to write removes the file.
bool setWindowsLaunchOptions(const QString &dataHome, const QString &prefix, const QString &options);

} // namespace OrielOSGames
