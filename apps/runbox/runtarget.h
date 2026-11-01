// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QString>
#include <QStringList>

#include <functional>

namespace RunBox {

// What the Run box does with what was typed.
struct Target
{
    enum class Kind {
        // Nothing was typed.
        Empty,
        // A website or other address, opened in its app.
        Url,
        // A file or folder that exists, opened in its app.
        Path,
        // A program, run with its arguments.
        Command,
        // Nothing by that name.
        NotFound,
    };
    Kind kind = Kind::Empty;
    // The address, the path as a file URL, or the command line.
    QString value;
};

// Finds the program a command names, as a path, or nothing.
using FindProgram = std::function<QString(const QString &program)>;

// Works out what to do with text typed into the Run box. Windows' own program names (cmd,
// explorer, control, taskmgr…) open OrielOS's equivalents.
Target resolve(const QString &text, const QString &home, const FindProgram &findProgram);

// OrielOS's program for a Windows program name typed in the Run box, with or without ".exe", or
// the name itself when it isn't one of them.
QString equivalentProgram(const QString &program);

// The history with text at the front, once, keeping the newest entries.
QStringList remember(const QStringList &history, const QString &text);

// How many entries the history keeps, as Windows does.
constexpr int HistoryLength = 26;

} // namespace RunBox
