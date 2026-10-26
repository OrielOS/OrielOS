// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <QList>
#include <QString>
#include <QStringList>

#include <functional>
#include <optional>

namespace OrielOSSettings {

// A group of pages in the sidebar, such as System or Bluetooth & devices.
struct Category
{
    QString id;
    QString title;
    QString icon;
};

// One settings page: a Plasma settings module shown under a category.
struct Page
{
    QString id;
    QString category;
    QString title;
    // One line under the title in the category's list.
    QString description;
    // Other words people search for, Windows' among them.
    QStringList keywords;
    // The settings module's plugin ID, such as kcm_kscreen.
    QString module;
    QString icon;
};

// The Settings app's categories and pages, in the order Windows Settings uses, and search over
// them. Pure data and rules, so they can be tested without a desktop.
class PageCatalogue
{
public:
    PageCatalogue() = default;
    PageCatalogue(QList<Category> categories, QList<Page> pages);

    // Every page OrielOS shows, whether or not its module is installed.
    static PageCatalogue standard();

    // The pages whose module is installed, and the categories that still have a page.
    PageCatalogue available(const std::function<bool(const QString &module)> &isInstalled) const;

    QList<Category> categories() const { return m_categories; }
    std::optional<Category> category(const QString &id) const;
    // A category's pages, in order.
    QList<Page> pages(const QString &categoryId) const;
    // A page by its ID or by its module's ID.
    std::optional<Page> page(const QString &idOrModule) const;

    // The pages that match every word of the query, best first: a match at the start of the title,
    // then anywhere in the title, then in the keywords, the category's name and the description.
    // Words match from their start, ignoring case and accents.
    QList<Page> search(const QString &query) const;
    // How well a page matches the query, as search() orders them: 0 when its title starts with
    // the query, 1 when every word is in its title, 2 in its title and keywords, 3 anywhere; -1
    // when it doesn't match.
    int rank(const Page &page, const QString &query) const;

private:
    QList<Category> m_categories;
    QList<Page> m_pages;
};

} // namespace OrielOSSettings
