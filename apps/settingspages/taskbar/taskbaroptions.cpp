// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "taskbaroptions.h"

namespace OrielOSSettingsPages {

TaskbarOptions::TaskbarOptions(QObject *parent)
    : TaskbarOptions(new ShellSettings(), parent)
{
}

TaskbarOptions::TaskbarOptions(ShellSettings *settings, QObject *parent)
    : QObject(parent)
    , m_settings(settings)
{
    m_settings->setParent(this);
    connect(m_settings, &ShellSettings::changed, this, &TaskbarOptions::changed);
}

void TaskbarOptions::setCentred(bool centred)
{
    if (canAlign() && centred != isCentred()) {
        m_settings->change(ShellSettings::Setting::Centred, centred);
    }
}

void TaskbarOptions::setAutoHide(bool hide)
{
    if (isAvailable() && hide != autoHide()) {
        m_settings->change(ShellSettings::Setting::AutoHide, hide);
    }
}

void TaskbarOptions::setShowSearch(bool show)
{
    if (hasSearch() && show != showSearch()) {
        m_settings->change(ShellSettings::Setting::ShowSearch, show);
    }
}

void TaskbarOptions::setShowTaskView(bool show)
{
    if (hasTaskView() && show != showTaskView()) {
        m_settings->change(ShellSettings::Setting::ShowTaskView, show);
    }
}

void TaskbarOptions::setCombineButtons(bool combine)
{
    if (hasTasks() && combine != combineButtons()) {
        m_settings->change(ShellSettings::Setting::CombineButtons, combine);
    }
}

void TaskbarOptions::setShowSeconds(bool show)
{
    if (hasClock() && show != showSeconds()) {
        m_settings->change(ShellSettings::Setting::ShowSeconds, show);
    }
}

void TaskbarOptions::setPeek(bool peek)
{
    if (hasSliver() && peek != this->peek()) {
        m_settings->change(ShellSettings::Setting::Peek, peek);
    }
}

void TaskbarOptions::setAllDisplays(bool all)
{
    if (isAvailable() && all != allDisplays()) {
        m_settings->change(ShellSettings::Setting::AllDisplays, all);
    }
}

} // namespace OrielOSSettingsPages
