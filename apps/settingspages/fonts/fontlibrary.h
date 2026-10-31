// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The installed fonts, and installing more for this account, as Windows' Personalisation › Fonts
// does with a font file dropped on it. Fonts go to ~/.local/share/fonts, where fontconfig finds
// them; the page shows them at once, and other apps the next time they start.
class FontLibrary : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Each family: { name, faces }, alphabetically.
    Q_PROPERTY(QVariantList families READ families NOTIFY changed FINAL)

public:
    explicit FontLibrary(QObject *parent = nullptr);

    QVariantList families() const;

    // Whether a file is one of the font formats fontconfig reads.
    Q_INVOKABLE static bool isFontFile(const QUrl &url);
    // Copy these font files into the account's fonts. Returns { installed, existing, unsupported },
    // each a list of file names: files already there aren't replaced.
    Q_INVOKABLE QVariantMap install(const QList<QUrl> &urls);

    // Install into this folder and don't refresh fontconfig's cache. For the unit tests.
    void setForTesting(const QString &folder);

Q_SIGNALS:
    void changed();

private:
    QString fontsFolder() const;

    QString m_folder;
    bool m_testing = false;
};

} // namespace OrielOSSettingsPages
