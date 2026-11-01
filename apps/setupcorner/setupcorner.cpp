// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "setupcorner.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDBusVariant>
#include <QProcess>
#include <QRegularExpression>

namespace {

const QString keyboardService = QStringLiteral("org.kde.keyboard");
const QString layoutsPath = QStringLiteral("/Layouts");
const QString layoutsInterface = QStringLiteral("org.kde.KeyboardLayouts");
const QString kwinService = QStringLiteral("org.kde.KWin");
const QString virtualKeyboardPath = QStringLiteral("/VirtualKeyboard");
const QString virtualKeyboardInterface = QStringLiteral("org.kde.kwin.VirtualKeyboard");
const QString sink = QStringLiteral("@DEFAULT_AUDIO_SINK@");

// KWin's keyboard layouts as D-Bus gives them: (short name, variant, long name) each.
struct LayoutNames
{
    QString shortName;
    QString variant;
    QString longName;
};

QList<LayoutNames> readLayoutList(const QDBusArgument &argument)
{
    QList<LayoutNames> list;
    argument.beginArray();
    while (!argument.atEnd()) {
        LayoutNames names;
        argument.beginStructure();
        argument >> names.shortName >> names.variant >> names.longName;
        argument.endStructure();
        list.append(names);
    }
    argument.endArray();
    return list;
}

QString runWpctl(const QStringList &arguments)
{
    QProcess process;
    process.start(QStringLiteral("wpctl"), arguments);
    process.waitForFinished(3000);
    return QString::fromUtf8(process.readAllStandardOutput());
}

} // namespace

SetupCorner::SetupCorner(QObject *parent)
    : QObject(parent)
{
    QDBusConnection::sessionBus().connect(keyboardService, layoutsPath, layoutsInterface, QStringLiteral("layoutChanged"), this, SLOT(readLayout()));
    QDBusConnection::sessionBus().connect(keyboardService, layoutsPath, layoutsInterface, QStringLiteral("layoutListChanged"), this, SLOT(readLayout()));
    QDBusConnection::sessionBus().connect(
        kwinService, virtualKeyboardPath, virtualKeyboardInterface, QStringLiteral("enabledChanged"), this, SIGNAL(keyboardShownChanged()));
    readLayout();
    readVolume();
}

void SetupCorner::readLayout()
{
    QDBusInterface layouts(keyboardService, layoutsPath, layoutsInterface);
    const QDBusReply<uint> current = layouts.call(QStringLiteral("getLayout"));
    const QDBusMessage listReply = layouts.call(QStringLiteral("getLayoutsList"));
    QList<LayoutNames> list;
    if (listReply.type() == QDBusMessage::ReplyMessage && !listReply.arguments().isEmpty()) {
        list = readLayoutList(listReply.arguments().constFirst().value<QDBusArgument>());
    }
    m_layoutCount = int(list.size());
    const int index = current.isValid() ? int(current.value()) : -1;
    if (index >= 0 && index < list.size()) {
        m_layoutName = list.at(index).longName;
        // Before a layout has been chosen, KWin's default has no short name: use the first letters
        // of its name, such as ENG for English (US).
        m_layout = list.at(index).shortName.isEmpty() ? m_layoutName.left(3) : list.at(index).shortName;
    } else {
        m_layout.clear();
        m_layoutName.clear();
    }
    Q_EMIT layoutChanged();
}

void SetupCorner::nextLayout()
{
    QDBusInterface layouts(keyboardService, layoutsPath, layoutsInterface);
    layouts.call(QStringLiteral("switchToNextLayout"));
}

std::pair<int, bool> SetupCorner::parseVolume(const QString &output)
{
    static const QRegularExpression pattern(QStringLiteral("Volume:\\s*([0-9.]+)(\\s*\\[MUTED\\])?"));
    const QRegularExpressionMatch match = pattern.match(output);
    if (!match.hasMatch()) {
        return { 0, false };
    }
    return { qBound(0, qRound(match.captured(1).toDouble() * 100), 100), match.capturedLength(2) > 0 };
}

void SetupCorner::readVolume()
{
    const auto [volume, muted] = parseVolume(runWpctl({ QStringLiteral("get-volume"), sink }));
    m_volume = volume;
    m_muted = muted;
    Q_EMIT volumeChanged();
}

void SetupCorner::setVolume(int percent)
{
    percent = qBound(0, percent, 100);
    runWpctl({ QStringLiteral("set-volume"), sink, QString::number(percent / 100.0, 'f', 2) });
    if (m_muted && percent > 0) {
        runWpctl({ QStringLiteral("set-mute"), sink, QStringLiteral("0") });
    }
    readVolume();
}

void SetupCorner::toggleMute()
{
    runWpctl({ QStringLiteral("set-mute"), sink, QStringLiteral("toggle") });
    readVolume();
}

void SetupCorner::invokeShortcut(const QString &component, const QString &shortcut)
{
    QDBusMessage message = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/component/") + component,
        QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
    message.setArguments({ shortcut });
    QDBusConnection::sessionBus().send(message);
}

void SetupCorner::toggleScreenReader()
{
    invokeShortcut(QStringLiteral("kaccess"), QStringLiteral("Toggle Screen Reader On and Off"));
}

void SetupCorner::toggleMagnifier()
{
    // KWin's zoom: twice its step in, or back to the actual size.
    if (m_magnified) {
        invokeShortcut(QStringLiteral("kwin"), QStringLiteral("view_actual_size"));
    } else {
        invokeShortcut(QStringLiteral("kwin"), QStringLiteral("view_zoom_in"));
        invokeShortcut(QStringLiteral("kwin"), QStringLiteral("view_zoom_in"));
    }
    m_magnified = !m_magnified;
    Q_EMIT magnifiedChanged();
}

bool SetupCorner::isKeyboardShown() const
{
    QDBusInterface keyboard(kwinService, virtualKeyboardPath, virtualKeyboardInterface);
    return keyboard.property("enabled").toBool();
}

void SetupCorner::toggleKeyboard()
{
    QDBusMessage message
        = QDBusMessage::createMethodCall(kwinService, virtualKeyboardPath, QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Set"));
    message.setArguments({ virtualKeyboardInterface, QStringLiteral("enabled"), QVariant::fromValue(QDBusVariant(!isKeyboardShown())) });
    QDBusConnection::sessionBus().call(message);
    Q_EMIT keyboardShownChanged();
}

void SetupCorner::toggleContrast()
{
    QProcess::startDetached(QStringLiteral("/usr/libexec/orielos/accessibility-keys"), { QStringLiteral("contrast") });
}
