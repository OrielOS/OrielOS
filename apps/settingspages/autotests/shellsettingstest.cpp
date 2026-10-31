// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

#include "shellsettings.h"
#include "startoptions.h"
#include "taskbaroptions.h"

#include <QJSEngine>
#include <QSignalSpy>
#include <QTest>

using namespace OrielOSSettingsPages;

namespace {

// Plasma's desktop scripting, as much of it as the script uses: panels with widgets, their
// settings, the saved widget order and the panel's hiding.
const QString fakeDesktop = QStringLiteral(R"JS(
function makeWidget(id, type, config) {
    return {
        id: id, type: type, config: config || {}, reloads: 0, currentConfigGroup: [],
        readConfig: function (key, fallback) { return key in this.config ? this.config[key] : fallback; },
        writeConfig: function (key, value) { this.config[key] = value; },
        reloadConfig: function () { this.reloads += 1; },
    };
}
function makePanel(list, order, hiding) {
    return {
        list: list, hiding: hiding || "none", currentConfigGroup: [], config: { AppletOrder: order },
        widgetIds: list.map(function (w) { return w.id; }),
        widgets: function (type) { return this.list.filter(function (w) { return !type || w.type === type; }); },
        widgetById: function (id) { return this.list.filter(function (w) { return w.id === id; })[0]; },
        readConfig: function (key, fallback) { return key in this.config ? this.config[key] : fallback; },
    };
}
var desktop = [];
function panels() { return desktop; }
var printed = "";
function print(text) { printed += text; }
)JS");

// OrielOS's taskbar: spacer, Start, task manager, spacer, system tray.
const QString orielosTaskbar = QStringLiteral(R"JS(
var leftSpacer = makeWidget(1, "org.kde.plasma.panelspacer", { expanding: true });
var start = makeWidget(2, "org.orielos.startmenu", {});
var taskbar = makePanel([leftSpacer, start, makeWidget(3, "org.kde.plasma.icontasks"),
    makeWidget(4, "org.kde.plasma.panelspacer", { expanding: true }), makeWidget(5, "org.kde.plasma.systemtray")], "1;2;3;4;5");
desktop = [taskbar];
)JS");

// Runs the script for a change against a desktop set up by setup, and returns the engine to look
// at the desktop afterwards; the state it printed is in "printed".
std::unique_ptr<QJSEngine> runScript(const QString &setup, std::optional<ShellSettings::Change> change = std::nullopt)
{
    auto engine = std::make_unique<QJSEngine>();
    const QJSValue result = engine->evaluate(fakeDesktop + setup + ShellSettings::script(change));
    if (result.isError()) {
        qWarning() << result.toString() << result.property(QStringLiteral("lineNumber")).toInt();
        return nullptr;
    }
    return engine;
}

ShellState printedState(QJSEngine &engine)
{
    const std::optional<ShellState> state = ShellState::fromJson(engine.globalObject().property(QStringLiteral("printed")).toString());
    return state.value_or(ShellState { });
}

// A runner that keeps each script and its callback until the test answers it.
struct FakeDesktop
{
    struct Call
    {
        QString script;
        std::function<void(bool, const QString &)> done;
    };
    QList<Call> calls;

    ShellSettings::Runner runner()
    {
        return [this](const QString &script, std::function<void(bool, const QString &)> done) { calls.append({ script, std::move(done) }); };
    }

    // Answers the oldest call.
    void answer(bool ok, const QString &output)
    {
        const Call call = calls.takeFirst();
        call.done(ok, output);
    }
};

const QString defaultState
    = QStringLiteral(R"({"hasStart":true,"showRecentlyAdded":true,"showRecentFiles":true,"canAlign":true,"centred":true,"autoHide":false})");

} // namespace

class ShellSettingsTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    // The script, against a fake desktop.

    void readsOrielosTaskbar()
    {
        const auto engine = runScript(orielosTaskbar);
        QVERIFY(engine);
        const ShellState state = printedState(*engine);
        QVERIFY(state.hasStart);
        QVERIFY(state.showRecentlyAdded);
        QVERIFY(state.showRecentFiles);
        QVERIFY(state.canAlign);
        QVERIFY(state.centred);
        QVERIFY(!state.autoHide);
    }

    void readsSettingsSavedAsText()
    {
        // Settings read back from the file, before the widget's configuration has them, are text.
        const auto engine = runScript(orielosTaskbar + QStringLiteral("start.config.showRecentFiles = \"false\"; taskbar.hiding = \"autohide\";"));
        QVERIFY(engine);
        const ShellState state = printedState(*engine);
        QVERIFY(state.showRecentlyAdded);
        QVERIFY(!state.showRecentFiles);
        QVERIFY(state.autoHide);
    }

    void changesStartsSettings()
    {
        const auto engine = runScript(orielosTaskbar, ShellSettings::Change { ShellSettings::Setting::ShowRecentFiles, false });
        QVERIFY(engine);
        QCOMPARE(engine->evaluate(QStringLiteral("start.config.showRecentFiles")).toBool(), false);
        QCOMPARE(engine->evaluate(QStringLiteral("start.reloads")).toInt(), 1);
        QVERIFY(!printedState(*engine).showRecentFiles);
        QVERIFY(printedState(*engine).showRecentlyAdded);

        const auto again = runScript(orielosTaskbar, ShellSettings::Change { ShellSettings::Setting::ShowRecentlyAdded, false });
        QVERIFY(again);
        QVERIFY(!printedState(*again).showRecentlyAdded);
    }

    void alignsWithTheSpacerBeforeStart()
    {
        const auto left = runScript(orielosTaskbar, ShellSettings::Change { ShellSettings::Setting::Centred, false });
        QVERIFY(left);
        QCOMPARE(left->evaluate(QStringLiteral("leftSpacer.config.expanding")).toBool(), false);
        // The spacer after the task manager still fills the rest of the panel.
        QCOMPARE(left->evaluate(QStringLiteral("taskbar.list[3].config.expanding")).toBool(), true);
        QVERIFY(!printedState(*left).centred);

        const auto centre = runScript(
            orielosTaskbar + QStringLiteral("leftSpacer.config.expanding = false;"), ShellSettings::Change { ShellSettings::Setting::Centred, true });
        QVERIFY(centre);
        QCOMPARE(centre->evaluate(QStringLiteral("leftSpacer.config.expanding")).toBool(), true);
        QVERIFY(printedState(*centre).centred);
    }

    void followsTheSavedOrder()
    {
        // Start moved to the front: the spacer is no longer before it, so nothing can align.
        const auto engine = runScript(
            orielosTaskbar + QStringLiteral("taskbar.config.AppletOrder = \"2;1;3;4;5\";"), ShellSettings::Change { ShellSettings::Setting::Centred, false });
        QVERIFY(engine);
        QVERIFY(!printedState(*engine).canAlign);
        QVERIFY(printedState(*engine).centred);
        QCOMPARE(engine->evaluate(QStringLiteral("leftSpacer.config.expanding")).toBool(), true);

        // Without a saved order, the widgets' own order counts.
        const auto unsaved = runScript(orielosTaskbar + QStringLiteral("taskbar.config.AppletOrder = \"\";"));
        QVERIFY(unsaved);
        QVERIFY(printedState(*unsaved).canAlign);
    }

    void hidesTheTaskbar()
    {
        const auto engine = runScript(orielosTaskbar, ShellSettings::Change { ShellSettings::Setting::AutoHide, true });
        QVERIFY(engine);
        QCOMPARE(engine->evaluate(QStringLiteral("taskbar.hiding")).toString(), QStringLiteral("autohide"));
        QVERIFY(printedState(*engine).autoHide);

        const auto shown
            = runScript(orielosTaskbar + QStringLiteral("taskbar.hiding = \"autohide\";"), ShellSettings::Change { ShellSettings::Setting::AutoHide, false });
        QVERIFY(shown);
        QCOMPARE(shown->evaluate(QStringLiteral("taskbar.hiding")).toString(), QStringLiteral("none"));
    }

    void changesTheTaskbarsItems()
    {
        // Search, Task View and the clock on the taskbar too, as layout.js lays it out.
        const QString full = orielosTaskbar + QStringLiteral(R"JS(
var search = makeWidget(6, "org.orielos.search", {});
var taskView = makeWidget(7, "org.orielos.taskview", {});
var clock = makeWidget(8, "org.orielos.clock", {});
taskbar.list.push(search, taskView, clock);
)JS");
        const auto before = runScript(full);
        QVERIFY(before);
        const ShellState state = printedState(*before);
        QVERIFY(state.hasSearch && state.showSearch);
        QVERIFY(state.hasTaskView && state.showTaskView);
        QVERIFY(state.hasTasks && state.combineButtons);
        QVERIFY(state.hasClock && !state.showSeconds);

        const auto hidden = runScript(full, ShellSettings::Change { ShellSettings::Setting::ShowTaskView, false });
        QVERIFY(hidden);
        QCOMPARE(hidden->evaluate(QStringLiteral("taskView.config.shown")).toBool(), false);
        QCOMPARE(hidden->evaluate(QStringLiteral("taskView.reloads")).toInt(), 1);
        QVERIFY(!printedState(*hidden).showTaskView);
        QVERIFY(printedState(*hidden).showSearch);

        const auto apart = runScript(full, ShellSettings::Change { ShellSettings::Setting::CombineButtons, false });
        QVERIFY(apart);
        QCOMPARE(apart->evaluate(QStringLiteral("taskbar.list[2].config.groupingStrategy")).toInt(), 0);
        QVERIFY(!printedState(*apart).combineButtons);

        const auto seconds = runScript(full, ShellSettings::Change { ShellSettings::Setting::ShowSeconds, true });
        QVERIFY(seconds);
        QCOMPARE(seconds->evaluate(QStringLiteral("clock.config.showSeconds")).toBool(), true);
        QVERIFY(printedState(*seconds).showSeconds);
    }

    void withoutTheItemsNothingChanges()
    {
        // The plain taskbar has no Search, Task View or clock; asking for them changes nothing.
        const auto engine = runScript(orielosTaskbar, ShellSettings::Change { ShellSettings::Setting::ShowSearch, false });
        QVERIFY(engine);
        QVERIFY(!printedState(*engine).hasSearch);
        QVERIFY(!printedState(*engine).hasClock);
    }

    void findsStartOnAnyPanel()
    {
        const auto engine = runScript(
            orielosTaskbar + QStringLiteral("desktop = [makePanel([makeWidget(9, \"org.kde.plasma.digitalclock\")], \"9\", \"autohide\"), taskbar];"));
        QVERIFY(engine);
        QVERIFY(printedState(*engine).hasStart);
        QVERIFY(!printedState(*engine).autoHide);
    }

    void changesNothingWithoutStart()
    {
        const auto engine = runScript(QStringLiteral("var other = makePanel([makeWidget(1, \"org.kde.plasma.kickoff\")], \"1\"); desktop = [other];"),
            ShellSettings::Change { ShellSettings::Setting::AutoHide, true });
        QVERIFY(engine);
        QVERIFY(!printedState(*engine).hasStart);
        QCOMPARE(engine->evaluate(QStringLiteral("other.hiding")).toString(), QStringLiteral("none"));
    }

    void readsOnlyItsOwnOutput()
    {
        QVERIFY(ShellState::fromJson(defaultState));
        QVERIFY(!ShellState::fromJson(QString()));
        QVERIFY(!ShellState::fromJson(QStringLiteral("not json")));
        QVERIFY(!ShellState::fromJson(QStringLiteral("{}")));
        QVERIFY(!ShellState::fromJson(QStringLiteral("[1]")));
    }

    // Running scripts and showing changes.

    void readsWhenCreated()
    {
        FakeDesktop desktop;
        ShellSettings settings(desktop.runner());
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(!desktop.calls.first().script.contains(QLatin1String("writeConfig(")));
        QVERIFY(!settings.isReady());
        QVERIFY(!settings.state().hasStart);
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"showRecentFiles":false,"canAlign":true,"centred":false,"autoHide":true})"));
        QVERIFY(settings.isReady());
        QVERIFY(settings.state().hasStart);
        QVERIFY(!settings.state().showRecentFiles);
        QVERIFY(!settings.state().centred);
        QVERIFY(settings.state().autoHide);
        QVERIFY(settings.error().isEmpty());
        QVERIFY(!settings.isBusy());
    }

    void showsAChangeAtOnceAndRunsOneScriptAtATime()
    {
        FakeDesktop desktop;
        ShellSettings settings(desktop.runner());
        desktop.answer(true, defaultState);
        QSignalSpy changed(&settings, &ShellSettings::changed);

        settings.change(ShellSettings::Setting::Centred, false);
        settings.change(ShellSettings::Setting::AutoHide, true);
        QVERIFY(changed.size() >= 2);
        QVERIFY(!settings.state().centred);
        QVERIFY(settings.state().autoHide);
        QVERIFY(settings.isBusy());
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(desktop.calls.first().script.contains(QLatin1String("spacer.writeConfig(\"expanding\", false)")));

        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":true,"centred":false,"autoHide":false})"));
        // The second change still shows while it runs.
        QVERIFY(settings.state().autoHide);
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(desktop.calls.first().script.contains(QLatin1String("panel.hiding = true ? \"autohide\" : \"none\"")));
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":true,"centred":false,"autoHide":true})"));
        QVERIFY(!settings.isBusy());
        QVERIFY(!settings.state().centred);
        QVERIFY(settings.state().autoHide);
    }

    void copesWithChangesMadeFromItsOwnSignal()
    {
        FakeDesktop desktop;
        ShellSettings settings(desktop.runner());
        desktop.answer(true, defaultState);
        bool asked = false;
        connect(&settings, &ShellSettings::changed, &settings, [&]() {
            if (!asked) {
                asked = true;
                settings.change(ShellSettings::Setting::AutoHide, true);
            }
        });
        settings.change(ShellSettings::Setting::Centred, false);
        // The first change's script runs; the one made from the signal waits for it.
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(desktop.calls.first().script.contains(QLatin1String("spacer.writeConfig(\"expanding\", false)")));
        QVERIFY(settings.state().autoHide);
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":true,"centred":false,"autoHide":false})"));
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(desktop.calls.first().script.contains(QLatin1String("panel.hiding = true")));
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":true,"centred":false,"autoHide":true})"));
        QVERIFY(desktop.calls.isEmpty());
        QVERIFY(!settings.isBusy());
    }

    void goesBackWhenAChangeFails()
    {
        FakeDesktop desktop;
        ShellSettings settings(desktop.runner());
        desktop.answer(true, defaultState);
        settings.change(ShellSettings::Setting::ShowRecentlyAdded, false);
        QVERIFY(!settings.state().showRecentlyAdded);
        desktop.answer(false, QStringLiteral("Widgets are locked"));
        QVERIFY(settings.state().showRecentlyAdded);
        QCOMPARE(settings.error(), QStringLiteral("The change couldn't be made."));

        // The next change that works clears the message.
        settings.change(ShellSettings::Setting::ShowRecentlyAdded, false);
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"showRecentlyAdded":false})"));
        QVERIFY(settings.error().isEmpty());
        QVERIFY(!settings.state().showRecentlyAdded);
    }

    void saysWhenItCantRead()
    {
        FakeDesktop desktop;
        ShellSettings settings(desktop.runner());
        desktop.answer(false, QStringLiteral("org.kde.plasmashell isn't running"));
        QVERIFY(settings.isReady());
        QVERIFY(!settings.state().hasStart);
        QCOMPARE(settings.error(), QStringLiteral("The taskbar's settings couldn't be read."));

        // Output that isn't the script's counts as a failure too.
        settings.reload();
        desktop.answer(true, QStringLiteral("ReferenceError: panels is not defined"));
        QCOMPARE(settings.error(), QStringLiteral("The taskbar's settings couldn't be read."));
    }

    // The pages' models.

    void startOptionsChangeOnlyWhatsThere()
    {
        FakeDesktop desktop;
        StartOptions options(new ShellSettings(desktop.runner()));
        QSignalSpy changed(&options, &StartOptions::changed);
        // Nothing to change before the first read says there's a Start menu.
        options.setShowRecentFiles(false);
        QCOMPARE(desktop.calls.size(), 1);
        desktop.answer(true, defaultState);
        QVERIFY(changed.size() >= 1);
        QVERIFY(options.isReady());
        QVERIFY(options.isAvailable());
        QVERIFY(options.showRecentFiles());

        options.setShowRecentFiles(false);
        QVERIFY(!options.showRecentFiles());
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(desktop.calls.first().script.contains(QLatin1String("start.writeConfig(\"showRecentFiles\", false)")));
        // Setting the value it already has runs nothing more.
        options.setShowRecentFiles(false);
        QCOMPARE(desktop.calls.size(), 1);
    }

    void taskbarOptionsAlignOnlyWithTheSpacer()
    {
        FakeDesktop desktop;
        TaskbarOptions options(new ShellSettings(desktop.runner()));
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":false,"centred":true,"autoHide":false})"));
        QVERIFY(options.isAvailable());
        QVERIFY(!options.canAlign());
        options.setCentred(false);
        QVERIFY(desktop.calls.isEmpty());
        QVERIFY(options.isCentred());

        options.setAutoHide(true);
        QCOMPARE(desktop.calls.size(), 1);
        QVERIFY(options.autoHide());
        desktop.answer(true, QStringLiteral(R"({"hasStart":true,"canAlign":false,"centred":true,"autoHide":true})"));
        QVERIFY(options.autoHide());
        QVERIFY(options.error().isEmpty());
    }
};

QTEST_GUILESS_MAIN(ShellSettingsTest)

#include "shellsettingstest.moc"
