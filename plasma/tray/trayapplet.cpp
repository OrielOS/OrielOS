// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "drives.h"
#include "traylogic.h"

#include <KPluginFactory>
#include <Plasma/Applet>
#include <Plasma/Containment>

#include <QDBusConnection>
#include <QDBusMessage>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>

namespace {

const QString plasmaTrayId = QStringLiteral("org.kde.plasma.systemtray");

// Where a point of an item is on the screen, as Plasma's tray works it out for an app's menu.
QPoint screenPosition(QQuickItem *item, qreal x, qreal y)
{
    if (!item || !item->window()) {
        return { };
    }
    return item->window()->mapToGlobal(item->mapToScene(QPointF(x, y)).toPoint());
}

} // namespace

/**
 * The tray's applet. Its QML draws the apps' icons from Plasma's status notifier model; this class
 * keeps Plasma's own tray on the same taskbar hidden and hands it the clicks, scrolls and menus,
 * which it already knows how to do for every kind of tray icon (including the apps that draw
 * their menus over D-Bus), decides which icons go on the taskbar, and runs the eject menu.
 */
class TrayApplet : public Plasma::Applet
{
    Q_OBJECT
    Q_PROPERTY(QVariantList drives READ drives NOTIFY drivesChanged)

public:
    TrayApplet(QObject *parent, const KPluginMetaData &data, const QVariantList &args)
        : Plasma::Applet(parent, data, args)
    {
        connect(&m_drives, &Drives::changed, this, &TrayApplet::drivesChanged);
    }

    void init() override
    {
        Plasma::Applet::init();
        connect(this, &Plasma::Applet::containmentChanged, this, &TrayApplet::watchContainment);
        watchContainment();
    }

    QVariantList drives() const { return m_drives.list(); }

    // Which icons go on the taskbar and which in the pane, as { taskbar, pane }.
    Q_INVOKABLE QVariantMap split(const QStringList &present, const QStringList &passive, const QStringList &shown) const
    {
        const Tray::Split result = Tray::split(present, passive, shown);
        return { { QStringLiteral("taskbar"), result.taskbar }, { QStringLiteral("pane"), result.pane } };
    }
    Q_INVOKABLE QStringList showAt(const QStringList &shown, const QString &id, int index) const { return Tray::showAt(shown, id, index); }
    Q_INVOKABLE QStringList hide(const QStringList &shown, const QString &id) const { return Tray::hide(shown, id); }

    // A click on an app's icon. Without Plasma's tray, the app is asked over D-Bus directly.
    Q_INVOKABLE void activate(const QString &service, QQuickItem *icon)
    {
        const QPoint position = screenPosition(icon, icon ? icon->width() / 2 : 0, icon ? icon->height() / 2 : 0);
        if (m_plasmaTray) {
            QMetaObject::invokeMethod(m_plasmaTray, "activate", Q_ARG(QString, service), Q_ARG(QPoint, position), Q_ARG(QQuickItem *, icon));
            return;
        }
        const qsizetype slash = service.indexOf(QLatin1Char('/'));
        QDBusMessage message = QDBusMessage::createMethodCall(slash > 0 ? service.left(slash) : service,
            slash > 0 ? service.mid(slash) : QStringLiteral("/StatusNotifierItem"), QStringLiteral("org.kde.StatusNotifierItem"), QStringLiteral("Activate"));
        message.setArguments({ position.x(), position.y() });
        QDBusConnection::sessionBus().send(message);
    }

    Q_INVOKABLE void openMenu(const QString &service, QQuickItem *icon, qreal x, qreal y)
    {
        if (m_plasmaTray) {
            QMetaObject::invokeMethod(
                m_plasmaTray, "openContextMenu", Q_ARG(QString, service), Q_ARG(QPoint, screenPosition(icon, x, y)), Q_ARG(QQuickItem *, icon));
        }
    }

    Q_INVOKABLE void secondaryActivate(const QString &service, QQuickItem *icon)
    {
        if (m_plasmaTray) {
            QMetaObject::invokeMethod(m_plasmaTray, "secondaryActivate", Q_ARG(QString, service),
                Q_ARG(QPoint, screenPosition(icon, icon ? icon->width() / 2 : 0, icon ? icon->height() / 2 : 0)));
        }
    }

    Q_INVOKABLE void scroll(const QString &service, int delta, const QString &direction)
    {
        if (m_plasmaTray) {
            QMetaObject::invokeMethod(m_plasmaTray, "scroll", Q_ARG(QString, service), Q_ARG(int, delta), Q_ARG(QString, direction));
        }
    }

    Q_INVOKABLE void eject(const QString &udi) { m_drives.eject(udi); }

Q_SIGNALS:
    void drivesChanged();

private:
    void watchContainment()
    {
        if (m_containment == containment()) {
            return;
        }
        if (m_containment) {
            disconnect(m_containment, nullptr, this, nullptr);
        }
        m_containment = containment();
        if (m_containment) {
            connect(m_containment, &Plasma::Containment::appletAdded, this, &TrayApplet::findPlasmaTray);
            connect(m_containment, &Plasma::Containment::appletRemoved, this, &TrayApplet::findPlasmaTray);
        }
        findPlasmaTray();
    }

    void findPlasmaTray()
    {
        Plasma::Applet *found = nullptr;
        if (m_containment) {
            const QList<Plasma::Applet *> applets = m_containment->applets();
            for (Plasma::Applet *applet : applets) {
                if (applet->pluginName() == plasmaTrayId) {
                    found = applet;
                    break;
                }
            }
        }
        if (found == m_plasmaTray) {
            return;
        }
        if (m_plasmaTray) {
            disconnect(m_plasmaTray, nullptr, this, nullptr);
        }
        m_plasmaTray = found;
        if (m_plasmaTray) {
            // Plasma's tray sets its own status when one of its widgets opens or closes; the panel
            // shows it again unless it goes straight back to hidden.
            connect(m_plasmaTray, &Plasma::Applet::statusChanged, this, [this] {
                QTimer::singleShot(0, this, &TrayApplet::keepPlasmaTrayHidden);
            });
            keepPlasmaTrayHidden();
        }
    }

    void keepPlasmaTrayHidden()
    {
        if (m_plasmaTray && m_plasmaTray->status() != Plasma::Types::HiddenStatus) {
            m_plasmaTray->setStatus(Plasma::Types::HiddenStatus);
        }
    }

    QPointer<Plasma::Containment> m_containment;
    QPointer<Plasma::Applet> m_plasmaTray;
    Drives m_drives;
};

K_PLUGIN_CLASS_WITH_JSON(TrayApplet, "metadata.json")

#include "trayapplet.moc"
