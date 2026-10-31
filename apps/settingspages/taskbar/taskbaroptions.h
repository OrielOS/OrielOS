// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "shellsettings.h"

#include <QObject>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The taskbar's alignment, centred or on the left, whether it hides itself, its Search and Task View
// buttons, whether each app's windows share a button, and seconds in the clock. Changes go to the
// taskbar straight away.
class TaskbarOptions : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool ready READ isReady NOTIFY changed)
    // Whether there's an OrielOS taskbar, the panel with OrielOS's Start menu, to change.
    Q_PROPERTY(bool available READ isAvailable NOTIFY changed)
    // Whether the taskbar still has the spacer before Start that centres it.
    Q_PROPERTY(bool canAlign READ canAlign NOTIFY changed)
    Q_PROPERTY(bool centred READ isCentred WRITE setCentred NOTIFY changed)
    Q_PROPERTY(bool autoHide READ autoHide WRITE setAutoHide NOTIFY changed)
    Q_PROPERTY(bool hasSearch READ hasSearch NOTIFY changed)
    Q_PROPERTY(bool showSearch READ showSearch WRITE setShowSearch NOTIFY changed)
    Q_PROPERTY(bool hasTaskView READ hasTaskView NOTIFY changed)
    Q_PROPERTY(bool showTaskView READ showTaskView WRITE setShowTaskView NOTIFY changed)
    Q_PROPERTY(bool hasTasks READ hasTasks NOTIFY changed)
    Q_PROPERTY(bool combineButtons READ combineButtons WRITE setCombineButtons NOTIFY changed)
    Q_PROPERTY(bool hasClock READ hasClock NOTIFY changed)
    Q_PROPERTY(bool showSeconds READ showSeconds WRITE setShowSeconds NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit TaskbarOptions(QObject *parent = nullptr);
    // Uses these settings instead of the desktop's. For the unit tests.
    explicit TaskbarOptions(ShellSettings *settings, QObject *parent = nullptr);

    bool isReady() const { return m_settings->isReady(); }
    bool isAvailable() const { return m_settings->state().hasStart; }
    bool canAlign() const { return m_settings->state().canAlign; }
    bool isCentred() const { return m_settings->state().centred; }
    void setCentred(bool centred);
    bool autoHide() const { return m_settings->state().autoHide; }
    void setAutoHide(bool hide);
    bool hasSearch() const { return m_settings->state().hasSearch; }
    bool showSearch() const { return m_settings->state().showSearch; }
    void setShowSearch(bool show);
    bool hasTaskView() const { return m_settings->state().hasTaskView; }
    bool showTaskView() const { return m_settings->state().showTaskView; }
    void setShowTaskView(bool show);
    bool hasTasks() const { return m_settings->state().hasTasks; }
    bool combineButtons() const { return m_settings->state().combineButtons; }
    void setCombineButtons(bool combine);
    bool hasClock() const { return m_settings->state().hasClock; }
    bool showSeconds() const { return m_settings->state().showSeconds; }
    void setShowSeconds(bool show);
    QString error() const { return m_settings->error(); }

Q_SIGNALS:
    void changed();

private:
    ShellSettings *m_settings;
};

} // namespace OrielOSSettingsPages
