// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "networkcheck.h"

#include <KLocalizedString>

#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QVariantMap>

#include <algorithm>

namespace OrielOSNetwork {

namespace {

constexpr auto checkTool = "/usr/libexec/orielos/network-check";
// Restarting NetworkManager needs an administrator, so it has a tool of its own for pkexec.
constexpr auto restartTool = "/usr/libexec/orielos/restart-networking";
constexpr auto restartFix = "restart-networking";
// The sign-in page opens in the browser; checking again at once would only find it again.
constexpr auto portalFix = "open-portal";
// pkexec exits with these when the password prompt is dismissed or the user isn't allowed.
constexpr int pkexecDismissed = 126;
constexpr int pkexecNotAuthorised = 127;

// A command and its arguments, where done gets the exit code and the last line it wrote to
// stderr: network-check ends with its own reason for failing.
void runProcess(const QString &program, const QStringList &arguments, std::function<void(int exitCode, const QString &detail)> done)
{
    auto *process = new QProcess;
    QObject::connect(process, &QProcess::finished, process, [process, done](int exitCode, QProcess::ExitStatus status) {
        const QStringList lines = QString::fromLocal8Bit(process->readAllStandardError()).split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        process->deleteLater();
        done(status == QProcess::NormalExit ? exitCode : 1, lines.isEmpty() ? QString() : lines.constLast().trimmed());
    });
    QObject::connect(process, &QProcess::errorOccurred, process, [process, done, program](QProcess::ProcessError error) {
        // Other errors end in finished() above.
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            done(1, i18nc("@info %1 is a program", "%1 couldn't be started.", program));
        }
    });
    process->start(program, arguments);
}

CheckResult::Result resultFrom(const QString &name)
{
    if (name == QLatin1String("ok")) {
        return CheckResult::Result::Ok;
    }
    if (name == QLatin1String("problem")) {
        return CheckResult::Result::Problem;
    }
    return CheckResult::Result::Skipped;
}

// What a check found when it passed, in a few words, or empty for a reason this app doesn't know.
QString passedDetail(const QString &reason)
{
    if (reason == QLatin1String("adapter-both")) {
        return i18nc("@info:status network adapters found", "Wi-Fi and a network cable socket");
    }
    if (reason == QLatin1String("adapter-wifi")) {
        return i18nc("@info:status network adapter found", "Wi-Fi");
    }
    if (reason == QLatin1String("adapter-ethernet")) {
        return i18nc("@info:status network adapter found", "Network cable socket");
    }
    if (reason == QLatin1String("radio-ok")) {
        return i18nc("@info:status the Wi-Fi radio", "On");
    }
    if (reason == QLatin1String("radio-not-needed")) {
        return i18nc("@info:status the Wi-Fi radio", "Not needed with a network cable");
    }
    if (reason == QLatin1String("connected")) {
        return i18nc("@info:status", "Connected");
    }
    if (reason == QLatin1String("address-ok")) {
        return i18nc("@info:status the network address", "Given by the network");
    }
    if (reason == QLatin1String("address-unchecked")) {
        return i18nc("@info:status the network address", "Not checked for this kind of connection");
    }
    if (reason == QLatin1String("gateway-ok")) {
        return i18nc("@info:status the router", "Answers");
    }
    if (reason == QLatin1String("gateway-quiet")) {
        return i18nc("@info:status the router", "Doesn't answer test messages, but traffic gets through");
    }
    if (reason == QLatin1String("dns-ok")) {
        return i18nc("@info:status website names", "Found");
    }
    if (reason == QLatin1String("internet-ok")) {
        return i18nc("@info:status the internet", "Reachable");
    }
    if (reason == QLatin1String("internet-unchecked")) {
        return i18nc("@info:status the internet", "Not checked: this PC's internet check is turned off");
    }
    return { };
}

// The problem in a sentence or two, or empty for a reason this app doesn't know.
QString problemText(const QString &reason)
{
    if (reason == QLatin1String("nm-not-running")) {
        return i18nc("@info", "The service that runs this PC's network connections has stopped. Restarting it needs an administrator's password.");
    }
    if (reason == QLatin1String("no-adapter")) {
        return i18nc("@info",
            "No network adapter was found. If this PC has one, its driver may be missing, or the adapter may be turned off in the PC's firmware settings.");
    }
    if (reason == QLatin1String("hard-blocked")) {
        return i18nc("@info", "Wi-Fi is turned off by a switch or key on this PC. Turn it on with the wireless switch, or the key with the wireless symbol.");
    }
    if (reason == QLatin1String("airplane")) {
        return i18nc("@info", "Airplane mode is on, so Wi-Fi is off.");
    }
    if (reason == QLatin1String("wifi-off")) {
        return i18nc("@info", "Wi-Fi is turned off.");
    }
    if (reason == QLatin1String("networking-off")) {
        return i18nc("@info", "Networking is turned off.");
    }
    if (reason == QLatin1String("connecting")) {
        return i18nc("@info", "This PC is still connecting to a network. Wait a moment, then check again.");
    }
    if (reason == QLatin1String("disconnected")) {
        return i18nc("@info", "This PC isn't connected to a network.");
    }
    if (reason == QLatin1String("no-saved-network")) {
        return i18nc("@info", "This PC isn't connected to a network. Choose a Wi-Fi network in Quick Settings, or plug in a network cable.");
    }
    if (reason == QLatin1String("no-cable")) {
        return i18nc("@info", "No network cable is plugged in. Plug one in, or connect to Wi-Fi in Quick Settings.");
    }
    if (reason == QLatin1String("no-address")) {
        return i18nc("@info", "This PC is connected, but the network didn't give it an address.");
    }
    if (reason == QLatin1String("no-gateway")) {
        return i18nc("@info", "The network didn't tell this PC where its router is, so it has no way out to the internet.");
    }
    if (reason == QLatin1String("gateway-down")) {
        return i18nc("@info", "The router doesn't answer. Restart it: switch it off, wait 30 seconds, then switch it on again.");
    }
    if (reason == QLatin1String("dns-failed")) {
        return i18nc("@info", "Website names can't be looked up, so websites won't open.");
    }
    if (reason == QLatin1String("portal")) {
        return i18nc("@info", "This network wants you to sign in, as hotel and café Wi-Fi often do.");
    }
    if (reason == QLatin1String("limited")) {
        return i18nc("@info", "The network isn't reaching the internet. Restart the router, or ask whoever runs the network.");
    }
    return { };
}

} // namespace

std::optional<CheckResult> CheckResult::parse(const QByteArray &line)
{
    const QJsonObject object = QJsonDocument::fromJson(line).object();
    const QString check = object.value(QStringLiteral("check")).toString();
    if (check.isEmpty()) {
        return std::nullopt;
    }
    CheckResult result;
    result.check = check;
    result.result = resultFrom(object.value(QStringLiteral("result")).toString());
    result.reason = object.value(QStringLiteral("reason")).toString();
    result.message = object.value(QStringLiteral("message")).toString();
    result.fix = object.value(QStringLiteral("fix")).toString();
    return result;
}

QList<CheckResult> CheckResult::takeLines(QByteArray &buffer)
{
    QList<CheckResult> results;
    qsizetype end;
    while ((end = buffer.indexOf('\n')) >= 0) {
        const QByteArray line = buffer.left(end).trimmed();
        buffer.remove(0, end + 1);
        if (const auto result = parse(line)) {
            results.append(*result);
        }
    }
    return results;
}

NetworkCheck::NetworkCheck(QObject *parent)
    : NetworkCheck(Environment { QLatin1String(checkTool), runProcess }, parent)
{
}

NetworkCheck::NetworkCheck(Environment environment, QObject *parent)
    : QObject(parent)
    , m_environment(std::move(environment))
{
    m_checks = {
        { QStringLiteral("adapter"), i18nc("@title a step of the network check", "Network adapter"), { }, { } },
        { QStringLiteral("radio"), i18nc("@title a step of the network check", "Wi-Fi radio"), { }, { } },
        { QStringLiteral("connected"), i18nc("@title a step of the network check", "Network connection"), { }, { } },
        { QStringLiteral("address"), i18nc("@title a step of the network check", "Network address"), { }, { } },
        { QStringLiteral("gateway"), i18nc("@title a step of the network check", "Router"), { }, { } },
        { QStringLiteral("dns"), i18nc("@title a step of the network check", "Website names"), { }, { } },
        { QStringLiteral("internet"), i18nc("@title a step of the network check", "Internet"), { }, { } },
    };
    // network-check's own messages go to the journal with the app's.
    m_process.setProcessChannelMode(QProcess::ForwardedErrorChannel);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &NetworkCheck::readResults);
    connect(&m_process, &QProcess::finished, this, &NetworkCheck::onChecksFinished);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        // Other errors end in finished().
        if (error == QProcess::FailedToStart) {
            m_error = i18nc("@info", "The network checks couldn't be started.");
            onChecksFinished(1, QProcess::CrashExit);
        }
    });
    start();
}

NetworkCheck::~NetworkCheck()
{
    // The checks only read, so a run still going is stopped rather than waited for.
    m_process.disconnect(this);
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
}

QVariantList NetworkCheck::checks() const
{
    QVariantList out;
    for (const Check &check : m_checks) {
        out.append(QVariantMap {
            { QStringLiteral("id"), check.id },
            { QStringLiteral("title"), check.title },
            { QStringLiteral("state"), check.state },
            { QStringLiteral("detail"), check.detail },
        });
    }
    return out;
}

bool NetworkCheck::allPassed() const
{
    return m_finished && std::all_of(m_checks.cbegin(), m_checks.cend(), [](const Check &check) { return check.state == QLatin1String("ok"); });
}

void NetworkCheck::run()
{
    if (m_running || m_fixing) {
        return;
    }
    m_error.clear();
    m_notice.clear();
    m_fixedReason.clear();
    start();
}

void NetworkCheck::start()
{
    if (m_process.state() != QProcess::NotRunning) {
        return;
    }
    m_running = true;
    m_finished = false;
    m_problem.clear();
    m_problemReason.clear();
    m_problemFix.clear();
    m_buffer.clear();
    for (Check &check : m_checks) {
        check.state = QStringLiteral("pending");
        check.detail.clear();
    }
    m_checks.first().state = QStringLiteral("running");
    m_checks.first().detail = i18nc("@info:status", "Checking…");
    Q_EMIT changed();
    m_process.start(m_environment.program, QStringList { });
}

void NetworkCheck::readResults()
{
    m_buffer.append(m_process.readAllStandardOutput());
    const QList<CheckResult> results = CheckResult::takeLines(m_buffer);
    for (const CheckResult &result : results) {
        apply(result);
    }
    if (!results.isEmpty()) {
        Q_EMIT changed();
    }
}

void NetworkCheck::apply(const CheckResult &result)
{
    const auto check = std::find_if(m_checks.begin(), m_checks.end(), [&result](const Check &item) { return item.id == result.check; });
    if (check == m_checks.end()) {
        return;
    }
    switch (result.result) {
    case CheckResult::Result::Ok: {
        check->state = QStringLiteral("ok");
        const QString detail = passedDetail(result.reason);
        check->detail = detail.isEmpty() ? result.message : detail;
        break;
    }
    case CheckResult::Result::Problem:
        check->state = QStringLiteral("problem");
        check->detail = i18nc("@info:status", "Problem found");
        // network-check stops at the first problem; only that one is shown.
        if (m_problemReason.isEmpty()) {
            const QString text = problemText(result.reason);
            m_problem = text.isEmpty() ? result.message : text;
            m_problemReason = result.reason.isEmpty() ? result.check : result.reason;
            m_problemFix = result.fix;
        }
        break;
    case CheckResult::Result::Skipped:
        check->state = QStringLiteral("skipped");
        check->detail = i18nc("@info:status", "Checked once the problem above is fixed");
        break;
    }
    // The next check is the one running now, until a problem stops them.
    const auto next = std::find_if(m_checks.begin(), m_checks.end(), [](const Check &check) { return check.state == QLatin1String("pending"); });
    if (next != m_checks.end() && m_problemReason.isEmpty()) {
        next->state = QStringLiteral("running");
        next->detail = i18nc("@info:status", "Checking…");
    }
}

void NetworkCheck::onChecksFinished(int exitCode, QProcess::ExitStatus status)
{
    if (!m_running) {
        return;
    }
    // A last line without a newline.
    m_buffer.append(m_process.readAllStandardOutput());
    m_buffer.append('\n');
    for (const CheckResult &result : CheckResult::takeLines(m_buffer)) {
        apply(result);
    }
    m_running = false;
    m_finished = true;
    // Checks that never reported go back to waiting.
    bool incomplete = false;
    for (Check &check : m_checks) {
        if (check.state == QLatin1String("pending") || check.state == QLatin1String("running")) {
            check.state = QStringLiteral("pending");
            check.detail.clear();
            incomplete = true;
        }
    }
    if (m_error.isEmpty() && (incomplete || status != QProcess::NormalExit || exitCode != 0)) {
        m_error = i18nc("@info", "The network checks stopped before the end. Check again, or restart this PC.");
    }
    // Checking again after a fix: say so when the same problem is still there.
    if (!m_fixedReason.isEmpty() && m_fixedReason == m_problemReason) {
        m_notice = i18nc("@info", "That didn't fix it. Restarting this PC and the router often helps.");
    }
    m_fixedReason.clear();
    Q_EMIT changed();
}

void NetworkCheck::fix(const QString &fixId)
{
    if (fixId.isEmpty() || m_running || m_fixing) {
        return;
    }
    m_fixing = true;
    m_error.clear();
    m_notice.clear();
    Q_EMIT changed();
    const bool restart = fixId == QLatin1String(restartFix);
    const QString program = restart ? QStringLiteral("pkexec") : m_environment.program;
    const QStringList arguments = restart ? QStringList { QLatin1String(restartTool) } : QStringList { QStringLiteral("fix"), fixId };
    m_environment.run(program, arguments, [self = QPointer<NetworkCheck>(this), fixId](int exitCode, const QString &detail) {
        if (!self) {
            return;
        }
        self->onFixed(fixId, exitCode, detail);
    });
}

void NetworkCheck::onFixed(const QString &fixId, int exitCode, const QString &detail)
{
    m_fixing = false;
    const bool restart = fixId == QLatin1String(restartFix);
    if (restart && (exitCode == pkexecDismissed || exitCode == pkexecNotAuthorised)) {
        // The password prompt was dismissed: nothing changed, so there's nothing to check.
        Q_EMIT changed();
        return;
    }
    if (exitCode != 0) {
        m_error = detail.isEmpty() ? i18nc("@info", "That fix didn't work.") : i18nc("@info %1 is the reason", "That fix didn't work: %1", detail);
    } else if (fixId == QLatin1String(portalFix)) {
        m_notice = i18nc("@info", "Sign in on the page that opened in your browser, then check again.");
        Q_EMIT changed();
        return;
    } else {
        m_fixedReason = m_problemReason;
    }
    // Check again either way: a fix can work part of the way, and the problem may have moved on.
    start();
}

} // namespace OrielOSNetwork
