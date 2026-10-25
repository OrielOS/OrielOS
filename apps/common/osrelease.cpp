// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "osrelease.h"

#include <QFile>

namespace OrielOS {

namespace {

// A shell variable name: a letter or underscore, then letters, digits or underscores.
bool isValidKey(QStringView key)
{
    if (key.isEmpty()) {
        return false;
    }
    for (qsizetype i = 0; i < key.size(); ++i) {
        const char16_t c = key[i].unicode();
        const bool letter = (c >= u'A' && c <= u'Z') || (c >= u'a' && c <= u'z') || c == u'_';
        const bool digit = c >= u'0' && c <= u'9';
        if (!letter && !(digit && i > 0)) {
            return false;
        }
    }
    return true;
}

// The characters a backslash escapes inside double quotes.
bool isEscapable(char16_t c)
{
    return c == u'\\' || c == u'"' || c == u'`' || c == u'$';
}

// Parses the value of an assignment the way a shell would read a single word. Returns false
// if the value is not one well-formed word, for example an unclosed quote or a second word.
bool parseValue(QStringView raw, QString &out)
{
    out.clear();
    const qsizetype n = raw.size();
    qsizetype i = 0;
    if (n > 0 && raw[0] == u'"') {
        for (i = 1; i < n && raw[i] != u'"'; ++i) {
            if (raw[i] == u'\\' && i + 1 < n && isEscapable(raw[i + 1].unicode())) {
                ++i;
            }
            out += raw[i];
        }
        if (i >= n) {
            return false;
        }
        ++i;
    } else if (n > 0 && raw[0] == u'\'') {
        const qsizetype end = raw.indexOf(u'\'', 1);
        if (end < 0) {
            return false;
        }
        out = raw.sliced(1, end - 1).toString();
        i = end + 1;
    } else {
        for (; i < n && !raw[i].isSpace(); ++i) {
            const char16_t c = raw[i].unicode();
            if (c == u'"' || c == u'\'' || c == u'`' || c == u'$') {
                return false;
            }
            if (c == u'\\') {
                if (++i >= n) {
                    return false;
                }
            }
            out += raw[i];
        }
    }
    return raw.sliced(i).trimmed().isEmpty();
}

bool readFile(const QString &path, OsRelease &result)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return false;
    }
    result = OsRelease::fromString(QString::fromUtf8(file.readAll()));
    return true;
}

} // namespace

OsRelease OsRelease::fromFile(const QString &path)
{
    OsRelease result;
    if (readFile(path, result)) {
        result.m_path = path;
    }
    return result;
}

OsRelease OsRelease::fromString(QStringView text)
{
    OsRelease result;
    QString value;
    for (QStringView line : text.tokenize(u'\n')) {
        line = line.trimmed();
        if (line.isEmpty() || line.startsWith(u'#')) {
            continue;
        }
        const qsizetype equals = line.indexOf(u'=');
        if (equals < 0) {
            continue;
        }
        const QStringView key = line.first(equals);
        if (!isValidKey(key) || !parseValue(line.sliced(equals + 1), value)) {
            continue;
        }
        result.m_values.insert(key.toString(), value);
    }
    return result;
}

OsRelease OsRelease::fromFirstReadable(const QStringList &paths)
{
    for (const QString &path : paths) {
        OsRelease result;
        if (readFile(path, result)) {
            result.m_path = path;
            return result;
        }
    }
    return { };
}

OsRelease OsRelease::fromSystem()
{
    return fromFirstReadable(defaultPaths());
}

QStringList OsRelease::defaultPaths()
{
    return { QStringLiteral("/etc/os-release"), QStringLiteral("/usr/lib/os-release") };
}

QString OsRelease::value(QStringView key) const
{
    return m_values.value(key.toString());
}

bool OsRelease::isValid() const
{
    return !m_values.isEmpty();
}

QString OsRelease::path() const
{
    return m_path;
}

QString OsRelease::prettyName() const
{
    const QString name = value(u"PRETTY_NAME");
    return name.isEmpty() ? QStringLiteral("Linux") : name;
}

QString OsRelease::id() const
{
    const QString name = value(u"ID");
    return name.isEmpty() ? QStringLiteral("linux") : name;
}

QString OsRelease::versionId() const
{
    return value(u"VERSION_ID");
}

} // namespace OrielOS
