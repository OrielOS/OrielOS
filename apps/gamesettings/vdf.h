// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>
#include <QStringList>

#include <optional>

namespace OrielOSGames {

// One entry of Valve's text KeyValues format (VDF), which Steam keeps its settings and manifests
// in: a key with either a value or a block of entries. Keys keep their order and case; Steam
// matches them without regard to case.
struct VdfNode
{
    QString key;
    QString value;
    QList<VdfNode> children;
    bool block = false;

    // The entry under this one with the key, matched without regard to case, or nullptr.
    VdfNode *child(const QString &name);
    const VdfNode *child(const QString &name) const;
    // The entry at the path of keys under this one, or nullptr.
    const VdfNode *find(const QStringList &path) const;
    // The block at the path, made where it's missing.
    VdfNode &ensure(const QStringList &path);
    // The value of the entry with the key, or an empty string.
    QString valueOf(const QString &name) const;
    // Sets the value of the entry with the key, adding it where it's missing.
    void set(const QString &name, const QString &value);
    // Removes the entries with the key; says whether there were any.
    bool remove(const QString &name);
};

// Parses a whole file into a root block. Comments (//) and unquoted tokens are read as Steam
// reads them; conditions such as [$WIN32] are skipped. Nothing for malformed text.
std::optional<VdfNode> parseVdf(const QString &text);
// Writes the root block's entries back in Steam's layout: tabs, quoted keys and values.
QString writeVdf(const VdfNode &root);

} // namespace OrielOSGames
