// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>
#include <QStringList>

namespace OrielOSGames {

// A game installed in Steam.
struct SteamGame
{
    QString appId;
    QString name;
    // The game's portrait art from Steam's library cache, or empty.
    QString art;
};

// A compatibility tool Steam can run Windows games with.
struct CompatTool
{
    // The name Steam keeps in config.vdf, such as proton_experimental or GE-Proton.
    QString id;
    QString displayName;
};

// Steam from the Store's files in one user's home: its libraries and the games in them, the
// compatibility tools, and each game's tool and launch options. Steam rewrites config.vdf and
// localconfig.vdf when it quits, so changes are written only while it isn't running.
class SteamLibrary
{
public:
    // root is Steam's folder, normally ~/.var/app/com.valvesoftware.Steam/.local/share/Steam.
    explicit SteamLibrary(QString root);
    static QString defaultRoot();

    bool installed() const;
    // Every library folder: Steam's own, then those in steamapps/libraryfolders.vdf.
    QStringList libraries() const;
    // The games in every library, by name; Steam's tools (Proton, the runtimes) are left out.
    QList<SteamGame> games() const;
    // GE-Proton (Flathub's extension, from the folders given), then Valve's Protons installed as apps.
    QList<CompatTool> compatTools(const QStringList &extensionFolders) const;

    // The tool a game uses, or empty when it follows Steam's default.
    QString compatTool(const QString &appId) const;
    // Sets the game's tool, or with an empty id makes it follow Steam's default again.
    bool setCompatTool(const QString &appId, const QString &toolId) const;
    // The game's launch options for the Steam account that used Steam last.
    QString launchOptions(const QString &appId) const;
    bool setLaunchOptions(const QString &appId, const QString &options) const;

private:
    QString configPath() const;
    QString localConfigPath() const;

    QString m_root;
};

// Reads and writes a VDF file whole, keeping a copy of the first version OrielOS changed.
bool writeVdfFile(const QString &path, const QString &text);

} // namespace OrielOSGames
