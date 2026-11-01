// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fontlibrary.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFontDatabase>
#include <QProcess>
#include <QStandardPaths>

namespace OrielOSSettingsPages {

namespace {

// The formats fontconfig reads, as Windows' page takes TrueType and OpenType files.
const QStringList fontSuffixes = {
    QStringLiteral("ttf"),
    QStringLiteral("otf"),
    QStringLiteral("ttc"),
    QStringLiteral("otc"),
};

} // namespace

FontLibrary::FontLibrary(QObject *parent)
    : QObject(parent)
{
}

QVariantList FontLibrary::families() const
{
    QVariantList list;
    const QStringList names = QFontDatabase::families();
    for (const QString &name : names) {
        // Fonts the system keeps for itself, such as emoji fallbacks marked private.
        if (QFontDatabase::isPrivateFamily(name)) {
            continue;
        }
        list.append(QVariantMap { { QStringLiteral("name"), name }, { QStringLiteral("faces"), QFontDatabase::styles(name).size() } });
    }
    return list;
}

bool FontLibrary::isFontFile(const QUrl &url)
{
    return url.isLocalFile() && fontSuffixes.contains(QFileInfo(url.toLocalFile()).suffix().toLower());
}

QString FontLibrary::fontsFolder() const
{
    if (!m_folder.isEmpty()) {
        return m_folder;
    }
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/fonts");
}

QVariantMap FontLibrary::install(const QList<QUrl> &urls)
{
    QStringList installed;
    QStringList existing;
    QStringList unsupported;
    const QDir folder(fontsFolder());
    folder.mkpath(QStringLiteral("."));
    for (const QUrl &url : urls) {
        const QString name = url.fileName();
        if (!isFontFile(url)) {
            unsupported.append(name);
            continue;
        }
        const QString target = folder.filePath(name);
        if (QFile::exists(target)) {
            existing.append(name);
            continue;
        }
        if (!QFile::copy(url.toLocalFile(), target)) {
            unsupported.append(name);
            continue;
        }
        QFile::setPermissions(target, QFile::ReadOwner | QFile::WriteOwner | QFile::ReadGroup | QFile::ReadOther);
        // Shown on this page straight away; other apps read fontconfig's cache when they start.
        if (QFontDatabase::addApplicationFont(target) < 0) {
            QFile::remove(target);
            unsupported.append(name);
            continue;
        }
        installed.append(name);
    }
    if (!installed.isEmpty()) {
        if (!m_testing) {
            QProcess::startDetached(QStringLiteral("fc-cache"), { folder.path() });
        }
        Q_EMIT changed();
    }
    return {
        { QStringLiteral("installed"), installed },
        { QStringLiteral("existing"), existing },
        { QStringLiteral("unsupported"), unsupported },
    };
}

void FontLibrary::setForTesting(const QString &folder)
{
    m_folder = folder;
    m_testing = true;
}

} // namespace OrielOSSettingsPages
