// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "signinoptions.h"

#include <KConfigGroup>
#include <KLocalizedString>
#include <KSharedConfig>

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QLocalSocket>
#include <QProcess>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QTimer>

namespace OrielOSSettingsPages {

namespace {

const QString pinSocket = QStringLiteral("/run/orielos/pin.socket");
const QString signInSettings = QStringLiteral("/usr/libexec/orielos/sign-in-settings");
const QString startupSoundOff = QStringLiteral("/etc/orielos/startup-sound-off");
const QString dynamicLockUnit = QStringLiteral("orielos-dynamic-lock.service");

QString dynamicLockPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/orielos/dynamic-lock");
}

KConfigGroup lockScreenGreeter()
{
    return KSharedConfig::openConfig(QStringLiteral("kscreenlockerrc"))->group(QStringLiteral("Greeter")).group(QStringLiteral("LnF")).group(QStringLiteral("General"));
}

KConfigGroup lockScreenDaemon()
{
    return KSharedConfig::openConfig(QStringLiteral("kscreenlockerrc"))->group(QStringLiteral("Daemon"));
}

// The lock screen rereads its settings when told to.
void tellLockScreen()
{
    QDBusConnection::sessionBus().send(QDBusMessage::createSignal(QStringLiteral("/ScreenSaver"), QStringLiteral("org.kde.screensaver"), QStringLiteral("configChanged")));
}

} // namespace

SignInOptions::SignInOptions(QObject *parent)
    : QObject(parent)
    , m_startupSound(!QFile::exists(startupSoundOff))
{
    refresh();
}

bool SignInOptions::isValidPin(const QString &pin)
{
    static const QRegularExpression digits(QStringLiteral("^[0-9]{4,12}$"));
    return digits.match(pin).hasMatch();
}

QString SignInOptions::parseDynamicLockFile(const QByteArray &contents)
{
    static const QRegularExpression line(QStringLiteral("^device=([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})$"), QRegularExpression::MultilineOption);
    const QRegularExpressionMatch match = line.match(QString::fromUtf8(contents));
    return match.hasMatch() ? match.captured(1).toUpper() : QString();
}

QByteArray SignInOptions::formatDynamicLockFile(const QString &address)
{
    return QByteArrayLiteral("device=") + address.toUpper().toUtf8() + '\n';
}

void SignInOptions::refresh()
{
    askPinService({ { QStringLiteral("op"), QStringLiteral("info") } }, [this](const QJsonObject &answer) {
        m_pinServiceAvailable = !answer.isEmpty();
        m_pinLength = answer.value(QStringLiteral("pin")).toBool() ? answer.value(QStringLiteral("length")).toInt() : 0;
        Q_EMIT pinChanged();
    });
    readFingerprintReaders();

    QFile file(dynamicLockPath());
    m_dynamicLockDevice = file.open(QIODevice::ReadOnly) ? parseDynamicLockFile(file.read(256)) : QString();
    readPairedDevices();
}

void SignInOptions::askPinService(const QJsonObject &request, std::function<void(const QJsonObject &)> done)
{
    auto *socket = new QLocalSocket(this);
    auto *timeout = new QTimer(socket);
    timeout->setSingleShot(true);
    // Checking a password can take a few seconds after a wrong one; the service gives up at 60.
    timeout->start(20000);
    auto finish = [socket, timeout, done](const QJsonObject &answer) {
        timeout->stop();
        socket->disconnect();
        socket->abort();
        socket->deleteLater();
        done(answer);
    };
    connect(timeout, &QTimer::timeout, socket, [finish]() {
        finish({ });
    });
    connect(socket, &QLocalSocket::errorOccurred, socket, [finish](QLocalSocket::LocalSocketError error) {
        if (error != QLocalSocket::PeerClosedError) {
            finish({ });
        }
    });
    connect(socket, &QLocalSocket::connected, socket, [socket, request]() {
        socket->write(QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n');
    });
    connect(socket, &QLocalSocket::readyRead, socket, [socket, finish]() {
        if (!socket->canReadLine()) {
            return;
        }
        finish(QJsonDocument::fromJson(socket->readLine(4096)).object());
    });
    socket->connectToServer(pinSocket);
}

void SignInOptions::setPin(const QString &pin, const QString &credential)
{
    setError({ });
    if (!isValidPin(pin)) {
        setError(i18nc("@info", "A PIN is 4 to 12 digits."));
        return;
    }
    setBusy(true);
    const QJsonObject request { { QStringLiteral("op"), QStringLiteral("set") }, { QStringLiteral("pin"), pin }, { QStringLiteral("credential"), credential } };
    askPinService(request, [this](const QJsonObject &answer) {
        setBusy(false);
        if (answer.isEmpty()) {
            setError(i18nc("@info", "The PIN service didn't answer."));
        } else if (!answer.value(QStringLiteral("ok")).toBool()) {
            setError(i18nc("@info", "That isn't your password or PIN."));
        }
        refresh();
    });
}

void SignInOptions::removePin(const QString &credential)
{
    setError({ });
    setBusy(true);
    const QJsonObject request { { QStringLiteral("op"), QStringLiteral("remove") }, { QStringLiteral("credential"), credential } };
    askPinService(request, [this](const QJsonObject &answer) {
        setBusy(false);
        if (answer.isEmpty()) {
            setError(i18nc("@info", "The PIN service didn't answer."));
        } else if (!answer.value(QStringLiteral("ok")).toBool()) {
            setError(i18nc("@info", "That isn't your password or PIN."));
        }
        refresh();
    });
}

void SignInOptions::readFingerprintReaders()
{
    const QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("net.reactivated.Fprint"), QStringLiteral("/net/reactivated/Fprint/Manager"),
                                                                QStringLiteral("net.reactivated.Fprint.Manager"), QStringLiteral("GetDevices"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        watcher->deleteLater();
        const QDBusPendingReply<QList<QDBusObjectPath>> reply = *watcher;
        m_fingerprintReader = reply.isValid() && !reply.value().isEmpty();
        Q_EMIT fingerprintChanged();
    });
}

void SignInOptions::openFingerprintSetup()
{
    // Plasma's Users page enrols fingers.
    QProcess::startDetached(QStringLiteral("kcmshell6"), { QStringLiteral("kcm_users") });
}

void SignInOptions::readPairedDevices()
{
    const QDBusMessage message =
        QDBusMessage::createMethodCall(QStringLiteral("org.bluez"), QStringLiteral("/"), QStringLiteral("org.freedesktop.DBus.ObjectManager"), QStringLiteral("GetManagedObjects"));
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::systemBus().asyncCall(message), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, watcher]() {
        watcher->deleteLater();
        m_pairedDevices.clear();
        const QDBusMessage reply = watcher->reply();
        if (reply.type() == QDBusMessage::ReplyMessage && !reply.arguments().isEmpty()) {
            // a{oa{sa{sv}}}: each object's interfaces and their properties.
            QMap<QDBusObjectPath, QMap<QString, QVariantMap>> objects;
            reply.arguments().constFirst().value<QDBusArgument>() >> objects;
            for (const auto &interfaces : std::as_const(objects)) {
                const QVariantMap device = interfaces.value(QStringLiteral("org.bluez.Device1"));
                if (!device.value(QStringLiteral("Paired")).toBool()) {
                    continue;
                }
                const QString address = device.value(QStringLiteral("Address")).toString();
                QString name = device.value(QStringLiteral("Alias")).toString();
                if (name.isEmpty()) {
                    name = device.value(QStringLiteral("Name"), address).toString();
                }
                m_pairedDevices.append(QVariantMap { { QStringLiteral("address"), address }, { QStringLiteral("name"), name } });
            }
        }
        Q_EMIT dynamicLockChanged();
    });
}

void SignInOptions::setDynamicLock(bool enabled, const QString &address)
{
    setError({ });
    const QString path = dynamicLockPath();
    if (enabled) {
        if (parseDynamicLockFile(formatDynamicLockFile(address)).isEmpty()) {
            return;
        }
        QDir().mkpath(QFileInfo(path).absolutePath());
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(formatDynamicLockFile(address)) < 0 || !file.commit()) {
            setError(i18nc("@info", "Dynamic lock couldn't be saved."));
            return;
        }
        m_dynamicLockDevice = address.toUpper();
    } else {
        QFile::remove(path);
        m_dynamicLockDevice.clear();
    }
    // The service runs only while a phone is chosen.
    QProcess::startDetached(QStringLiteral("systemctl"), { QStringLiteral("--user"), enabled ? QStringLiteral("restart") : QStringLiteral("stop"), dynamicLockUnit });
    Q_EMIT dynamicLockChanged();
}

bool SignInOptions::lockOnResume() const
{
    return lockScreenDaemon().readEntry("LockOnResume", true);
}

void SignInOptions::setLockOnResume(bool lock)
{
    if (lock == lockOnResume()) {
        return;
    }
    KConfigGroup group = lockScreenDaemon();
    group.writeEntry("LockOnResume", lock);
    group.sync();
    tellLockScreen();
    Q_EMIT settingsChanged();
}

bool SignInOptions::requireCtrlAltDel() const
{
    return lockScreenGreeter().readEntry("requireCtrlAltDel", false);
}

void SignInOptions::setRequireCtrlAltDel(bool require)
{
    if (require == requireCtrlAltDel()) {
        return;
    }
    // The sign-in screen first, which needs an administrator; the lock screen follows only if that
    // worked, so the two never disagree.
    runSignInSettings(QStringLiteral("ctrl-alt-del"), require, [this, require](bool ok) {
        if (ok) {
            KConfigGroup group = lockScreenGreeter();
            group.writeEntry("requireCtrlAltDel", require);
            group.sync();
            tellLockScreen();
        } else {
            setError(i18nc("@info", "The sign-in screen's setting couldn't be changed."));
        }
        Q_EMIT settingsChanged();
    });
}

bool SignInOptions::startupSound() const
{
    return m_startupSound;
}

void SignInOptions::setStartupSound(bool play)
{
    if (play == m_startupSound) {
        return;
    }
    runSignInSettings(QStringLiteral("startup-sound"), play, [this, play](bool ok) {
        if (ok) {
            m_startupSound = play;
        } else {
            setError(i18nc("@info", "The startup sound couldn't be changed."));
        }
        Q_EMIT settingsChanged();
    });
}

void SignInOptions::runSignInSettings(const QString &setting, bool on, std::function<void(bool)> done)
{
    setError({ });
    setBusy(true);
    auto *process = new QProcess(this);
    connect(process, &QProcess::finished, this, [this, process, done](int exitCode, QProcess::ExitStatus status) {
        process->deleteLater();
        setBusy(false);
        done(status == QProcess::NormalExit && exitCode == 0);
    });
    connect(process, &QProcess::errorOccurred, this, [this, process, done](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            process->deleteLater();
            setBusy(false);
            done(false);
        }
    });
    process->start(QStringLiteral("pkexec"), { signInSettings, setting, on ? QStringLiteral("on") : QStringLiteral("off") });
}

void SignInOptions::setError(const QString &error)
{
    if (error != m_error) {
        m_error = error;
        Q_EMIT errorChanged();
    }
}

void SignInOptions::setBusy(bool busy)
{
    if (busy != m_busy) {
        m_busy = busy;
        Q_EMIT busyChanged();
    }
}

} // namespace OrielOSSettingsPages
