// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "desktopmenu.h"

#include <KDirNotify>
#include <KLocalizedString>
#include <KPluginFactory>
#include <KTerminalLauncherJob>
#include <Plasma/Containment>
#include <Plasma/Corona>

#include <QAction>
#include <QDesktopServices>
#include <QMenu>
#include <QQmlListProperty>
#include <QStandardPaths>
#include <QUrl>

K_PLUGIN_CLASS_WITH_JSON(OrielOSDesktopMenu::DesktopMenu, "desktopmenu.json")

namespace OrielOSDesktopMenu {

namespace {

// The folder view's actions among the desktop's, found by their icons: they have no names.
QAction *findByIcon(const QList<QAction *> &actions, const QString &iconName)
{
    for (QAction *action : actions) {
        if (action && action->icon().name() == iconName) {
            return action;
        }
    }
    return nullptr;
}

QString desktopFolder()
{
    return QStandardPaths::writableLocation(QStandardPaths::DesktopLocation);
}

} // namespace

DesktopMenu::DesktopMenu(QObject *parent, const QVariantList &args)
    : Plasma::ContainmentActions(parent, args)
    , m_viewMenu(std::make_unique<QMenu>())
    , m_moreMenu(std::make_unique<QMenu>())
{
    m_view = new QAction(QIcon::fromTheme(QStringLiteral("view-list-icons")), i18nc("@action:inmenu The desktop's icon options", "View"), this);
    m_view->setMenu(m_viewMenu.get());

    m_sortBy = new QAction(QIcon::fromTheme(QStringLiteral("view-sort")), i18nc("@action:inmenu", "Sort by"), this);

    m_refresh = new QAction(QIcon::fromTheme(QStringLiteral("view-refresh")), i18nc("@action:inmenu", "Refresh"), this);
    connect(m_refresh, &QAction::triggered, this, &DesktopMenu::refresh);

    m_displaySettings = new QAction(QIcon::fromTheme(QStringLiteral("preferences-desktop-display")), i18nc("@action:inmenu", "Display settings"), this);
    connect(m_displaySettings, &QAction::triggered, this, []() { QDesktopServices::openUrl(QUrl(QStringLiteral("orielos-settings:display"))); });

    m_personalise = new QAction(
        QIcon::fromTheme(QStringLiteral("preferences-desktop-wallpaper")), i18nc("@action:inmenu Change the wallpaper and colours", "Personalise"), this);
    connect(m_personalise, &QAction::triggered, this, []() { QDesktopServices::openUrl(QUrl(QStringLiteral("orielos-settings:background"))); });

    m_terminal = new QAction(QIcon::fromTheme(QStringLiteral("utilities-terminal")), i18nc("@action:inmenu", "Open in Terminal"), this);
    connect(m_terminal, &QAction::triggered, this, &DesktopMenu::openTerminal);

    m_more = new QAction(QIcon::fromTheme(QStringLiteral("overflow-menu")), i18nc("@action:inmenu", "Show more options"), this);
    m_more->setMenu(m_moreMenu.get());
}

DesktopMenu::~DesktopMenu() = default;

QAction *DesktopMenu::separator()
{
    // Each separator in the menu is its own action.
    auto *action = new QAction(this);
    action->setSeparator(true);
    m_separators.append(action);
    return action;
}

void DesktopMenu::refresh()
{
    // The desktop's folder view lists the folder again when told it has changed.
    org::kde::KDirNotify::emitFilesAdded(QUrl(QStringLiteral("desktop:/")));
    org::kde::KDirNotify::emitFilesAdded(QUrl::fromLocalFile(desktopFolder()));
}

void DesktopMenu::openTerminal()
{
    auto *job = new KTerminalLauncherJob(QString());
    job->setWorkingDirectory(desktopFolder());
    job->start();
}

QList<QAction *> DesktopMenu::contextualActions()
{
    Plasma::Containment *desktop = containment();
    qDeleteAll(m_separators);
    m_separators.clear();
    m_viewMenu->clear();
    m_moreMenu->clear();

    // The folder view's: New, Paste, Undo, Empty Bin, and its Icons menu.
    const QList<QAction *> folder = desktop->contextualActions();
    QAction *newMenu = findByIcon(folder, QStringLiteral("document-new"));
    QAction *paste = findByIcon(folder, QStringLiteral("edit-paste"));
    QAction *undo = findByIcon(folder, QStringLiteral("edit-undo"));
    QAction *emptyBin = findByIcon(folder, QStringLiteral("edit-delete"));
    QAction *icons = findByIcon(folder, QStringLiteral("view-list-icons"));

    // View holds the Icons menu's options but Sort By, which comes next on its own.
    QMenu *sortMenu = nullptr;
    if (QMenu *iconsMenu = icons ? icons->menu<QMenu *>() : nullptr) {
        for (QAction *option : iconsMenu->actions()) {
            if (option->menu<QMenu *>() && option->icon().name() == QStringLiteral("view-sort")) {
                sortMenu = option->menu<QMenu *>();
            } else {
                m_viewMenu->addAction(option);
            }
        }
    }
    m_sortBy->setMenu(sortMenu);

    QList<QAction *> actions;
    if (!m_viewMenu->isEmpty()) {
        actions << m_view;
    }
    if (sortMenu) {
        actions << m_sortBy;
    }
    actions << m_refresh;
    if (undo && undo->isEnabled()) {
        actions << undo;
    }
    if (paste && paste->isEnabled()) {
        actions << paste;
    }
    if (newMenu) {
        actions << newMenu;
    }
    actions << separator() << m_displaySettings << m_personalise << separator() << m_terminal;

    // Show more options: what Plasma's own menu offers that Windows' first menu doesn't.
    if (emptyBin && emptyBin->isVisible()) {
        m_moreMenu->addAction(emptyBin);
    }
    for (const QString &name : { QStringLiteral("add widgets"), QStringLiteral("configure") }) {
        if (QAction *action = desktop->internalAction(name)) {
            m_moreMenu->addAction(action);
        }
    }
    if (desktop->corona()) {
        if (QAction *editMode = desktop->corona()->action(QStringLiteral("edit mode"))) {
            m_moreMenu->addAction(editMode);
        }
    }
    if (auto *wallpaper = desktop->property("wallpaperGraphicsObject").value<QObject *>()) {
        auto list = wallpaper->property("contextualActions").value<QQmlListProperty<QAction>>();
        if (list.count && list.at) {
            const qsizetype count = list.count(&list);
            if (count > 0) {
                m_moreMenu->addSeparator();
            }
            for (qsizetype i = 0; i < count; ++i) {
                m_moreMenu->addAction(list.at(&list, i));
            }
        }
    }
    if (!m_moreMenu->isEmpty()) {
        actions << separator() << m_more;
    }
    return actions;
}

} // namespace OrielOSDesktopMenu

#include "desktopmenu.moc"
