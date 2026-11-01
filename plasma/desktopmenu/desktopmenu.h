// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <Plasma/ContainmentActions>

#include <QVariant>

#include <memory>

class QMenu;

namespace OrielOSDesktopMenu {

/**
 * The desktop's right-click menu in Windows' order: View, Sort by, Refresh, Undo and Paste when
 * there's something to undo or paste, New, Display settings, Personalise, Open in Terminal, and
 * Show more options with the rest of Plasma's (widgets, edit mode, the wallpaper's own actions and
 * the desktop's settings). View, Sort by, New, Undo and Paste are the desktop folder view's own
 * actions, rearranged; the folder view keeps its menu for icons.
 */
class DesktopMenu : public Plasma::ContainmentActions
{
    Q_OBJECT

public:
    explicit DesktopMenu(QObject *parent, const QVariantList &args);
    ~DesktopMenu() override;

    QList<QAction *> contextualActions() override;

private:
    QAction *separator();
    void refresh();
    void openTerminal();

    QAction *m_view = nullptr;
    QAction *m_sortBy = nullptr;
    QAction *m_refresh = nullptr;
    QAction *m_displaySettings = nullptr;
    QAction *m_personalise = nullptr;
    QAction *m_terminal = nullptr;
    QAction *m_more = nullptr;
    std::unique_ptr<QMenu> m_viewMenu;
    std::unique_ptr<QMenu> m_moreMenu;
    QList<QAction *> m_separators;
};

} // namespace OrielOSDesktopMenu
