// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "drives.h"
#include "traylogic.h"

#include <KLocalizedString>
#include <Solid/Device>
#include <Solid/DeviceNotifier>
#include <Solid/OpticalDrive>
#include <Solid/StorageAccess>
#include <Solid/StorageDrive>
#include <Solid/StorageVolume>

#include <QDBusConnection>
#include <QDBusMessage>

#include <memory>

namespace {

const QString udisksDrives = QStringLiteral("/org/freedesktop/UDisks2/drives/");

// The volumes with a file system on a drive: its own, or its partitions'.
QList<Solid::Device> volumesOf(const QString &driveUdi)
{
    QList<Solid::Device> volumes;
    const QList<Solid::Device> all = Solid::Device::listFromType(Solid::DeviceInterface::StorageAccess);
    for (const Solid::Device &volume : all) {
        for (Solid::Device ancestor = volume.parent(); ancestor.isValid(); ancestor = ancestor.parent()) {
            if (ancestor.udi() == driveUdi) {
                volumes.append(volume);
                break;
            }
        }
    }
    return volumes;
}

QString nameOf(const Solid::Device &drive, const QList<Solid::Device> &volumes)
{
    QString label;
    for (const Solid::Device &volume : volumes) {
        if (const auto *storage = volume.as<Solid::StorageVolume>(); storage && !storage->label().isEmpty()) {
            label = storage->label();
            break;
        }
    }
    return Tray::driveName(label, drive.vendor(), drive.product(), drive.description());
}

void notify(const QString &summary, const QString &body)
{
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
    message.setArguments(
        { i18nc("@title The notification's app name", "Drives"), 0u, QStringLiteral("media-eject"), summary, body, QStringList(), QVariantMap(), -1 });
    QDBusConnection::sessionBus().send(message);
}

} // namespace

Drives::Drives(QObject *parent)
    : QObject(parent)
{
    connect(Solid::DeviceNotifier::instance(), &Solid::DeviceNotifier::deviceAdded, this, &Drives::refresh);
    connect(Solid::DeviceNotifier::instance(), &Solid::DeviceNotifier::deviceRemoved, this, &Drives::refresh);
    refresh();
}

void Drives::refresh()
{
    QVariantList list;
    const QList<Solid::Device> drives = Solid::Device::listFromType(Solid::DeviceInterface::StorageDrive);
    for (const Solid::Device &drive : drives) {
        const auto *storage = drive.as<Solid::StorageDrive>();
        if (!storage || !(storage->isHotpluggable() || storage->isRemovable())) {
            continue;
        }
        // A card reader with no card in it has no volumes, so nothing to eject.
        const QList<Solid::Device> volumes = volumesOf(drive.udi());
        if (volumes.isEmpty()) {
            continue;
        }
        list.append(QVariantMap { { QStringLiteral("udi"), drive.udi() }, { QStringLiteral("name"), nameOf(drive, volumes) } });
    }
    if (list != m_list) {
        m_list = list;
        Q_EMIT changed();
    }
}

void Drives::eject(const QString &udi)
{
    const Solid::Device drive(udi);
    const QList<Solid::Device> volumes = volumesOf(udi);
    const QString name = nameOf(drive, volumes);

    // Unmount every mounted volume, then finish once the last one is done.
    auto pending = std::make_shared<int>(0);
    auto inUse = std::make_shared<bool>(false);
    for (Solid::Device volume : volumes) {
        auto *access = volume.as<Solid::StorageAccess>();
        if (!access || !access->isAccessible()) {
            continue;
        }
        ++*pending;
        // The lambda keeps its copy of the device, and so the StorageAccess, alive until it runs.
        connect(
            access, &Solid::StorageAccess::teardownDone, this,
            [this, volume, udi, name, pending, inUse](Solid::ErrorType error) {
                Q_UNUSED(volume)
                if (error != Solid::NoError) {
                    *inUse = true;
                }
                if (--*pending == 0) {
                    finish(udi, name, *inUse);
                }
            },
            Qt::SingleShotConnection);
        access->teardown();
    }
    if (*pending == 0) {
        finish(udi, name, false);
    }
}

void Drives::finish(const QString &udi, const QString &name, bool inUse)
{
    if (inUse) {
        notify(i18nc("@title %1 is a drive's name", "%1 is in use", name), i18nc("@info", "Close the files and apps that use it, then eject it again."));
        return;
    }
    Solid::Device drive(udi);
    if (auto *optical = drive.as<Solid::OpticalDrive>()) {
        optical->eject();
    } else if (udi.startsWith(udisksDrives)) {
        // Like unplugging it: the drive turns off and leaves the list.
        QDBusMessage message = QDBusMessage::createMethodCall(
            QStringLiteral("org.freedesktop.UDisks2"), udi, QStringLiteral("org.freedesktop.UDisks2.Drive"), QStringLiteral("PowerOff"));
        message.setArguments({ QVariantMap() });
        QDBusConnection::systemBus().send(message);
    }
    notify(i18nc("@title %1 is a drive's name", "%1 can be removed", name), i18nc("@info", "You can unplug it now."));
}
