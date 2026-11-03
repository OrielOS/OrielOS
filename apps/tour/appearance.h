// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <KConfigWatcher>

#include <QList>
#include <QObject>
#include <QProcess>
#include <QString>
#include <QStringList>
#include <qqmlintegration.h>

namespace OrielOSTour {

// Light or dark: OrielOS's look-and-feel, org.orielos.desktop or org.orielos.desktop.dark, applied
// with plasma-apply-lookandfeel in its own process, as the Themes page applies it, leaving the
// layout alone. Its colour scheme is applied again with plasma-apply-colorscheme, because the
// look-and-feel tool changes nothing when the package is already the chosen one, even if the colours
// were changed since. The look-and-feel sets OrielOS's plain Plasma theme, so the accent colour on
// Start and the taskbar (orielos-accent) is put back afterwards if it was on.
class Appearance : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // Whether the colour scheme is a dark one; while a change is applied, the choice.
    Q_PROPERTY(bool dark READ isDark WRITE setDark NOTIFY changed)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed)
    // What went wrong with the last change, or empty.
    Q_PROPERTY(QString error READ error NOTIFY changed)

public:
    explicit Appearance(QObject *parent = nullptr);
    ~Appearance() override;

    bool isDark() const;
    void setDark(bool dark);
    bool isBusy() const { return m_process != nullptr; }
    QString error() const { return m_error; }

    // Run each command as program with arguments, then the command and its own arguments. For the
    // unit tests.
    void setCommandForTesting(const QString &program, const QStringList &arguments);
    // Read plasmarc from this file. For the unit tests.
    void setPlasmaConfigForTesting(const QString &config);

Q_SIGNALS:
    void changed();
    void applied(bool ok);

private:
    struct Step
    {
        QStringList command;
        // Whether the change has failed if this step does.
        bool required = true;
    };

    void reload();
    void runNext();
    void finish(bool ok);

    bool m_dark = true;
    // The choice being applied.
    bool m_pending = false;
    // The commands still to run; the first one is running.
    QList<Step> m_steps;
    QProcess *m_process = nullptr;
    QString m_error;
    QString m_program;
    QStringList m_arguments;
    QString m_plasmaConfig;
    KConfigWatcher::Ptr m_watcher;
};

} // namespace OrielOSTour
