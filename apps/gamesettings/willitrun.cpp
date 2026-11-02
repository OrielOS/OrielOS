// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "willitrun.h"

#include <KLocalizedString>

#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

#include <algorithm>

namespace OrielOSGames {

namespace {

// AreWeAntiCheatYet's statuses: Supported and Running work, Denied is the publisher's choice.
Verdict::Status statusOf(const QString &status)
{
    if (status == QLatin1String("Supported") || status == QLatin1String("Running")) {
        return Verdict::Status::Works;
    }
    if (status == QLatin1String("Denied")) {
        return Verdict::Status::Blocked;
    }
    if (status == QLatin1String("Broken")) {
        return Verdict::Status::Broken;
    }
    return Verdict::Status::Planned;
}

QString reasonFor(const QString &status, const QStringList &antiCheats)
{
    const QString antiCheat = antiCheats.isEmpty() ? i18nc("@info", "its anti-cheat") : antiCheats.join(i18nc("@info between anti-cheat names", " and "));
    if (status == QLatin1String("Supported")) {
        return i18nc("@info %1 is an anti-cheat, such as Easy Anti-Cheat", "Works: the publisher supports Linux with %1.", antiCheat);
    }
    if (status == QLatin1String("Running")) {
        return i18nc("@info", "Works, though the publisher doesn't support Linux officially.");
    }
    if (status == QLatin1String("Denied")) {
        return i18nc("@info %1 is an anti-cheat", "Blocked by the publisher: %1 is set to refuse Linux players.", antiCheat);
    }
    if (status == QLatin1String("Broken")) {
        return i18nc("@info %1 is an anti-cheat", "Doesn't work yet: %1 doesn't support Linux in this game.", antiCheat);
    }
    return i18nc("@info", "Not yet: Linux support is planned.");
}

QJsonArray gamesOf(const QJsonDocument &document)
{
    return document.isArray() ? document.array() : document.object().value(QLatin1String("games")).toArray();
}

} // namespace

WillItRun WillItRun::fromJson(const QByteArray &games, const QByteArray &overrides)
{
    WillItRun out;
    const QJsonDocument document = QJsonDocument::fromJson(games);
    out.m_fetched = document.object().value(QLatin1String("fetched")).toString();

    QHash<QString, QJsonObject> ours;
    for (const QJsonValue &value : QJsonDocument::fromJson(overrides).object().value(QLatin1String("games")).toArray()) {
        const QJsonObject game = value.toObject();
        ours.insert(game.value(QLatin1String("name")).toString().toLower(), game);
    }

    const auto add = [&out](const QJsonObject &game, const QString &reason) {
        Verdict verdict;
        verdict.name = game.value(QLatin1String("name")).toString();
        const QString status = game.value(QLatin1String("status")).toString();
        verdict.status = statusOf(status);
        for (const QJsonValue &antiCheat : game.value(QLatin1String("anticheats")).toArray()) {
            verdict.antiCheats.append(antiCheat.toString());
        }
        verdict.native = game.value(QLatin1String("native")).toBool();
        verdict.reason = reason.isEmpty() ? reasonFor(status, verdict.antiCheats) : reason;
        if (!verdict.name.isEmpty()) {
            out.m_verdicts.append(verdict);
        }
    };
    for (const QJsonValue &value : gamesOf(document)) {
        QJsonObject game = value.toObject();
        const auto override = ours.constFind(game.value(QLatin1String("name")).toString().toLower());
        if (override != ours.constEnd()) {
            game.insert(QStringLiteral("status"), override->value(QLatin1String("status")));
            add(game, override->value(QLatin1String("reason")).toString());
            ours.remove(override.key());
        } else {
            add(game, { });
        }
    }
    // OrielOS's verdicts for games the list doesn't have.
    for (const QJsonObject &game : std::as_const(ours)) {
        add(game, game.value(QLatin1String("reason")).toString());
    }
    return out;
}

QList<Verdict> WillItRun::search(const QString &words, int limit) const
{
    const QString wanted = words.trimmed();
    if (wanted.isEmpty()) {
        return { };
    }
    QList<Verdict> exact;
    QList<Verdict> partial;
    for (const Verdict &verdict : m_verdicts) {
        if (verdict.name.compare(wanted, Qt::CaseInsensitive) == 0) {
            exact.append(verdict);
        } else if (verdict.name.contains(wanted, Qt::CaseInsensitive)) {
            partial.append(verdict);
        }
    }
    return (exact + partial).mid(0, limit);
}

QByteArray WillItRun::trimmed(const QByteArray &games, const QString &fetched)
{
    QJsonArray out;
    for (const QJsonValue &value : gamesOf(QJsonDocument::fromJson(games))) {
        const QJsonObject game = value.toObject();
        if (game.value(QLatin1String("name")).toString().isEmpty()) {
            continue;
        }
        out.append(QJsonObject {
            { QStringLiteral("name"), game.value(QLatin1String("name")) },
            { QStringLiteral("status"), game.value(QLatin1String("status")) },
            { QStringLiteral("anticheats"), game.value(QLatin1String("anticheats")) },
            { QStringLiteral("native"), game.value(QLatin1String("native")).toBool() },
        });
    }
    if (out.isEmpty()) {
        return { };
    }
    return QJsonDocument(QJsonObject { { QStringLiteral("source"), QStringLiteral("https://github.com/AreWeAntiCheatYet/AreWeAntiCheatYet") },
                             { QStringLiteral("fetched"), fetched }, { QStringLiteral("games"), out } })
        .toJson(QJsonDocument::Compact);
}

} // namespace OrielOSGames
