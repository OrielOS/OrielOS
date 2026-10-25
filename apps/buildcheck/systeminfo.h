// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QObject>
#include <QString>
#include <QtQmlIntegration>

/**
 * The running system's identification, from os-release, for QML.
 */
class SystemInfo : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString prettyName READ prettyName CONSTANT FINAL)

public:
    explicit SystemInfo(QObject *parent = nullptr);

    QString prettyName() const;

private:
    QString m_prettyName;
};
