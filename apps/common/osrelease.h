// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QHash>
#include <QString>
#include <QStringList>
#include <QStringView>

namespace OrielOS {

/**
 * The operating system identification data from os-release, parsed as the os-release(5)
 * manual describes: KEY=value lines with optional single or double quotes. Blank lines,
 * comments and lines that are not valid assignments are ignored.
 */
class OsRelease
{
public:
    OsRelease() = default;

    /** Parses the file at @p path. The result is invalid if the file cannot be read. */
    static OsRelease fromFile(const QString &path);

    /** Parses os-release data held in memory. */
    static OsRelease fromString(QStringView text);

    /** Parses the first of @p paths that can be opened, in order. */
    static OsRelease fromFirstReadable(const QStringList &paths);

    /** Parses the running system's data: /etc/os-release, or /usr/lib/os-release if that is missing. */
    static OsRelease fromSystem();

    /** The paths fromSystem() tries, in order. */
    static QStringList defaultPaths();

    /** The value of @p key, or an empty string if it is not set. */
    QString value(QStringView key) const;

    /** True if at least one valid assignment was read. */
    bool isValid() const;

    /** The file the data came from, or an empty string if it came from a string or no file was found. */
    QString path() const;

    /** PRETTY_NAME, or "Linux" if it is not set, as os-release(5) specifies. */
    QString prettyName() const;

    /** ID, or "linux" if it is not set, as os-release(5) specifies. */
    QString id() const;

    /** VERSION_ID, or an empty string if it is not set. */
    QString versionId() const;

    /** IMAGE_VERSION, OrielOS's own version such as v0.0.7, or "dev" if it is not set, as outside an OrielOS build. */
    QString imageVersion() const;

private:
    QHash<QString, QString> m_values;
    QString m_path;
};

} // namespace OrielOS
