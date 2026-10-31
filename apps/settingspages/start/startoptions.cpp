// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "startoptions.h"

namespace OrielOSSettingsPages {

StartOptions::StartOptions(QObject *parent)
    : StartOptions(new ShellSettings(), parent)
{
}

StartOptions::StartOptions(ShellSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    m_settings->setParent(this);
    connect(m_settings, &ShellSettings::changed, this, &StartOptions::changed);
}

void StartOptions::setShowRecentlyAdded(bool show)
{
    if (isAvailable() && show != showRecentlyAdded()) {
        m_settings->change(ShellSettings::Setting::ShowRecentlyAdded, show);
    }
}

void StartOptions::setShowRecentFiles(bool show)
{
    if (isAvailable() && show != showRecentFiles()) {
        m_settings->change(ShellSettings::Setting::ShowRecentFiles, show);
    }
}

namespace {
const QList<ShellSettings::Setting> layouts
    = { ShellSettings::Setting::LayoutMorePins, ShellSettings::Setting::LayoutDefault, ShellSettings::Setting::LayoutMoreRecommendations };
} // namespace

int StartOptions::layout() const
{
    for (qsizetype i = 0; i < layouts.size(); ++i) {
        if (ShellSettings::layoutId(layouts.at(i)) == m_settings->state().startLayout) {
            return int(i);
        }
    }
    return 1;
}

void StartOptions::setLayout(int layout)
{
    if (isAvailable() && layout >= 0 && layout < layouts.size() && layout != this->layout()) {
        m_settings->change(layouts.at(layout), true);
    }
}

void StartOptions::setFolder(const QString &id, bool shown)
{
    const std::optional<ShellSettings::Setting> setting = ShellSettings::folderSetting(id);
    if (isAvailable() && setting && folders().contains(id) != shown) {
        m_settings->change(*setting, shown);
    }
}

} // namespace OrielOSSettingsPages
