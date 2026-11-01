// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatenotifier.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KNotification>
#include <KSharedConfig>
#include <KStatusNotifierItem>

#include <QAction>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QFile>
#include <QFileInfo>
#include <QMenu>
#include <QProcess>
#include <QProcessEnvironment>

namespace UpdateNotifier {

namespace {

constexpr auto iconName = "system-software-update";
// The Update settings page, a Plasma settings module that System Settings opens by its name.
constexpr auto settingsModule = "kcm_orielos_update";

QString readBootId(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return { };
    }
    return QString::fromLatin1(file.readAll()).trimmed();
}

} // namespace

Notifier::Notifier(const QString &statePath, const QString &bootIdPath, QObject *parent)
    : QObject(parent)
    , m_statePath(statePath)
    , m_bootId(readBootId(bootIdPath))
{
    // orielos-update replaces the file in one step, which drops it from the watch list, so the
    // folder is watched too and the file is added back after every change. A slow periodic read
    // covers a folder that doesn't exist yet.
    m_reloadDelay.setSingleShot(true);
    m_reloadDelay.setInterval(200);
    connect(&m_reloadDelay, &QTimer::timeout, this, &Notifier::reload);
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, &m_reloadDelay, qOverload<>(&QTimer::start));
    m_periodicReload.setInterval(5 * 60 * 1000);
    connect(&m_periodicReload, &QTimer::timeout, this, &Notifier::reload);
    m_periodicReload.start();

    reload();
}

void Notifier::createItem()
{
    m_item = new KStatusNotifierItem(QStringLiteral("org.orielos.UpdateNotifier"), this);
    m_item->setCategory(KStatusNotifierItem::SystemServices);
    m_item->setStatus(KStatusNotifierItem::Active);
    m_item->setTitle(i18nc("@title The tray icon's name", "OrielOS updates"));
    m_item->setIconByName(QLatin1String(iconName));
    m_item->setToolTipIconByName(QLatin1String(iconName));
    m_item->setToolTipTitle(i18nc("@title The tray icon's name", "OrielOS updates"));
    // Updates run as long as the computer does; there is nothing to quit.
    m_item->setStandardActionsEnabled(false);
    // The item deletes its menu with itself.
    m_item->setContextMenu(buildMenu());
    connect(m_item, &KStatusNotifierItem::activateRequested, this, &Notifier::openSettings);
}

void Notifier::removeItem()
{
    delete m_item;
    m_item = nullptr;
    m_restartAction = nullptr;
}

void Notifier::watchStateFile()
{
    const QString folder = QFileInfo(m_statePath).absolutePath();
    if (!m_watcher.directories().contains(folder) && QFileInfo::exists(folder)) {
        m_watcher.addPath(folder);
    }
    if (!m_watcher.files().contains(m_statePath) && QFileInfo::exists(m_statePath)) {
        m_watcher.addPath(m_statePath);
    }
}

void Notifier::reload()
{
    watchStateFile();
    m_state = OrielOSUpdates::UpdateState::fromFile(m_statePath);
    updateItem();
    if (m_state.goingBack(m_bootId)) {
        if (m_state.previous()->digest != m_announcedGoBackDigest) {
            showGoBackNotification();
        }
    } else if (m_state.updateWaiting(m_bootId) && m_state.staged()->digest != m_announcedDigest) {
        showReadyNotification();
    } else if (m_state.updateUndone(m_bootId) && !m_announcedUndone) {
        showUndoneNotification();
    }
    // An undone update means the version running is the old one, with nothing new to show.
    if (m_state.isForThisBoot(m_bootId) && !m_state.updateUndone(m_bootId)) {
        showInstalledNotification();
    }
}

void Notifier::showInstalledNotification()
{
    // Once per version and person: the version last seen is kept in their own settings. A new
    // account, which saw none, starts from the version it first sees, with nothing to announce.
    const QString version = m_state.running().version;
    KConfigGroup seen(KSharedConfig::openConfig(QStringLiteral("orielos-update-notifierrc")), QStringLiteral("General"));
    const QString last = seen.readEntry("lastVersion", QString());
    if (version.isEmpty() || version == QLatin1String("unknown") || version == last) {
        return;
    }
    seen.writeEntry("lastVersion", version);
    seen.sync();
    if (last.isEmpty()) {
        return;
    }
    auto *notification = new KNotification(QStringLiteral("updateInstalled"));
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QLatin1String(iconName));
    notification->setTitle(i18nc("@title", "OrielOS was updated"));
    notification->setText(i18nc("@info %1 is a version such as v0.2.0", "OrielOS %1 is running now.", version));
    KNotificationAction *whatsNew = notification->addAction(i18nc("@action:button", "See what's new"));
    connect(whatsNew, &KNotificationAction::activated, this, &Notifier::openSettings);
    notification->sendEvent();
}

QMenu *Notifier::buildMenu()
{
    auto *menu = new QMenu;

    m_restartAction = menu->addAction(QIcon::fromTheme(QStringLiteral("system-reboot")), i18nc("@action:inmenu", "Restart to update"));
    connect(m_restartAction, &QAction::triggered, this, &Notifier::restart);
    menu->addSeparator();

    QAction *settings = menu->addAction(QIcon::fromTheme(QLatin1String(iconName)), i18nc("@action:inmenu", "Open update settings"));
    connect(settings, &QAction::triggered, this, &Notifier::openSettings);

    return menu;
}

void Notifier::updateItem()
{
    const bool waiting = m_state.updateWaiting(m_bootId);
    const bool goingBack = m_state.goingBack(m_bootId);

    // No icon until there's something to restart for, and none once it's done: the Update settings
    // page has the rest.
    if (!waiting && !goingBack) {
        removeItem();
        return;
    }
    if (!m_item) {
        createItem();
    }
    m_item->setToolTipSubTitle(OrielOSUpdates::statusText(m_state, m_bootId, QDateTime::currentDateTimeUtc()));
    m_restartAction->setText(goingBack ? i18nc("@action:inmenu", "Restart to go back") : i18nc("@action:inmenu", "Restart to update"));
}

void Notifier::showReadyNotification()
{
    if (m_readyNotification) {
        m_readyNotification->close();
    }
    const OrielOSUpdates::Build staged = *m_state.staged();
    m_announcedDigest = staged.digest;

    auto *notification = new KNotification(QStringLiteral("updateReady"), KNotification::Persistent);
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QLatin1String(iconName));
    notification->setTitle(i18nc("@title", "Restart to update"));
    notification->setText(i18nc("@info", "OrielOS %1 is ready. Restart to finish updating. Your files and apps stay as they are.", staged.version));
    KNotificationAction *restart = notification->addAction(i18nc("@action:button", "Restart to update"));
    connect(restart, &KNotificationAction::activated, this, &Notifier::restart);
    // Settings' Update page schedules the restart.
    KNotificationAction *pick = notification->addAction(i18nc("@action:button", "Pick a time"));
    connect(pick, &KNotificationAction::activated, this, &Notifier::openSettings);
    KNotificationAction *later = notification->addAction(i18nc("@action:button", "Later"));
    connect(later, &KNotificationAction::activated, notification, &KNotification::close);
    m_readyNotification = notification;
    notification->sendEvent();
}

void Notifier::showGoBackNotification()
{
    if (m_goBackNotification) {
        m_goBackNotification->close();
    }
    const OrielOSUpdates::Build previous = *m_state.previous();
    m_announcedGoBackDigest = previous.digest;

    auto *notification = new KNotification(QStringLiteral("goBackReady"), KNotification::Persistent);
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QLatin1String(iconName));
    notification->setTitle(i18nc("@title", "Restart to go back"));
    notification->setText(i18nc("@info", "OrielOS %1 starts after a restart. Your files and apps stay as they are.", previous.version));
    KNotificationAction *restart = notification->addAction(i18nc("@action:button", "Restart to go back"));
    connect(restart, &KNotificationAction::activated, this, &Notifier::restart);
    KNotificationAction *later = notification->addAction(i18nc("@action:button", "Later"));
    connect(later, &KNotificationAction::activated, notification, &KNotification::close);
    m_goBackNotification = notification;
    notification->sendEvent();
}

void Notifier::showUndoneNotification()
{
    m_announcedUndone = true;
    // It stays until it's dismissed: the undo happened at startup, perhaps with nobody watching.
    auto *notification = new KNotification(QStringLiteral("updateUndone"), KNotification::Persistent);
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QLatin1String(iconName));
    notification->setTitle(i18nc("@title", "The update was undone"));
    // orielos-update's message names the version that didn't start and the one running now.
    notification->setText(m_state.message());
    notification->sendEvent();
}

void Notifier::restart()
{
    // Plasma signs out cleanly, saving the session, then restarts; bootc finishes switching to the
    // staged or the previous build while the computer shuts down.
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot"));
    QDBusConnection::sessionBus().asyncCall(message);
}

void Notifier::openSettings()
{
    // Settings opens the page in its own window, or in the window it already has. The tray passes
    // an activation token with the click, so the window gets the focus.
    QProcess process;
    process.setProgram(QStringLiteral("orielos-settings"));
    process.setArguments({ QLatin1String(settingsModule) });
    const QString token = m_item ? m_item->providedToken() : QString();
    if (!token.isEmpty()) {
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert(QStringLiteral("XDG_ACTIVATION_TOKEN"), token);
        process.setProcessEnvironment(environment);
    }
    process.startDetached();
}

} // namespace UpdateNotifier
