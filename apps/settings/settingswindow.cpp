// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "settingswindow.h"

#include <KCModule>
#include <KCModuleLoader>
#include <KLocalizedString>
#include <KMessageBox>
#include <KStandardGuiItem>

#include <QAction>
#include <QCloseEvent>
#include <QHBoxLayout>
#include <QIcon>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QPushButton>
#include <QQmlEngine>
#include <QStackedWidget>
#include <QVBoxLayout>

namespace OrielOSSettings {

namespace {

// Where System Settings finds its modules: Plasma's QML and Qt Widgets ones, other Plasma ones,
// and Info Center's, such as About.
const QStringList moduleNamespaces {
    QStringLiteral("plasma/kcms/systemsettings"),
    QStringLiteral("plasma/kcms/systemsettings_qwidgets"),
    QStringLiteral("plasma/kcms"),
    QStringLiteral("plasma/kcms/kinfocenter"),
};

constexpr int idRole = Qt::UserRole;
constexpr int kindRole = Qt::UserRole + 1;
const QString pageKind = QStringLiteral("page");

} // namespace

KPluginMetaData findModule(const QString &id)
{
    for (const QString &space : moduleNamespaces) {
        const KPluginMetaData metadata = KPluginMetaData::findPluginById(space, id);
        if (metadata.isValid()) {
            return metadata;
        }
    }
    return { };
}

SettingsWindow::SettingsWindow(PageCatalogue catalogue, QWidget *parent)
    : QWidget(parent)
    , m_catalogue(std::move(catalogue))
    , m_engine(std::make_shared<QQmlEngine>())
{
    setWindowTitle(i18nc("@title:window", "Settings"));
    setWindowIcon(QIcon::fromTheme(QStringLiteral("preferences-system")));
    resize(1100, 720);

    // The sidebar: search, then the categories.
    m_search = new QLineEdit;
    m_search->setPlaceholderText(i18nc("@info:placeholder", "Find a setting"));
    m_search->setClearButtonEnabled(true);
    m_search->addAction(QIcon::fromTheme(QStringLiteral("search")), QLineEdit::LeadingPosition);
    m_search->setAccessibleName(i18nc("@label:textbox", "Find a setting"));

    m_categories = new QListWidget;
    m_categories->setFrameShape(QFrame::NoFrame);
    m_categories->setIconSize(QSize(22, 22));
    m_categories->setAccessibleName(i18nc("@label", "Categories"));
    for (const Category &category : m_catalogue.categories()) {
        auto *item = new QListWidgetItem(QIcon::fromTheme(category.icon), category.title, m_categories);
        item->setData(idRole, category.id);
        item->setSizeHint(QSize(0, 36));
    }

    auto *sidebar = new QVBoxLayout;
    sidebar->addWidget(m_search);
    sidebar->addWidget(m_categories, 1);
    auto *sidebarWidget = new QWidget;
    sidebarWidget->setLayout(sidebar);
    sidebarWidget->setFixedWidth(280);

    // The page area: a heading, then the list or a page, then the buttons.
    m_heading = new QLabel;
    QFont headingFont = m_heading->font();
    headingFont.setPointSizeF(headingFont.pointSizeF() * 1.6);
    m_heading->setFont(headingFont);
    m_heading->setTextFormat(Qt::PlainText);

    m_list = new QListWidget;
    m_list->setFrameShape(QFrame::NoFrame);
    m_list->setIconSize(QSize(32, 32));
    m_list->setSpacing(4);
    m_noResults = new QLabel(i18nc("@info", "No settings match your search."));
    m_noResults->setAlignment(Qt::AlignCenter);
    m_stack = new QStackedWidget;
    m_stack->addWidget(m_list);
    m_stack->addWidget(m_noResults);

    m_defaults = new QPushButton;
    KGuiItem::assign(m_defaults, KStandardGuiItem::defaults());
    m_reset = new QPushButton;
    KGuiItem::assign(m_reset, KStandardGuiItem::reset());
    m_apply = new QPushButton;
    KGuiItem::assign(m_apply, KStandardGuiItem::apply());
    auto *buttons = new QHBoxLayout;
    buttons->setContentsMargins(0, 0, 0, 0);
    buttons->addWidget(m_defaults);
    buttons->addStretch();
    buttons->addWidget(m_reset);
    buttons->addWidget(m_apply);
    m_buttonBar = new QWidget;
    m_buttonBar->setLayout(buttons);

    auto *content = new QVBoxLayout;
    content->addWidget(m_heading);
    content->addWidget(m_stack, 1);
    content->addWidget(m_buttonBar);

    auto *layout = new QHBoxLayout(this);
    layout->addWidget(sidebarWidget);
    layout->addLayout(content, 1);

    // Staying on a page with unsaved changes puts the sidebar back on that page's category.
    const auto openCategory = [this](QListWidgetItem *item) {
        if (!open(item->data(idRole).toString())) {
            selectCategory(m_currentCategory);
        }
    };
    connect(m_categories, &QListWidget::itemClicked, this, openCategory);
    connect(m_categories, &QListWidget::itemActivated, this, openCategory);
    connect(m_list, &QListWidget::itemActivated, this, &SettingsWindow::openListItem);
    connect(m_list, &QListWidget::itemClicked, this, &SettingsWindow::openListItem);
    connect(m_search, &QLineEdit::textChanged, this, [this](const QString &text) {
        if (text.trimmed().isEmpty()) {
            showCategory(m_currentCategory);
        } else {
            showSearch(text);
        }
    });
    // Enter opens the best match.
    connect(m_search, &QLineEdit::returnPressed, this, [this] {
        const QList<Page> results = m_catalogue.search(m_search->text());
        if (!results.isEmpty()) {
            showPage(results.first());
        }
    });
    connect(m_defaults, &QPushButton::clicked, this, [this] {
        if (KCModule *module = currentModule()) {
            module->defaults();
        }
    });
    connect(m_reset, &QPushButton::clicked, this, [this] {
        if (KCModule *module = currentModule()) {
            module->load();
        }
    });
    connect(m_apply, &QPushButton::clicked, this, [this] {
        if (KCModule *module = currentModule()) {
            module->save();
        }
    });

    auto *find = new QAction(this);
    find->setShortcut(QKeySequence::Find);
    connect(find, &QAction::triggered, this, [this] {
        m_search->setFocus(Qt::ShortcutFocusReason);
        m_search->selectAll();
    });
    addAction(find);

    m_buttonBar->hide();
}

bool SettingsWindow::open(const QString &target)
{
    if (const std::optional<Page> page = m_catalogue.page(target)) {
        if (!leaveCurrentPage()) {
            return false;
        }
        showPage(*page);
        return true;
    }
    if (m_catalogue.category(target)) {
        if (!leaveCurrentPage()) {
            return false;
        }
        m_search->clear();
        showCategory(target);
        return true;
    }
    return false;
}

void SettingsWindow::openFirst()
{
    if (!m_catalogue.categories().isEmpty()) {
        open(m_catalogue.categories().first().id);
    }
}

void SettingsWindow::closeEvent(QCloseEvent *event)
{
    if (leaveCurrentPage()) {
        event->accept();
    } else {
        event->ignore();
    }
}

void SettingsWindow::showCategory(const QString &categoryId)
{
    const std::optional<Category> category = m_catalogue.category(categoryId);
    if (!category) {
        return;
    }
    const QList<Page> pages = m_catalogue.pages(categoryId);
    // A category with one page, such as Update, opens it straight away.
    if (pages.size() == 1) {
        showPage(pages.first());
        return;
    }
    m_currentCategory = categoryId;
    m_currentPage.clear();
    selectCategory(categoryId);
    m_heading->setText(category->title);
    m_list->clear();
    for (const Page &page : pages) {
        const KPluginMetaData metadata = findModule(page.module);
        const QString icon = page.icon.isEmpty() ? metadata.iconName() : page.icon;
        auto *item = new QListWidgetItem(QIcon::fromTheme(icon), page.title + QLatin1Char('\n') + page.description, m_list);
        item->setData(idRole, page.id);
        item->setData(kindRole, pageKind);
        item->setToolTip(page.description);
    }
    m_stack->setCurrentWidget(m_list);
    updateButtons();
}

void SettingsWindow::showSearch(const QString &query)
{
    m_currentPage.clear();
    m_heading->setText(i18nc("@title", "Search results"));
    m_list->clear();
    const QList<Page> results = m_catalogue.search(query);
    for (const Page &page : results) {
        const std::optional<Category> category = m_catalogue.category(page.category);
        const QString where = category && m_catalogue.pages(page.category).size() > 1
            ? i18nc("@item A settings page in its category: %1 is the category, %2 the page", "%1 › %2", category->title, page.title)
            : page.title;
        const KPluginMetaData metadata = findModule(page.module);
        const QString icon = page.icon.isEmpty() ? metadata.iconName() : page.icon;
        auto *item = new QListWidgetItem(QIcon::fromTheme(icon), where + QLatin1Char('\n') + page.description, m_list);
        item->setData(idRole, page.id);
        item->setData(kindRole, pageKind);
    }
    m_stack->setCurrentWidget(results.isEmpty() ? static_cast<QWidget *>(m_noResults) : m_list);
    updateButtons();
}

void SettingsWindow::openListItem(QListWidgetItem *item)
{
    if (item && item->data(kindRole).toString() == pageKind) {
        if (const std::optional<Page> page = m_catalogue.page(item->data(idRole).toString())) {
            showPage(*page);
        }
    }
}

void SettingsWindow::showPage(const Page &page)
{
    if (page.id == m_currentPage) {
        return;
    }
    if (!leaveCurrentPage()) {
        return;
    }
    QWidget *widget = pageWidget(page);
    m_currentPage = page.id;
    m_currentCategory = page.category;
    selectCategory(page.category);
    const std::optional<Category> category = m_catalogue.category(page.category);
    m_heading->setText(category && m_catalogue.pages(page.category).size() > 1
            ? i18nc("@title A settings page in its category: %1 is the category, %2 the page", "%1 › %2", category->title, page.title)
            : page.title);
    m_stack->setCurrentWidget(widget);
    updateButtons();
}

void SettingsWindow::selectCategory(const QString &categoryId)
{
    const QSignalBlocker blocker(m_categories);
    for (int row = 0; row < m_categories->count(); ++row) {
        if (m_categories->item(row)->data(idRole).toString() == categoryId) {
            m_categories->setCurrentRow(row);
            return;
        }
    }
}

bool SettingsWindow::leaveCurrentPage()
{
    KCModule *module = currentModule();
    if (!module || !module->needsSave()) {
        return true;
    }
    const std::optional<Page> page = m_catalogue.page(m_currentPage);
    const KMessageBox::ButtonCode answer = KMessageBox::warningTwoActionsCancel(this,
        i18nc("@info %1 is a settings page", "The settings on the %1 page have changed. Apply them or discard them?", page ? page->title : QString()),
        i18nc("@title:window", "Apply settings?"), KStandardGuiItem::apply(), KStandardGuiItem::discard());
    switch (answer) {
    case KMessageBox::PrimaryAction:
        module->save();
        return true;
    case KMessageBox::SecondaryAction:
        module->load();
        return true;
    default:
        return false;
    }
}

QWidget *SettingsWindow::pageWidget(const Page &page)
{
    if (QWidget *widget = m_widgets.value(page.id)) {
        return widget;
    }
    QWidget *widget = nullptr;
    const KPluginMetaData metadata = findModule(page.module);
    if (metadata.isValid()) {
        KCModule *module = KCModuleLoader::loadModule(metadata, m_stack, { }, m_engine);
        module->load();
        connect(module, &KCModule::needsSaveChanged, this, &SettingsWindow::updateButtons);
        connect(module, &KCModule::representsDefaultsChanged, this, &SettingsWindow::updateButtons);
        m_modules.insert(page.id, module);
        widget = module->widget();
    } else {
        auto *label = new QLabel(i18nc("@info", "This page isn't available on this computer."));
        label->setAlignment(Qt::AlignCenter);
        widget = label;
    }
    m_stack->addWidget(widget);
    m_widgets.insert(page.id, widget);
    return widget;
}

KCModule *SettingsWindow::currentModule() const
{
    return m_currentPage.isEmpty() ? nullptr : m_modules.value(m_currentPage);
}

void SettingsWindow::updateButtons()
{
    KCModule *module = currentModule();
    m_buttonBar->setVisible(module != nullptr);
    if (!module) {
        return;
    }
    const KAbstractConfigModule::Buttons buttons = module->buttons();
    m_defaults->setVisible(buttons & KAbstractConfigModule::Default);
    m_apply->setVisible(buttons & KAbstractConfigModule::Apply);
    m_reset->setVisible(buttons & KAbstractConfigModule::Apply);
    m_apply->setEnabled(module->needsSave());
    m_reset->setEnabled(module->needsSave());
    m_defaults->setEnabled(!module->representsDefaults());
    // Modules that apply changes straight away have no buttons at all.
    m_buttonBar->setVisible(m_defaults->isVisible() || m_apply->isVisible());
}

} // namespace OrielOSSettings
