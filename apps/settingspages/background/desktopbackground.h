// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QStringList>
#include <QUrl>
#include <qqmlintegration.h>

#include <functional>

namespace OrielOSSettingsPages {

/**
 * The desktop's picture for Settings' Background page: the picture and how it fits the screen,
 * read from and set on every desktop through Plasma's desktop scripting, and the last five pictures
 * used. The recent pictures are kept in ~/.local/state/orielos/recent-backgrounds, one path a line,
 * newest first; recent-backgrounds adds the ones chosen from the desktop's own menu.
 */
class DesktopBackground : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    // The picture: an image file, or a folder holding one of Plasma's wallpaper packages.
    Q_PROPERTY(QString image READ image NOTIFY changed)
    Q_PROPERTY(int fillMode READ fillMode NOTIFY changed)
    Q_PROPERTY(QStringList recent READ recent NOTIFY recentChanged)
    // False until the desktop has answered, and when it can't.
    Q_PROPERTY(bool available READ available NOTIFY changed)

public:
    // Runs a desktop script and calls done with whether it ran and what it printed.
    using Runner = std::function<void(const QString &script, std::function<void(bool ok, const QString &output)> done)>;

    // Plasma's FillMode values for the fits the page offers.
    enum FillMode {
        Stretch = 0,
        Fit = 1,
        Fill = 2,
        Tile = 3,
        Centre = 6,
    };
    Q_ENUM(FillMode)

    explicit DesktopBackground(QObject *parent = nullptr);
    // For the tests: another runner and recent pictures file.
    DesktopBackground(Runner runner, const QString &stateFile, QObject *parent = nullptr);

    QString image() const { return m_image; }
    int fillMode() const { return m_fillMode; }
    QStringList recent() const;
    bool available() const { return m_available; }

    // image is a path or a file: URL.
    Q_INVOKABLE void setImage(const QString &image);
    Q_INVOKABLE void setFillMode(int mode);
    // The picture to show for path: a package's screenshot for a thumbnail, or its light or dark
    // image, whichever the desktop shows, for the large preview.
    Q_INVOKABLE QUrl previewUrl(const QString &path, bool large) const;

    // The scripts, for the tests.
    static QString readScript();
    static QString imageScript(const QString &path);
    static QString fillModeScript(int mode);
    // A local path for one of Plasma's Image values: a file: URL, a path, or a package's name.
    static QString localPath(const QString &image);
    // list with path first, once, and at most five pictures.
    static QStringList withRecent(QStringList list, const QString &path);

Q_SIGNALS:
    void changed();
    void recentChanged();

private:
    void reload();
    void readRecent();
    void writeRecent();
    void watchRecent();

    Runner m_runner;
    QString m_stateFile;
    QFileSystemWatcher m_watcher;
    QString m_image;
    int m_fillMode = Fill;
    bool m_available = false;
    QStringList m_recent;
    bool m_recentRead = false;
};

} // namespace OrielOSSettingsPages
