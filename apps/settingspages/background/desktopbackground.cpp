// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "desktopbackground.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPalette>
#include <QSaveFile>
#include <QStandardPaths>

namespace OrielOSSettingsPages {

namespace {

constexpr int MostRecent = 5;

// OrielOS's own wallpapers, offered among the recent pictures until five have been used.
const QStringList OwnWallpapers = { QStringLiteral("wallpapers/OrielOS"), QStringLiteral("wallpapers/OrielOS-Horizon") };

// A string as a JavaScript literal, so a path with quotes or backslashes can't break the script.
QString literal(const QString &text)
{
    const QString array = QString::fromUtf8(QJsonDocument(QJsonArray { text }).toJson(QJsonDocument::Compact));
    return array.mid(1, array.size() - 2);
}

// Every desktop's picture settings, set by body with "desktop" in scope.
QString forEveryDesktop(const QString &body)
{
    return QStringLiteral("desktops().forEach(function (desktop) {\n"
                          "    desktop.wallpaperPlugin = \"org.kde.image\";\n"
                          "    desktop.currentConfigGroup = [\"Wallpaper\", \"org.kde.image\", \"General\"];\n"
                          "    %1\n"
                          "    desktop.reloadConfig();\n"
                          "});\n")
        .arg(body);
}

// The image in a wallpaper package folder: images_dark for a dark desktop when it has one, and the
// largest picture there.
QString packageImage(const QString &folder, bool dark)
{
    for (const QString &sub : dark ? QStringList { QStringLiteral("images_dark"), QStringLiteral("images") } : QStringList { QStringLiteral("images") }) {
        const QFileInfoList images = QDir(folder + QStringLiteral("/contents/") + sub).entryInfoList(QDir::Files | QDir::Readable, QDir::Size);
        if (!images.isEmpty()) {
            return images.first().filePath();
        }
    }
    return QString();
}

} // namespace

DesktopBackground::DesktopBackground(QObject *parent)
    : DesktopBackground(
          [this](const QString &script, std::function<void(bool, const QString &)> done) {
              QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"),
                  QStringLiteral("org.kde.PlasmaShell"), QStringLiteral("evaluateScript"));
              message << script;
              // Parented to this, so no answer arrives after the page is gone.
              auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(message), this);
              connect(watcher, &QDBusPendingCallWatcher::finished, this, [watcher, done = std::move(done)]() {
                  watcher->deleteLater();
                  const QDBusPendingReply<QString> reply = *watcher;
                  done(!reply.isError(), reply.isError() ? reply.error().message() : reply.value());
              });
          },
          QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation) + QStringLiteral("/orielos/recent-backgrounds"), parent)
{
}

DesktopBackground::DesktopBackground(Runner runner, const QString &stateFile, QObject *parent)
    : QObject(parent)
    , m_runner(std::move(runner))
    , m_stateFile(stateFile)
{
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, &DesktopBackground::readRecent);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, &DesktopBackground::readRecent);
    readRecent();
    reload();
}

QString DesktopBackground::readScript()
{
    return QStringLiteral("var found = desktops().filter(function (desktop) { return desktop.wallpaperPlugin === \"org.kde.image\"; })[0];\n"
                          "var answer = { image: \"\", fillMode: 2 };\n"
                          "if (found) {\n"
                          "    found.currentConfigGroup = [\"Wallpaper\", \"org.kde.image\", \"General\"];\n"
                          "    answer.image = String(found.readConfig(\"Image\", \"\"));\n"
                          "    answer.fillMode = Number(found.readConfig(\"FillMode\", 2));\n"
                          "}\n"
                          "print(JSON.stringify(answer));\n");
}

QString DesktopBackground::imageScript(const QString &path)
{
    // Plasma recognises a wallpaper package by its folder's URL ending in a slash.
    QString url = QUrl::fromLocalFile(path).toString();
    if (QFileInfo(path).isDir() && !url.endsWith(QLatin1Char('/'))) {
        url += QLatin1Char('/');
    }
    return forEveryDesktop(QStringLiteral("desktop.writeConfig(\"Image\", %1);").arg(literal(url)));
}

QString DesktopBackground::fillModeScript(int mode)
{
    return forEveryDesktop(QStringLiteral("desktop.writeConfig(\"FillMode\", %1);").arg(mode));
}

QString DesktopBackground::localPath(const QString &image)
{
    if (image.isEmpty()) {
        return QString();
    }
    QString path;
    if (image.startsWith(QLatin1String("file:"))) {
        path = QUrl(image).toLocalFile();
    } else if (image.startsWith(QLatin1Char('/'))) {
        path = image;
    } else {
        // A package's name, as the look-and-feel package gives it.
        path = QStandardPaths::locate(QStandardPaths::GenericDataLocation, QStringLiteral("wallpapers/") + image, QStandardPaths::LocateDirectory);
    }
    return path.isEmpty() ? QString() : QDir::cleanPath(path);
}

QStringList DesktopBackground::withRecent(QStringList list, const QString &path)
{
    if (!path.isEmpty()) {
        list.removeAll(path);
        list.prepend(path);
    }
    list.removeDuplicates();
    return list.mid(0, MostRecent);
}

QStringList DesktopBackground::recent() const
{
    QStringList list = m_recent;
    if (!m_recentRead) {
        // Nothing used yet: the picture now, then OrielOS's own.
        list = { m_image };
        for (const QString &own : OwnWallpapers) {
            list.append(QStandardPaths::locate(QStandardPaths::GenericDataLocation, own, QStandardPaths::LocateDirectory));
        }
    }
    list.removeIf([](const QString &path) { return path.isEmpty() || !QFileInfo::exists(path); });
    list.removeDuplicates();
    return list.mid(0, MostRecent);
}

QUrl DesktopBackground::previewUrl(const QString &path, bool large) const
{
    if (!QFileInfo(path).isDir()) {
        return path.isEmpty() ? QUrl() : QUrl::fromLocalFile(path);
    }
    const QString screenshot = path + QStringLiteral("/contents/screenshot.png");
    if (!large && QFileInfo::exists(screenshot)) {
        return QUrl::fromLocalFile(screenshot);
    }
    const bool dark = QGuiApplication::palette().color(QPalette::Window).lightnessF() < 0.5;
    const QString image = packageImage(path, dark);
    return image.isEmpty() ? QUrl() : QUrl::fromLocalFile(image);
}

void DesktopBackground::setImage(const QString &image)
{
    const QString path = localPath(image);
    if (path.isEmpty()) {
        return;
    }
    // Shown at once; the desktop's answer follows.
    m_image = path;
    Q_EMIT changed();
    m_recent = withRecent(recent(), path);
    m_recentRead = true;
    writeRecent();
    Q_EMIT recentChanged();
    m_runner(imageScript(path), [this](bool, const QString &) { reload(); });
}

void DesktopBackground::setFillMode(int mode)
{
    if (mode == m_fillMode) {
        return;
    }
    m_fillMode = mode;
    Q_EMIT changed();
    m_runner(fillModeScript(mode), [this](bool, const QString &) { reload(); });
}

void DesktopBackground::reload()
{
    m_runner(readScript(), [this](bool ok, const QString &output) {
        const QJsonObject answer = QJsonDocument::fromJson(output.toUtf8()).object();
        m_available = ok && !answer.isEmpty();
        if (m_available) {
            m_image = localPath(answer.value(QStringLiteral("image")).toString());
            m_fillMode = answer.value(QStringLiteral("fillMode")).toInt(Fill);
        }
        Q_EMIT changed();
        Q_EMIT recentChanged();
    });
}

void DesktopBackground::readRecent()
{
    QFile file(m_stateFile);
    m_recentRead = file.open(QIODevice::ReadOnly | QIODevice::Text);
    m_recent.clear();
    if (m_recentRead) {
        for (const QByteArray &line : file.readAll().split('\n')) {
            const QString path = QString::fromUtf8(line).trimmed();
            if (!path.isEmpty()) {
                m_recent.append(path);
            }
        }
    }
    watchRecent();
    Q_EMIT recentChanged();
}

void DesktopBackground::writeRecent()
{
    QDir().mkpath(QFileInfo(m_stateFile).absolutePath());
    QSaveFile file(m_stateFile);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        return;
    }
    file.write(m_recent.join(QLatin1Char('\n')).toUtf8() + '\n');
    file.commit();
    watchRecent();
}

void DesktopBackground::watchRecent()
{
    // A file replaced whole leaves the watch, so it's set again each time; the folder's watch sees
    // the file appear.
    const QString folder = QFileInfo(m_stateFile).absolutePath();
    if (QFileInfo::exists(folder) && !m_watcher.directories().contains(folder)) {
        m_watcher.addPath(folder);
    }
    if (QFileInfo::exists(m_stateFile) && !m_watcher.files().contains(m_stateFile)) {
        m_watcher.addPath(m_stateFile);
    }
}

} // namespace OrielOSSettingsPages
