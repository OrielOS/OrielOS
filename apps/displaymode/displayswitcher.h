// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "displaylayout.h"

#include <KScreen/Types>

#include <QObject>
#include <QtQmlIntegration/qqmlintegration.h>

// The screens as the Windows + P panel shows them: reads Plasma's screen configuration, tells which
// mode it is in, and applies a mode through Plasma's screen configuration service, which KWin
// carries out and Plasma saves.
class DisplaySwitcher : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Whether the configuration has been read.
    Q_PROPERTY(bool ready READ ready NOTIFY changed FINAL)
    // The number of connected screens; the modes other than the main screen need two.
    Q_PROPERTY(int screenCount READ screenCount NOTIFY changed FINAL)
    // The mode the screens are in, as a DisplayLayout::Mode.
    Q_PROPERTY(int currentMode READ currentMode NOTIFY changed FINAL)

public:
    explicit DisplaySwitcher(QObject *parent = nullptr);

    bool ready() const;
    int screenCount() const;
    int currentMode() const;

    // Applies a mode (a DisplayLayout::Mode) to the screens; `applied` reports how it went.
    Q_INVOKABLE void apply(int mode);

Q_SIGNALS:
    void changed();
    void applied(bool succeeded);
    // The screen configuration couldn't be read, so nothing can be shown or applied.
    void unavailable();

private:
    void load();
    QList<DisplayLayout::Screen> screens() const;

    KScreen::ConfigPtr m_config;
};
