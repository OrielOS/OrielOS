// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "aboutinfo.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QLocale>
#include <QSignalSpy>
#include <QSysInfo>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

void writeFile(const QString &path, const QByteArray &contents)
{
    QVERIFY(QDir().mkpath(QFileInfo(path).absolutePath()));
    QFile file(path);
    QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
    file.write(contents);
}

QByteArray cpuinfo(const QByteArray &model, int threads)
{
    QByteArray out;
    for (int i = 0; i < threads; ++i) {
        out += "processor\t: " + QByteArray::number(i) + "\nvendor_id\t: AuthenticAMD\nmodel name\t: " + model + "\nflags\t\t: fpu vme\n\n";
    }
    return out;
}

constexpr auto pciIds = R"(#	List of PCI ID's
#
1002  Advanced Micro Devices, Inc. [AMD/ATI]
	73bf  Navi 21 [Radeon RX 6800/6800 XT / 6900 XT]
10de  NVIDIA Corporation
	1c82  GP107 [GeForce GTX 1050 Ti]
	28e1  AD107M [GeForce RTX 4050 Max-Q / Mobile]
		17aa 3cd8  AD107M [GeForce RTX 4050 Laptop GPU]
8086  Intel Corporation
	a780  Raptor Lake-S GT1 [UHD Graphics 770]
C 03  Display controller
	00  VGA compatible controller
)";

// The values of the rows with this label.
QStringList values(const QVariantList &rows, const QString &label)
{
    QStringList out;
    for (const QVariant &item : rows) {
        const QVariantMap row = item.toMap();
        if (row.value(QStringLiteral("label")).toString() == label) {
            out.append(row.value(QStringLiteral("value")).toString());
        }
    }
    return out;
}

} // namespace

class AboutInfoTest : public QObject
{
    Q_OBJECT

private:
    QTemporaryDir m_dir;
    QVariantMap m_names;
    // The arguments of each run of rename-pc, and how to answer the last.
    QList<QStringList> m_runs;
    std::function<void(int, const QString &)> m_done;
    QString m_copied;

    QString file(const QString &relative) const { return m_dir.filePath(relative); }

    // Answers the last run with rename-pc's exit code and last line.
    void answer(int exitCode, const QString &detail = { })
    {
        auto done = std::move(m_done);
        m_done = nullptr;
        QVERIFY(done);
        done(exitCode, detail);
    }

    void addCard(const QString &address, const char *pciClass, const char *vendor, const char *device)
    {
        const QString card = QStringLiteral("sys/bus/pci/devices/") + address;
        writeFile(file(card + QStringLiteral("/class")), QByteArray(pciClass) + '\n');
        writeFile(file(card + QStringLiteral("/vendor")), QByteArray(vendor) + '\n');
        writeFile(file(card + QStringLiteral("/device")), QByteArray(device) + '\n');
    }

    void setDmi(const char *vendor, const char *product, const char *version = "", const char *boardVendor = "", const char *boardName = "")
    {
        writeFile(file(QStringLiteral("sys/class/dmi/id/sys_vendor")), QByteArray(vendor) + '\n');
        writeFile(file(QStringLiteral("sys/class/dmi/id/product_name")), QByteArray(product) + '\n');
        writeFile(file(QStringLiteral("sys/class/dmi/id/product_version")), QByteArray(version) + '\n');
        writeFile(file(QStringLiteral("sys/class/dmi/id/board_vendor")), QByteArray(boardVendor) + '\n');
        writeFile(file(QStringLiteral("sys/class/dmi/id/board_name")), QByteArray(boardName) + '\n');
    }

    AboutInfo::Environment environment()
    {
        return AboutInfo::Environment {
            file(QStringLiteral("proc")),
            file(QStringLiteral("sys")),
            file(QStringLiteral("os-release")),
            file(QStringLiteral("pci.ids")),
            [this](std::function<void(const QVariantMap &)> done) { done(m_names); },
            [this](const QStringList &arguments, std::function<void(int, const QString &)> done) {
                m_runs.append(arguments);
                m_done = std::move(done);
            },
            [this](const QString &text) { m_copied = text; },
        };
    }

private Q_SLOTS:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        QLocale::setDefault(QLocale(QLocale::English, QLocale::UnitedKingdom));
        qputenv("KDE_SESSION_VERSION", "6");
    }

    // A laptop with an AMD processor, an NVIDIA card and the processor's own graphics.
    void init()
    {
        QDir(m_dir.path()).removeRecursively();
        QVERIFY(QDir().mkpath(m_dir.path()));
        writeFile(file(QStringLiteral("proc/cpuinfo")), cpuinfo("AMD Ryzen 7 7840HS w/ Radeon 780M Graphics", 16));
        writeFile(file(QStringLiteral("proc/meminfo")), "MemTotal:       16255620 kB\nMemFree:         8000000 kB\n");
        writeFile(file(QStringLiteral("proc/sys/kernel/osrelease")), "6.17.5-200.fc43.x86_64\n");
        writeFile(file(QStringLiteral("os-release")), "NAME=\"OrielOS\"\nVERSION=\"0.2.3\"\nID=fedora\n");
        writeFile(file(QStringLiteral("pci.ids")), pciIds);
        addCard(QStringLiteral("0000:01:00.0"), "0x030000", "0x10de", "0x28e1");
        // Audio on the same card isn't graphics.
        addCard(QStringLiteral("0000:01:00.1"), "0x040300", "0x10de", "0x22be");
        setDmi("LENOVO", "82XV", "Legion Slim 5 16APH8");
        m_names = { { QStringLiteral("PrettyHostname"), QString() }, { QStringLiteral("StaticHostname"), QStringLiteral("orielos") },
            { QStringLiteral("Hostname"), QStringLiteral("orielos") } };
        m_runs.clear();
        m_done = nullptr;
        m_copied.clear();
    }

    void readsTheProcessorAndItsThreads()
    {
        AboutInfo info(environment(), nullptr);
        QCOMPARE(
            values(info.deviceSpecs(), QStringLiteral("Processor")), QStringList { QStringLiteral("AMD Ryzen 7 7840HS w/ Radeon 780M Graphics (16 threads)") });

        writeFile(file(QStringLiteral("proc/cpuinfo")), cpuinfo("Intel(R) Core(TM)  i5-8250U CPU @ 1.60GHz", 1));
        info.reload();
        QCOMPARE(values(info.deviceSpecs(), QStringLiteral("Processor")), QStringList { QStringLiteral("Intel Core i5-8250U CPU @ 1.60GHz (1 thread)") });
    }

    void showsUsableMemoryInGigabytes()
    {
        AboutInfo info(environment(), nullptr);
        QCOMPARE(values(info.deviceSpecs(), QStringLiteral("Installed memory")), QStringList { QStringLiteral("15.5 GB usable") });
    }

    void namesEveryGraphicsCard()
    {
        // Intel's built-in graphics comes first, by its address; an unknown device of a known maker,
        // and a maker pci.ids doesn't know, show their ids.
        addCard(QStringLiteral("0000:00:02.0"), "0x030000", "0x8086", "0xa780");
        addCard(QStringLiteral("0000:05:00.0"), "0x030200", "0x10de", "0xffff");
        addCard(QStringLiteral("0000:06:00.0"), "0x038000", "0x1234", "0xabcd");
        AboutInfo info(environment(), nullptr);
        QCOMPARE(values(info.deviceSpecs(), QStringLiteral("Graphics")),
            (QStringList {
                QStringLiteral("Intel UHD Graphics 770"),
                QStringLiteral("NVIDIA GeForce RTX 4050 Max-Q / Mobile"),
                QStringLiteral("NVIDIA, device ffff"),
                QStringLiteral("Vendor 1234, device abcd"),
            }));
    }

    void namesGraphicsWithoutPciIds()
    {
        QFile::remove(file(QStringLiteral("pci.ids")));
        AboutInfo info(environment(), nullptr);
        QCOMPARE(values(info.deviceSpecs(), QStringLiteral("Graphics")), QStringList { QStringLiteral("Vendor 10de, device 28e1") });
    }

    void readsTheMakerAndModel()
    {
        // Lenovo's model name is in product_version.
        AboutInfo lenovo(environment(), nullptr);
        QCOMPARE(lenovo.device(), QStringLiteral("LENOVO Legion Slim 5 16APH8"));
        QCOMPARE(values(lenovo.deviceSpecs(), QStringLiteral("Device")), QStringList { lenovo.device() });

        setDmi("Framework", "Laptop 16 (AMD Ryzen 7040 Series)");
        AboutInfo framework(environment(), nullptr);
        QCOMPARE(framework.device(), QStringLiteral("Framework Laptop 16 (AMD Ryzen 7040 Series)"));
    }

    void ignoresFirmwarePlaceholders()
    {
        // A desktop PC built from parts: the motherboard says more.
        setDmi("To Be Filled By O.E.M.", "To Be Filled By O.E.M.", "", "ASUSTeK COMPUTER INC.", "ROG STRIX B650-A GAMING WIFI");
        AboutInfo board(environment(), nullptr);
        QCOMPARE(board.device(), QStringLiteral("ASUSTeK COMPUTER INC. ROG STRIX B650-A GAMING WIFI"));

        setDmi("System manufacturer", "System Product Name", "System Version", "Default string", "Default string");
        AboutInfo none(environment(), nullptr);
        QVERIFY(none.device().isEmpty());
        QVERIFY(values(none.deviceSpecs(), QStringLiteral("Device")).isEmpty());
    }

    void readsTheNameShown()
    {
        AboutInfo plain(environment(), nullptr);
        QCOMPARE(plain.name(), QStringLiteral("orielos"));
        QCOMPARE(values(plain.deviceSpecs(), QStringLiteral("Device name")), QStringList { QStringLiteral("orielos") });

        m_names.insert(QStringLiteral("PrettyHostname"), QStringLiteral("Games PC"));
        AboutInfo pretty(environment(), nullptr);
        QCOMPARE(pretty.name(), QStringLiteral("Games PC"));

        m_names = { { QStringLiteral("Hostname"), QStringLiteral("localhost") } };
        AboutInfo kernel(environment(), nullptr);
        QCOMPARE(kernel.name(), QStringLiteral("localhost"));
    }

    void validatesNames()
    {
        AboutInfo info(environment(), nullptr);
        QVERIFY(info.validate(QStringLiteral("Games-PC-2")).isEmpty());
        QVERIFY(info.validate(QString(63, QLatin1Char('a'))).isEmpty());
        QCOMPARE(info.validate(QString()), QStringLiteral("Enter a name."));
        QCOMPARE(info.validate(QString(64, QLatin1Char('a'))), QStringLiteral("Use up to 63 characters."));
        QCOMPARE(info.validate(QStringLiteral("games pc")), QStringLiteral("Spaces can't be used. Try a hyphen instead."));
        QCOMPARE(info.validate(QStringLiteral("games_pc")), QStringLiteral("“_” can't be used. Use only letters A to Z, numbers and hyphens."));
        QCOMPARE(info.validate(QStringLiteral("café")), QStringLiteral("“é” can't be used. Use only letters A to Z, numbers and hyphens."));
        QCOMPARE(info.validate(QStringLiteral("pc\U0001F3AE")), QStringLiteral("“\U0001F3AE” can't be used. Use only letters A to Z, numbers and hyphens."));
        QCOMPARE(info.validate(QStringLiteral("-games")), QStringLiteral("The name can't start or end with a hyphen."));
        QCOMPARE(info.validate(QStringLiteral("games-")), QStringLiteral("The name can't start or end with a hyphen."));
    }

    void renamesThroughRenamePC()
    {
        AboutInfo info(environment(), nullptr);
        QSignalSpy renamed(&info, &AboutInfo::renamed);
        info.rename(QStringLiteral("games-pc"));
        QVERIFY(info.isRenaming());
        QCOMPARE(m_runs, QList<QStringList> { QStringList { QStringLiteral("games-pc") } });
        // Another rename meanwhile does nothing.
        info.rename(QStringLiteral("other"));
        QCOMPARE(m_runs.size(), 1);

        answer(0);
        QVERIFY(!info.isRenaming());
        QCOMPARE(info.name(), QStringLiteral("games-pc"));
        QCOMPARE(info.message(), QStringLiteral("This PC is now called games-pc."));
        QVERIFY(!info.messageIsError());
        QCOMPARE(renamed.size(), 1);
        QCOMPARE(values(info.deviceSpecs(), QStringLiteral("Device name")), QStringList { QStringLiteral("games-pc") });
    }

    void aDismissedPromptKeepsTheName_data()
    {
        QTest::addColumn<int>("exitCode");
        QTest::newRow("dismissed") << 126;
        QTest::newRow("not allowed") << 127;
    }

    void aDismissedPromptKeepsTheName()
    {
        QFETCH(int, exitCode);
        AboutInfo info(environment(), nullptr);
        QSignalSpy renamed(&info, &AboutInfo::renamed);
        info.rename(QStringLiteral("games-pc"));
        answer(exitCode, QStringLiteral("Error executing command as another user: Not authorized"));
        QVERIFY(!info.isRenaming());
        QCOMPARE(info.name(), QStringLiteral("orielos"));
        QCOMPARE(info.message(), QStringLiteral("This PC's name wasn't changed: permission wasn't given."));
        QVERIFY(info.messageIsError());
        QCOMPARE(renamed.size(), 0);
    }

    void aFailedRenameSaysWhy()
    {
        AboutInfo info(environment(), nullptr);
        QSignalSpy renamed(&info, &AboutInfo::renamed);
        info.rename(QStringLiteral("games-pc"));
        answer(1, QStringLiteral("rename-pc: Could not set hostname: Connection timed out"));
        QVERIFY(!info.isRenaming());
        QCOMPARE(info.message(), QStringLiteral("This PC's name couldn't be changed: Could not set hostname: Connection timed out"));
        QVERIFY(info.messageIsError());
        QCOMPARE(info.name(), QStringLiteral("orielos"));
        QCOMPARE(renamed.size(), 0);

        info.rename(QStringLiteral("games-pc"));
        answer(1);
        QCOMPARE(info.message(), QStringLiteral("This PC's name couldn't be changed: the rename stopped with an error."));
    }

    void closingThePageWhileRenamingIsSafe()
    {
        auto *info = new AboutInfo(environment(), nullptr);
        info->rename(QStringLiteral("games-pc"));
        delete info;
        // rename-pc finishes after the page has gone.
        answer(0);
    }

    void anInvalidNameIsntSent()
    {
        AboutInfo info(environment(), nullptr);
        info.rename(QStringLiteral("games pc"));
        QVERIFY(m_runs.isEmpty());
        QVERIFY(!info.isRenaming());
        QCOMPARE(info.message(), QStringLiteral("Spaces can't be used. Try a hyphen instead."));
        QVERIFY(info.messageIsError());
    }

    void copiesEachCardAsText()
    {
        AboutInfo info(environment(), nullptr);
        info.copyDevice();
        QString expected = QStringLiteral("Device name: orielos\n"
                                          "Processor: AMD Ryzen 7 7840HS w/ Radeon 780M Graphics (16 threads)\n"
                                          "Installed memory: 15.5 GB usable\n"
                                          "Graphics: NVIDIA GeForce RTX 4050 Max-Q / Mobile\n"
                                          "Device: LENOVO Legion Slim 5 16APH8\n"
                                          "System type: ");
        expected += values(info.deviceSpecs(), QStringLiteral("System type")).value(0);
        QCOMPARE(m_copied, expected);
        if (QSysInfo::currentCpuArchitecture() == QLatin1String("x86_64")) {
            QVERIFY(m_copied.endsWith(QStringLiteral("System type: 64-bit, x86-64 processor")));
        }

        info.copyOrielOS();
        QCOMPARE(m_copied, QStringLiteral("Version: 0.2.3\nKernel: 6.17.5-200.fc43.x86_64\nDesktop: KDE Plasma 6"));
    }
};

QTEST_GUILESS_MAIN(AboutInfoTest)

#include "aboutinfotest.moc"
