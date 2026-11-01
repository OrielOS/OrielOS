// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QFutureWatcher>
#include <QHash>
#include <QObject>
#include <QProcess>
#include <QStringList>
#include <QVariantList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// What fills the disk the home folder is on, as Windows' System › Storage shows it: the disk's
// used and free space, how much of it the apps, temporary files, the Bin and the personal folders
// take, and the rest as System and other. Sizes count the space files take on the disk, each hard
// link once, so the Store's shared files aren't counted twice. Also Storage Sense's settings, which
// the storage-sense script reads when its daily timer runs it.
class StorageUsage : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(qint64 total READ total NOTIFY changed FINAL)
    Q_PROPERTY(qint64 used READ used NOTIFY changed FINAL)
    // Each part: { id, name, icon, bytes }, largest first, then System and other.
    Q_PROPERTY(QVariantList categories READ categories NOTIFY changed FINAL)
    Q_PROPERTY(qint64 temporaryBytes READ temporaryBytes NOTIFY changed FINAL)
    Q_PROPERTY(qint64 binBytes READ binBytes NOTIFY changed FINAL)
    Q_PROPERTY(bool calculating READ isCalculating NOTIFY changed FINAL)
    Q_PROPERTY(bool cleaning READ isCleaning NOTIFY changed FINAL)
    Q_PROPERTY(bool senseEnabled READ isSenseEnabled WRITE setSenseEnabled NOTIFY senseChanged FINAL)
    // Bin items older than this many days go; 0 never.
    Q_PROPERTY(int binDays READ binDays WRITE setBinDays NOTIFY senseChanged FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    explicit StorageUsage(QObject *parent = nullptr);
    ~StorageUsage() override;

    qint64 total() const { return m_total; }
    qint64 used() const { return m_used; }
    QVariantList categories() const;
    qint64 temporaryBytes() const { return m_sizes.value(QStringLiteral("temporary")); }
    qint64 binBytes() const { return m_sizes.value(QStringLiteral("bin")); }
    bool isCalculating() const { return m_watcher != nullptr; }
    bool isCleaning() const { return m_process != nullptr; }
    bool isSenseEnabled() const;
    void setSenseEnabled(bool enabled);
    int binDays() const;
    void setBinDays(int days);
    QString error() const { return m_error; }

    // Measure everything again, in the background.
    Q_INVOKABLE void refresh();
    // Run Storage Sense now, with its settings; with everything, also empty the whole Bin and the
    // thumbnails, as Windows' Clean up now does.
    Q_INVOKABLE void cleanUp(bool everything);
    // Open a part: its folder in Files, or Settings' Apps page.
    Q_INVOKABLE void open(const QString &id);

    // The space a folder's files take on the disk, each hard-linked file once; unreadable parts are
    // skipped. Public for the unit tests.
    static qint64 diskUsage(const QString &path);

    // Measure these folders instead of the home folder's (by part id) and keep the settings in
    // this file; run program instead of storage-sense. For the unit tests.
    void setForTesting(const QHash<QString, QStringList> &folders, const QString &config, const QString &program);

Q_SIGNALS:
    void changed();
    void senseChanged();
    void cleaned(bool ok);

private:
    QHash<QString, QStringList> folders() const;
    QString senseProgram() const;

    QHash<QString, QStringList> m_testFolders;
    QString m_config;
    QString m_program;
    qint64 m_total = 0;
    qint64 m_used = 0;
    QHash<QString, qint64> m_sizes;
    QFutureWatcher<QHash<QString, qint64>> *m_watcher = nullptr;
    QProcess *m_process = nullptr;
    QString m_error;
};

} // namespace OrielOSSettingsPages
