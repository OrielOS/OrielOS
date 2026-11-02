// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "gamesettings.h"

#include "launchoptions.h"

#include <KLocalizedString>

#include <QDate>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QProcess>
#include <QSaveFile>
#include <QStandardPaths>

namespace OrielOSGames {

namespace {

const QString steamApp = QStringLiteral("com.valvesoftware.Steam");
// Flathub's GE-Proton for Steam, where its compatibilitytool.vdf is.
const QStringList extensionFolders = { QStringLiteral("/var/lib/flatpak/runtime/com.valvesoftware.Steam.CompatibilityTool.Proton-GE") };
const QString gamescopeExtension = QStringLiteral("com.valvesoftware.Steam.Utility.gamescope");
const QString bundledAntiCheat = QStringLiteral("/usr/share/orielos/anticheat-games.json");
const QString overrides = QStringLiteral("/usr/share/orielos/will-it-run-overrides.json");

QString antiCheatCache()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/orielos/anticheat-games.json");
}

const QString windowsPrefix = QStringLiteral("windows:");

QString dataHome()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation);
}

QByteArray readFile(const QString &path)
{
    QFile file(path);
    return file.open(QIODevice::ReadOnly) ? file.readAll() : QByteArray();
}

QString runQuietly(const QString &program, const QStringList &arguments, int *exitCode = nullptr)
{
    QProcess process;
    process.start(program, arguments);
    const bool finished = process.waitForFinished(10000);
    if (exitCode) {
        *exitCode = finished && process.exitStatus() == QProcess::NormalExit ? process.exitCode() : -1;
    }
    return QString::fromUtf8(process.readAllStandardOutput());
}

} // namespace

GameSettings::GameSettings(QObject *parent)
    : QObject(parent)
    , m_library(SteamLibrary::defaultRoot())
{
    // Steam is checked every few seconds, so the page knows when changes can be written.
    m_watch.setInterval(3000);
    connect(&m_watch, &QTimer::timeout, this, &GameSettings::checkSteam);
    m_watch.start();
    loadWillItRun();
    fetchWillItRun();
    reload();
}

void GameSettings::loadWillItRun()
{
    // The copy fetched last, else the one in the image, which says when it was taken.
    m_willItRun = WillItRun::fromJson(readFile(antiCheatCache()), readFile(overrides));
    if (m_willItRun.isEmpty()) {
        m_willItRun = WillItRun::fromJson(readFile(bundledAntiCheat), readFile(overrides));
    }
}

void GameSettings::fetchWillItRun()
{
    auto *network = new QNetworkAccessManager(this);
    QNetworkRequest request(QUrl(QStringLiteral("https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json")));
    request.setTransferTimeout(15000);
    QNetworkReply *reply = network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        reply->deleteLater();
        const QByteArray copy
            = reply->error() == QNetworkReply::NoError ? WillItRun::trimmed(reply->readAll(), QDate::currentDate().toString(Qt::ISODate)) : QByteArray();
        if (copy.isEmpty()) {
            return;
        }
        QDir().mkpath(QFileInfo(antiCheatCache()).absolutePath());
        QSaveFile file(antiCheatCache());
        if (file.open(QIODevice::WriteOnly)) {
            file.write(copy);
            file.commit();
        }
        loadWillItRun();
        ++m_revision;
        Q_EMIT changed();
    });
}

QVariantList GameSettings::willItRun(const QString &words) const
{
    QVariantList out;
    for (const Verdict &verdict : m_willItRun.search(words)) {
        static const QStringList statuses = { QStringLiteral("works"), QStringLiteral("blocked"), QStringLiteral("broken"), QStringLiteral("planned") };
        out.append(QVariantMap {
            { QStringLiteral("name"), verdict.name },
            { QStringLiteral("status"), statuses.at(static_cast<int>(verdict.status)) },
            { QStringLiteral("reason"), verdict.reason },
            { QStringLiteral("antiCheats"), verdict.antiCheats.join(QStringLiteral(", ")) },
        });
    }
    return out;
}

void GameSettings::reload()
{
    m_games = m_library.games();
    m_programs = windowsPrograms(QStandardPaths::writableLocation(QStandardPaths::ApplicationsLocation));
    m_tools = m_library.compatTools(extensionFolders);
    m_steamRunning
        = runQuietly(QStringLiteral("flatpak"), { QStringLiteral("ps"), QStringLiteral("--columns=application") }).split(QLatin1Char('\n')).contains(steamApp);
    ++m_revision;
    Q_EMIT changed();
}

void GameSettings::checkSteam()
{
    const bool running
        = runQuietly(QStringLiteral("flatpak"), { QStringLiteral("ps"), QStringLiteral("--columns=application") }).split(QLatin1Char('\n')).contains(steamApp);
    if (running != m_steamRunning) {
        m_steamRunning = running;
        if (!running) {
            // Steam wrote its settings as it quit; read them again.
            reload();
            return;
        }
        ++m_revision;
        Q_EMIT changed();
    }
}

QVariantList GameSettings::games() const
{
    QVariantList out;
    for (const SteamGame &game : m_games) {
        out.append(QVariantMap { { QStringLiteral("appId"), game.appId }, { QStringLiteral("name"), game.name }, { QStringLiteral("art"), game.art },
            { QStringLiteral("icon"), QString() }, { QStringLiteral("windows"), false } });
    }
    for (const WindowsProgram &program : m_programs) {
        out.append(QVariantMap { { QStringLiteral("appId"), QString(windowsPrefix + program.prefix) }, { QStringLiteral("name"), program.name },
            { QStringLiteral("art"), QString() }, { QStringLiteral("icon"), program.icon }, { QStringLiteral("windows"), true } });
    }
    return out;
}

QVariantList GameSettings::tools() const
{
    QVariantList out { QVariantMap {
        { QStringLiteral("id"), QString() }, { QStringLiteral("name"), i18nc("@item:inlistbox", "Steam's default (GE-Proton)") } } };
    for (const CompatTool &tool : m_tools) {
        out.append(QVariantMap { { QStringLiteral("id"), tool.id }, { QStringLiteral("name"), tool.displayName } });
    }
    return out;
}

QVariantMap GameSettings::settingsFor(const QString &appId) const
{
    const bool windows = appId.startsWith(windowsPrefix);
    const GameOptions options = GameOptions::read(windows ? windowsLaunchOptions(dataHome(), appId.mid(windowsPrefix.size())) : m_library.launchOptions(appId));
    return {
        { QStringLiteral("tool"), windows ? QString() : m_library.compatTool(appId) },
        { QStringLiteral("dlssUpgrade"), options.dlssUpgrade },
        { QStringLiteral("waylandHdr"), options.waylandHdr },
        { QStringLiteral("gamescope"), options.gamescope },
        { QStringLiteral("fpsOverlay"), options.fpsOverlay },
        { QStringLiteral("gameMode"), options.gameMode },
        { QStringLiteral("descriptorHeap"), options.descriptorHeap },
    };
}

void GameSettings::setTool(const QString &appId, const QString &toolId)
{
    if (m_steamRunning) {
        return;
    }
    m_error = m_library.setCompatTool(appId, toolId) ? QString()
                                                     : i18nc("@info", "Steam's settings couldn't be changed. Start Steam once, close it, then try again.");
    ++m_revision;
    Q_EMIT changed();
}

void GameSettings::setOption(const QString &appId, const QString &name, bool on)
{
    // Programs installed with Run this app keep their options in a file of their own, which
    // Run this app reads when it starts them; Steam's wait until Steam is closed.
    const bool windows = appId.startsWith(windowsPrefix);
    const QString prefix = appId.mid(windowsPrefix.size());
    if (m_steamRunning && !windows) {
        return;
    }
    const QString current = windows ? windowsLaunchOptions(dataHome(), prefix) : m_library.launchOptions(appId);
    GameOptions options = GameOptions::read(current);
    if (name == QLatin1String("dlssUpgrade")) {
        options.dlssUpgrade = on;
    } else if (name == QLatin1String("waylandHdr")) {
        options.waylandHdr = on;
        // Proton keeps the XWayland driver under gamescope.
        options.gamescope = options.gamescope && !on;
    } else if (name == QLatin1String("gamescope")) {
        options.gamescope = on;
        options.waylandHdr = options.waylandHdr && !on;
    } else if (name == QLatin1String("fpsOverlay")) {
        options.fpsOverlay = on;
    } else if (name == QLatin1String("gameMode")) {
        options.gameMode = on;
    } else if (name == QLatin1String("descriptorHeap")) {
        options.descriptorHeap = on;
    } else {
        return;
    }
    if (windows) {
        m_error = setWindowsLaunchOptions(dataHome(), prefix, options.apply(current)) ? QString() : i18nc("@info", "The program's settings couldn't be saved.");
    } else {
        m_error = m_library.setLaunchOptions(appId, options.apply(current))
            ? QString()
            : i18nc("@info", "Steam's settings couldn't be changed. Start Steam once, close it, then try again.");
    }
    ++m_revision;
    Q_EMIT changed();
}

QString GameSettings::missingAddon(const QString &name) const
{
    int code = 0;
    if (name == QLatin1String("gamescope")) {
        runQuietly(QStringLiteral("flatpak"), { QStringLiteral("info"), gamescopeExtension + QStringLiteral("//stable") }, &code);
        return code == 0 ? QString() : QStringLiteral("gamescope");
    }
    if (name == QLatin1String("fpsOverlay")) {
        const QString status = runQuietly(QStringLiteral("/usr/libexec/orielos/fps-overlay"), { QStringLiteral("status") });
        return status.contains(QLatin1String("steam=needs-addon")) ? QStringLiteral("overlay") : QString();
    }
    return { };
}

void GameSettings::installAddon(const QString &addon)
{
    if (addon == QLatin1String("gamescope")) {
        runDetached(QStringLiteral("flatpak"),
            { QStringLiteral("install"), QStringLiteral("--noninteractive"), QStringLiteral("flathub"), gamescopeExtension + QStringLiteral("//stable") });
    } else if (addon == QLatin1String("overlay")) {
        runDetached(QStringLiteral("/usr/libexec/orielos/fps-overlay"), { QStringLiteral("steam-addon") });
    }
}

void GameSettings::closeSteam()
{
    runDetached(QStringLiteral("flatpak"), { QStringLiteral("run"), steamApp, QStringLiteral("-shutdown") });
}

void GameSettings::runDetached(const QString &program, const QStringList &arguments)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    ++m_revision;
    Q_EMIT changed();
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process](int exitCode, QProcess::ExitStatus status) {
        if (status != QProcess::NormalExit || exitCode != 0) {
            m_error = i18nc("@info", "That didn't work. Check the internet connection and try again.");
        }
        process->deleteLater();
        m_busy = false;
        reload();
    });
    process->start(program, arguments);
}

} // namespace OrielOSGames
