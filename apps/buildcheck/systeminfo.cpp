// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "systeminfo.h"

#include "osrelease.h"

SystemInfo::SystemInfo(QObject *parent)
    : QObject(parent)
    , m_prettyName(OrielOS::OsRelease::fromSystem().prettyName())
{
}

QString SystemInfo::prettyName() const
{
    return m_prettyName;
}
