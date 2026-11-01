// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "traylogic.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>

#include <algorithm>

namespace Tray {

Split split(const QStringList &present, const QStringList &passive, const QStringList &shown)
{
    Split result;
    for (const QString &id : shown) {
        if (present.contains(id) && !passive.contains(id) && !result.taskbar.contains(id)) {
            result.taskbar.append(id);
        }
    }
    for (const QString &id : present) {
        if (!result.taskbar.contains(id) && !result.pane.contains(id)) {
            result.pane.append(id);
        }
    }
    return result;
}

QStringList showAt(const QStringList &shown, const QString &id, int index)
{
    QStringList result = hide(shown, id);
    result.insert(std::clamp(index, 0, int(result.size())), id);
    return result;
}

QStringList hide(const QStringList &shown, const QString &id)
{
    QStringList result = shown;
    result.removeAll(id);
    return result;
}

QString driveName(const QString &label, const QString &vendor, const QString &product, const QString &description)
{
    if (!label.trimmed().isEmpty()) {
        return label.trimmed();
    }
    const QString model = QStringList { vendor.trimmed(), product.trimmed() }.join(QLatin1Char(' ')).trimmed();
    return model.isEmpty() ? description.trimmed() : model;
}

namespace {

bool inside(const QString &path, const QStringList &folders)
{
    return std::any_of(folders.cbegin(), folders.cend(),
        [&path](const QString &folder) { return !folder.isEmpty() && (path == folder || path.startsWith(folder + QLatin1Char('/'))); });
}

} // namespace

QStringList processesUsing(const QStringList &folders, const QString &proc)
{
    QStringList names;
    const QStringList pids = QDir(proc).entryList({ QStringLiteral("[0-9]*") }, QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &pid : pids) {
        const QString base = proc + QLatin1Char('/') + pid;
        bool uses = inside(QFileInfo(base + QStringLiteral("/cwd")).symLinkTarget(), folders);
        if (!uses) {
            const QFileInfoList fds = QDir(base + QStringLiteral("/fd")).entryInfoList(QDir::Files | QDir::System | QDir::NoDotAndDotDot);
            uses = std::any_of(fds.cbegin(), fds.cend(), [&folders](const QFileInfo &fd) { return inside(fd.symLinkTarget(), folders); });
        }
        if (!uses) {
            continue;
        }
        QFile comm(base + QStringLiteral("/comm"));
        if (comm.open(QIODevice::ReadOnly)) {
            const QString name = QString::fromUtf8(comm.readAll()).trimmed();
            if (!name.isEmpty() && !names.contains(name)) {
                names.append(name);
            }
        }
    }
    return names;
}

} // namespace Tray
