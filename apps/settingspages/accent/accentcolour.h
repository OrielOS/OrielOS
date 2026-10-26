// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KConfigWatcher>

#include <QColor>
#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The accent colour: highlights, selected items and focus rings. It's set with
// plasma-apply-colorscheme --accent-color, in its own process, so Plasma's colours module, which
// links GPL-2.0-only code, is never loaded into Settings. Light and dark mode stay with the Themes
// page; the accent carries over between them.
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
    // Go back to the colour scheme's own selection colour.
    Q_INVOKABLE void useThemeColour();
    // Read the settings again.
    Q_INVOKABLE void reload();

    // Run program with arguments, then the accent's, instead of plasma-apply-colorscheme. For the
    // unit tests.
    void setCommandForTesting(const QString &program, const QStringList &arguments);

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
    QProcess *m_process = nullptr;
    QString m_error;
    QString m_program;
    QStringList m_arguments;
    KConfigWatcher::Ptr m_watcher;
};

} // namespace OrielOSSettingsPages
