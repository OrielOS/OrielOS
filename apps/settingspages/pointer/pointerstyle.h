// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QProcess>
#include <QStringList>
#include <qqmlintegration.h>

namespace OrielOSSettingsPages {

// The mouse pointer's colour and size, as Windows' Accessibility › Mouse pointer offers them: white
// (Breeze's light pointers) or black (Breeze's), from 24 to 96 pixels. Read from kcminputrc, where
// Plasma keeps them, and applied with plasma-apply-cursortheme in its own process, so the change
// shows at once without loading Plasma's pointer module into Settings.
class PointerStyle : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool white READ isWhite NOTIFY changed FINAL)
    Q_PROPERTY(int size READ size NOTIFY changed FINAL)
    Q_PROPERTY(int minimumSize READ minimumSize CONSTANT FINAL)
    Q_PROPERTY(int maximumSize READ maximumSize CONSTANT FINAL)
    Q_PROPERTY(int sizeStep READ sizeStep CONSTANT FINAL)
    Q_PROPERTY(bool busy READ isBusy NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    explicit PointerStyle(QObject *parent = nullptr);
    ~PointerStyle() override;

    bool isWhite() const;
    int size() const;
    static int minimumSize() { return 24; }
    static int maximumSize() { return 96; }
    static int sizeStep() { return 8; }
    bool isBusy() const { return m_process != nullptr; }
    QString error() const { return m_error; }

    // Change the colour, keeping the size, or the size, keeping the colour.
    Q_INVOKABLE void setWhite(bool white);
    Q_INVOKABLE void setSize(int size);
    // Read the settings again.
    Q_INVOKABLE void reload();

    // Read kcminputrc from this file and run program with arguments, then the theme's, instead of
    // plasma-apply-cursortheme. For the unit tests.
    void setForTesting(const QString &config, const QString &program, const QStringList &arguments);

Q_SIGNALS:
    void changed();
    void applied(bool ok);

private:
    void apply(const QString &theme, int size);

    QString m_theme;
    int m_size = 24;
    QString m_config;
    QString m_program;
    QStringList m_arguments;
    QProcess *m_process = nullptr;
    QString m_error;
};

} // namespace OrielOSSettingsPages
