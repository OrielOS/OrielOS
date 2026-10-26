// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "securitychecks.h"
#include "devicesecurity.h"

#include <QDir>
#include <QFile>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTest>

using namespace OrielOSSettingsPages;
using Result = SecurityCheck::Result;

namespace {

// A copy of the files the checks read, as an OrielOS VM with Secure Boot and a software TPM 2.0
// has them (recorded from the boot test in QEMU), which each test then changes.
class FakeSystem
{
public:
    FakeSystem()
    {
        // The SecureBoot variable: four bytes of attributes, then 1 for on.
        write(QStringLiteral("sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"), QByteArray("\x06\x00\x00\x00\x01", 5));
        write(QStringLiteral("sys/class/tpm/tpm0/tpm_version_major"), "2\n");
        write(QStringLiteral("sys/kernel/security/tpm0/binary_bios_measurements"), "");
        write(QStringLiteral("sys/kernel/security/lockdown"), "none [integrity] confidentiality\n");
        write(QStringLiteral("sys/kernel/security/lsm"), "lockdown,capability,yama,selinux,bpf,landlock,ipe,ima,evm");
        write(QStringLiteral("proc/sys/kernel/kexec_load_disabled"), "1\n");
        write(QStringLiteral("proc/sys/kernel/tainted"), "0\n");
        mkdir(QStringLiteral("sys/class/iommu/dmar0"));
        write(QStringLiteral("proc/modules"),
            "hid_xpadneo 49152 0 - Live 0x0000000000000000\n"
            "xone_gip 69632 0 - Live 0x0000000000000000\n"
            "virtio_gpu 102400 2 - Live 0x0000000000000000\n");
        write(QStringLiteral("usr/share/orielos/module-signers.txt"),
            "# The signers a kernel module in the OrielOS image may have.\nFedora kernel signing key\nublue kernel\n");
        signers = {
            { QStringLiteral("hid_xpadneo"), QStringLiteral("ublue kernel") },
            { QStringLiteral("xone_gip"), QStringLiteral("ublue kernel") },
            { QStringLiteral("virtio_gpu"), QStringLiteral("Fedora kernel signing key") },
        };
    }

    void write(const QString &relative, const QByteArray &content)
    {
        const QString path = m_dir.filePath(relative);
        QDir().mkpath(QFileInfo(path).path());
        QFile file(path);
        QVERIFY(file.open(QIODevice::WriteOnly | QIODevice::Truncate));
        file.write(content);
    }

    void mkdir(const QString &relative) { QDir().mkpath(m_dir.filePath(relative)); }

    void remove(const QString &relative)
    {
        const QString path = m_dir.filePath(relative);
        if (QFileInfo(path).isDir()) {
            QDir(path).removeRecursively();
        } else {
            QFile::remove(path);
        }
    }

    SecuritySources sources() const
    {
        return { m_dir.path(), [signers = signers](const QString &module) { return signers.value(module); } };
    }

    // The check with this ID.
    SecurityCheck check(const QString &id) const
    {
        for (const SecurityCheck &check : runSecurityChecks(sources())) {
            if (check.id == id) {
                return check;
            }
        }
        return { };
    }

    QHash<QString, QString> signers;

private:
    QTemporaryDir m_dir;
};

} // namespace

class SecurityChecksTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void meetsEveryRequirementInTheVm()
    {
        const FakeSystem system;
        const QList<SecurityCheck> checks = runSecurityChecks(system.sources());
        QStringList ids;
        for (const SecurityCheck &check : checks) {
            ids.append(check.id);
            QVERIFY2(check.result == Result::Met, qPrintable(check.id + QStringLiteral(": ") + check.explanation));
            QVERIFY(!check.title.isEmpty());
            QVERIFY(!check.explanation.isEmpty());
        }
        QCOMPARE(ids,
            (QStringList { QStringLiteral("secure-boot"), QStringLiteral("tpm"), QStringLiteral("lockdown"), QStringLiteral("bpf-lsm"), QStringLiteral("kexec"),
                QStringLiteral("iommu"), QStringLiteral("signed-drivers") }));
        QCOMPARE(system.check(QStringLiteral("signed-drivers")).explanation, QStringLiteral("All 3 loaded drivers are signed by Fedora or Universal Blue."));
    }

    void secureBoot()
    {
        FakeSystem system;
        system.write(QStringLiteral("sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"), QByteArray("\x06\x00\x00\x00\x00", 5));
        SecurityCheck check = system.check(QStringLiteral("secure-boot"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("firmware settings")));

        system.write(QStringLiteral("sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"), QByteArray("\x06", 1));
        QCOMPARE(system.check(QStringLiteral("secure-boot")).result, Result::Unknown);

        system.remove(QStringLiteral("sys/firmware/efi"));
        check = system.check(QStringLiteral("secure-boot"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("UEFI")));
    }

    void tpm()
    {
        FakeSystem system;
        system.remove(QStringLiteral("sys/kernel/security/tpm0/binary_bios_measurements"));
        SecurityCheck check = system.check(QStringLiteral("tpm"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("measured-boot log")));

        system.write(QStringLiteral("sys/class/tpm/tpm0/tpm_version_major"), "1\n");
        check = system.check(QStringLiteral("tpm"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("version 1")));

        system.remove(QStringLiteral("sys/class/tpm"));
        check = system.check(QStringLiteral("tpm"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("No TPM")));
    }

    void lockdown()
    {
        FakeSystem system;
        system.write(QStringLiteral("sys/kernel/security/lockdown"), "none integrity [confidentiality]\n");
        QCOMPARE(system.check(QStringLiteral("lockdown")).result, Result::Met);
        system.write(QStringLiteral("sys/kernel/security/lockdown"), "[none] integrity confidentiality\n");
        QCOMPARE(system.check(QStringLiteral("lockdown")).result, Result::NotMet);
        system.remove(QStringLiteral("sys/kernel/security/lockdown"));
        QCOMPARE(system.check(QStringLiteral("lockdown")).result, Result::Unknown);
    }

    void bpfLsm()
    {
        FakeSystem system;
        // "bpf" must be a whole entry.
        system.write(QStringLiteral("sys/kernel/security/lsm"), "lockdown,capability,yama,selinux,bpfx,landlock");
        QCOMPARE(system.check(QStringLiteral("bpf-lsm")).result, Result::NotMet);
        system.remove(QStringLiteral("sys/kernel/security/lsm"));
        QCOMPARE(system.check(QStringLiteral("bpf-lsm")).result, Result::Unknown);
    }

    void kexec()
    {
        FakeSystem system;
        system.write(QStringLiteral("proc/sys/kernel/kexec_load_disabled"), "0\n");
        QCOMPARE(system.check(QStringLiteral("kexec")).result, Result::NotMet);
        system.remove(QStringLiteral("proc/sys/kernel/kexec_load_disabled"));
        QCOMPARE(system.check(QStringLiteral("kexec")).result, Result::Unknown);
    }

    void iommu()
    {
        FakeSystem system;
        system.remove(QStringLiteral("sys/class/iommu/dmar0"));
        const SecurityCheck check = system.check(QStringLiteral("iommu"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("VT-d")));
        // AMD's units have other names.
        system.mkdir(QStringLiteral("sys/class/iommu/ivhd0"));
        QCOMPARE(system.check(QStringLiteral("iommu")).result, Result::Met);
    }

    void signedDrivers()
    {
        FakeSystem system;
        system.write(QStringLiteral("proc/modules"),
            "xone_gip 69632 0 - Live 0x0000000000000000\n"
            "v4l2loopback 49152 0 - Live 0x0000000000000000\n"
            "mydriver 16384 0 - Live 0x0000000000000000\n");
        system.signers.insert(QStringLiteral("v4l2loopback"), QStringLiteral("Someone Else"));
        SecurityCheck check = system.check(QStringLiteral("signed-drivers"));
        QCOMPARE(check.result, Result::NotMet);
        QCOMPARE(check.explanation,
            QStringLiteral("These drivers aren't signed by Fedora or Universal Blue: v4l2loopback (signed by Someone Else), mydriver (unsigned)."));

        // Signed drivers, but an unsigned one was loaded earlier (taint flag E).
        system.write(QStringLiteral("proc/modules"), "xone_gip 69632 0 - Live 0x0000000000000000\n");
        system.write(QStringLiteral("proc/sys/kernel/tainted"), "12288\n");
        check = system.check(QStringLiteral("signed-drivers"));
        QCOMPARE(check.result, Result::NotMet);
        QVERIFY(check.explanation.contains(QLatin1String("unsigned driver was loaded")));

        // Other taint flags don't matter here.
        system.write(QStringLiteral("proc/sys/kernel/tainted"), "4096\n");
        check = system.check(QStringLiteral("signed-drivers"));
        QCOMPARE(check.result, Result::Met);
        QCOMPARE(check.explanation, QStringLiteral("The loaded driver is signed by Fedora or Universal Blue."));

        system.remove(QStringLiteral("usr/share/orielos/module-signers.txt"));
        QCOMPARE(system.check(QStringLiteral("signed-drivers")).result, Result::Unknown);
    }

    void runsOffTheGuiThread()
    {
        FakeSystem system;
        system.write(QStringLiteral("proc/sys/kernel/kexec_load_disabled"), "0\n");
        DeviceSecurity security(system.sources());
        QSignalSpy changed(&security, &DeviceSecurity::changed);
        QVERIFY(security.isRunning());
        // A second run while one is going is ignored.
        security.run();
        QVERIFY(changed.wait());
        QVERIFY(!security.isRunning());
        QVERIFY(!security.allMet());
        const QVariantList checks = security.checks();
        QCOMPARE(checks.size(), 7);
        const QVariantMap kexec = checks.at(4).toMap();
        QCOMPARE(kexec.value(QStringLiteral("id")).toString(), QStringLiteral("kexec"));
        QCOMPARE(kexec.value(QStringLiteral("result")).toString(), QStringLiteral("not-met"));
        QCOMPARE(checks.at(0).toMap().value(QStringLiteral("result")).toString(), QStringLiteral("met"));

        system.write(QStringLiteral("proc/sys/kernel/kexec_load_disabled"), "1\n");
        security.run();
        QVERIFY(security.isRunning());
        QVERIFY(changed.wait());
        QVERIFY(security.allMet());
    }
};

QTEST_GUILESS_MAIN(SecurityChecksTest)

#include "securitycheckstest.moc"
