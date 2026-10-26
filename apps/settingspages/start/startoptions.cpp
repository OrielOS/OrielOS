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

} // namespace OrielOSSettingsPages
