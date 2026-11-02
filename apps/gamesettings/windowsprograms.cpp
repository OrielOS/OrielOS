// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "windowsprograms.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>

#include <algorithm>

namespace OrielOSGames {

namespace {

QString optionsPath(const QString &dataHome, const QString &prefix)
{
    return dataHome + QStringLiteral("/orielos/windows-apps/") + prefix + QStringLiteral("/launch-options");
}

// The value of a key in a desktop entry's main group.
QString entryValue(const QStringList &lines, const QString &key)
{
    const QString start = key + QLatin1Char('=');
    for (const QString &line : lines) {
        if (line.startsWith(QLatin1Char('[')) && line != QLatin1String("[Desktop Entry]")) {
            break;
        }
        if (line.startsWith(start)) {
            return line.mid(start.size()).trimmed();
        }
    }
    return { };
}

} // namespace

QList<WindowsProgram> windowsPrograms(const QString &applicationsDir)
{
    QList<WindowsProgram> out;
    const QDir dir(applicationsDir);
    for (const QString &file : dir.entryList({ QStringLiteral("*.desktop") }, QDir::Files, QDir::Name)) {
        QFile entry(dir.filePath(file));
        if (!entry.open(QIODevice::ReadOnly)) {
            continue;
        }
        const QStringList lines = QString::fromUtf8(entry.readAll()).split(QLatin1Char('\n'));
        const QString prefix = entryValue(lines, QStringLiteral("X-OrielOS-WindowsPrefix"));
        if (prefix.isEmpty() || prefix.contains(QLatin1Char('/'))
            || std::any_of(out.cbegin(), out.cend(), [&prefix](const WindowsProgram &p) { return p.prefix == prefix; })) {
            continue;
        }
        out.append({ prefix, entryValue(lines, QStringLiteral("Name")), entryValue(lines, QStringLiteral("Icon")) });
    }
    std::sort(out.begin(), out.end(), [](const WindowsProgram &a, const WindowsProgram &b) { return a.name.compare(b.name, Qt::CaseInsensitive) < 0; });
    return out;
}

QString windowsLaunchOptions(const QString &dataHome, const QString &prefix)
{
    QFile file(optionsPath(dataHome, prefix));
    return file.open(QIODevice::ReadOnly) ? QString::fromUtf8(file.readAll()).trimmed() : QString();
}

bool setWindowsLaunchOptions(const QString &dataHome, const QString &prefix, const QString &options)
{
    const QString path = optionsPath(dataHome, prefix);
    if (options.trimmed().isEmpty()) {
        return !QFileInfo::exists(path) || QFile::remove(path);
    }
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(options.toUtf8() + '\n');
    return file.commit();
}

} // namespace OrielOSGames
