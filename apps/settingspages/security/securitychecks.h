// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>

#include <functional>

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
    // The signer of a loaded kernel module, as modinfo -F signer prints it; empty when unsigned.
    // By default, runs modinfo.
    std::function<QString(const QString &module)> moduleSigner;
};

// Every requirement, in order: Secure Boot, the TPM and its measured-boot log, kernel lockdown, the
// BPF security module, kexec turned off, the IOMMU, and signed drivers. Reads files and runs
// modinfo for each loaded module, so it takes a second or so: run it off the GUI thread.
QList<SecurityCheck> runSecurityChecks(const SecuritySources &sources = { });

} // namespace OrielOSSettingsPages
