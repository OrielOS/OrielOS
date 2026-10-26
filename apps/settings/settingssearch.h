// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "pagecatalogue.h"

#include <KPluginMetaData>

namespace OrielOSSettings {

// A setting found by Start's or KRunner's search, and how to open it.
struct SettingsResult
{
    // The Settings page's ID, or the module's for System Settings.
    QString id;
    QString title;
    // Where it opens, such as "Settings › System".
    QString subtext;
    QString icon;
    // The program and its arguments: orielos-settings <page>, or systemsettings <module>.
    QStringList command;
    // As PageCatalogue::rank(): 0 when the title starts with the query, up to 3.
    int rank = 0;
    bool inSettings = true;
};

// What search shows for settings: Settings' own pages first, then the other modules System
// Settings lists, so every module can still be found, each opened where it lives and none twice.
class SettingsSearch
{
public:
    // settings: Settings' pages, with their icons. others: the other modules, as pages without a
    // category.
    SettingsSearch(PageCatalogue settings, QList<Page> others);

    // Settings' installed pages and every other module System Settings lists, as installed now.
    static SettingsSearch installed();

    // The other modules from System Settings' module list, leaving out those Settings has a page
    // for.
    static QList<Page> otherModules(const PageCatalogue &settings, const QList<KPluginMetaData> &modules);

    // Every match for the query, Settings' first, each list best first.
    QList<SettingsResult> search(const QString &query) const;

private:
    PageCatalogue m_settings;
    PageCatalogue m_others;
};

} // namespace OrielOSSettings
