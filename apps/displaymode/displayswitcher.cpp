// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "displayswitcher.h"

#include <KScreen/Config>
#include <KScreen/GetConfigOperation>
#include <KScreen/Output>
#include <KScreen/SetConfigOperation>

#include <algorithm>

using namespace DisplayLayout;

DisplaySwitcher::DisplaySwitcher(QObject *parent)
    : QObject(parent)
{
    load();
}

void DisplaySwitcher::load()
{
    auto *operation = new KScreen::GetConfigOperation();
    connect(operation, &KScreen::ConfigOperation::finished, this, [this](KScreen::ConfigOperation *op) {
        if (op->hasError()) {
            qWarning("orielos-display-mode: can't read the screen configuration: %s", qPrintable(op->errorString()));
            return;
        }
        m_config = qobject_cast<KScreen::GetConfigOperation *>(op)->config();
        Q_EMIT changed();
    });
}

bool DisplaySwitcher::ready() const
{
    return m_config != nullptr;
}

int DisplaySwitcher::screenCount() const
{
    return m_config ? int(m_config->connectedOutputs().size()) : 0;
}

int DisplaySwitcher::currentMode() const
{
    return int(DisplayLayout::currentMode(screens()));
}

QList<Screen> DisplaySwitcher::screens() const
{
    QList<Screen> result;
    if (!m_config) {
        return result;
    }
    const KScreen::OutputList outputs = m_config->connectedOutputs();
    bool haveBuiltIn = false;
    for (const KScreen::OutputPtr &output : outputs) {
        haveBuiltIn = haveBuiltIn || output->type() == KScreen::Output::Panel;
    }
    // OutputList is ordered by id, so without a built-in screen the first one is the main one.
    for (const KScreen::OutputPtr &output : outputs) {
        Screen screen;
        screen.id = output->id();
        screen.main = haveBuiltIn ? output->type() == KScreen::Output::Panel : result.isEmpty();
        // Only one built-in screen counts as the main one.
        if (screen.main && std::any_of(result.cbegin(), result.cend(), [](const Screen &s) { return s.main; })) {
            screen.main = false;
        }
        screen.enabled = output->isEnabled();
        screen.position = output->pos();
        screen.replicationSource = output->replicationSource();
        screen.priority = output->priority();
        result.append(screen);
    }
    return result;
}

void DisplaySwitcher::apply(int mode)
{
    if (!m_config) {
        Q_EMIT applied(false);
        return;
    }
    const KScreen::ConfigPtr config = m_config->clone();
    const KScreen::OutputList outputs = config->connectedOutputs();

    // A screen that is off has no mode yet; it gets its preferred one, so its size is known.
    QList<Screen> current = screens();
    for (Screen &screen : current) {
        const KScreen::OutputPtr output = outputs.value(screen.id);
        if (output->currentModeId().isEmpty() || !output->currentMode()) {
            output->setCurrentModeId(output->preferredModeId());
        }
        screen.logicalSize = config->logicalSizeForOutputInt(*output);
    }

    const QList<Screen> arranged = arrange(current, static_cast<Mode>(mode));
    for (const Screen &screen : arranged) {
        const KScreen::OutputPtr output = outputs.value(screen.id);
        output->setEnabled(screen.enabled);
        output->setReplicationSource(screen.replicationSource);
        if (screen.enabled) {
            output->setPos(screen.position);
            config->setOutputPriority(output, screen.priority);
        }
    }
    if (!KScreen::Config::canBeApplied(config)) {
        qWarning("orielos-display-mode: the screens can't be set up that way");
        Q_EMIT applied(false);
        return;
    }

    auto *operation = new KScreen::SetConfigOperation(config);
    connect(operation, &KScreen::ConfigOperation::finished, this, [this, config](KScreen::ConfigOperation *op) {
        const bool succeeded = !op->hasError();
        if (succeeded) {
            m_config = config;
            Q_EMIT changed();
        } else {
            qWarning("orielos-display-mode: can't change the screens: %s", qPrintable(op->errorString()));
        }
        Q_EMIT applied(succeeded);
    });
}
