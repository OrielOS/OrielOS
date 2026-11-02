// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "fixitsession.h"

#include "launchoptions.h"

#include <KLocalizedString>

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

#include <utility>

namespace OrielOSGames {

namespace {

const QString steamApp = QStringLiteral("com.valvesoftware.Steam");
const QString protonLog = QStringLiteral("PROTON_LOG=1");
const QString rulesFile = QStringLiteral("/usr/share/orielos/fix-it.json");
// How long a game has to keep running for a fix to count, and how long Steam gets to start it.
constexpr int keepsRunningSeconds = 120;
constexpr int startSeconds = 120;

// Whether the game is running: Steam starts each game under its reaper, as
// "reaper SteamLaunch AppId=<id> -- ...", and a process's command line is readable by anyone.
bool gameRunning(const QString &appId)
{
    const QByteArray wanted = "AppId=" + appId.toUtf8();
    const QStringList pids = QDir(QStringLiteral("/proc")).entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &pid : pids) {
        if (pid.isEmpty() || !pid.at(0).isDigit()) {
            continue;
        }
        QFile cmdline(QStringLiteral("/proc/%1/cmdline").arg(pid));
        if (!cmdline.open(QIODevice::ReadOnly)) {
            continue;
        }
        const QList<QByteArray> words = cmdline.readAll().split('\0');
        if (words.contains("SteamLaunch") && words.contains(wanted)) {
            return true;
        }
    }
    return false;
}

// Proton writes steam-<id>.log to its home, which for Steam from the Store is its own folder.
QString logPath(const QString &appId)
{
    const QString home = QDir::homePath();
    const QStringList candidates
        = { home + QStringLiteral("/.var/app/com.valvesoftware.Steam/steam-%1.log").arg(appId), home + QStringLiteral("/steam-%1.log").arg(appId) };
    QString newest;
    for (const QString &path : candidates) {
        if (QFileInfo::exists(path) && (newest.isEmpty() || QFileInfo(path).lastModified() > QFileInfo(newest).lastModified())) {
            newest = path;
        }
    }
    return newest;
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

// The game's shader cache in whichever library has it, or empty.
QString shaderCacheOf(const SteamLibrary &library, const QString &appId)
{
    for (const QString &folder : library.libraries()) {
        const QString path = folder + QStringLiteral("/steamapps/shadercache/") + appId;
        if (QFileInfo(path).isDir()) {
            return path;
        }
    }
    return { };
}

} // namespace

FixIt::FixIt(QObject *parent)
    : QObject(parent)
    , m_rules(FixItRules::fromJson(readFile(rulesFile)))
{
    m_timer.setInterval(2000);
    connect(&m_timer, &QTimer::timeout, this, &FixIt::tick);
}

void FixIt::setSettings(GameSettings *settings)
{
    if (m_settings == settings) {
        return;
    }
    m_settings = settings;
    Q_EMIT changed();
}

QString FixIt::folder() const
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/orielos/fix-it");
}

QVariantList FixIt::causes() const
{
    QVariantList out;
    for (const Diagnosis &diagnosis : m_causes) {
        QVariantList fixes;
        for (const Fix &fix : diagnosis.fixes) {
            fixes.append(QVariantMap {
                { QStringLiteral("id"), fix.id },
                { QStringLiteral("explanation"), fix.explanation },
                { QStringLiteral("advice"), fix.kind == Fix::Kind::Advice },
            });
        }
        out.append(QVariantMap {
            { QStringLiteral("id"), diagnosis.id },
            { QStringLiteral("cause"), diagnosis.cause },
            { QStringLiteral("fixes"), fixes },
        });
    }
    return out;
}

void FixIt::setState(const QString &state, const QString &message)
{
    m_state = state;
    m_message = message;
    Q_EMIT changed();
}

void FixIt::reset()
{
    m_timer.stop();
    m_causes.clear();
    m_appId.clear();
    setState(QStringLiteral("idle"));
}

void FixIt::start(const QString &appId, const QString &gameName)
{
    if (!m_settings || m_settings->steamRunning() || m_timer.isActive()) {
        return;
    }
    m_appId = appId;
    m_causes.clear();
    // A publisher that refuses Linux players can't be fixed from this PC.
    if (const std::optional<Verdict> verdict = m_settings->verdictFor(gameName); verdict && verdict->status == Verdict::Status::Blocked) {
        setState(QStringLiteral("blocked"), verdict->reason);
        return;
    }
    if (m_rules.isEmpty()) {
        setState(QStringLiteral("failed"), i18nc("@info", "Fix it's list of problems is missing."));
        return;
    }
    const SteamLibrary &library = m_settings->library();
    m_original = library.launchOptions(appId);
    if (!library.setLaunchOptions(appId, withVariable(m_original, protonLog))) {
        setState(QStringLiteral("failed"), i18nc("@info", "Steam's settings couldn't be changed. Start Steam once, close it, then try again."));
        return;
    }
    QFile::remove(logPath(appId));
    m_diagnosisId.clear();
    m_fixId.clear();
    launch();
    setState(QStringLiteral("starting"));
}

void FixIt::launch()
{
    QProcess::startDetached(QStringLiteral("flatpak"), { QStringLiteral("run"), steamApp, QStringLiteral("steam://rungameid/") + m_appId });
    m_seen = false;
    m_closeAskedAt = QDateTime();
    m_deadline = QDateTime::currentDateTimeUtc().addSecs(startSeconds);
    m_timer.start();
}

void FixIt::tick()
{
    if (!m_settings) {
        m_timer.stop();
        return;
    }
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const bool running = gameRunning(m_appId);
    if (m_state == QLatin1String("starting") || m_state == QLatin1String("playing")) {
        if (running && !m_seen) {
            m_seen = true;
            setState(QStringLiteral("playing"));
        } else if ((m_seen && !running) || (!m_seen && now > m_deadline)) {
            // The game closed, or never started: close Steam, so its settings can be put back.
            setState(QStringLiteral("closing"));
        }
        return;
    }
    if (m_state == QLatin1String("closing")) {
        if (m_settings->steamRunning()) {
            // Asked again every half minute: Game Settings ignores the request while it's busy.
            if (!m_closeAskedAt.isValid() || m_closeAskedAt.secsTo(now) >= 30) {
                m_closeAskedAt = now;
                m_settings->closeSteam();
            }
            return;
        }
        m_timer.stop();
        diagnose();
        return;
    }
    if (m_state == QLatin1String("verifying")) {
        if (running && !m_seen) {
            m_seen = true;
            m_seenAt = now;
        } else if (m_seen && running && m_seenAt.secsTo(now) >= keepsRunningSeconds) {
            finishCheck(true);
        } else if ((m_seen && !running) || (!m_seen && now > m_deadline)) {
            finishCheck(false);
        }
    }
}

void FixIt::diagnose()
{
    const SteamLibrary &library = m_settings->library();
    // Proton's log goes again, leaving the launch options exactly as they were.
    if (!library.setLaunchOptions(m_appId, m_original)) {
        setState(QStringLiteral("failed"), i18nc("@info", "The game's launch options couldn't be put back. In Steam, remove PROTON_LOG=1 from them."));
        return;
    }
    const QString path = logPath(m_appId);
    if (path.isEmpty()) {
        setState(QStringLiteral("no-log"), i18nc("@info", "The game didn't write Proton's log. Fix it works with Windows games that Steam runs with Proton."));
        return;
    }
    const QString log = QString::fromUtf8(readFile(path));
    QStringList installed;
    for (const QVariant &tool : m_settings->tools()) {
        installed.append(tool.toMap().value(QStringLiteral("id")).toString());
    }
    const QList<Attempt> history = readAttempts(folder() + QStringLiteral("/attempts.json"));
    const SystemFacts system = SystemFacts::current();
    m_causes = m_rules.diagnose(log, m_original, library.compatTool(m_appId), installed);
    for (Diagnosis &diagnosis : m_causes) {
        diagnosis.fixes = rankFixes(diagnosis.fixes, diagnosis.id, history, system);
    }
    setState(m_causes.isEmpty() ? QStringLiteral("nothing-found") : QStringLiteral("diagnosed"));
}

void FixIt::apply(const QString &diagnosisId, const QString &fixId)
{
    if (!m_settings || m_settings->steamRunning() || m_appId.isEmpty()) {
        return;
    }
    const SteamLibrary &library = m_settings->library();
    std::optional<Fix> chosen = std::nullopt;
    for (const Diagnosis &diagnosis : std::as_const(m_causes)) {
        for (const Fix &fix : diagnosis.fixes) {
            if (diagnosis.id == diagnosisId && fix.id == fixId) {
                chosen = fix;
            }
        }
    }
    if (!chosen || chosen->kind == Fix::Kind::Advice) {
        return;
    }
    Undo undo { m_appId, fixId, library.compatTool(m_appId), library.launchOptions(m_appId), { }, { } };
    if (chosen->kind == Fix::Kind::ClearShaderCache) {
        undo.shaderCache = shaderCacheOf(library, m_appId);
        if (!undo.shaderCache.isEmpty()) {
            undo.shaderCacheMovedTo = undo.shaderCache + QStringLiteral(".before-fix-it");
        }
    }
    if (!undo.write(folder() + QStringLiteral("/undo-%1.json").arg(m_appId))) {
        setState(QStringLiteral("failed"), i18nc("@info", "Fix it couldn't save what it would change, so it changed nothing."));
        return;
    }
    bool ok = true;
    switch (chosen->kind) {
    case Fix::Kind::Tool:
        ok = library.setCompatTool(m_appId, chosen->value);
        break;
    case Fix::Kind::Variable:
        ok = library.setLaunchOptions(m_appId, withVariable(undo.launchOptions, chosen->value));
        break;
    case Fix::Kind::TurnOff: {
        GameOptions options = GameOptions::read(undo.launchOptions);
        const QString &name = chosen->value;
        options.dlssUpgrade = options.dlssUpgrade && name != QLatin1String("dlssUpgrade");
        options.waylandHdr = options.waylandHdr && name != QLatin1String("waylandHdr");
        options.gamescope = options.gamescope && name != QLatin1String("gamescope");
        options.fpsOverlay = options.fpsOverlay && name != QLatin1String("fpsOverlay");
        options.gameMode = options.gameMode && name != QLatin1String("gameMode");
        options.descriptorHeap = options.descriptorHeap && name != QLatin1String("descriptorHeap");
        ok = library.setLaunchOptions(m_appId, options.apply(undo.launchOptions));
        break;
    }
    case Fix::Kind::ClearShaderCache:
        if (!undo.shaderCache.isEmpty()) {
            QDir(undo.shaderCacheMovedTo).removeRecursively();
            ok = QDir().rename(undo.shaderCache, undo.shaderCacheMovedTo);
        }
        break;
    case Fix::Kind::Advice:
        break;
    }
    if (!ok) {
        setState(QStringLiteral("failed"), i18nc("@info", "Steam's settings couldn't be changed. Start Steam once, close it, then try again."));
        return;
    }
    m_diagnosisId = diagnosisId;
    m_fixId = fixId;
    m_settings->reload();
    launch();
    setState(QStringLiteral("verifying"));
}

void FixIt::finishCheck(bool worked)
{
    m_timer.stop();
    const SteamLibrary &library = m_settings->library();
    appendAttempt(folder() + QStringLiteral("/attempts.json"),
        { m_appId, m_diagnosisId, m_fixId, library.compatTool(m_appId), SystemFacts::current(), worked, QDateTime::currentDateTimeUtc() });
    setState(worked ? QStringLiteral("worked") : QStringLiteral("failed"),
        worked ? QString() : i18nc("@info", "The game still didn't keep running. Undo the change, or try another fix."));
}

bool FixIt::canUndo(const QString &appId) const
{
    return QFileInfo::exists(folder() + QStringLiteral("/undo-%1.json").arg(appId));
}

void FixIt::undo(const QString &appId)
{
    if (!m_settings || m_settings->steamRunning()) {
        return;
    }
    const QString path = folder() + QStringLiteral("/undo-%1.json").arg(appId);
    const Undo undo = Undo::read(path);
    if (!undo.isValid()) {
        return;
    }
    const SteamLibrary &library = m_settings->library();
    bool ok = library.setCompatTool(appId, undo.tool) && library.setLaunchOptions(appId, undo.launchOptions);
    if (!undo.shaderCacheMovedTo.isEmpty() && QFileInfo(undo.shaderCacheMovedTo).isDir()) {
        // Steam built a new cache since; the old one goes back in its place.
        QDir(undo.shaderCache).removeRecursively();
        ok = QDir().rename(undo.shaderCacheMovedTo, undo.shaderCache) && ok;
    }
    if (!ok) {
        setState(QStringLiteral("failed"), i18nc("@info", "Steam's settings couldn't be changed. Start Steam once, close it, then try again."));
        return;
    }
    QFile::remove(path);
    m_appId = appId;
    m_causes.clear();
    m_settings->reload();
    setState(QStringLiteral("undone"));
}

} // namespace OrielOSGames
