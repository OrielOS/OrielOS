// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QObject>
#include <QString>
#include <QStringList>

#include <functional>
#include <optional>

namespace OrielOSSettingsPages {

// Start's and the taskbar's settings, as the running Plasma desktop has them. OrielOS's taskbar is
// the panel with OrielOS's Start menu on it, centred by the panel spacer just before Start.
struct ShellState
{
    // Whether a panel has OrielOS's Start menu; the rest means nothing without it.
    bool hasStart = false;
    bool showRecentlyAdded = true;
    bool showRecentFiles = true;
    // Whether the spacer before Start is there, to centre the taskbar with.
    bool canAlign = false;
    bool centred = true;
    bool autoHide = false;
    // The Search and Task View buttons, the task manager and the clock on the taskbar, and their
    // settings; a button or widget that isn't there can't be changed.
    bool hasSearch = false;
    bool showSearch = true;
    bool hasTaskView = false;
    bool showTaskView = true;
    bool hasTasks = false;
    // Each app's windows on one button (Windows' "Always combine"), or each window on its own.
    bool combineButtons = true;
    bool hasClock = false;
    bool showSeconds = false;
    // Pointing at the show desktop strip at the far end peeks at the desktop.
    bool hasSliver = false;
    bool peek = false;
    // A taskbar on every display, each listing that display's windows.
    bool allDisplays = false;
    // Smaller taskbar buttons: the taskbars 40 px high rather than 48.
    bool smallButtons = false;
    // The shortcuts next to Start's power button, by ID (settings, files, documents, downloads,
    // music, pictures, videos, network, personal), in Windows' order.
    QStringList startFolders = { QStringLiteral("files"), QStringLiteral("downloads"), QStringLiteral("settings") };
    // Start's layout: morePins, default or moreRecommendations.
    QString startLayout = QStringLiteral("default");
    // OrielOS's tray on the taskbar, and the apps whose icons it shows on the taskbar rather than
    // under its arrow, by the icons' ids.
    bool hasTray = false;
    QStringList trayShown;

    // The state a script printed, or nothing if the output isn't that JSON.
    static std::optional<ShellState> fromJson(const QString &json);
};

// Reads and changes those settings through Plasma's desktop scripting
// (org.kde.PlasmaShell.evaluateScript), so a change applies at once, as one made on the desktop
// would. One script runs at a time and changes made meanwhile wait their turn. A change shows
// straight away and goes back if it fails.
class ShellSettings : public QObject
{
    Q_OBJECT

public:
    enum class Setting {
        ShowRecentlyAdded,
        ShowRecentFiles,
        Centred,
        AutoHide,
        ShowSearch,
        ShowTaskView,
        CombineButtons,
        ShowSeconds,
        Peek,
        AllDisplays,
        SmallButtons,
        // One shortcut next to Start's power button each.
        FolderSettings,
        FolderFiles,
        FolderDocuments,
        FolderDownloads,
        FolderMusic,
        FolderPictures,
        FolderVideos,
        FolderNetwork,
        FolderPersonal,
        // Start's layout; a change to true chooses it.
        LayoutMorePins,
        LayoutDefault,
        LayoutMoreRecommendations,
        // An app's icon on the taskbar, or under the tray's arrow; the change names the app.
        TrayIcon,
    };

    // A layout setting's name in Start's settings, or empty for any other setting.
    static QString layoutId(Setting setting);

    // A folder setting's ID in Start's folders list, or empty for any other setting.
    static QString folderId(Setting setting);
    // The folder setting for an ID, if there is one.
    static std::optional<Setting> folderSetting(const QString &id);
    // A setting and its new value; a TrayIcon change also has the icon's id.
    struct Change
    {
        Setting setting;
        bool value;
        QString item = { };
    };

    // Runs a script in the desktop, then calls done with whether it ran, and what it printed or
    // why it failed.
    using Runner = std::function<void(const QString &script, std::function<void(bool ok, const QString &output)> done)>;

    // Runs scripts in plasmashell over D-Bus, and reads the settings.
    explicit ShellSettings(QObject *parent = nullptr);
    // Runs scripts with runner instead, and reads the settings. For the unit tests.
    ShellSettings(Runner runner, QObject *parent = nullptr);

    // The settings, with the changes still being made.
    ShellState state() const;
    // Whether the first read has finished, whether or not it worked.
    bool isReady() const { return m_ready; }
    bool isBusy() const { return !m_queue.isEmpty(); }
    QString error() const { return m_error; }

    void reload();
    void change(Setting setting, bool value);
    // Puts an app's icon on the taskbar, or under the tray's arrow.
    void changeTrayIcon(const QString &item, bool shown);

    // The script that makes the change, if any, then prints the settings as JSON.
    static QString script(std::optional<Change> change = std::nullopt);

Q_SIGNALS:
    void changed();

private:
    void runNext();
    void finish(bool ok, const QString &output);
    static void apply(ShellState &state, const Change &change);

    Runner m_runner;
    ShellState m_confirmed;
    // The scripts to run, the first one running: a change, or a read.
    QList<std::optional<Change>> m_queue;
    // Whether the first script in the queue is running.
    bool m_running = false;
    bool m_ready = false;
    QString m_error;
};

} // namespace OrielOSSettingsPages
