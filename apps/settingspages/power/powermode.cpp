// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "powermode.h"

#include <KLocalizedString>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

namespace OrielOSSettingsPages {

namespace {

const QString service = QStringLiteral("org.freedesktop.UPower.PowerProfiles");
const QString path = QStringLiteral("/org/freedesktop/UPower/PowerProfiles");
const QString interface = QStringLiteral("org.freedesktop.UPower.PowerProfiles");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

// The power profiles daemon on the system bus. tuned-ppd implements the same interface as
// power-profiles-daemon, and polkit lets the active session switch profiles.
class DBusPowerProfiles : public PowerProfilesBackend
{
    Q_OBJECT

public:
    explicit DBusPowerProfiles(QObject *parent = nullptr)
        : PowerProfilesBackend(parent)
    {
        // The tray's widget, or anything else, may change the mode too.
        QDBusConnection::systemBus().connect(service, path, propertiesInterface, QStringLiteral("PropertiesChanged"), this, SLOT(read()));
    }

    void read() override
    {
        QDBusMessage message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("GetAll"));
        message << interface;
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
            watcher->deleteLater();
            const QDBusPendingReply<QVariantMap> reply = *watcher;
            if (reply.isError()) {
                Q_EMIT stateRead({ });
                return;
            }
            QVariantMap properties = reply.value();
            // Profiles is an array of dictionaries (aa{sv}), which arrives still marshalled.
            const QVariant profiles = properties.value(QStringLiteral("Profiles"));
            if (profiles.canConvert<QDBusArgument>()) {
                QList<QVariantMap> list;
                profiles.value<QDBusArgument>() >> list;
                QVariantList plain;
                for (const QVariantMap &profile : std::as_const(list)) {
                    plain.append(profile);
                }
                properties.insert(QStringLiteral("Profiles"), plain);
            }
            Q_EMIT stateRead(PowerProfilesState::fromProperties(properties));
        });
    }

    void setActive(const QString &profile) override
    {
        QDBusMessage message = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("Set"));
        message << interface << QStringLiteral("ActiveProfile") << QVariant::fromValue(QDBusVariant(profile));
        message.setInteractiveAuthorizationAllowed(true);
        auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
        connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
            watcher->deleteLater();
            Q_EMIT setFinished(!watcher->isError());
        });
    }
};

} // namespace

PowerProfilesState PowerProfilesState::fromProperties(const QVariantMap &properties)
{
    PowerProfilesState state;
    state.available = true;
    state.active = properties.value(QStringLiteral("ActiveProfile")).toString();
    state.degraded = properties.value(QStringLiteral("PerformanceDegraded")).toString();
    for (const QVariant &profile : properties.value(QStringLiteral("Profiles")).toList()) {
        const QString name = profile.toMap().value(QStringLiteral("Profile")).toString();
        if (!name.isEmpty()) {
            state.profiles.append(name);
        }
    }
    return state;
}

PowerMode::PowerMode(QObject *parent)
    : PowerMode(new DBusPowerProfiles(), parent)
{
}

PowerMode::PowerMode(PowerProfilesBackend *backend, QObject *parent)
    : QObject(parent)
    , m_backend(backend)
{
    m_backend->setParent(this);
    connect(m_backend, &PowerProfilesBackend::stateRead, this, [this](const PowerProfilesState &state) {
        m_state = state;
        m_ready = true;
        Q_EMIT changed();
    });
    connect(m_backend, &PowerProfilesBackend::setFinished, this, [this](bool ok) {
        // The daemon took the new mode: show it until the next read says what it is, rather than
        // the old one in between. Refused, the old one shows again.
        if (ok) {
            m_state.active = m_pending;
        }
        m_pending.clear();
        m_error = ok ? QString() : i18nc("@info", "The power mode couldn't be changed.");
        Q_EMIT changed();
        m_backend->read();
    });
    m_backend->read();
}

QVariantList PowerMode::modes() const
{
    struct Mode
    {
        QString id;
        QString name;
        QString description;
    };
    const QList<Mode> all {
        { QStringLiteral("performance"), i18nc("@option:radio A power mode", "Performance"),
            i18nc("@info", "Full speed, with no power saving. OrielOS starts in this mode.") },
        { QStringLiteral("balanced"), i18nc("@option:radio A power mode", "Balanced"), i18nc("@info", "Saves some power when the PC isn't busy.") },
        { QStringLiteral("power-saver"), i18nc("@option:radio A power mode", "Power saver"),
            i18nc("@info", "Saves the most power, so the PC is slower. Useful on battery.") },
    };
    QVariantList out;
    for (const Mode &mode : all) {
        if (m_state.profiles.contains(mode.id)) {
            out.append(QVariantMap {
                { QStringLiteral("id"), mode.id },
                { QStringLiteral("name"), mode.name },
                { QStringLiteral("description"), mode.description },
            });
        }
    }
    return out;
}

void PowerMode::setActive(const QString &profile)
{
    if (!m_state.available || !m_pending.isEmpty() || profile == active() || !m_state.profiles.contains(profile)) {
        return;
    }
    m_pending = profile;
    m_error.clear();
    Q_EMIT changed();
    m_backend->setActive(profile);
}

QString PowerMode::degraded() const
{
    if (m_state.degraded.isEmpty()) {
        return { };
    }
    if (m_state.degraded == QLatin1String("lap-detected")) {
        return i18nc("@info", "Performance is held back because the computer seems to be on your lap.");
    }
    if (m_state.degraded == QLatin1String("high-operating-temperature")) {
        return i18nc("@info", "Performance is held back because the computer is too hot.");
    }
    return i18nc("@info %1 is the reason the system gives", "Performance is held back by the system (%1).", m_state.degraded);
}

} // namespace OrielOSSettingsPages

#include "powermode.moc"
