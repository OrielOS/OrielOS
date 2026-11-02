// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "runapp.h"

#include <QObject>
#include <QProcess>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <qqmlintegration.h>

// One Windows program the user opened: what the window shows about it, and running it once the
// user agrees. While it runs, and when it ends, the Start entries for the shortcuts its installer
// made are added.
class Runner : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Made by orielos-run-app for the file it opens")

public:
    enum Stage : quint8 {
        Confirm,
        Running,
        Finished,
    };
    Q_ENUM(Stage)

private:
    Q_PROPERTY(QString fileName READ fileName CONSTANT)
    Q_PROPERTY(QString programName READ programName CONSTANT)
    Q_PROPERTY(QString sourceUrl READ sourceUrl CONSTANT)
    Q_PROPERTY(QString sourceHost READ sourceHost CONSTANT)
    Q_PROPERTY(QString size READ size CONSTANT)
    // An .msi, which is installed rather than run.
    Q_PROPERTY(bool msi READ msi CONSTANT)
    Q_PROPERTY(Stage stage READ stage NOTIFY changed)
    // GE-Proton or its runtime is still to be downloaded, the first time a program runs.
    Q_PROPERTY(bool firstDownload READ firstDownload CONSTANT)
    // The Start entries added so far, by name.
    Q_PROPERTY(QStringList added READ added NOTIFY changed)
    // The program ended with an error and added nothing to Start, or didn't start at all.
    Q_PROPERTY(bool failed READ failed NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // The program itself can go in Start: it isn't an installer, and nothing was added for it.
    Q_PROPERTY(bool canAddItself READ canAddItself NOTIFY changed)
    // Where this person lets apps come from, chosen in Settings › Apps › Installed apps: anywhere
    // (the default), suggest (anywhere, with the Store suggested first) or store (the Store only,
    // so Windows programs don't run).
    Q_PROPERTY(QString appSource READ appSource CONSTANT)
    // What OrielOS's known-apps list says about this program: its name, the Store app to offer
    // first, a launcher's note, or that it's a Microsoft Store package OrielOS can't run and where
    // to get the app instead. Empty strings and false when the list doesn't know it.
    Q_PROPERTY(QString knownName READ knownName CONSTANT)
    Q_PROPERTY(QString storeApp READ storeApp CONSTANT)
    Q_PROPERTY(QString launcherNote READ launcherNote CONSTANT)
    Q_PROPERTY(bool package READ package CONSTANT)
    Q_PROPERTY(QString alternative READ alternative CONSTANT)

public:
    // dataHome, stateHome and applicationsDir are normally ~/.local/share, ~/.local/state and
    // ~/.local/share/applications.
    Runner(const QString &filePath, const QString &dataHome, const QString &stateHome, const QString &applicationsDir, QObject *parent = nullptr);

    QString fileName() const;
    QString programName() const;
    QString sourceUrl() const;
    QString sourceHost() const;
    QString size() const;
    bool msi() const;
    Stage stage() const;
    bool firstDownload() const;
    QStringList added() const;
    bool failed() const;
    QString error() const;
    bool canAddItself() const;
    QString appSource() const;
    QString knownName() const { return m_known ? m_known->name : QString(); }
    QString storeApp() const { return m_known ? m_known->store : QString(); }
    QString launcherNote() const { return m_known && m_known->launcher ? m_known->note : QString(); }
    bool package() const { return m_known && m_known->package; }
    QString alternative() const { return m_known ? m_known->alternative : QString(); }

    Q_INVOKABLE void run();
    Q_INVOKABLE void addItself();
    Q_INVOKABLE void openLog() const;

Q_SIGNALS:
    void changed();

private:
    void addShortcuts();
    void finish(int exitCode, QProcess::ExitStatus status);

    const QString m_filePath;
    const QString m_dataHome;
    const QString m_stateHome;
    const QString m_applicationsDir;
    const QString m_name;
    const OrielOSRunApp::DownloadSource m_source;
    const bool m_firstDownload;
    const std::optional<OrielOSRunApp::KnownApp> m_known;
    Stage m_stage = Confirm;
    QStringList m_added;
    QSet<QString> m_targets;
    bool m_failed = false;
    QString m_error;
    QProcess m_process;
    QTimer m_scan;
};
