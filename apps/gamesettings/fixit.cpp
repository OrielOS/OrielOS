// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixit.h"

#include "launchoptions.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSysInfo>

#include <algorithm>

namespace OrielOSGames {

namespace {

const QString command = QStringLiteral("%command%");

Fix::Kind kindFrom(const QString &name)
{
    if (name == QLatin1String("tool")) {
        return Fix::Kind::Tool;
    }
    if (name == QLatin1String("variable")) {
        return Fix::Kind::Variable;
    }
    if (name == QLatin1String("turn-off")) {
        return Fix::Kind::TurnOff;
    }
    if (name == QLatin1String("clear-shader-cache")) {
        return Fix::Kind::ClearShaderCache;
    }
    return Fix::Kind::Advice;
}

bool switchOn(const GameOptions &options, const QString &name)
{
    if (name == QLatin1String("dlssUpgrade")) {
        return options.dlssUpgrade;
    }
    if (name == QLatin1String("waylandHdr")) {
        return options.waylandHdr;
    }
    if (name == QLatin1String("gamescope")) {
        return options.gamescope;
    }
    if (name == QLatin1String("fpsOverlay")) {
        return options.fpsOverlay;
    }
    if (name == QLatin1String("gameMode")) {
        return options.gameMode;
    }
    if (name == QLatin1String("descriptorHeap")) {
        return options.descriptorHeap;
    }
    return false;
}

// The first line of a file, or empty.
QString firstLine(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromUtf8(file.readLine()).trimmed();
}

// "580.95.05" from NVIDIA's driver, the series ("580") being what matching hardware compares.
QString driverSeries(const QString &driver)
{
    return driver.section(QLatin1Char('.'), 0, 0);
}

QJsonObject toJson(const Attempt &attempt)
{
    return {
        { QStringLiteral("appId"), attempt.appId },
        { QStringLiteral("diagnosis"), attempt.diagnosis },
        { QStringLiteral("fix"), attempt.fix },
        { QStringLiteral("tool"), attempt.tool },
        { QStringLiteral("gpu"), attempt.system.gpu },
        { QStringLiteral("driver"), attempt.system.driver },
        { QStringLiteral("kernel"), attempt.system.kernel },
        { QStringLiteral("worked"), attempt.worked },
        { QStringLiteral("when"), attempt.when.toUTC().toString(Qt::ISODate) },
    };
}

} // namespace

SystemFacts SystemFacts::current()
{
    SystemFacts facts;
    facts.kernel = QSysInfo::kernelVersion();
    // NVIDIA's driver: "NVRM version: NVIDIA UNIX Open Kernel Module for x86_64  580.95.05  Release Build ...".
    const QString nvrm = firstLine(QStringLiteral("/proc/driver/nvidia/version"));
    static const QRegularExpression version(QStringLiteral("\\s(\\d+\\.\\d+(?:\\.\\d+)?)\\s"));
    if (const QRegularExpressionMatch match = version.match(nvrm); match.hasMatch()) {
        facts.driver = match.captured(1);
    }
    const QStringList gpus = QDir(QStringLiteral("/proc/driver/nvidia/gpus")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    if (!gpus.isEmpty()) {
        QFile information(QStringLiteral("/proc/driver/nvidia/gpus/%1/information").arg(gpus.first()));
        if (information.open(QIODevice::ReadOnly)) {
            while (!information.atEnd()) {
                const QString line = QString::fromUtf8(information.readLine());
                if (line.startsWith(QLatin1String("Model:"))) {
                    facts.gpu = line.mid(6).trimmed();
                    break;
                }
            }
        }
    }
    return facts;
}

FixItRules FixItRules::fromJson(const QByteArray &json)
{
    FixItRules rules;
    const QJsonArray signatures = QJsonDocument::fromJson(json).object().value(QLatin1String("signatures")).toArray();
    for (const QJsonValue &value : signatures) {
        const QJsonObject object = value.toObject();
        Signature signature;
        signature.id = object.value(QLatin1String("id")).toString();
        signature.when = object.value(QLatin1String("when")).toString();
        signature.cause = object.value(QLatin1String("cause")).toString();
        for (const QJsonValue &pattern : object.value(QLatin1String("patterns")).toArray()) {
            QRegularExpression expression(pattern.toString());
            if (expression.isValid()) {
                signature.patterns.append(expression);
            }
        }
        for (const QJsonValue &fixValue : object.value(QLatin1String("fixes")).toArray()) {
            const QJsonObject fixObject = fixValue.toObject();
            signature.fixes.append({ fixObject.value(QLatin1String("id")).toString(), kindFrom(fixObject.value(QLatin1String("kind")).toString()),
                fixObject.value(QLatin1String("value")).toString(), fixObject.value(QLatin1String("explanation")).toString() });
        }
        if (!signature.id.isEmpty() && !signature.patterns.isEmpty() && !signature.fixes.isEmpty()) {
            rules.m_signatures.append(signature);
        }
    }
    return rules;
}

QList<Diagnosis> FixItRules::diagnose(const QString &log, const QString &launchOptions, const QString &tool, const QStringList &installedTools) const
{
    const GameOptions options = GameOptions::read(launchOptions);
    QList<Diagnosis> out;
    for (const Signature &signature : m_signatures) {
        if (!signature.when.isEmpty() && !switchOn(options, signature.when)) {
            continue;
        }
        const bool matched = std::any_of(
            signature.patterns.cbegin(), signature.patterns.cend(), [&log](const QRegularExpression &pattern) { return pattern.match(log).hasMatch(); });
        if (!matched) {
            continue;
        }
        Diagnosis diagnosis { signature.id, signature.cause, { } };
        for (const Fix &fix : signature.fixes) {
            switch (fix.kind) {
            case Fix::Kind::Tool:
                if (fix.value == tool || (!fix.value.isEmpty() && !installedTools.contains(fix.value))) {
                    continue;
                }
                break;
            case Fix::Kind::Variable:
                if (withVariable(launchOptions, fix.value) == launchOptions) {
                    continue;
                }
                break;
            case Fix::Kind::TurnOff:
                if (!switchOn(options, fix.value)) {
                    continue;
                }
                break;
            case Fix::Kind::ClearShaderCache:
            case Fix::Kind::Advice:
                break;
            }
            diagnosis.fixes.append(fix);
        }
        if (!diagnosis.fixes.isEmpty()) {
            out.append(diagnosis);
        }
    }
    return out;
}

QList<Fix> rankFixes(const QList<Fix> &fixes, const QString &diagnosis, const QList<Attempt> &history, const SystemFacts &system)
{
    struct Score
    {
        int worked = 0;
        int failed = 0;
    };
    QHash<QString, Score> scores;
    for (const Attempt &attempt : history) {
        if (attempt.diagnosis != diagnosis || attempt.system.gpu != system.gpu || driverSeries(attempt.system.driver) != driverSeries(system.driver)) {
            continue;
        }
        Score &score = scores[attempt.fix];
        (attempt.worked ? score.worked : score.failed) += 1;
    }
    // Worked at least once: by share of tries that worked. Untried: 0.5, in the file's order.
    // Only failed: below every other.
    const auto rate = [&scores](const Fix &fix) {
        const Score score = scores.value(fix.id);
        if (score.worked + score.failed == 0) {
            return 0.5;
        }
        if (score.worked == 0) {
            return -1.0 * score.failed;
        }
        return 0.5 + 0.5 * score.worked / double(score.worked + score.failed);
    };
    QList<Fix> ranked = fixes;
    std::stable_sort(ranked.begin(), ranked.end(), [&rate](const Fix &a, const Fix &b) { return rate(a) > rate(b); });
    return ranked;
}

QString withVariable(const QString &launchOptions, const QString &assignment)
{
    QStringList words = launchOptions.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    qsizetype at = words.indexOf(command);
    if (at >= 0 && words.mid(0, at).contains(assignment)) {
        return launchOptions;
    }
    if (at < 0) {
        // Without %command%, everything typed is the game's own arguments.
        words.prepend(command);
        at = 0;
    }
    words.insert(at, assignment);
    return words.join(QLatin1Char(' '));
}

QString withoutVariable(const QString &launchOptions, const QString &assignment)
{
    QStringList words = launchOptions.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    const qsizetype at = words.indexOf(command);
    if (at < 0) {
        return launchOptions;
    }
    const qsizetype found = words.mid(0, at).indexOf(assignment);
    if (found < 0) {
        return launchOptions;
    }
    words.removeAt(found);
    // Only %command% left: the options were empty before the variable was added.
    if (words.size() == 1) {
        return { };
    }
    return words.join(QLatin1Char(' '));
}

QList<Attempt> readAttempts(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    QList<Attempt> out;
    for (const QJsonValue &value : QJsonDocument::fromJson(file.readAll()).array()) {
        const QJsonObject object = value.toObject();
        Attempt attempt;
        attempt.appId = object.value(QLatin1String("appId")).toString();
        attempt.diagnosis = object.value(QLatin1String("diagnosis")).toString();
        attempt.fix = object.value(QLatin1String("fix")).toString();
        attempt.tool = object.value(QLatin1String("tool")).toString();
        attempt.system = { object.value(QLatin1String("gpu")).toString(), object.value(QLatin1String("driver")).toString(),
            object.value(QLatin1String("kernel")).toString() };
        attempt.worked = object.value(QLatin1String("worked")).toBool();
        attempt.when = QDateTime::fromString(object.value(QLatin1String("when")).toString(), Qt::ISODate);
        out.append(attempt);
    }
    return out;
}

bool appendAttempt(const QString &path, const Attempt &attempt)
{
    QJsonArray array;
    for (const Attempt &old : readAttempts(path)) {
        array.append(toJson(old));
    }
    array.append(toJson(attempt));
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(QJsonDocument(array).toJson());
    return file.commit();
}

Undo Undo::read(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    const QJsonObject object = QJsonDocument::fromJson(file.readAll()).object();
    return { object.value(QLatin1String("appId")).toString(), object.value(QLatin1String("fix")).toString(), object.value(QLatin1String("tool")).toString(),
        object.value(QLatin1String("launchOptions")).toString(), object.value(QLatin1String("shaderCache")).toString(),
        object.value(QLatin1String("shaderCacheMovedTo")).toString() };
}

bool Undo::write(const QString &path) const
{
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        return false;
    }
    file.write(QJsonDocument(QJsonObject {
                                 { QStringLiteral("appId"), appId },
                                 { QStringLiteral("fix"), fix },
                                 { QStringLiteral("tool"), tool },
                                 { QStringLiteral("launchOptions"), launchOptions },
                                 { QStringLiteral("shaderCache"), shaderCache },
                                 { QStringLiteral("shaderCacheMovedTo"), shaderCacheMovedTo },
                             })
            .toJson());
    return file.commit();
}

} // namespace OrielOSGames
