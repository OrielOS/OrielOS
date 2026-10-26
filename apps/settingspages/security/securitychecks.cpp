// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "securitychecks.h"

#include <KLocalizedString>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QRegularExpression>
#include <QStandardPaths>

#include <optional>

namespace OrielOSSettingsPages {

namespace {

using Result = SecurityCheck::Result;

QString pathIn(const SecuritySources &sources, const QString &relative)
{
    return QDir(sources.root).filePath(relative);
}

std::optional<QByteArray> readFile(const SecuritySources &sources, const QString &relative)
{
    QFile file(pathIn(sources, relative));
    if (!file.open(QIODevice::ReadOnly)) {
        return std::nullopt;
    }
    return file.readAll();
}

QString defaultSigner(const QString &module)
{
    QString modinfo = QStandardPaths::findExecutable(QStringLiteral("modinfo"));
    if (modinfo.isEmpty()) {
        modinfo = QStandardPaths::findExecutable(QStringLiteral("modinfo"), { QStringLiteral("/usr/sbin"), QStringLiteral("/sbin") });
    }
    QProcess process;
    process.start(modinfo, { QStringLiteral("-F"), QStringLiteral("signer"), module });
    if (!process.waitForFinished(5000)) {
        process.kill();
        return { };
    }
    return QString::fromUtf8(process.readAllStandardOutput()).section(QLatin1Char('\n'), 0, 0).trimmed();
}

SecurityCheck secureBoot(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("secure-boot"), i18nc("@title A requirement of games with anti-cheat", "Secure Boot") };
    if (!QFileInfo::exists(pathIn(sources, QStringLiteral("sys/firmware/efi")))) {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "This PC didn't start in UEFI mode, so Secure Boot isn't available.");
        return check;
    }
    // The variable's first four bytes are its attributes; the fifth is 1 when Secure Boot is on.
    const std::optional<QByteArray> data = readFile(sources, QStringLiteral("sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"));
    if (!data || data->size() < 5) {
        check.explanation = i18nc("@info", "Whether Secure Boot is on couldn't be read.");
    } else if (data->at(4) == 1) {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "Secure Boot is on: the PC only starts software signed by a key it trusts.");
    } else {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "Secure Boot is off. Turn it on in the PC's firmware settings, usually under Boot or Security.");
    }
    return check;
}

SecurityCheck tpm(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("tpm"), i18nc("@title A requirement of games with anti-cheat", "TPM 2.0 and measured boot") };
    const std::optional<QByteArray> version = readFile(sources, QStringLiteral("sys/class/tpm/tpm0/tpm_version_major"));
    if (!version) {
        check.result = Result::NotMet;
        check.explanation
            = i18nc("@info", "No TPM was found. Turn the TPM on in the PC's firmware settings, where it may be called fTPM, PTT or Security Device.");
    } else if (version->trimmed() != "2") {
        check.result = Result::NotMet;
        check.explanation
            = i18nc("@info %1 is a version number", "This PC's TPM is version %1; games need version 2.0.", QString::fromUtf8(version->trimmed()));
    } else if (!QFileInfo::exists(pathIn(sources, QStringLiteral("sys/kernel/security/tpm0/binary_bios_measurements")))) {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "The PC has a TPM 2.0, but its firmware didn't record what it started (the measured-boot log).");
    } else {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "The PC has a TPM 2.0, and its firmware recorded what it started (the measured-boot log).");
    }
    return check;
}

// Lockdown, the BPF security module and kexec are set at every start; only a changed start can
// lose them.
SecurityCheck lockdown(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("lockdown"), i18nc("@title A requirement of games with anti-cheat", "Kernel lockdown") };
    const std::optional<QByteArray> modes = readFile(sources, QStringLiteral("sys/kernel/security/lockdown"));
    // The mode in use is in brackets, as in "none [integrity] confidentiality".
    const QRegularExpressionMatch current = QRegularExpression(QStringLiteral("\\[(\\w+)\\]")).match(QString::fromUtf8(modes.value_or(QByteArray())));
    if (!current.hasMatch()) {
        check.explanation = i18nc("@info", "Whether the kernel is locked down couldn't be read.");
    } else if (current.captured(1) == QLatin1String("integrity") || current.captured(1) == QLatin1String("confidentiality")) {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "The kernel is locked down: not even an administrator can change it while it runs.");
    } else {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info",
            "Kernel lockdown is off. OrielOS turns it on at every start, so this start's options were changed, for example in the boot menu. Restart without "
            "changing them.");
    }
    return check;
}

SecurityCheck bpfLsm(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("bpf-lsm"), i18nc("@title A requirement of games with anti-cheat", "BPF security module") };
    const std::optional<QByteArray> modules = readFile(sources, QStringLiteral("sys/kernel/security/lsm"));
    if (!modules) {
        check.explanation = i18nc("@info", "The kernel's active security modules couldn't be read.");
    } else if (modules->trimmed().split(',').contains("bpf")) {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "The kernel's BPF security module, which can watch for tampering, is active.");
    } else {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info",
            "The kernel's BPF security module isn't active. OrielOS turns it on at every start, so this start's options were changed. Restart without "
            "changing them.");
    }
    return check;
}

SecurityCheck kexec(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("kexec"), i18nc("@title A requirement of games with anti-cheat", "No switching kernels") };
    const std::optional<QByteArray> disabled = readFile(sources, QStringLiteral("proc/sys/kernel/kexec_load_disabled"));
    if (!disabled) {
        check.explanation = i18nc("@info", "Whether another kernel can be started couldn't be read.");
    } else if (disabled->trimmed() == "1") {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "Nothing can start a different kernel in place of the running one without a full restart.");
    } else {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "A different kernel could be started in place of the running one (kexec is allowed).");
    }
    return check;
}

SecurityCheck iommu(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("iommu"), i18nc("@title A requirement of games with anti-cheat", "IOMMU") };
    // Each IOMMU unit the kernel uses, such as dmar0 or ivhd0, is a link here.
    const QStringList units = QDir(pathIn(sources, QStringLiteral("sys/class/iommu"))).entryList(QDir::AllEntries | QDir::System | QDir::NoDotAndDotDot);
    if (!units.isEmpty()) {
        check.result = Result::Met;
        check.explanation = i18nc("@info", "The IOMMU is on, so each device can only reach the memory it's given.");
    } else {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "The IOMMU is off. Turn on VT-d (Intel) or AMD-Vi, also called IOMMU, in the PC's firmware settings.");
    }
    return check;
}

SecurityCheck signedDrivers(const SecuritySources &sources)
{
    SecurityCheck check { QStringLiteral("signed-drivers"), i18nc("@title A requirement of games with anti-cheat", "Signed drivers") };
    const std::optional<QByteArray> loaded = readFile(sources, QStringLiteral("proc/modules"));
    // The image installs the list its build checks every module against.
    const std::optional<QByteArray> signersFile = readFile(sources, QStringLiteral("usr/share/orielos/module-signers.txt"));
    if (!loaded || !signersFile) {
        check.explanation = i18nc("@info", "The loaded drivers, or the signers they may have, couldn't be read.");
        return check;
    }
    QStringList accepted;
    for (const QByteArray &line : signersFile->split('\n')) {
        const QByteArray signer = line.trimmed();
        if (!signer.isEmpty() && !signer.startsWith('#')) {
            accepted.append(QString::fromUtf8(signer));
        }
    }

    const auto signer = sources.moduleSigner ? sources.moduleSigner : defaultSigner;
    QStringList modules;
    QStringList others;
    for (const QByteArray &line : loaded->split('\n')) {
        const QString name = QString::fromUtf8(line.left(line.indexOf(' ')).trimmed());
        if (name.isEmpty()) {
            continue;
        }
        modules.append(name);
        const QString by = signer(name);
        if (!accepted.contains(by)) {
            others.append(by.isEmpty() ? i18nc("@item %1 is a driver", "%1 (unsigned)", name)
                                       : i18nc("@item %1 is a driver, %2 who signed it", "%1 (signed by %2)", name, by));
        }
    }
    // The kernel's taint flag E: an unsigned module was loaded since the start, even if it's gone.
    const qulonglong taint = readFile(sources, QStringLiteral("proc/sys/kernel/tainted")).value_or(QByteArray("0")).trimmed().toULongLong();
    constexpr qulonglong unsignedModule = 1ULL << 13;

    if (!others.isEmpty()) {
        check.result = Result::NotMet;
        check.explanation
            = i18nc("@info %1 is a list of drivers", "These drivers aren't signed by Fedora or Universal Blue: %1.", others.join(QStringLiteral(", ")));
    } else if (taint & unsignedModule) {
        check.result = Result::NotMet;
        check.explanation = i18nc("@info", "An unsigned driver was loaded since the PC started. Restart to clear it.");
    } else {
        check.result = Result::Met;
        check.explanation = i18ncp("@info", "The loaded driver is signed by Fedora or Universal Blue.",
            "All %1 loaded drivers are signed by Fedora or Universal Blue.", modules.size());
    }
    return check;
}

} // namespace

QList<SecurityCheck> runSecurityChecks(const SecuritySources &sources)
{
    return { secureBoot(sources), tpm(sources), lockdown(sources), bpfLsm(sources), kexec(sources), iommu(sources), signedDrivers(sources) };
}

} // namespace OrielOSSettingsPages
