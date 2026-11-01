// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "agent.h"
#include "promptdetails.h"

#include <KLocalizedString>
#include <PolkitQt1/Authority>
#include <PolkitQt1/Details>

#include <unistd.h>

Agent::Agent(QObject *parent)
    : PolkitQt1::Agent::Listener(parent)
{
}

QString Agent::account() const
{
    return m_identity.isValid() ? m_identity.toString().section(QLatin1Char(':'), 1) : QString();
}

void Agent::initiateAuthentication(const QString &actionId, const QString &message, const QString &iconName, const PolkitQt1::Details &details,
    const QString &cookie, const PolkitQt1::Identity::List &identities, PolkitQt1::Agent::AsyncResult *result)
{
    if (m_result) {
        // polkit sends one request at a time to an agent; refuse a second rather than lose the first.
        result->setError(i18nc("@info", "Another administrator prompt is already open."));
        result->setCompleted();
        return;
    }
    m_result = result;
    m_actionId = actionId;
    m_message = message;
    m_iconName = iconName;
    m_cookie = cookie;
    m_refused = false;
    m_error.clear();
    m_info.clear();

    // The person at the computer, when they may answer; otherwise the first administrator.
    m_identity = identities.value(0);
    const auto self = PolkitQt1::UnixUserIdentity(getuid());
    for (const PolkitQt1::Identity &identity : identities) {
        if (identity.toString() == self.toString()) {
            m_identity = identity;
            break;
        }
    }

    QString description;
    QString vendor;
    const PolkitQt1::ActionDescription::List actions = PolkitQt1::Authority::instance()->enumerateActionsSync();
    for (const PolkitQt1::ActionDescription &action : actions) {
        if (action.actionId() == actionId) {
            description = action.description();
            vendor = action.vendorName();
            break;
        }
    }
    QMap<QString, QString> values;
    for (const QString &key : details.keys()) {
        values.insert(key, details.lookup(key));
    }
    const PromptDetails prompt = PromptDetails::from(actionId, description, vendor, message, values);
    m_name = prompt.name;
    m_publisher = prompt.publisher;
    m_verified = prompt.verified;
    m_program = prompt.program;
    m_commandLine = prompt.commandLine;

    startSession();
    Q_EMIT changed();
}

void Agent::startSession()
{
    if (m_session) {
        m_session->deleteLater();
    }
    m_prompt.clear();
    m_waitingForAnswer = false;
    m_session = new PolkitQt1::Agent::Session(m_identity, m_cookie, nullptr, this);
    connect(m_session, &PolkitQt1::Agent::Session::request, this, [this](const QString &request, bool echo) {
        m_prompt = request;
        m_echo = echo;
        m_waitingForAnswer = true;
        Q_EMIT changed();
    });
    connect(m_session, &PolkitQt1::Agent::Session::showInfo, this, [this](const QString &text) {
        m_info = text;
        Q_EMIT changed();
    });
    connect(m_session, &PolkitQt1::Agent::Session::showError, this, [this](const QString &text) {
        m_error = text;
        Q_EMIT changed();
    });
    connect(m_session, &PolkitQt1::Agent::Session::completed, this, [this](bool gainedAuthorization) {
        if (gainedAuthorization || m_refused || !m_result) {
            finish();
            return;
        }
        // A wrong password or PIN: say so and ask again, as Windows does.
        if (m_error.isEmpty()) {
            m_error = i18nc("@info", "That wasn't right. Try again.");
        }
        startSession();
        Q_EMIT changed();
    });
    m_session->initiate();
}

void Agent::answer(const QString &response)
{
    if (m_session && m_waitingForAnswer) {
        m_waitingForAnswer = false;
        m_error.clear();
        Q_EMIT changed();
        m_session->setResponse(response);
    }
}

void Agent::refuse()
{
    m_refused = true;
    if (m_session) {
        m_session->cancel();
    }
    finish();
}

void Agent::cancelAuthentication()
{
    refuse();
}

bool Agent::initiateAuthenticationFinish()
{
    return true;
}

void Agent::finish()
{
    if (m_session) {
        m_session->deleteLater();
        m_session = nullptr;
    }
    if (m_result) {
        // Either way polkit learns the answer from the helper; completing tells it the agent is done.
        m_result->setCompleted();
        m_result = nullptr;
    }
    m_waitingForAnswer = false;
    m_prompt.clear();
    m_error.clear();
    m_info.clear();
    Q_EMIT changed();
}
