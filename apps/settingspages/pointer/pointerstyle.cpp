// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "pointerstyle.h"

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>

#include <algorithm>

namespace OrielOSSettingsPages {

namespace {

const QString whiteTheme = QStringLiteral("Breeze_Light");
// Plasma's default pointers.
const QString blackTheme = QStringLiteral("breeze_cursors");

} // namespace

PointerStyle::PointerStyle(QObject *parent)
    : QObject(parent)
    , m_config(QStringLiteral("kcminputrc"))
    , m_program(QStringLiteral("plasma-apply-cursortheme"))
{
    reload();
}

PointerStyle::~PointerStyle()
{
    if (m_process) {
        disconnect(m_process, nullptr, this, nullptr);
        m_process->waitForFinished(5000);
    }
}

bool PointerStyle::isWhite() const
{
    return m_theme == whiteTheme;
}

int PointerStyle::size() const
{
    return m_size;
}

void PointerStyle::reload()
{
    const KConfig config(m_config);
    const KConfigGroup mouse(&config, QStringLiteral("Mouse"));
    m_theme = mouse.readEntry("cursorTheme", blackTheme);
    m_size = mouse.readEntry("cursorSize", 24);
    Q_EMIT changed();
}

void PointerStyle::setWhite(bool white)
{
    if (white != isWhite()) {
        apply(white ? whiteTheme : blackTheme, m_size);
    }
}

void PointerStyle::setSize(int size)
{
    size = std::clamp(size, minimumSize(), maximumSize());
    if (size != m_size) {
        // Another theme than these two keeps its name.
        apply(m_theme, size);
    }
}

void PointerStyle::setForTesting(const QString &config, const QString &program, const QStringList &arguments)
{
    m_config = config;
    m_program = program;
    m_arguments = arguments;
    reload();
}

void PointerStyle::apply(const QString &theme, int size)
{
    if (m_process) {
        return;
    }
    m_error.clear();
    m_process = new QProcess(this);
    const auto finish = [this](bool ok) {
        m_process->deleteLater();
        m_process = nullptr;
        if (!ok) {
            m_error = i18nc("@info", "The mouse pointer couldn't be changed.");
        }
        reload();
        Q_EMIT applied(ok);
    };
    connect(
        m_process, &QProcess::finished, this, [finish](int exitCode, QProcess::ExitStatus status) { finish(status == QProcess::NormalExit && exitCode == 0); });
    connect(m_process, &QProcess::errorOccurred, this, [finish](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            finish(false);
        }
    });
    m_process->start(m_program, m_arguments + QStringList { QStringLiteral("--size"), QString::number(size), theme });
    Q_EMIT changed();
}

} // namespace OrielOSSettingsPages
