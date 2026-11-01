// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <PolkitQt1/Agent/Listener>
#include <PolkitQt1/Agent/Session>
#include <PolkitQt1/Details>
#include <PolkitQt1/Identity>

#include <QObject>
#include <QPointer>
#include <QStringList>
#include <qqmlintegration.h>

// OrielOS's polkit authentication agent: answers polkit's requests for an administrator's
// password (or PIN, or fingerprint, through the PAM stack) with Windows' prompt. One request at a
// time; the prompt window reads this object's properties.
class Agent : public PolkitQt1::Agent::Listener
{
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("The agent is made by main()")

    // Whether a request is open, so the prompt shows.
    Q_PROPERTY(bool asking READ isAsking NOTIFY changed FINAL)
    Q_PROPERTY(QString name READ name NOTIFY changed FINAL)
    Q_PROPERTY(QString iconName READ iconName NOTIFY changed FINAL)
    Q_PROPERTY(QString publisher READ publisher NOTIFY changed FINAL)
    Q_PROPERTY(bool verified READ isVerified NOTIFY changed FINAL)
    Q_PROPERTY(QString program READ program NOTIFY changed FINAL)
    Q_PROPERTY(QString commandLine READ commandLine NOTIFY changed FINAL)
    Q_PROPERTY(QString actionId READ actionId NOTIFY changed FINAL)
    Q_PROPERTY(QString message READ message NOTIFY changed FINAL)
    // The account whose password is asked for.
    Q_PROPERTY(QString account READ account NOTIFY changed FINAL)
    // What PAM asks for ("Password:", the PIN prompt…), and whether its answer may show.
    Q_PROPERTY(QString prompt READ prompt NOTIFY changed FINAL)
    Q_PROPERTY(bool echo READ echo NOTIFY changed FINAL)
    // Waiting for an answer from the user, rather than for PAM.
    Q_PROPERTY(bool waitingForAnswer READ isWaitingForAnswer NOTIFY changed FINAL)
    // PAM's messages, and why the last try failed.
    Q_PROPERTY(QString info READ info NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    explicit Agent(QObject *parent = nullptr);

    bool isAsking() const { return m_result != nullptr; }
    QString name() const { return m_name; }
    QString iconName() const { return m_iconName; }
    QString publisher() const { return m_publisher; }
    bool isVerified() const { return m_verified; }
    QString program() const { return m_program; }
    QString commandLine() const { return m_commandLine; }
    QString actionId() const { return m_actionId; }
    QString message() const { return m_message; }
    QString account() const;
    QString prompt() const { return m_prompt; }
    bool echo() const { return m_echo; }
    bool isWaitingForAnswer() const { return m_waitingForAnswer; }
    QString info() const { return m_info; }
    QString error() const { return m_error; }

    // Yes, with what was typed.
    Q_INVOKABLE void answer(const QString &response);
    // No, or Escape.
    Q_INVOKABLE void refuse();

public Q_SLOTS:
    void initiateAuthentication(const QString &actionId, const QString &message, const QString &iconName, const PolkitQt1::Details &details,
        const QString &cookie, const PolkitQt1::Identity::List &identities, PolkitQt1::Agent::AsyncResult *result) override;
    bool initiateAuthenticationFinish() override;
    void cancelAuthentication() override;

Q_SIGNALS:
    void changed();

private:
    void startSession();
    void finish();

    PolkitQt1::Agent::AsyncResult *m_result = nullptr;
    QPointer<PolkitQt1::Agent::Session> m_session;
    PolkitQt1::Identity m_identity;
    QString m_cookie;
    QString m_actionId;
    QString m_message;
    QString m_name;
    QString m_iconName;
    QString m_publisher;
    bool m_verified = false;
    QString m_program;
    QString m_commandLine;
    QString m_prompt;
    bool m_echo = false;
    bool m_waitingForAnswer = false;
    bool m_refused = false;
    QString m_info;
    QString m_error;
};
