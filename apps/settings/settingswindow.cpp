// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "settingswindow.h"

#include "modules.h"

#include <KCModule>
#include <KCModuleLoader>
#include <KConfigGroup>
#include <KIO/ApplicationLauncherJob>
#include <KLocalizedString>
#include <KMessageBox>
#include <KService>
#include <KSharedConfig>
#include <KStandardGuiItem>
#include <KUser>

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
#include <QResizeEvent>
#include <QStackedWidget>
#include <QToolButton>
#include <QVBoxLayout>

namespace OrielOSSettings {

namespace {

constexpr int idRole = Qt::UserRole;
constexpr int kindRole = Qt::UserRole + 1;
const QString pageKind = QStringLiteral("page");
// Home, which isn't a category of pages but comes first among them.
const QString homeId = QStringLiteral("home");
// The settings Home recommends, as Windows' Home does, when they're installed.
const QStringList recommendedPages = { QStringLiteral("display"), QStringLiteral("sound"), QStringLiteral("network"), QStringLiteral("bluetooth"),
    QStringLiteral("background"), QStringLiteral("update") };
constexpr int recentCount = 6;

KConfigGroup homeConfig()
{
    return KSharedConfig::openConfig(QStringLiteral("orielos-settingsrc"))->group(QStringLiteral("Home"));
}

// A heading among a list's pages.
void addHeading(QListWidget *list, const QString &text)
{
    auto *item = new QListWidgetItem(text, list);
    QFont font = item->font();
    font.setBold(true);
    item->setFont(font);
    item->setFlags(Qt::NoItemFlags);
    item->setSizeHint(QSize(0, 40));
}

} // namespace

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

    // The account at the top, as in Windows: its picture, name and kind; clicking it opens Your info.
    const KUser user;
    auto *account = new QPushButton;
    account->setFlat(true);
    account->setIconSize(QSize(48, 48));
    const QString face = user.faceIconPath();
    account->setIcon(face.isEmpty() ? QIcon::fromTheme(QStringLiteral("user-identity")) : QIcon(face));
    const QString name = user.property(KUser::FullName).toString();
    account->setText((name.isEmpty() ? user.loginName() : name) + QLatin1Char('\n') + i18nc("@info:status", "Local account"));
    account->setStyleSheet(QStringLiteral("text-align: left; padding: 8px;"));
    account->setAccessibleName(i18nc("@action:button", "Your info"));
    connect(account, &QPushButton::clicked, this, [this] { open(QStringLiteral("your-info")); });

    m_categories = new QListWidget;
    m_categories->setFrameShape(QFrame::NoFrame);
    m_categories->setIconSize(QSize(22, 22));
    m_categories->setAccessibleName(i18nc("@label", "Categories"));
    auto *home = new QListWidgetItem(QIcon::fromTheme(QStringLiteral("go-home")), i18nc("@title Settings' first page", "Home"), m_categories);
    home->setData(idRole, homeId);
    home->setSizeHint(QSize(0, 36));
    for (const Category &category : m_catalogue.categories()) {
        auto *item = new QListWidgetItem(QIcon::fromTheme(category.icon), category.title, m_categories);
        item->setData(idRole, category.id);
        item->setSizeHint(QSize(0, 36));
    }

    auto *sidebar = new QVBoxLayout;
    sidebar->addWidget(account);
    sidebar->addWidget(m_search);
    sidebar->addWidget(m_categories, 1);
    m_sidebar = new QWidget;
    m_sidebar->setLayout(sidebar);
    m_sidebar->setFixedWidth(280);

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

    // In a narrow window the sidebar hides, as Windows' Settings does, and this button shows it.
    m_menuButton = new QToolButton;
    m_menuButton->setIcon(QIcon::fromTheme(QStringLiteral("application-menu")));
    m_menuButton->setAutoRaise(true);
    m_menuButton->setToolTip(i18nc("@info:tooltip", "Show the categories"));
    m_menuButton->setAccessibleName(i18nc("@action:button", "Categories"));
    connect(m_menuButton, &QToolButton::clicked, this, [this]() { fitSidebar(m_sidebar->isHidden()); });
    auto *headingRow = new QHBoxLayout;
    headingRow->addWidget(m_menuButton);
    headingRow->addWidget(m_heading, 1);

    auto *content = new QVBoxLayout;
    content->addLayout(headingRow);
    content->addWidget(m_stack, 1);
    content->addWidget(m_buttonBar);

    auto *layout = new QHBoxLayout(this);
    layout->addWidget(m_sidebar);
    layout->addLayout(content, 1);

    // Staying on a page with unsaved changes puts the sidebar back on that page's category. In a
    // narrow window, choosing a category puts the sidebar away again.
    const auto openCategory = [this](QListWidgetItem *item) {
        if (!open(item->data(idRole).toString())) {
            selectCategory(m_currentCategory);
        } else if (isNarrow()) {
            fitSidebar();
        }
    };
    connect(m_categories, &QListWidget::itemClicked, this, openCategory);
    connect(m_categories, &QListWidget::itemActivated, this, openCategory);
    connect(m_list, &QListWidget::itemActivated, this, &SettingsWindow::openListItem);
    connect(m_list, &QListWidget::itemClicked, this, &SettingsWindow::openListItem);
    connect(m_search, &QLineEdit::textChanged, this, [this](const QString &text) {
        if (text.trimmed().isEmpty()) {
            if (m_currentCategory == homeId) {
                showHome();
            } else {
                showCategory(m_currentCategory);
            }
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

QString SettingsWindow::moreCategoryId()
{
    return QStringLiteral("more");
}

bool SettingsWindow::open(const QString &target)
{
    if (target == homeId) {
        if (!leaveCurrentPage()) {
            return false;
        }
        m_search->clear();
        showHome();
        return true;
    }
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
    // A module that isn't in the sidebar, such as one hidden from System Settings' own list.
    const KPluginMetaData metadata = findModule(target);
    if (metadata.isValid() && m_catalogue.category(moreCategoryId())) {
        if (!leaveCurrentPage()) {
            return false;
        }
        m_search->clear();
        showPage({ metadata.pluginId(), moreCategoryId(), metadata.name(), metadata.description(), { }, metadata.pluginId(), metadata.iconName() });
        return true;
    }
    return false;
}

void SettingsWindow::openFirst()
{
    open(homeId);
}

void SettingsWindow::showHome()
{
    m_currentCategory = homeId;
    m_currentPage.clear();
    selectCategory(homeId);
    m_heading->setText(i18nc("@title Settings' first page", "Home"));
    m_list->clear();
    const auto addPages = [this](const QString &heading, const QStringList &ids) {
        QList<Page> pages;
        for (const QString &id : ids) {
            if (const std::optional<Page> page = m_catalogue.page(id)) {
                pages.append(*page);
            }
        }
        if (pages.isEmpty()) {
            return;
        }
        addHeading(m_list, heading);
        for (const Page &page : std::as_const(pages)) {
            const KPluginMetaData metadata = findModule(page.module);
            const QString icon = page.icon.isEmpty() ? metadata.iconName() : page.icon;
            auto *item = new QListWidgetItem(QIcon::fromTheme(icon), page.title + QLatin1Char('\n') + page.description, m_list);
            item->setData(idRole, page.id);
            item->setData(kindRole, pageKind);
        }
    };
    const QStringList recent = homeConfig().readEntry("RecentPages", QStringList());
    addPages(i18nc("@title On Settings' Home", "Recently used settings"), recent);
    // A page already under Recently used isn't recommended a second time.
    QStringList recommended = recommendedPages;
    recommended.removeIf([&recent](const QString &id) { return recent.contains(id); });
    addPages(i18nc("@title On Settings' Home", "Recommended settings"), recommended);
    m_stack->setCurrentWidget(m_list);
    updateButtons();
}

void SettingsWindow::rememberPage(const QString &pageId)
{
    KConfigGroup group = homeConfig();
    QStringList recent = group.readEntry("RecentPages", QStringList());
    recent.removeAll(pageId);
    recent.prepend(pageId);
    group.writeEntry("RecentPages", recent.mid(0, recentCount));
    group.sync();
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
    // Settings that live in an app of their own open the app; Settings stays where it is.
    if (isAppModule(page.module)) {
        if (const KService::Ptr service = KService::serviceByDesktopName(appDesktopName(page.module))) {
            (new KIO::ApplicationLauncherJob(service))->start();
        }
        return;
    }
    if (page.id == m_currentPage) {
        return;
    }
    if (!leaveCurrentPage()) {
        return;
    }
    QWidget *widget = pageWidget(page);
    m_currentPage = page.id;
    rememberPage(page.id);
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
        // Info Center's pages offer Defaults and Apply but have nothing to apply; Info Center
        // itself never shows those buttons.
        if (isInfoModule(metadata)) {
            module->setButtons(KAbstractConfigModule::NoAdditionalButton);
        }
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

namespace {
// Below this width the page would be squeezed beside the 280 px sidebar.
constexpr int narrowWidth = 760;
} // namespace

bool SettingsWindow::isNarrow() const
{
    return width() < narrowWidth;
}

void SettingsWindow::fitSidebar(bool showSidebar)
{
    m_menuButton->setVisible(isNarrow());
    m_sidebar->setVisible(!isNarrow() || showSidebar);
}

void SettingsWindow::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    // Crossing the width keeps the sidebar as it was in a narrow window that already had it open.
    const int before = event->oldSize().width();
    fitSidebar(isNarrow() && m_sidebar->isVisible() && before >= 0 && before < narrowWidth);
}

} // namespace OrielOSSettings
