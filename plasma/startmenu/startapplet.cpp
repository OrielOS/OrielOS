// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KGlobalAccel>
#include <KIO/ApplicationLauncherJob>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KService>
#include <KTerminalLauncherJob>
#include <Plasma/Applet>
#include <PlasmaQuick/AppletQuickItem>

#include <QAction>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDesktopServices>
#include <QHash>
#include <QUrl>

namespace {

void callDBus(
    QDBusConnection bus, const QString &service, const QString &path, const QString &interface, const QString &method, const QVariantList &arguments = { })
{
    QDBusMessage message = QDBusMessage::createMethodCall(service, path, interface, method);
    message.setArguments(arguments);
    bus.send(message);
}

void launch(const QString &desktopName)
{
    if (KService::Ptr service = KService::serviceByDesktopName(desktopName)) {
        auto *job = new KIO::ApplicationLauncherJob(service);
        job->start();
    }
}

void openSettings(const QString &page)
{
    QDesktopServices::openUrl(QUrl(QStringLiteral("orielos-settings:") + page));
}

} // namespace

/**
 * The Start button's applet. Besides the menu, which its QML draws, it gives Start Windows' power
 * user menu: Win+X, or a right-click on the Start button, opens PowerUserMenu.qml above the button,
 * with the system's tools and the shut down and sign out choices; this runs the one chosen.
 */
class StartApplet : public Plasma::Applet
{
    Q_OBJECT

public:
    StartApplet(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
        : Plasma::Applet(parent, data, args)
    {
    }

    void init() override
    {
        Plasma::Applet::init();
        auto *shortcut = new QAction(i18nc("@action Global shortcut", "Show the power user menu"), this);
        shortcut->setObjectName(QStringLiteral("power user menu"));
        KGlobalAccel::self()->setDefaultShortcut(shortcut, { QKeySequence(Qt::META | Qt::Key_X) });
        KGlobalAccel::self()->setShortcut(shortcut, { QKeySequence(Qt::META | Qt::Key_X) });
        connect(shortcut, &QAction::triggered, this, &StartApplet::showPowerUserMenu);
    }

    // Opens the menu above the Start button, which the QML draws (PowerUserMenu.qml).
    void showPowerUserMenu()
    {
        if (auto *item = PlasmaQuick::AppletQuickItem::itemForApplet(this)) {
            QMetaObject::invokeMethod(item, "openPowerUserMenu");
        }
    }

    // Runs the menu's item with this id.
    Q_INVOKABLE void activatePowerUserItem(const QString &id)
    {
        const QDBusConnection session = QDBusConnection::sessionBus();
        static const QHash<QString, QString> settingsPages = {
            { QStringLiteral("apps"), QStringLiteral("apps") },
            { QStringLiteral("power"), QStringLiteral("power") },
            { QStringLiteral("system"), QStringLiteral("about") },
            { QStringLiteral("devices"), QStringLiteral("devices") },
            { QStringLiteral("network"), QStringLiteral("network") },
            { QStringLiteral("settings"), QString() },
        };
        static const QHash<QString, QString> apps = {
            { QStringLiteral("terminal"), QStringLiteral("org.kde.konsole") },
            { QStringLiteral("process-manager"), QStringLiteral("org.kde.plasma-systemmonitor") },
            { QStringLiteral("files"), QStringLiteral("org.kde.dolphin") },
        };
        static const QHash<QString, QString> sessionMethods = {
            { QStringLiteral("sign-out"), QStringLiteral("logout") },
            { QStringLiteral("shut-down"), QStringLiteral("logoutAndShutdown") },
            { QStringLiteral("restart"), QStringLiteral("logoutAndReboot") },
        };
        if (settingsPages.contains(id)) {
            openSettings(settingsPages.value(id));
        } else if (apps.contains(id)) {
            launch(apps.value(id));
        } else if (sessionMethods.contains(id)) {
            callDBus(session, QStringLiteral("org.kde.Shutdown"), QStringLiteral("/Shutdown"), QStringLiteral("org.kde.Shutdown"), sessionMethods.value(id));
        } else if (id == QLatin1String("admin-terminal")) {
            // A shell as the administrator, after asking for the password.
            auto *job = new KTerminalLauncherJob(QStringLiteral("run0"));
            job->start();
        } else if (id == QLatin1String("search")) {
            callDBus(session, QStringLiteral("org.kde.plasmashell"), QStringLiteral("/PlasmaShell"), QStringLiteral("org.kde.PlasmaShell"),
                QStringLiteral("activateLauncherMenu"));
        } else if (id == QLatin1String("run")) {
            callDBus(session, QStringLiteral("org.kde.krunner"), QStringLiteral("/App"), QStringLiteral("org.kde.krunner.App"), QStringLiteral("display"));
        } else if (id == QLatin1String("sleep")) {
            callDBus(QDBusConnection::systemBus(), QStringLiteral("org.freedesktop.login1"), QStringLiteral("/org/freedesktop/login1"),
                QStringLiteral("org.freedesktop.login1.Manager"), QStringLiteral("Suspend"), { true });
        } else if (id == QLatin1String("desktop")) {
            callDBus(session, QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/kwin"), QStringLiteral("org.kde.kglobalaccel.Component"),
                QStringLiteral("invokeShortcut"), { QStringLiteral("Show Desktop") });
        }
    }
};

K_PLUGIN_CLASS_WITH_JSON(StartApplet, "metadata.json")

#include "startapplet.moc"
