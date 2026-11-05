// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QByteArray>
#include <QList>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <qqmlintegration.h>

#include <functional>
#include <optional>

namespace OrielOSNetwork {

// One line network-check prints as a check finishes.
struct CheckResult
{
    enum class Result {
        Ok,
        Problem,
        // An earlier check found the problem, so this one didn't run.
        Skipped,
    };

    // adapter, radio, connected, address, gateway, dns or internet.
    QString check;
    Result result = Result::Skipped;
    // What it found, such as wifi-off, for the app's own words.
    QString reason;
    // The same in English, for when the app has no words for the reason.
    QString message;
    // The fix network-check offers, such as wifi-on, or empty.
    QString fix;

    // Reads one line; anything that isn't a result, or whose result isn't ok, problem or skipped,
    // reads as nothing.
    static std::optional<CheckResult> parse(const QByteArray &line);
    // Takes every complete line from the front of the buffer and reads it; a line still being
    // written stays in the buffer for the next call.
    static QList<CheckResult> takeLines(QByteArray &buffer);
};

// The network troubleshooter's window model. It runs network-check, which checks each part of the
// connection in turn, from the network adapter to the internet, and shows each result as it comes;
// the first problem comes with a fix when there's one. Fixes run as the signed-in user through
// network-check, except restarting NetworkManager, which goes through pkexec. After a fix, the
// checks run again by themselves. Every string is ready to show.
class NetworkCheck : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // { id, title, state, detail } for each check, in order. state is pending, running, ok,
    // problem or skipped; detail is what it found, in a few words.
    Q_PROPERTY(QVariantList checks READ checks NOTIFY changed FINAL)
    Q_PROPERTY(bool running READ isRunning NOTIFY changed FINAL)
    // A fix is being applied; only one runs at a time.
    Q_PROPERTY(bool fixing READ isFixing NOTIFY changed FINAL)
    // The checks have finished and every one passed.
    Q_PROPERTY(bool allPassed READ allPassed NOTIFY changed FINAL)
    // The first problem, as a sentence or two, and the fix for it, or empty.
    Q_PROPERTY(QString problem READ problem NOTIFY changed FINAL)
    Q_PROPERTY(QString problemFix READ problemFix NOTIFY changed FINAL)
    // What to do after a fix that needs a step of the user's own, or that a fix didn't help.
    Q_PROPERTY(QString notice READ notice NOTIFY changed FINAL)
    // What went wrong with the checks or the last fix, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    struct Environment
    {
        // network-check: run with no arguments it checks; "fix <id>" applies a fix.
        QString program;
        // Runs a fix's command and calls done with its exit code and the last line it wrote to
        // stderr. pkexec's 126 and 127 mean the password prompt was dismissed.
        std::function<void(const QString &program, const QStringList &arguments, std::function<void(int exitCode, const QString &detail)> done)> run;
    };

    // The real network-check, and QProcess for the fixes. The checks start at once.
    explicit NetworkCheck(QObject *parent = nullptr);
    NetworkCheck(Environment environment, QObject *parent);
    ~NetworkCheck() override;

    QVariantList checks() const;
    bool isRunning() const { return m_running; }
    bool isFixing() const { return m_fixing; }
    bool allPassed() const;
    QString problem() const { return m_problem; }
    QString problemFix() const { return m_problemFix; }
    QString notice() const { return m_notice; }
    QString error() const { return m_error; }

    // Check again, unless the checks or a fix are running.
    Q_INVOKABLE void run();
    // Apply one of network-check's fixes, then check again.
    Q_INVOKABLE void fix(const QString &fixId);

Q_SIGNALS:
    void changed();

private:
    enum class State {
        Pending,
        Running,
        Ok,
        Problem,
        // Waiting for the problem above to be fixed.
        Skipped,
    };

    struct Check
    {
        QString id;
        QString title;
        State state = State::Pending;
        QString detail;
    };

    // The name checks() gives a state, as Main.qml reads it.
    static QString stateName(State state);

    void start();
    void readResults();
    void apply(const CheckResult &result);
    void onChecksFinished(int exitCode, QProcess::ExitStatus status);
    void onFixed(const QString &fixId, int exitCode, const QString &detail);

    Environment m_environment;
    QList<Check> m_checks;
    QProcess m_process;
    QByteArray m_buffer;
    bool m_running = false;
    bool m_finished = false;
    bool m_fixing = false;
    QString m_problem;
    QString m_problemReason;
    QString m_problemFix;
    QString m_notice;
    QString m_error;
    // The problem the last fix was for, to tell whether it helped.
    QString m_fixedReason;
};

} // namespace OrielOSNetwork
