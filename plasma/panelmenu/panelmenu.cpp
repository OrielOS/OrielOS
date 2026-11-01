// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include <KIO/ApplicationLauncherJob>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KService>
#include <Plasma/ContainmentActions>

#include <QAction>
#include <QDesktopServices>
#include <QUrl>

namespace OrielOSPanelMenu {

/**
 * The taskbar's right-click menu, as in Windows 11: System Monitor and Taskbar settings, and
 * nothing else. Plasma's own panel menu (adding widgets, edit mode) stays in the desktop's
 * Show more options.
 */
class PanelMenu : public Plasma::ContainmentActions
{
    Q_OBJECT

public:
    PanelMenu(QObject *parent, const QVariantList &args)
        : Plasma::ContainmentActions(parent, args)
    {
        m_systemMonitor = new QAction(QIcon::fromTheme(QStringLiteral("utilities-system-monitor")), i18nc("@action:inmenu", "System Monitor"), this);
        connect(m_systemMonitor, &QAction::triggered, this, []() {
            const KService::Ptr service = KService::serviceByDesktopName(QStringLiteral("org.kde.plasma-systemmonitor"));
            if (service) {
                (new KIO::ApplicationLauncherJob(service))->start();
            }
        });
        m_settings = new QAction(QIcon::fromTheme(QStringLiteral("orielos-settings-symbolic")), i18nc("@action:inmenu", "Taskbar settings"), this);
        connect(m_settings, &QAction::triggered, this, []() { QDesktopServices::openUrl(QUrl(QStringLiteral("orielos-settings:taskbar"))); });
    }

    QList<QAction *> contextualActions() override { return { m_systemMonitor, m_settings }; }

private:
    QAction *m_systemMonitor = nullptr;
    QAction *m_settings = nullptr;
};

} // namespace OrielOSPanelMenu

K_PLUGIN_CLASS_WITH_JSON(OrielOSPanelMenu::PanelMenu, "panelmenu.json")

#include "panelmenu.moc"
