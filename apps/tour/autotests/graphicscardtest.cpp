// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "graphicscard.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSTour;

namespace {

// A few lines of hwdata's pci.ids, with a subsystem line and the class list after the vendors.
const char pciIds[] = "# pci.ids\n"
                      "1002  Advanced Micro Devices, Inc. [AMD/ATI]\n"
                      "\t744c  Navi 31 [Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M]\n"
                      "10de  NVIDIA Corporation\n"
                      "\t2786  AD104 [GeForce RTX 4070]\n"
                      "\t\t1043 8899  Dual GeForce RTX 4070\n"
                      "\t2860  AD106M [GeForce RTX 4070 Max-Q / Mobile]\n"
                      "8086  Intel Corporation\n"
                      "\ta7a0  Raptor Lake-P [Iris Xe Graphics]\n"
                      "C 03  Display controller\n"
                      "\t00  VGA compatible controller\n";

void write(const QString &path, const QByteArray &content)
{
    QDir().mkpath(QFileInfo(path).path());
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly));
    file.write(content);
}

} // namespace

class GraphicsCardTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QString m_sysfs;
    QString m_hwdata;
    QString m_keyState;

    // A PCI device of this class, IDs and driver (none if empty), and boot_vga if given.
    void addDevice(const QString &address, const QByteArray &cls, const QByteArray &vendor, const QByteArray &device, const QString &driver,
        const QByteArray &bootVga = { })
    {
        const QString dir = m_sysfs + QStringLiteral("/bus/pci/devices/") + address;
        write(dir + QStringLiteral("/class"), cls + '\n');
        write(dir + QStringLiteral("/vendor"), vendor + '\n');
        write(dir + QStringLiteral("/device"), device + '\n');
        if (!bootVga.isEmpty()) {
            write(dir + QStringLiteral("/boot_vga"), bootVga + '\n');
        }
        if (!driver.isEmpty()) {
            const QString target = m_sysfs + QStringLiteral("/bus/pci/drivers/") + driver;
            QDir().mkpath(target);
            QVERIFY(QFile::link(target, dir + QStringLiteral("/driver")));
        }
    }

private Q_SLOTS:
    void init()
    {
        const QString root = m_dir.filePath(QString::fromLatin1(QTest::currentTestFunction()));
        m_sysfs = root + QStringLiteral("/sys");
        m_hwdata = root + QStringLiteral("/hwdata");
        m_keyState = root + QStringLiteral("/secure-boot-state");
        QDir().mkpath(m_sysfs + QStringLiteral("/bus/pci/devices"));
        write(m_hwdata + QStringLiteral("/pci.ids"), pciIds);
    }

    void nvidiaOnItsOwnDriver()
    {
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x2786", QStringLiteral("nvidia"), "1");
        write(m_sysfs + QStringLiteral("/module/nvidia/version"), "580.95.05\n");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QVERIFY(card.isAvailable());
        QCOMPARE(card.vendor(), QStringLiteral("nvidia"));
        QCOMPARE(card.name(), QStringLiteral("NVIDIA GeForce RTX 4070"));
        QCOMPARE(card.driver(), QStringLiteral("nvidia"));
        QCOMPARE(card.driverVersion(), QStringLiteral("580.95.05"));
        QCOMPARE(card.state(), GraphicsCard::State::Working);
    }

    void theGamingCardComesFirst()
    {
        // A laptop: Intel drives the screen, NVIDIA runs games. NVIDIA's card is named.
        addDevice(QStringLiteral("0000:00:02.0"), "0x030000", "0x8086", "0xa7a0", QStringLiteral("i915"), "1");
        addDevice(QStringLiteral("0000:00:1f.3"), "0x040300", "0x8086", "0x51c8", QStringLiteral("snd_hda_intel"));
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x2860", QStringLiteral("nvidia"), "0");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QCOMPARE(card.name(), QStringLiteral("NVIDIA GeForce RTX 4070 Max-Q / Mobile"));
        QCOMPARE(card.vendor(), QStringLiteral("nvidia"));
        QCOMPARE(card.state(), GraphicsCard::State::Working);
    }

    void intelAlone()
    {
        addDevice(QStringLiteral("0000:00:02.0"), "0x030000", "0x8086", "0xa7a0", QStringLiteral("xe"), "1");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QCOMPARE(card.name(), QStringLiteral("Intel Iris Xe Graphics"));
        QCOMPARE(card.driverVersion(), QString());
        QCOMPARE(card.state(), GraphicsCard::State::Working);
    }

    void theScreensCardBetweenTwoOfAKind()
    {
        addDevice(QStringLiteral("0000:03:00.0"), "0x030000", "0x10de", "0x2860", QStringLiteral("nvidia"));
        addDevice(QStringLiteral("0000:04:00.0"), "0x030000", "0x10de", "0x2786", QStringLiteral("nvidia"), "1");
        QCOMPARE(GraphicsCard(m_sysfs, m_hwdata, m_keyState).name(), QStringLiteral("NVIDIA GeForce RTX 4070"));
    }

    void amdBeforeIntel()
    {
        addDevice(QStringLiteral("0000:00:02.0"), "0x030000", "0x8086", "0xa7a0", QStringLiteral("i915"), "1");
        addDevice(QStringLiteral("0000:03:00.0"), "0x030000", "0x1002", "0x744c", QStringLiteral("amdgpu"));
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QCOMPARE(card.vendor(), QStringLiteral("amd"));
        // The last brackets hold the model; AMD's long name is shortened.
        QCOMPARE(card.name(), QStringLiteral("AMD Radeon RX 7900 XT/7900 XTX/7900 GRE/7900M"));
        QCOMPARE(card.driver(), QStringLiteral("amdgpu"));
        QCOMPARE(card.state(), GraphicsCard::State::Working);
    }

    void unknownDevice()
    {
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0xffff", QStringLiteral("nvidia"), "1");
        QCOMPARE(GraphicsCard(m_sysfs, m_hwdata, m_keyState).name(), QStringLiteral("NVIDIA graphics card"));
    }

    void unknownVendor()
    {
        addDevice(QStringLiteral("0000:00:01.0"), "0x030000", "0x1234", "0x1111", QStringLiteral("bochs-drm"), "1");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QCOMPARE(card.vendor(), QStringLiteral("other"));
        QCOMPARE(card.name(), QStringLiteral("Graphics card"));
        QCOMPARE(card.state(), GraphicsCard::State::Working);
    }

    void nouveauIsABasicDriver()
    {
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x2786", QStringLiteral("nouveau"), "1");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QCOMPARE(card.state(), GraphicsCard::State::BasicDriver);
        QCOMPARE(card.driverVersion(), QString());
    }

    void noDriver()
    {
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x2786", QString(), "1");
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QVERIFY(card.isAvailable());
        QCOMPARE(card.driver(), QString());
        QCOMPARE(card.state(), GraphicsCard::State::NoDriver);
    }

    void driverKeyWaiting()
    {
        addDevice(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x2786", QString(), "1");
        QVERIFY(!GraphicsCard(m_sysfs, m_hwdata, m_keyState).keyPending());
        write(m_keyState, "key=pending\nrequested=2026-11-03T08:00:00Z\nca2023=present\n");
        QVERIFY(GraphicsCard(m_sysfs, m_hwdata, m_keyState).keyPending());
        write(m_keyState, "key=enrolled\nca2023=present\n");
        QVERIFY(!GraphicsCard(m_sysfs, m_hwdata, m_keyState).keyPending());
    }

    void noDisplayController()
    {
        addDevice(QStringLiteral("0000:00:1f.3"), "0x040300", "0x8086", "0x51c8", QStringLiteral("snd_hda_intel"));
        const GraphicsCard card(m_sysfs, m_hwdata, m_keyState);
        QVERIFY(!card.isAvailable());
        QCOMPARE(card.name(), QStringLiteral("Graphics card"));
    }
};

QTEST_GUILESS_MAIN(GraphicsCardTest)

#include "graphicscardtest.moc"
