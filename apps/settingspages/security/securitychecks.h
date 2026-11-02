// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QDateTime>
#include <QList>
#include <QString>

#include <functional>
#include <optional>

namespace OrielOSSettingsPages {

// One requirement that games with anti-cheat (Easy Anti-Cheat for Linux) check, and whether the
// running system meets it.
struct SecurityCheck
{
    enum class Result {
        Met,
        NotMet,
        // The check couldn't find out, for example because a file couldn't be read.
        Unknown,
    };

    QString id;
    QString title;
    Result result = Result::Unknown;
    // What was found, in plain words, and what to do when it isn't met.
    QString explanation;
};

// Where the checks look. The defaults read the running system; the tests point them at copies.
struct SecuritySources
{
    // The folder that sys, proc and usr are in.
    QString root = QStringLiteral("/");
    // The signer of a loaded kernel module, as modinfo -F signer prints it: empty when it's
    // unsigned, nothing when that couldn't be found out. By default, runs modinfo.
    std::function<std::optional<QString>(const QString &module)> moduleSigner;
    // Whether to stop: checked between modules, the slow part. Optional.
    std::function<bool()> cancelled;
    // Whether the firewall is running. By default, asks systemd about firewalld.
    std::function<bool()> firewallActive;
    // The current time, for how long ago updates were checked. By default, the clock.
    std::function<QDateTime()> now;
};

// Every requirement, in order: Secure Boot, the TPM and its measured-boot log, kernel lockdown, the
// BPF security module, kexec turned off, the IOMMU, and signed drivers. Reads files and runs
// modinfo for each loaded module, so it takes a second or so: run it off the GUI thread.
QList<SecurityCheck> runSecurityChecks(const SecuritySources &sources = { });

// The computer's protection at a glance, as Windows' security app shows it: the firewall, and
// updates, from the state orielos-update writes. Quick enough for the GUI thread.
QList<SecurityCheck> runProtectionChecks(const SecuritySources &sources = { });

} // namespace OrielOSSettingsPages
