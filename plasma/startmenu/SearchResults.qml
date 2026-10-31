// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kitemmodels as KItemModels
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// The search results, as Windows 11 lays them out: filters along the top (All, Apps, Documents,
// Settings, Folders), the best match large at the head of the list and the rest under headings for
// their kind, and on the right the highlighted result's details with its actions. The keyboard focus
// usually stays in the search field, which moves the highlighted result.
Item {
    id: results

    required property MenuState menu

    readonly property ListView view: list
    // Whether the highlight was moved with Up or Down. Until it is, it stays on the first result
    // while more results arrive. The pointer never moves it: it often rests over the menu, and
    // Enter would then run whatever happens to be under it.
    property bool moved: false

    function resetCurrent() {
        results.moved = false;
        list.currentIndex = list.count > 0 ? 0 : -1;
        list.positionViewAtBeginning();
    }

    function moveCurrent(step: int) {
        if (list.count === 0) {
            return;
        }
        results.moved = true;
        list.currentIndex = Math.max(0, Math.min(list.count - 1, list.currentIndex + step));
    }

    function triggerCurrent() {
        if (list.count > 0) {
            results.menu.launchResult(Math.max(0, list.currentIndex));
        }
    }

    function openCurrentMenu() {
        const current = list.currentItem;
        if (current && list.currentIndex >= 0) {
            results.menu.openResultMenu(list.currentIndex, current, current.width / 2, current.height / 2, true);
        }
    }

    // The highlighted result's details: what the actions pane shows.
    readonly property int currentRow: list.currentIndex
    readonly property var currentData: {
        const model = results.menu.resultsModel;
        const row = results.currentRow;
        if (!model || row < 0 || row >= list.count) {
            return null;
        }
        const roles = model.KItemModels.KRoleNames;
        const data = roleName => model.data(model.index(row, 0), roles.role(roleName));
        return { display: String(data("display") ?? ""), decoration: data("decoration") ?? "", group: String(data("group") ?? "") };
    }

    RowLayout {
        id: filters

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            model: [
                { id: "all", text: KI18n.i18nc("@option:radio Search filter", "All") },
                { id: "apps", text: KI18n.i18nc("@option:radio Search filter", "Apps") },
                { id: "documents", text: KI18n.i18nc("@option:radio Search filter", "Documents") },
                { id: "settings", text: KI18n.i18nc("@option:radio Search filter", "Settings") },
                { id: "folders", text: KI18n.i18nc("@option:radio Search filter", "Folders") },
            ]

            delegate: PC3.ToolButton {
                id: filter

                required property var modelData

                implicitHeight: 28
                text: filter.modelData.text
                checkable: true
                checked: results.menu.searchFilter === filter.modelData.id
                focusPolicy: Qt.NoFocus
                Accessible.role: Accessible.RadioButton
                onClicked: {
                    results.menu.searchFilter = filter.modelData.id;
                    results.resetCurrent();
                }

                background: Rectangle {
                    radius: height / 2
                    color: filter.checked ? Kirigami.Theme.highlightColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, filter.hovered ? 0.14 : 0.06)
                }
                contentItem: PC3.Label {
                    text: filter.text
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    color: filter.checked ? Kirigami.Theme.highlightedTextColor : Kirigami.Theme.textColor
                    horizontalAlignment: Text.AlignHCenter
                }
                leftPadding: 12
                rightPadding: 12
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }

    PC3.ScrollView {
        id: scroll

        anchors.top: filters.bottom
        anchors.topMargin: Kirigami.Units.largeSpacing
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: Math.round(parent.width * 0.55)

        PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

        ListView {
            id: list

            clip: true
            model: results.menu.resultsModel
            keyNavigationEnabled: false
            highlightMoveDuration: 0

            Accessible.name: KI18n.i18nc("@title", "Search results")
            Accessible.role: Accessible.List

            onCountChanged: {
                if (!results.moved || list.currentIndex < 0) {
                    list.currentIndex = list.count > 0 ? 0 : -1;
                }
            }
            onModelChanged: {
                if (!results.moved) {
                    list.currentIndex = list.count > 0 ? 0 : -1;
                }
            }

            // The first result is the best match, under its own heading with its kind beneath it;
            // the rest are under a heading for their kind, which starts again after the best match.
            delegate: Column {
                id: entry

                required property int index
                required property var model
                readonly property string group: String(entry.model.group ?? "")
                readonly property string previousGroup: entry.index < 2 ? "" : results.menu.resultGroup(entry.index - 1)

                width: list.width

                PlasmaExtras.ListSectionHeader {
                    width: parent.width
                    visible: entry.index <= 1 || entry.group !== entry.previousGroup
                    text: entry.index === 0 ? KI18n.i18nc("@title The first search result", "Best match") : entry.group
                }

                ListRow {
                    id: row

                    width: parent.width
                    label: String(entry.model.display ?? "")
                    iconSource: entry.model.decoration ?? ""
                    subtitle: entry.index === 0 ? entry.group : String(entry.model.description ?? "")
                    current: entry.ListView.isCurrentItem

                    onClicked: results.menu.launchResult(entry.index)
                    onContextMenuRequested: (x, y) => results.menu.openResultMenu(entry.index, row, x, y, false)
                }
            }

            Keys.onTabPressed: results.menu.cycleFocus(true)
            Keys.onBacktabPressed: results.menu.cycleFocus(false)
            Keys.onPressed: event => {
                if (results.menu.isContextMenuKey(event)) {
                    results.openCurrentMenu();
                    event.accepted = true;
                    return;
                }
                switch (event.key) {
                case Qt.Key_Up:
                    if (list.currentIndex > 0) {
                        results.moveCurrent(-1);
                    } else {
                        results.menu.focusSearch();
                    }
                    event.accepted = true;
                    break;
                case Qt.Key_Down:
                    results.moveCurrent(1);
                    event.accepted = true;
                    break;
                case Qt.Key_Return:
                case Qt.Key_Enter:
                case Qt.Key_Space:
                    results.triggerCurrent();
                    event.accepted = true;
                    break;
                }
            }
        }
    }

    // The actions pane: the highlighted result large, with its actions.
    Rectangle {
        id: pane

        anchors.top: scroll.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.left: scroll.right
        anchors.leftMargin: Kirigami.Units.largeSpacing
        visible: results.currentData !== null
        radius: 8
        color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.04)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing * 2
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.largeSpacing
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64
                source: results.currentData?.decoration ?? ""
                fallback: "unknown"
            }
            PC3.Label {
                Layout.fillWidth: true
                text: results.currentData?.display ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 16
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            PC3.Label {
                Layout.fillWidth: true
                text: results.currentData?.group ?? ""
                textFormat: Text.PlainText
                font.pixelSize: 12
                opacity: 0.7
                horizontalAlignment: Text.AlignHCenter
            }
            Kirigami.Separator {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.largeSpacing
                Layout.bottomMargin: Kirigami.Units.smallSpacing
            }

            // Open, then the result's own actions, as its context menu lists them.
            PC3.ToolButton {
                Layout.fillWidth: true
                icon.name: "document-open"
                text: KI18n.i18nc("@action:button Open a search result", "Open")
                focusPolicy: Qt.NoFocus
                onClicked: results.menu.launchResult(results.currentRow)
            }
            Repeater {
                model: results.currentData ? results.menu.resultEntries(results.currentRow).filter(entry => !entry.separator && !entry.title) : []

                delegate: PC3.ToolButton {
                    required property var modelData

                    Layout.fillWidth: true
                    icon.name: modelData.icon ?? ""
                    text: modelData.text ?? ""
                    enabled: modelData.enabled ?? true
                    focusPolicy: Qt.NoFocus
                    onClicked: modelData.handler()
                }
            }
            Item {
                Layout.fillHeight: true
            }
        }
    }

    PlasmaExtras.PlaceholderMessage {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.gridUnit * 4
        visible: list.count === 0 && !results.menu.runnerModel.querying
        iconName: "edit-none"
        text: KI18n.i18nc("@info:status %1 is what was searched for", "No results for “%1”", results.menu.query)
    }
}
