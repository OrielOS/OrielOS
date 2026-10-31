// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runtarget.h"

#include <QDir>
#include <QFileInfo>
#include <QHash>
#include <QProcess>
#include <QUrl>

namespace RunBox {

QString equivalentProgram(const QString &program)
{
    // What people type from habit. Only programs on the image: anything else falls through to the
    // name as typed.
    static const QHash<QString, QString> equivalents = {
        { QStringLiteral("cmd"), QStringLiteral("konsole") },
        { QStringLiteral("powershell"), QStringLiteral("konsole") },
        { QStringLiteral("pwsh"), QStringLiteral("konsole") },
        { QStringLiteral("wt"), QStringLiteral("konsole") },
        { QStringLiteral("explorer"), QStringLiteral("dolphin") },
        { QStringLiteral("control"), QStringLiteral("orielos-settings") },
        { QStringLiteral("ms-settings:"), QStringLiteral("orielos-settings") },
        { QStringLiteral("taskmgr"), QStringLiteral("plasma-systemmonitor") },
    };
    QString name = program.toLower();
    if (name.endsWith(QLatin1String(".exe"))) {
        name.chop(4);
    }
    return equivalents.value(name, program);
}

Target resolve(const QString &text, const QString &home, const FindProgram &findProgram)
{
    const QString typed = text.trimmed();
    if (typed.isEmpty()) {
        return { };
    }

    // A path Browse quoted, because it has spaces.
    QString path = typed;
    if (path.size() > 2 && path.startsWith(QLatin1Char('"')) && path.endsWith(QLatin1Char('"'))) {
        path = path.mid(1, path.size() - 2);
    }
    if (path == QLatin1String("~") || path.startsWith(QLatin1String("~/"))) {
        path = home + path.mid(1);
    }
    if (QDir::isAbsolutePath(path) && QFileInfo::exists(path)) {
        return { Target::Kind::Path, QUrl::fromLocalFile(path).toString() };
    }

    // An address is one word; with more, it's a program's argument.
    const bool oneWord = !typed.contains(QLatin1Char(' '));
    if (oneWord && (typed.contains(QLatin1String("://")) || typed.startsWith(QLatin1String("mailto:"), Qt::CaseInsensitive))) {
        return { Target::Kind::Url, typed };
    }
    // As Windows does, an address without its scheme opens as a website.
    if (oneWord && typed.startsWith(QLatin1String("www."), Qt::CaseInsensitive)) {
        return { Target::Kind::Url, QStringLiteral("https://") + typed };
    }

    QStringList words = QProcess::splitCommand(typed);
    if (words.isEmpty()) {
        return { Target::Kind::NotFound, typed };
    }
    words.first() = equivalentProgram(words.first());
    if (findProgram(words.first()).isEmpty()) {
        return { Target::Kind::NotFound, typed };
    }
    // Quoted again, so arguments with spaces stay whole.
    QStringList quoted;
    for (const QString &word : std::as_const(words)) {
        quoted.append(word.contains(QLatin1Char(' ')) ? QLatin1Char('"') + word + QLatin1Char('"') : word);
    }
    return { Target::Kind::Command, quoted.join(QLatin1Char(' ')) };
}

QStringList remember(const QStringList &history, const QString &text)
{
    const QString typed = text.trimmed();
    if (typed.isEmpty()) {
        return history;
    }
    QStringList updated { typed };
    for (const QString &entry : history) {
        if (entry != typed && updated.size() < HistoryLength) {
            updated.append(entry);
        }
    }
    return updated;
}

} // namespace RunBox
