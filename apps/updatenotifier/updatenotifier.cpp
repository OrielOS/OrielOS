// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "updatenotifier.h"

#include <KGuiItem>
#include <KLocalizedString>
#include <KMessageBox>
#include <KNotification>
#include <KStandardGuiItem>
#include <KStatusNotifierItem>

#include <QAction>
#include <QActionGroup>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCall>
#include <QFile>
#include <QFileInfo>
#include <QMenu>
#include <QProcess>
#include <QScopedValueRollback>

namespace UpdateNotifier {

namespace {

constexpr auto iconName = "system-software-update";
constexpr auto updateTool = "/usr/bin/orielos-update";
// pkexec exits with these when the user cancels the password dialog or isn't allowed; neither is
// worth a second message.
constexpr int pkexecDismissed = 126;
constexpr int pkexecNotAuthorised = 127;

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
    m_item = new KStatusNotifierItem(QStringLiteral("org.orielos.UpdateNotifier"), this);
    m_item->setCategory(KStatusNotifierItem::SystemServices);
    m_item->setTitle(i18nc("@title The tray icon's name", "OrielOS updates"));
    m_item->setIconByName(QLatin1String(iconName));
    m_item->setToolTipIconByName(QLatin1String(iconName));
    m_item->setToolTipTitle(i18nc("@title The tray icon's name", "OrielOS updates"));
    // Updates run as long as the computer does; there is nothing to quit.
    m_item->setStandardActionsEnabled(false);
    m_item->setContextMenu(buildMenu());
    connect(m_item, &KStatusNotifierItem::activateRequested, this, [this] {
        if (m_state.goingBack(m_bootId)) {
            showGoBackNotification();
        } else if (m_state.updateWaiting(m_bootId)) {
            showReadyNotification();
        }
    });

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
    m_state = UpdateState::fromFile(m_statePath);
    updateItem();
    if (m_state.goingBack(m_bootId)) {
        if (m_state.previous()->digest != m_announcedGoBackDigest) {
            showGoBackNotification();
        }
    } else if (m_state.updateWaiting(m_bootId) && m_state.staged()->digest != m_announcedDigest) {
        showReadyNotification();
    }
}

QMenu *Notifier::buildMenu()
{
    auto *menu = new QMenu;

    m_restartAction = menu->addAction(QIcon::fromTheme(QStringLiteral("system-reboot")), i18nc("@action:inmenu", "Restart to update"));
    connect(m_restartAction, &QAction::triggered, this, &Notifier::restart);
    menu->addSeparator();

    QAction *check = menu->addAction(QIcon::fromTheme(QStringLiteral("view-refresh")), i18nc("@action:inmenu", "Check for updates"));
    connect(check, &QAction::triggered, this, [this] { runUpdateCommand({ QStringLiteral("check-now") }); });

    m_goBackAction = menu->addAction(QIcon::fromTheme(QStringLiteral("edit-undo")), i18nc("@action:inmenu", "Go back to the previous version…"));
    connect(m_goBackAction, &QAction::triggered, this, &Notifier::goBack);

    m_pauseMenu = menu->addMenu(QIcon::fromTheme(QStringLiteral("media-playback-pause")), i18nc("@title:menu", "Pause updates"));
    for (const int weeks : pauseChoices()) {
        QAction *pause = m_pauseMenu->addAction(pauseChoiceLabel(weeks));
        connect(pause, &QAction::triggered, this, [this, weeks] { runUpdateCommand({ QStringLiteral("pause"), QString::number(weeks) }); });
    }

    m_pausedLine = menu->addAction(QString());
    m_pausedLine->setEnabled(false);
    m_resumeAction = menu->addAction(QIcon::fromTheme(QStringLiteral("media-playback-start")), i18nc("@action:inmenu", "Resume updates"));
    connect(m_resumeAction, &QAction::triggered, this, [this] { runUpdateCommand({ QStringLiteral("resume") }); });

    QMenu *channelMenu = menu->addMenu(i18nc("@title:menu", "Update channel"));
    m_channelGroup = new QActionGroup(channelMenu);
    m_channelGroup->setExclusive(true);
    m_stableAction = channelMenu->addAction(channelLabel(Channel::Stable));
    m_testingAction = channelMenu->addAction(channelLabel(Channel::Testing));
    for (QAction *action : { m_stableAction, m_testingAction }) {
        action->setCheckable(true);
        m_channelGroup->addAction(action);
    }
    connect(m_channelGroup, &QActionGroup::triggered, this, [this](QAction *action) {
        const Channel chosen = action == m_testingAction ? Channel::Testing : Channel::Stable;
        if (chosen != m_state.channel()) {
            runUpdateCommand({ QStringLiteral("channel"), channelName(chosen) });
        }
        // Show the saved channel until orielos-update has written the new one.
        updateItem();
    });

    return menu;
}

void Notifier::updateItem()
{
    const QDateTime now = QDateTime::currentDateTimeUtc();
    const bool waiting = m_state.updateWaiting(m_bootId);
    const bool goingBack = m_state.goingBack(m_bootId);
    const bool paused = m_state.isPaused(now);

    // Passive keeps the icon in the tray's hidden area until there is something to do.
    m_item->setStatus(waiting || goingBack ? KStatusNotifierItem::Active : KStatusNotifierItem::Passive);
    m_item->setToolTipSubTitle(statusText(m_state, m_bootId, now));

    m_restartAction->setVisible(waiting || goingBack);
    m_restartAction->setText(goingBack ? i18nc("@action:inmenu", "Restart to go back") : i18nc("@action:inmenu", "Restart to update"));
    m_goBackAction->setVisible(m_state.canGoBack(m_bootId));
    m_pauseMenu->menuAction()->setVisible(!paused);
    m_pausedLine->setVisible(paused);
    m_resumeAction->setVisible(paused);
    if (paused) {
        m_pausedLine->setText(i18nc("@info %1 is a date", "Updates resume on %1", displayDate(m_state.pausedUntil())));
    }
    m_stableAction->setChecked(m_state.channel() == Channel::Stable);
    m_testingAction->setChecked(m_state.channel() == Channel::Testing);
}

void Notifier::showReadyNotification()
{
    if (m_readyNotification) {
        m_readyNotification->close();
    }
    const Build staged = *m_state.staged();
    m_announcedDigest = staged.digest;

    auto *notification = new KNotification(QStringLiteral("updateReady"), KNotification::Persistent);
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QLatin1String(iconName));
    notification->setTitle(i18nc("@title", "Restart to update"));
    notification->setText(i18nc("@info", "OrielOS %1 is ready. Restart to finish updating. Your files and apps stay as they are.", staged.version));
    KNotificationAction *restart = notification->addAction(i18nc("@action:button", "Restart to update"));
    connect(restart, &KNotificationAction::activated, this, &Notifier::restart);
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
    const Build previous = *m_state.previous();
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

void Notifier::showErrorNotification(const QString &title, const QString &detail)
{
    auto *notification = new KNotification(QStringLiteral("settingsFailed"));
    notification->setComponentName(QStringLiteral("orielos-update-notifier"));
    notification->setIconName(QStringLiteral("dialog-error"));
    notification->setTitle(title);
    notification->setText(detail);
    notification->sendEvent();
}

void Notifier::goBack()
{
    // The question runs its own event loop, so the menu can be opened and chosen again meanwhile.
    if (m_askingToGoBack || !m_state.canGoBack(m_bootId)) {
        return;
    }
    const QScopedValueRollback asking(m_askingToGoBack, true);
    const QString previous = m_state.previous()->version;
    const QString running = m_state.running().version;
    // Cancel is the default button: going back replaces the whole system at the next restart.
    const KMessageBox::ButtonCode answer = KMessageBox::questionTwoActions(nullptr,
        i18nc("@info",
            "OrielOS %1 starts after you restart. OrielOS %2, the version running now, won't be offered again; a newer version will be. "
            "Your files and apps stay as they are.",
            previous, running),
        i18nc("@title:window", "Go back to the previous version"), KGuiItem(i18nc("@action:button", "&Go back"), QStringLiteral("edit-undo")),
        KStandardGuiItem::cancel(), QString(), KMessageBox::Options(KMessageBox::Notify | KMessageBox::Dangerous));
    if (answer == KMessageBox::PrimaryAction) {
        runUpdateCommand({ QStringLiteral("rollback") });
    }
}

void Notifier::restart()
{
    // Plasma signs out cleanly, saving the session, then restarts; bootc finishes switching to the
    // staged or the previous build while the computer shuts down.
    const QDBusMessage message = QDBusMessage::createMethodCall(
        QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), QStringLiteral("logoutAndReboot"));
    QDBusConnection::sessionBus().asyncCall(message);
}

void Notifier::runUpdateCommand(const QStringList &arguments)
{
    auto *process = new QProcess(this);
    process->setProgram(QStringLiteral("pkexec"));
    process->setArguments(QStringList { QLatin1String(updateTool) } + arguments);
    const QString title = arguments.value(0) == QLatin1String("rollback") ? i18nc("@title", "Couldn't go back to the previous version")
                                                                          : i18nc("@title", "Couldn't change the update settings");
    connect(process, &QProcess::finished, this, [this, process, title](int exitCode, QProcess::ExitStatus status) {
        process->deleteLater();
        if (status == QProcess::NormalExit && (exitCode == 0 || exitCode == pkexecDismissed || exitCode == pkexecNotAuthorised)) {
            return;
        }
        const QString detail = QString::fromLocal8Bit(process->readAllStandardError()).section(QLatin1Char('\n'), 0, 0).trimmed();
        showErrorNotification(title, detail.isEmpty() ? i18nc("@info", "orielos-update stopped with an error.") : detail);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, title](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            showErrorNotification(title, i18nc("@info", "pkexec couldn't be started."));
        }
    });
    process->start();
}

} // namespace UpdateNotifier
