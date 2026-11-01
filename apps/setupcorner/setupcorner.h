// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QStringList>
#include <qqmlintegration.h>

#include <utility>

// What the first-run setup's bottom-left corner controls, as Windows' setup offers there before
// anything is typed: the accessibility tools (screen reader, magnifier, on-screen keyboard, high
// contrast), the volume and the keyboard layout. Each works through the session's own services:
// kglobalaccel's shortcuts for the screen reader and KWin's zoom, KWin's virtual keyboard, the
// accessibility-keys script for contrast, WirePlumber for the volume and KWin's keyboard layouts.
class SetupCorner : public QObject
{
    Q_OBJECT
    QML_ELEMENT

    // The keyboard layout in use, by its short name such as "gb", and how many there are.
    Q_PROPERTY(QString layout READ layout NOTIFY layoutChanged FINAL)
    Q_PROPERTY(QString layoutName READ layoutName NOTIFY layoutChanged FINAL)
    Q_PROPERTY(int layoutCount READ layoutCount NOTIFY layoutChanged FINAL)
    // The speakers' volume, 0 to 100, and whether they're muted.
    Q_PROPERTY(int volume READ volume NOTIFY volumeChanged FINAL)
    Q_PROPERTY(bool muted READ isMuted NOTIFY volumeChanged FINAL)
    Q_PROPERTY(bool magnified READ isMagnified NOTIFY magnifiedChanged FINAL)
    Q_PROPERTY(bool keyboardShown READ isKeyboardShown NOTIFY keyboardShownChanged FINAL)

public:
    explicit SetupCorner(QObject *parent = nullptr);

    QString layout() const { return m_layout; }
    QString layoutName() const { return m_layoutName; }
    int layoutCount() const { return m_layoutCount; }
    int volume() const { return m_volume; }
    bool isMuted() const { return m_muted; }
    bool isMagnified() const { return m_magnified; }
    bool isKeyboardShown() const;

    Q_INVOKABLE void nextLayout();
    Q_INVOKABLE void setVolume(int percent);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void toggleScreenReader();
    Q_INVOKABLE void toggleMagnifier();
    Q_INVOKABLE void toggleKeyboard();
    Q_INVOKABLE void toggleContrast();

    // WirePlumber's "Volume: 0.40 [MUTED]" as a percentage and whether it's muted. Public for the
    // unit tests.
    static std::pair<int, bool> parseVolume(const QString &output);

Q_SIGNALS:
    void layoutChanged();
    void volumeChanged();
    void magnifiedChanged();
    void keyboardShownChanged();

private Q_SLOTS:
    void readLayout();

private:
    void readVolume();
    static void invokeShortcut(const QString &component, const QString &shortcut);

    QString m_layout;
    QString m_layoutName;
    int m_layoutCount = 0;
    int m_volume = 0;
    bool m_muted = false;
    bool m_magnified = false;
};
