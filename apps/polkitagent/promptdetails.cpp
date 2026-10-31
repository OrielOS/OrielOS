// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "promptdetails.h"

#include <QFileInfo>
#include <QRegularExpression>

namespace {

// The image's own programs: /usr is read-only and covered by the image's signature, apart from
// /usr/local, which is /var/usrlocal (nor is /etc: both can be changed on the computer).
bool isFromTheImage(const QString &path)
{
    return path.startsWith(QLatin1String("/usr/")) && !path.startsWith(QLatin1String("/usr/local/")) && !path.contains(QLatin1String("/../"));
}

} // namespace

PromptDetails PromptDetails::from(
    const QString &actionId, const QString &description, const QString &vendor, const QString &message, const QMap<QString, QString> &details)
{
    PromptDetails prompt;
    prompt.program = details.value(QStringLiteral("program"));
    prompt.commandLine = details.value(QStringLiteral("command_line"));
    if (prompt.program.isEmpty() && actionId == QLatin1String("org.freedesktop.policykit.exec")) {
        // "Authentication is needed to run `/usr/bin/tool --option' as the super user", in any
        // language: the command line, whose first word is the program.
        static const QRegularExpression quoted(QStringLiteral("`(/[^']+)'"));
        const QString commandLine = quoted.match(message).captured(1);
        prompt.program = commandLine.section(QLatin1Char(' '), 0, 0);
        if (prompt.commandLine.isEmpty() && commandLine != prompt.program) {
            prompt.commandLine = commandLine;
        }
    }

    if (actionId == QLatin1String("org.freedesktop.policykit.exec") && !prompt.program.isEmpty()) {
        // pkexec runs a program: the program is what asks.
        prompt.name = QFileInfo(prompt.program).fileName();
        prompt.verified = isFromTheImage(prompt.program);
        prompt.publisher = prompt.verified ? QStringLiteral("OrielOS") : QString();
        return prompt;
    }

    // Any other action belongs to a service that comes with the image, whose policy file is in
    // /usr/share/polkit-1/actions.
    prompt.name = description.isEmpty() ? actionId : description;
    prompt.publisher = vendor.isEmpty() ? QStringLiteral("OrielOS") : vendor;
    prompt.verified = true;
    return prompt;
}
