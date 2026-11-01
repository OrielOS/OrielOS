// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "multitaskingoptions.h"

#include <KConfigGroup>

#include <QDBusConnection>
#include <QDBusMessage>

namespace OrielOSSettingsPages {

namespace {

const QString windowsGroup = QStringLiteral("Windows");
const QString pluginsGroup = QStringLiteral("Plugins");
const QString decorationGroup = QStringLiteral("org.kde.kdecoration2");
const QString tabBoxGroup = QStringLiteral("TabBox");
// OrielOS's snap assist effect, enabled by default in its metadata.
const QString snapAssistKey = QStringLiteral("orielos-snapassistEnabled");
// Read by OrielOS's window frames each time the pointer rests on maximise.
const QString snapLayoutsKey = QStringLiteral("SnapLayoutsOnHover");

void askKWinToReconfigure()
{
    QDBusConnection::sessionBus().send(
        QDBusMessage::createMethodCall(QStringLiteral("org.kde.KWin"), QStringLiteral("/KWin"), QStringLiteral("org.kde.KWin"), QStringLiteral("reconfigure")));
}

} // namespace

MultitaskingOptions::MultitaskingOptions(QObject *parent)
    : QObject(parent)
    , m_config(KSharedConfig::openConfig(QStringLiteral("kwinrc")))
    , m_reconfigure(askKWinToReconfigure)
{
    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, &MultitaskingOptions::changed);
}

bool MultitaskingOptions::snapWindows() const
{
    // KWin's defaults: both on.
    const KConfigGroup windows(m_config, windowsGroup);
    return windows.readEntry("ElectricBorderMaximize", true) && windows.readEntry("ElectricBorderTiling", true);
}

void MultitaskingOptions::setSnapWindows(bool snap)
{
    if (snap == snapWindows()) {
        return;
    }
    KConfigGroup windows(m_config, windowsGroup);
    windows.writeEntry("ElectricBorderMaximize", snap, KConfig::Notify);
    write(windowsGroup, QStringLiteral("ElectricBorderTiling"), snap);
}

bool MultitaskingOptions::snapLayoutsOnMaximise() const
{
    return KConfigGroup(m_config, decorationGroup).readEntry(snapLayoutsKey, true);
}

void MultitaskingOptions::setSnapLayoutsOnMaximise(bool show)
{
    if (show != snapLayoutsOnMaximise()) {
        write(decorationGroup, snapLayoutsKey, show);
    }
}

bool MultitaskingOptions::suggestNextSnap() const
{
    return KConfigGroup(m_config, pluginsGroup).readEntry(snapAssistKey, true);
}

void MultitaskingOptions::setSuggestNextSnap(bool suggest)
{
    if (suggest != suggestNextSnap()) {
        write(pluginsGroup, snapAssistKey, suggest);
    }
}

bool MultitaskingOptions::minimiseOnDisconnect() const
{
    return KConfigGroup(m_config, QStringLiteral("Script-orielos-windowkeys")).readEntry("MinimiseOnDisconnect", true);
}

void MultitaskingOptions::setMinimiseOnDisconnect(bool minimise)
{
    if (minimise != minimiseOnDisconnect()) {
        write(QStringLiteral("Script-orielos-windowkeys"), QStringLiteral("MinimiseOnDisconnect"), minimise);
    }
}

bool MultitaskingOptions::altTabAllDesktops() const
{
    // 1 shows only the desktop in use, 0 every desktop; OrielOS's default is 1.
    return KConfigGroup(m_config, tabBoxGroup).readEntry("DesktopMode", 1) == 0;
}

void MultitaskingOptions::setAltTabAllDesktops(bool all)
{
    if (all == altTabAllDesktops()) {
        return;
    }
    KConfigGroup tabBox(m_config, tabBoxGroup);
    tabBox.writeEntry("DesktopMode", all ? 0 : 1, KConfig::Notify);
    m_config->sync();
    m_reconfigure();
    Q_EMIT changed();
}

void MultitaskingOptions::write(const QString &group, const QString &key, bool value)
{
    KConfigGroup(m_config, group).writeEntry(key, value, KConfig::Notify);
    m_config->sync();
    m_reconfigure();
    Q_EMIT changed();
}

void MultitaskingOptions::setConfigForTesting(KSharedConfig::Ptr config, std::function<void()> reconfigure)
{
    m_config = std::move(config);
    m_watcher = KConfigWatcher::create(m_config);
    connect(m_watcher.data(), &KConfigWatcher::configChanged, this, &MultitaskingOptions::changed);
    m_reconfigure = std::move(reconfigure);
    Q_EMIT changed();
}

} // namespace OrielOSSettingsPages
