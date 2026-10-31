// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "storageusage.h"

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QSet>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QUrl>
#include <QtConcurrent>

#include <algorithm>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace OrielOSSettingsPages {

namespace {

const QString senseGroup = QStringLiteral("StorageSense");

struct Inode {
    dev_t device;
    ino_t inode;
    bool operator==(const Inode &other) const { return device == other.device && inode == other.inode; }
};

size_t qHash(const Inode &key, size_t seed = 0)
{
    return qHashMulti(seed, quint64(key.device), quint64(key.inode));
}

// Adds up the blocks under the open directory dir, staying on its file system. A file with more
// than one link counts once, the first time it's met.
qint64 directoryUsage(int dir, dev_t device, QSet<Inode> &seen)
{
    DIR *stream = fdopendir(dir);
    if (!stream) {
        close(dir);
        return 0;
    }
    qint64 total = 0;
    while (const dirent *entry = readdir(stream)) {
        const char *name = entry->d_name;
        if (qstrcmp(name, ".") == 0 || qstrcmp(name, "..") == 0) {
            continue;
        }
        struct stat info;
        if (fstatat(dirfd(stream), name, &info, AT_SYMLINK_NOFOLLOW) != 0 || info.st_dev != device) {
            continue;
        }
        if (info.st_nlink > 1 && !S_ISDIR(info.st_mode)) {
            const Inode key { info.st_dev, info.st_ino };
            if (seen.contains(key)) {
                continue;
            }
            seen.insert(key);
        }
        total += qint64(info.st_blocks) * 512;
        if (S_ISDIR(info.st_mode)) {
            const int child = openat(dirfd(stream), name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
            if (child >= 0) {
                total += directoryUsage(child, device, seen);
            }
        }
    }
    closedir(stream);
    return total;
}

QHash<QString, qint64> measure(const QHash<QString, QStringList> &folders)
{
    QHash<QString, qint64> sizes;
    for (auto it = folders.cbegin(); it != folders.cend(); ++it) {
        qint64 total = 0;
        for (const QString &path : it.value()) {
            total += StorageUsage::diskUsage(path);
        }
        sizes.insert(it.key(), total);
    }
    return sizes;
}

struct Part {
    QString id;
    QString name;
    QString icon;
};

QList<Part> parts()
{
    return {
        { QStringLiteral("apps"), i18nc("@item Storage used by", "Installed apps"), QStringLiteral("applications-all") },
        { QStringLiteral("temporary"), i18nc("@item Storage used by", "Temporary files"), QStringLiteral("edit-clear-history") },
        { QStringLiteral("bin"), i18nc("@item Storage used by", "Bin"), QStringLiteral("user-trash") },
        { QStringLiteral("documents"), i18nc("@item Storage used by", "Documents"), QStringLiteral("folder-documents") },
        { QStringLiteral("pictures"), i18nc("@item Storage used by", "Pictures"), QStringLiteral("folder-pictures") },
        { QStringLiteral("videos"), i18nc("@item Storage used by", "Videos"), QStringLiteral("folder-videos") },
        { QStringLiteral("music"), i18nc("@item Storage used by", "Music"), QStringLiteral("folder-music") },
        { QStringLiteral("downloads"), i18nc("@item Storage used by", "Downloads"), QStringLiteral("folder-download") },
        { QStringLiteral("desktop"), i18nc("@item Storage used by", "Desktop"), QStringLiteral("user-desktop") },
    };
}

} // namespace

StorageUsage::StorageUsage(QObject *parent)
    : QObject(parent)
{
    refresh();
}

StorageUsage::~StorageUsage()
{
    if (m_watcher) {
        m_watcher->waitForFinished();
    }
}

qint64 StorageUsage::diskUsage(const QString &path)
{
    const QByteArray encoded = QFile::encodeName(path);
    struct stat info;
    if (lstat(encoded.constData(), &info) != 0) {
        return 0;
    }
    if (!S_ISDIR(info.st_mode)) {
        return qint64(info.st_blocks) * 512;
    }
    const int dir = ::open(encoded.constData(), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (dir < 0) {
        return 0;
    }
    QSet<Inode> seen;
    return qint64(info.st_blocks) * 512 + directoryUsage(dir, info.st_dev, seen);
}

QHash<QString, QStringList> StorageUsage::folders() const
{
    if (!m_testFolders.isEmpty()) {
        return m_testFolders;
    }
    const QString home = QDir::homePath();
    const QString data = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
    QHash<QString, QStringList> folders {
        { QStringLiteral("apps"), { QStringLiteral("/var/lib/flatpak"), data + QStringLiteral("/flatpak") } },
        { QStringLiteral("temporary"), { QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) } },
        { QStringLiteral("bin"), { data + QStringLiteral("/Trash") } },
    };
    // A personal folder that isn't set is the home folder itself, which isn't counted.
    const QList<std::pair<QString, QStandardPaths::StandardLocation>> personal = {
        { QStringLiteral("documents"), QStandardPaths::DocumentsLocation },
        { QStringLiteral("pictures"), QStandardPaths::PicturesLocation },
        { QStringLiteral("videos"), QStandardPaths::MoviesLocation },
        { QStringLiteral("music"), QStandardPaths::MusicLocation },
        { QStringLiteral("downloads"), QStandardPaths::DownloadLocation },
        { QStringLiteral("desktop"), QStandardPaths::DesktopLocation },
    };
    for (const auto &[id, location] : personal) {
        const QString path = QStandardPaths::writableLocation(location);
        if (!path.isEmpty() && QDir(path) != QDir(home)) {
            folders.insert(id, { path });
        }
    }
    return folders;
}

void StorageUsage::refresh()
{
    if (m_watcher) {
        return;
    }
    const QHash<QString, QStringList> toMeasure = folders();
    const QStorageInfo disk(m_testFolders.isEmpty() ? QDir::homePath() : m_testFolders.cbegin().value().value(0));
    m_total = disk.bytesTotal();
    m_used = disk.bytesTotal() - disk.bytesFree();

    m_watcher = new QFutureWatcher<QHash<QString, qint64>>(this);
    connect(m_watcher, &QFutureWatcherBase::finished, this, [this]() {
        m_sizes = m_watcher->result();
        m_watcher->deleteLater();
        m_watcher = nullptr;
        Q_EMIT changed();
    });
    m_watcher->setFuture(QtConcurrent::run(measure, toMeasure));
    Q_EMIT changed();
}

QVariantList StorageUsage::categories() const
{
    QList<std::pair<Part, qint64>> measured;
    qint64 counted = 0;
    for (const Part &part : parts()) {
        if (m_sizes.contains(part.id)) {
            measured.append({ part, m_sizes.value(part.id) });
            counted += m_sizes.value(part.id);
        }
    }
    std::stable_sort(measured.begin(), measured.end(), [](const auto &a, const auto &b) {
        return a.second > b.second;
    });
    QVariantList list;
    for (const auto &[part, bytes] : measured) {
        list.append(QVariantMap { { QStringLiteral("id"), part.id }, { QStringLiteral("name"), part.name }, { QStringLiteral("icon"), part.icon },
            { QStringLiteral("bytes"), bytes } });
    }
    if (!m_sizes.isEmpty()) {
        // The system's own files, other people's folders and everything not listed above.
        list.append(QVariantMap { { QStringLiteral("id"), QStringLiteral("other") }, { QStringLiteral("name"), i18nc("@item Storage used by", "System and other") },
            { QStringLiteral("icon"), QStringLiteral("drive-harddisk") }, { QStringLiteral("bytes"), std::max<qint64>(0, m_used - counted) } });
    }
    return list;
}

bool StorageUsage::isSenseEnabled() const
{
    const KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-storagesenserc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    return config.group(senseGroup).readEntry("Enabled", false);
}

void StorageUsage::setSenseEnabled(bool enabled)
{
    if (enabled == isSenseEnabled()) {
        return;
    }
    KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-storagesenserc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    config.group(senseGroup).writeEntry("Enabled", enabled);
    config.sync();
    Q_EMIT senseChanged();
}

int StorageUsage::binDays() const
{
    const KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-storagesenserc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    return config.group(senseGroup).readEntry("BinDays", 30);
}

void StorageUsage::setBinDays(int days)
{
    if (days == binDays() || days < 0) {
        return;
    }
    KConfig config(m_config.isEmpty() ? QStringLiteral("orielos-storagesenserc") : m_config, m_config.isEmpty() ? KConfig::FullConfig : KConfig::SimpleConfig);
    config.group(senseGroup).writeEntry("BinDays", days);
    config.sync();
    Q_EMIT senseChanged();
}

QString StorageUsage::senseProgram() const
{
    if (!m_program.isEmpty()) {
        return m_program;
    }
    const QString installed = QStandardPaths::findExecutable(QStringLiteral("storage-sense"), { QStringLiteral("/usr/libexec/orielos") });
    // A sideloaded Settings finds its copy beside itself.
    return installed.isEmpty() ? QStandardPaths::findExecutable(QStringLiteral("orielos-storage-sense"), { QCoreApplication::applicationDirPath() }) : installed;
}

void StorageUsage::cleanUp(bool everything)
{
    if (m_process) {
        return;
    }
    m_error.clear();
    const QString program = senseProgram();
    if (program.isEmpty()) {
        m_error = i18nc("@info", "Storage Sense isn't installed.");
        Q_EMIT changed();
        Q_EMIT cleaned(false);
        return;
    }
    m_process = new QProcess(this);
    QStringList arguments { QStringLiteral("--now") };
    if (everything) {
        arguments.append(QStringLiteral("--all"));
    }
    if (!m_config.isEmpty()) {
        arguments << QStringLiteral("--config") << m_config;
    }
    connect(m_process, &QProcess::finished, this, [this](int exitCode, QProcess::ExitStatus status) {
        const bool ok = status == QProcess::NormalExit && exitCode == 0;
        if (!ok) {
            m_error = i18nc("@info", "Storage Sense couldn't remove everything. Some files may be in use.");
        }
        m_process->deleteLater();
        m_process = nullptr;
        Q_EMIT changed();
        Q_EMIT cleaned(ok);
        refresh();
    });
    connect(m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_error = i18nc("@info", "Storage Sense couldn't start.");
            m_process->deleteLater();
            m_process = nullptr;
            Q_EMIT changed();
            Q_EMIT cleaned(false);
        }
    });
    m_process->start(program, arguments);
    Q_EMIT changed();
}

void StorageUsage::open(const QString &id)
{
    if (id == QLatin1String("apps")) {
        QDesktopServices::openUrl(QUrl(QStringLiteral("orielos-settings:apps")));
        return;
    }
    if (id == QLatin1String("bin")) {
        QDesktopServices::openUrl(QUrl(QStringLiteral("trash:/")));
        return;
    }
    const QStringList paths = folders().value(id);
    if (!paths.isEmpty()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(paths.constFirst()));
    }
}

void StorageUsage::setForTesting(const QHash<QString, QStringList> &folders, const QString &config, const QString &program)
{
    m_testFolders = folders;
    m_config = config;
    m_program = program;
    if (m_watcher) {
        m_watcher->waitForFinished();
    }
}

} // namespace OrielOSSettingsPages
