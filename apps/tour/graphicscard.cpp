// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicscard.h"

#include <KLocalizedString>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QRegularExpression>
#include <QTextStream>

namespace OrielOSTour {

namespace {

QString readTrimmed(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromUtf8(file.readAll()).trimmed();
}

// "0x10de" becomes "10de".
QString hexId(const QString &path)
{
    QString id = readTrimmed(path).toLower();
    if (id.startsWith(QLatin1String("0x"))) {
        id = id.mid(2);
    }
    return id;
}

struct Names
{
    QString vendor;
    QString device;
};

// The vendor's and device's names in pci.ids: vendor lines at the start of a line, their devices
// after one tab, subsystems after two, and the class list from the first "C " line on.
Names lookUp(const QString &idsPath, const QString &vendor, const QString &device)
{
    Names names;
    QFile file(idsPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return names;
    }
    QTextStream in(&file);
    bool inVendor = false;
    QString line;
    while (in.readLineInto(&line)) {
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1String("C "))) {
            break;
        }
        if (!line.startsWith(QLatin1Char('\t'))) {
            if (inVendor) {
                break;
            }
            if (line.startsWith(vendor + QLatin1String("  "))) {
                inVendor = true;
                names.vendor = line.mid(vendor.size() + 2).trimmed();
            }
            continue;
        }
        if (inVendor && !line.startsWith(QLatin1String("\t\t")) && line.mid(1).startsWith(device + QLatin1String("  "))) {
            names.device = line.mid(device.size() + 3).trimmed();
            break;
        }
    }
    return names;
}

QString shortVendor(const QString &name)
{
    if (name == QLatin1String("NVIDIA Corporation")) {
        return QStringLiteral("NVIDIA");
    }
    if (name.startsWith(QLatin1String("Advanced Micro Devices"))) {
        return QStringLiteral("AMD");
    }
    if (name == QLatin1String("Intel Corporation")) {
        return QStringLiteral("Intel");
    }
    return name;
}

// The marketing name in the last brackets, when there is one: "AD104 [GeForce RTX 4070]".
QString model(const QString &device)
{
    static const QRegularExpression bracketed(QStringLiteral("\\[([^\\]]+)\\][^\\[]*$"));
    const QRegularExpressionMatch match = bracketed.match(device);
    return match.hasMatch() ? match.captured(1).trimmed() : device;
}

} // namespace

GraphicsCard::GraphicsCard(QObject *parent)
    : GraphicsCard(QStringLiteral("/sys"), QStringLiteral("/usr/share/hwdata"), QStringLiteral("/var/lib/orielos/secure-boot/state"), parent)
{
}

GraphicsCard::GraphicsCard(const QString &sysfs, const QString &hwdata, const QString &keyState, QObject *parent)
    : QObject(parent)
{
    // key=pending, one line of orielos-secure-boot-key's key=value state.
    QFile state(keyState);
    if (state.open(QIODevice::ReadOnly | QIODevice::Text)) {
        m_keyPending = QString::fromUtf8(state.readAll()).split(QLatin1Char('\n')).contains(QLatin1String("key=pending"));
    }

    // The display controllers (PCI class 0x03). The card games run on comes first: NVIDIA's, then
    // AMD's, then anyone else's, then Intel's, which is almost always the one built into the
    // processor next to a faster card. Between two of a kind, the one the firmware started the
    // screen on.
    const QDir devices(sysfs + QStringLiteral("/bus/pci/devices"));
    QString card;
    int best = -1;
    const QStringList entries = devices.entryList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::System, QDir::Name);
    for (const QString &entry : entries) {
        const QString path = devices.filePath(entry);
        if (!readTrimmed(path + QStringLiteral("/class")).startsWith(QLatin1String("0x03"))) {
            continue;
        }
        const QString vendor = hexId(path + QStringLiteral("/vendor"));
        int rank = vendor == QLatin1String("10de") ? 6 : vendor == QLatin1String("1002") ? 4 : vendor == QLatin1String("8086") ? 0 : 2;
        if (readTrimmed(path + QStringLiteral("/boot_vga")) == QLatin1String("1")) {
            ++rank;
        }
        if (rank > best) {
            best = rank;
            card = path;
        }
    }
    if (card.isEmpty()) {
        m_name = i18nc("@info", "Graphics card");
        return;
    }
    m_available = true;

    const QString vendorId = hexId(card + QStringLiteral("/vendor"));
    const QString deviceId = hexId(card + QStringLiteral("/device"));
    if (vendorId == QLatin1String("10de")) {
        m_vendor = QStringLiteral("nvidia");
    } else if (vendorId == QLatin1String("1002")) {
        m_vendor = QStringLiteral("amd");
    } else if (vendorId == QLatin1String("8086")) {
        m_vendor = QStringLiteral("intel");
    } else {
        m_vendor = QStringLiteral("other");
    }

    const Names names = lookUp(hwdata + QStringLiteral("/pci.ids"), vendorId, deviceId);
    const QString maker = shortVendor(names.vendor);
    if (maker.isEmpty()) {
        m_name = i18nc("@info", "Graphics card");
    } else if (names.device.isEmpty()) {
        m_name = i18nc("@info %1 is a maker such as NVIDIA", "%1 graphics card", maker);
    } else {
        m_name = maker + QLatin1Char(' ') + model(names.device);
    }

    const QFileInfo driverLink(card + QStringLiteral("/driver"));
    if (driverLink.isSymLink()) {
        m_driver = QFileInfo(driverLink.symLinkTarget()).fileName();
    }
    if (m_driver == QLatin1String("nvidia")) {
        m_driverVersion = readTrimmed(sysfs + QStringLiteral("/module/nvidia/version"));
    }

    if (m_driver.isEmpty()) {
        m_state = State::NoDriver;
    } else if (m_vendor == QLatin1String("nvidia")) {
        m_state = m_driver == QLatin1String("nvidia") ? State::Working : State::BasicDriver;
    } else if (m_vendor == QLatin1String("amd")) {
        m_state = m_driver == QLatin1String("amdgpu") ? State::Working : State::BasicDriver;
    } else if (m_vendor == QLatin1String("intel")) {
        m_state = m_driver == QLatin1String("i915") || m_driver == QLatin1String("xe") ? State::Working : State::BasicDriver;
    } else {
        m_state = State::Working;
    }
}

} // namespace OrielOSTour
