// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Loads the built settings modules the way Settings does, one after another into one shared QML
// engine, and fails on any QML warning. Start and Taskbar can't reach a desktop here, so they show
// that instead.

#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QQmlEngine>
#include <QQuickItem>
#include <QTest>

namespace {

QStringList qmlWarnings;
QtMessageHandler defaultHandler = nullptr;

void recordQmlWarnings(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    // QML names the file and line of a problem, such as "qrc:/qt/qml/.../AccentPage.qml:12:5: ...".
    if (type != QtDebugMsg && type != QtInfoMsg && message.contains(QLatin1String(".qml"))) {
        qmlWarnings.append(message);
    }
    defaultHandler(type, context, message);
}

} // namespace

class PagesLoadTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase() { defaultHandler = qInstallMessageHandler(recordQmlWarnings); }

    // The modules go before the engine they were loaded into.
    void cleanupTestCase()
    {
        qDeleteAll(m_modules);
        m_modules.clear();
        m_engine.reset();
    }

    void loadsThePage_data()
    {
        QTest::addColumn<QString>("id");
        QTest::addColumn<QString>("name");
        QTest::addColumn<QString>("category");

        QTest::newRow("accessories") << QStringLiteral("kcm_orielos_accessories") << QStringLiteral("Accessory Apps") << QStringLiteral("hardware");
        QTest::newRow("accent") << QStringLiteral("kcm_orielos_accent") << QStringLiteral("Accent Colour") << QStringLiteral("themes");
        QTest::newRow("start") << QStringLiteral("kcm_orielos_start") << QStringLiteral("Start") << QStringLiteral("workspace");
        QTest::newRow("taskbar") << QStringLiteral("kcm_orielos_taskbar") << QStringLiteral("Taskbar") << QStringLiteral("workspace");
        QTest::newRow("security") << QStringLiteral("kcm_orielos_security") << QStringLiteral("Device Security") << QStringLiteral("security-privacy");
        QTest::newRow("power mode") << QStringLiteral("kcm_orielos_powermode") << QStringLiteral("Power Mode") << QStringLiteral("hardware");
        QTest::newRow("sign-in options") << QStringLiteral("kcm_orielos_signin") << QStringLiteral("Sign-in Options") << QStringLiteral("security-privacy");
        QTest::newRow("multitasking") << QStringLiteral("kcm_orielos_multitasking") << QStringLiteral("Multitasking") << QStringLiteral("windowmanagement");
        QTest::newRow("mouse pointer") << QStringLiteral("kcm_orielos_pointer") << QStringLiteral("Mouse Pointer") << QStringLiteral("accessibility");
        QTest::newRow("do not disturb") << QStringLiteral("kcm_orielos_donotdisturb") << QStringLiteral("Do Not Disturb") << QStringLiteral("workspace");
        QTest::newRow("fonts") << QStringLiteral("kcm_orielos_fonts") << QStringLiteral("Fonts") << QStringLiteral("themes");
        QTest::newRow("background") << QStringLiteral("kcm_orielos_background") << QStringLiteral("Background") << QStringLiteral("themes");
        QTest::newRow("recent activity") << QStringLiteral("kcm_orielos_recentactivity") << QStringLiteral("Recent Activity")
                                         << QStringLiteral("security-privacy");
        QTest::newRow("storage") << QStringLiteral("kcm_orielos_storage") << QStringLiteral("Storage") << QStringLiteral("hardware");
        QTest::newRow("camera") << QStringLiteral("kcm_orielos_camera") << QStringLiteral("Camera") << QStringLiteral("hardware");
        QTest::newRow("fps overlay") << QStringLiteral("kcm_orielos_fpsoverlay") << QStringLiteral("FPS Overlay") << QStringLiteral("hardware");
    }

    void loadsThePage()
    {
        QFETCH(QString, id);
        QFETCH(QString, name);
        QFETCH(QString, category);
        qmlWarnings.clear();
        const KPluginMetaData metaData = KPluginMetaData::findPluginById(QStringLiteral("plasma/kcms/systemsettings"), id);
        QVERIFY2(metaData.isValid(), qPrintable(id + QStringLiteral(" isn't in plasma/kcms/systemsettings on QT_PLUGIN_PATH")));
        QCOMPARE(metaData.name(), name);
        QCOMPARE(metaData.value(QStringLiteral("X-KDE-System-Settings-Parent-Category")), category);
        // Settings shares one engine across every page, so each module here joins the ones before.
        const auto result = KQuickConfigModuleLoader::loadModule(metaData, nullptr, { }, m_engine);
        QVERIFY2(result.plugin, qPrintable(result.errorString));
        m_modules.append(result.plugin);
        QQuickItem *page = result.plugin->mainUi();
        QVERIFY2(page, qPrintable(result.plugin->errorString()));
        QVERIFY2(result.plugin->errorString().isEmpty(), qPrintable(result.plugin->errorString()));
        QCOMPARE(result.plugin->buttons(), KAbstractConfigModule::Buttons(KAbstractConfigModule::NoAdditionalButton));
        QTest::qWait(500);
        QVERIFY2(qmlWarnings.isEmpty(), qPrintable(qmlWarnings.join(QLatin1Char('\n'))));
    }

private:
    std::shared_ptr<QQmlEngine> m_engine = std::make_shared<QQmlEngine>();
    QList<KQuickConfigModule *> m_modules;
};

QTEST_MAIN(PagesLoadTest)

#include "pagesloadtest.moc"
