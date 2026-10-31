// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KConfigWatcher>

#include <QColor>
#include <QObject>
#include <QProcess>
#include <QVariantList>

#include <functional>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The accent colour: highlights, selected items and focus rings. The choice is recorded as
// AccentColor in kdeglobals, as Plasma's Colours module records it, and applied with
// plasma-apply-colorscheme --accent-color in its own process, so that module, which links
// GPL-2.0-only code, is never loaded into Settings. Light and dark mode stay with the Themes page;
// applying a scheme there reads AccentColor, so the accent carries over between them.
class AccentColour : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // { name, colour } for each colour offered, in order.
    Q_PROPERTY(QVariantList choices READ choices CONSTANT)
    // The accent in use, or an invalid colour when the colour scheme's own is.
    Q_PROPERTY(QColor current READ current NOTIFY changed)
    // The colour scheme's own selection colour.
    Q_PROPERTY(QColor themeColour READ themeColour NOTIFY changed)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    // Windows' Transparency effects: the taskbar and pop-ups show the blurred desktop through them.
    // Off, KWin's blur is off and the theme draws them solid.
    Q_PROPERTY(bool transparency READ transparency WRITE setTransparency NOTIFY changed)
    // Windows' Show accent colour on Start and taskbar: OrielOS's Plasma theme with the accent
    // over Start, the taskbar and pop-ups (orielos-accent) instead of the plain one.
    Q_PROPERTY(bool accentOnTaskbar READ accentOnTaskbar WRITE setAccentOnTaskbar NOTIFY changed)

public:
    explicit AccentColour(QObject *parent = nullptr);
    ~AccentColour() override;

    QVariantList choices() const;
    QColor current() const;
    QColor themeColour() const { return m_themeColour; }
    bool isBusy() const { return m_process != nullptr; }
    QString error() const { return m_error; }

    // Use this colour as the accent.
    Q_INVOKABLE void choose(const QColor &colour);
    // Go back to the colour scheme's own selection colour: no AccentColor, and the scheme applied
    // with the accent "transparent", which is how Plasma says none.
    Q_INVOKABLE void useThemeColour();
    // Read the settings again.
    Q_INVOKABLE void reload();
    bool transparency() const { return m_transparency; }
    void setTransparency(bool transparency);
    bool accentOnTaskbar() const { return m_accentOnTaskbar; }
    void setAccentOnTaskbar(bool accent);

    // Run program with arguments, then the accent's, instead of plasma-apply-colorscheme. For the
    // unit tests.
    void setCommandForTesting(const QString &program, const QStringList &arguments);
    // Use this file for kwinrc and call this instead of asking KWin to reconfigure. For the unit
    // tests.
    void setKWinForTesting(const QString &config, std::function<void()> reconfigure);
    // Read plasmarc from this file and start program with the theme's name instead of
    // plasma-apply-desktoptheme. For the unit tests.
    void setThemeForTesting(const QString &config, const QString &program);

Q_SIGNALS:
    void changed();
    void applied(bool ok);

private:
    void apply(const QColor &colour);
    void finish(bool ok);

    QColor m_current;
    QColor m_themeColour;
    // The colour being applied, shown as chosen until plasma-apply-colorscheme ends.
    QColor m_pending;
    // The AccentColor before the change, put back if it fails; invalid when there was none.
    QColor m_previous;
    QProcess *m_process = nullptr;
    QString m_error;
    QString m_program;
    QStringList m_arguments;
    KConfigWatcher::Ptr m_watcher;
    bool m_transparency = true;
    bool m_accentOnTaskbar = false;
    QString m_plasmaConfig;
    QString m_themeProgram;
    QString m_kwinConfig;
    std::function<void()> m_reconfigure;
};

} // namespace OrielOSSettingsPages
