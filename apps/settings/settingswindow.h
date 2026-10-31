// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "pagecatalogue.h"

#include <QHash>
#include <QWidget>

#include <memory>

class KCModule;
class QLabel;
class QLineEdit;
class QListWidget;
class QListWidgetItem;
class QPushButton;
class QQmlEngine;
class QStackedWidget;

namespace OrielOSSettings {

// The Settings window: the account, search and the categories on the left, Home first; on the
// right, Home (recommended and recently used settings), a category's pages, the search results, or
// a page. Pages are Plasma settings modules, QML or Qt Widgets, loaded on
// first use with KCModuleLoader into a stack; every QML module shares one engine. The window owns
// the Apply, Reset and Defaults buttons, shows those each module asks for, and asks about unsaved
// changes before leaving a page or closing.
class SettingsWindow : public QWidget
{
    Q_OBJECT

public:
    explicit SettingsWindow(PageCatalogue catalogue, QWidget *parent = nullptr);

    // The category the modules Settings has no page of its own for go under.
    static QString moreCategoryId();

    // Show a page, by its ID or its module's ID, or a category by its ID; any other installed
    // settings module, by its ID, shows under More settings, as systemsettings and kcmshell6 ask.
    // Returns false if there's no such page, category or module, or if the user chose to stay on a
    // page with unsaved changes.
    bool open(const QString &target);
    // Show Home.
    void openFirst();

protected:
    void closeEvent(QCloseEvent *event) override;

private:
    void showHome();
    void showCategory(const QString &categoryId);
    // Remembers a page for Home's recently used settings.
    void rememberPage(const QString &pageId);
    void showPage(const Page &page);
    void showSearch(const QString &query);
    void openListItem(QListWidgetItem *item);
    void selectCategory(const QString &categoryId);
    // Offers to apply or discard the current page's unsaved changes. Returns false to stay.
    bool leaveCurrentPage();
    QWidget *pageWidget(const Page &page);
    KCModule *currentModule() const;
    void updateButtons();

    PageCatalogue m_catalogue;
    QLineEdit *m_search = nullptr;
    QListWidget *m_categories = nullptr;
    QLabel *m_heading = nullptr;
    QStackedWidget *m_stack = nullptr;
    // A category's pages, or the search results.
    QListWidget *m_list = nullptr;
    QLabel *m_noResults = nullptr;
    QWidget *m_buttonBar = nullptr;
    QPushButton *m_defaults = nullptr;
    QPushButton *m_reset = nullptr;
    QPushButton *m_apply = nullptr;
    // The modules loaded so far, by page ID; a page whose module didn't load has none.
    QHash<QString, KCModule *> m_modules;
    QHash<QString, QWidget *> m_widgets;
    QString m_currentPage;
    QString m_currentCategory;
    std::shared_ptr<QQmlEngine> m_engine;
};

} // namespace OrielOSSettings
