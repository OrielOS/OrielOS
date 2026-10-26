// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

// Loads the built Update settings module the way System Settings does and fails on any QML warning.
// The build has no system bus or update state, so the page shows that it hasn't checked yet.

#include <KPluginMetaData>
#include <KQuickConfigModule>
#include <KQuickConfigModuleLoader>

#include <QQuickItem>
#include <QTest>

namespace {

QStringList qmlWarnings;
QtMessageHandler defaultHandler = nullptr;

void recordQmlWarnings(QtMsgType type, const QMessageLogContext &context, const QString &message)
{
    // QML names the file and line of a problem, such as "qrc:/qt/qml/.../UpdatePage.qml:12:5: ...".
    if (type != QtDebugMsg && type != QtInfoMsg && message.contains(QLatin1String(".qml"))) {
        qmlWarnings.append(message);
    }
    defaultHandler(type, context, message);
}

} // namespace

class KcmLoadTest : public QObject
{
    Q_OBJECT

private Q_SLOTS:
    void initTestCase() { defaultHandler = qInstallMessageHandler(recordQmlWarnings); }

    void findsTheModule()
    {
        const KPluginMetaData metaData = KPluginMetaData::findPluginById(QStringLiteral("plasma/kcms/systemsettings"), QStringLiteral("kcm_orielos_update"));
        QVERIFY2(metaData.isValid(), "kcm_orielos_update isn't in plasma/kcms/systemsettings on QT_PLUGIN_PATH");
        QCOMPARE(metaData.name(), QStringLiteral("OrielOS Update"));
        QCOMPARE(metaData.iconName(), QStringLiteral("system-software-update"));
        QCOMPARE(metaData.value(QStringLiteral("X-KDE-System-Settings-Parent-Category")), QStringLiteral("system-administration"));
    }

    void loadsThePage()
    {
        const KPluginMetaData metaData = KPluginMetaData::findPluginById(QStringLiteral("plasma/kcms/systemsettings"), QStringLiteral("kcm_orielos_update"));
        const auto result = KQuickConfigModuleLoader::loadModule(metaData, this);
        QVERIFY2(result.plugin, qPrintable(result.errorString));
        QQuickItem *page = result.plugin->mainUi();
        QVERIFY2(page, qPrintable(result.plugin->errorString()));
        QVERIFY2(result.plugin->errorString().isEmpty(), qPrintable(result.plugin->errorString()));
        QCOMPARE(result.plugin->buttons(), KAbstractConfigModule::Buttons(KAbstractConfigModule::NoAdditionalButton));
        // Let the bindings and the first read of the state settle.
        QTest::qWait(500);
        QVERIFY2(qmlWarnings.isEmpty(), qPrintable(qmlWarnings.join(QLatin1Char('\n'))));
    }
};

QTEST_MAIN(KcmLoadTest)

#include "kcmloadtest.moc"
