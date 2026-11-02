// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "runner.h"

#include "runapp.h"

#include <KFormat>
#include <KLocalizedString>

#include <QDesktopServices>
#include <QDir>
#include <QCoreApplication>
#include <QSaveFile>
#include <QJsonObject>
#include <QJsonDocument>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QNetworkAccessManager>
#include <QFileInfo>
#include <QProcessEnvironment>
#include <QSettings>
#include <QStandardPaths>
#include <QUrl>

#include <chrono>

using namespace OrielOSRunApp;

namespace {

// How often the prefix is looked at for new shortcuts while the program runs: an installer that
// starts its program straight away keeps running, so its entries shouldn't wait for it to close.
constexpr std::chrono::seconds scanInterval { 5 };

} // namespace

namespace {

// Where the copy of the known-apps list fetched from OrielOS's repository is kept.
QString knownAppsCache()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + QStringLiteral("/orielos/known-apps.json");
}

// Fetches the newest known-apps list in the background for next time; the image's copy covers
// the time until then, and being offline.
void refreshKnownApps()
{
    static QNetworkAccessManager *network = new QNetworkAccessManager(QCoreApplication::instance());
    QNetworkRequest request(QUrl(QStringLiteral("https://raw.githubusercontent.com/OrielOS/OrielOS/main/data/known-apps.json")));
    request.setTransferTimeout(10000);
    QNetworkReply *reply = network->get(request);
    QObject::connect(reply, &QNetworkReply::finished, reply, [reply] {
        reply->deleteLater();
        const QByteArray data = reply->readAll();
        if (reply->error() != QNetworkReply::NoError || !QJsonDocument::fromJson(data).object().value(QLatin1String("apps")).isArray()) {
            return;
        }
        QDir().mkpath(QFileInfo(knownAppsCache()).absolutePath());
        QSaveFile file(knownAppsCache());
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.commit();
        }
    });
}

} // namespace

Runner::Runner(const QString &filePath, const QString &dataHome, const QString &stateHome, const QString &applicationsDir, QObject *parent)
    : QObject(parent)
    , m_filePath(QFileInfo(filePath).absoluteFilePath())
    , m_dataHome(dataHome)
    , m_stateHome(stateHome)
    , m_applicationsDir(applicationsDir)
    , m_name(prefixName(filePath))
    , m_source(downloadSource(filePath))
    , m_firstDownload(needsFirstDownload(dataHome))
    , m_known(knownApp(knownAppsList(knownAppsCache(), QStringLiteral("/usr/share/orielos/known-apps.json")), filePath))
{
    refreshKnownApps();
    m_scan.setInterval(scanInterval);
    connect(&m_scan, &QTimer::timeout, this, &Runner::addShortcuts);
    connect(&m_process, &QProcess::finished, this, &Runner::finish);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_scan.stop();
            m_stage = Finished;
            m_failed = true;
            m_error = i18nc("@info", "Windows programs can't be run: umu-launcher didn't start.");
            Q_EMIT changed();
        }
    });
}

QString Runner::fileName() const
{
    return QFileInfo(m_filePath).fileName();
}

QString Runner::programName() const
{
    return QFileInfo(m_filePath).completeBaseName();
}

QString Runner::sourceUrl() const
{
    return m_source.url;
}

QString Runner::sourceHost() const
{
    return m_source.host;
}

QString Runner::size() const
{
    return KFormat().formatByteSize(QFileInfo(m_filePath).size());
}

bool Runner::msi() const
{
    return m_filePath.endsWith(QLatin1String(".msi"), Qt::CaseInsensitive);
}

Runner::Stage Runner::stage() const
{
    return m_stage;
}

bool Runner::firstDownload() const
{
    return m_firstDownload;
}

QStringList Runner::added() const
{
    return m_added;
}

bool Runner::failed() const
{
    return m_failed;
}

QString Runner::error() const
{
    return m_error;
}

bool Runner::canAddItself() const
{
    return m_stage == Finished && !m_failed && m_added.isEmpty() && !looksLikeInstaller(m_filePath);
}

QString Runner::appSource() const
{
    // Settings' Installed apps page keeps the choice in orielos-appsrc, [General] source=.
    const QSettings settings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/orielos-appsrc"), QSettings::IniFormat);
    const QString source = settings.value(QStringLiteral("source")).toString();
    return source == QLatin1String("suggest") || source == QLatin1String("store") ? source : QStringLiteral("anywhere");
}

void Runner::run()
{
    if (m_stage != Confirm || appSource() == QLatin1String("store") || package()) {
        return;
    }
    const QString prefix = prefixDir(m_dataHome, m_name);
    const QString log = logFile(m_stateHome, m_name);
    QDir().mkpath(prefix);
    QDir().mkpath(QFileInfo(log).absolutePath());

    const Command cmd = command(prefix, m_filePath);
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    for (auto it = cmd.environment.cbegin(); it != cmd.environment.cend(); ++it) {
        environment.insert(it.key(), it.value());
    }
    m_process.setProcessEnvironment(environment);
    m_process.setWorkingDirectory(QFileInfo(m_filePath).absolutePath());
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    m_process.setStandardOutputFile(log, QIODevice::Append);
    m_stage = Running;
    Q_EMIT changed();
    m_process.start(cmd.program, cmd.arguments);
    m_scan.start();
}

void Runner::addShortcuts()
{
    const QList<Shortcut> shortcuts = findShortcuts(prefixDir(m_dataHome, m_name));
    bool more = false;
    for (const Shortcut &shortcut : shortcuts) {
        if (m_targets.contains(shortcut.target)) {
            continue;
        }
        if (!writeStartEntry(m_applicationsDir, m_name, shortcut).isEmpty()) {
            m_targets.insert(shortcut.target);
            m_added.append(shortcut.name);
            more = true;
        }
    }
    if (more) {
        Q_EMIT changed();
    }
}

void Runner::finish(int exitCode, QProcess::ExitStatus status)
{
    m_scan.stop();
    addShortcuts();
    m_stage = Finished;
    if ((status != QProcess::NormalExit || exitCode != 0) && m_added.isEmpty()) {
        m_failed = true;
        m_error = i18nc("@info %1 is a program", "%1 closed with an error.", programName());
    }
    Q_EMIT changed();
}

void Runner::addItself()
{
    if (!canAddItself()) {
        return;
    }
    if (!writeStartEntry(m_applicationsDir, m_name, { programName(), m_filePath, { } }).isEmpty()) {
        m_targets.insert(m_filePath);
        m_added.append(programName());
        Q_EMIT changed();
    }
}

void Runner::openLog() const
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(logFile(m_stateHome, m_name)));
}
