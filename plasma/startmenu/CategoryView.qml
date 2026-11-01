// SPDX-FileCopyrightText: 2026 OrielOS contributors
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.ki18n
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

// All apps by category, as Windows' Category view: a box for each category with its first apps'
// icons, which open straight away, and the category's name; choosing the box lists all its apps.
Item {
    id: categoryView

    required property MenuState menu

    // The category whose apps are listed, or -1 for the boxes.
    property int openCategory: -1
    readonly property var category: categoryView.openCategory >= 0 ? categoryView.menu.categories[categoryView.openCategory] ?? null : null
    readonly property Item keyboardView: categoryView.category ? appList : boxes

    // Back to the boxes, as each time All apps opens.
    function reset() {
        categoryView.openCategory = -1;
        boxes.currentIndex = 0;
    }

    function open(index: int) {
        categoryView.openCategory = index;
        appList.currentIndex = 0;
        appList.forceActiveFocus(Qt.OtherFocusReason);
    }

    function close() {
        const index = categoryView.openCategory;
        categoryView.openCategory = -1;
        boxes.currentIndex = Math.max(0, index);
        boxes.forceActiveFocus(Qt.OtherFocusReason);
    }

    GridView {
        id: boxes

        // Room for a 2 × 2 square of 38 px icons and the category's name.
        readonly property int columns: 3

        anchors.fill: parent
        visible: !categoryView.category
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: categoryView.menu.categories
        cellWidth: Math.floor(width / columns)
        cellHeight: 150
        keyNavigationEnabled: false
        currentIndex: 0

        Accessible.name: KI18n.i18nc("@title All apps grouped by category", "Categories")
        Accessible.role: Accessible.List

        delegate: PC3.ItemDelegate {
            id: box

            required property int index
            required property var modelData

            readonly property var apps: box.modelData.model
            // Four icons, or three and a stack that opens the rest.
            readonly property int iconsShown: apps.count > 4 ? 3 : apps.count

            width: boxes.cellWidth
            height: boxes.cellHeight
            highlighted: GridView.isCurrentItem && boxes.activeFocus
            hoverEnabled: true
            focusPolicy: Qt.NoFocus
            text: String(box.modelData.name ?? "")
            Accessible.name: text
            Accessible.role: Accessible.Button

            onClicked: categoryView.open(box.index)

            contentItem: ColumnLayout {
                spacing: Kirigami.Units.smallSpacing

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 104
                    Layout.preferredHeight: 104
                    radius: 8
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)

                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: Kirigami.Units.smallSpacing * 2

                        Repeater {
                            model: box.iconsShown

                            delegate: MouseArea {
                                id: icon

                                required property int index
                                readonly property string appName: String(box.apps.data(box.apps.index(icon.index, 0), Qt.DisplayRole) ?? "")

                                width: 38
                                height: 38
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                Accessible.role: Accessible.Button
                                Accessible.name: icon.appName

                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        categoryView.menu.openOtherAppMenu(box.apps, icon.index, icon, mouse.x, mouse.y, false);
                                    } else {
                                        categoryView.menu.launchFrom(box.apps, icon.index);
                                    }
                                }

                                PC3.ToolTip.text: icon.appName
                                PC3.ToolTip.visible: icon.containsMouse
                                PC3.ToolTip.delay: Kirigami.Units.toolTipDelay

                                Kirigami.Icon {
                                    anchors.fill: parent
                                    source: box.apps.data(box.apps.index(icon.index, 0), Qt.DecorationRole) ?? ""
                                    active: icon.containsMouse
                                }
                            }
                        }

                        // The rest of the category's apps, as small icons.
                        Grid {
                            visible: box.apps.count > 4
                            width: 38
                            height: 38
                            columns: 2
                            spacing: 2

                            Repeater {
                                model: Math.min(4, Math.max(0, box.apps.count - 3))

                                delegate: Kirigami.Icon {
                                    required property int index

                                    width: 18
                                    height: 18
                                    source: box.apps.data(box.apps.index(3 + index, 0), Qt.DecorationRole) ?? ""
                                }
                            }
                        }
                    }
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: box.text
                    textFormat: Text.PlainText
                    font.pixelSize: 12
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }
        }

        Keys.onTabPressed: categoryView.menu.cycleFocus(true)
        Keys.onBacktabPressed: categoryView.menu.cycleFocus(false)
        Keys.onPressed: event => {
            const count = boxes.count;
            const index = boxes.currentIndex;
            const mirrored = boxes.effectiveLayoutDirection === Qt.RightToLeft;
            switch (event.key) {
            case Qt.Key_Left:
            case Qt.Key_Right: {
                const step = (event.key === Qt.Key_Right) !== mirrored ? 1 : -1;
                boxes.currentIndex = Math.max(0, Math.min(count - 1, index + step));
                event.accepted = true;
                break;
            }
            case Qt.Key_Up:
                if (index >= boxes.columns) {
                    boxes.currentIndex = index - boxes.columns;
                } else {
                    categoryView.menu.focusSearch();
                }
                event.accepted = true;
                break;
            case Qt.Key_Down:
                boxes.currentIndex = Math.min(count - 1, index + boxes.columns);
                event.accepted = true;
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                if (index >= 0) {
                    categoryView.open(index);
                }
                event.accepted = true;
                break;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        visible: !!categoryView.category
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true

            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 5
                text: String(categoryView.category?.name ?? "")
                textFormat: Text.PlainText
            }

            PillButton {
                back: true
                text: KI18n.i18nc("@action:button Go back to the categories", "Categories")
                onClicked: categoryView.close()
            }
        }

        PC3.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true

            PC3.ScrollBar.horizontal.policy: PC3.ScrollBar.AlwaysOff

            ListView {
                id: appList

                readonly property var apps: categoryView.category?.model ?? null

                clip: true
                model: appList.apps
                keyNavigationEnabled: false
                currentIndex: 0

                Accessible.name: String(categoryView.category?.name ?? "")
                Accessible.role: Accessible.List

                delegate: ListRow {
                    id: row

                    required property int index
                    required property var model

                    width: appList.width
                    label: String(row.model.display ?? "")
                    iconSource: row.model.decoration ?? ""
                    current: ListView.isCurrentItem && appList.activeFocus

                    onClicked: categoryView.menu.launchFrom(appList.apps, row.index)
                    onContextMenuRequested: (x, y) => categoryView.menu.openOtherAppMenu(appList.apps, row.index, row, x, y, false)
                }

                Keys.onTabPressed: categoryView.menu.cycleFocus(true)
                Keys.onBacktabPressed: categoryView.menu.cycleFocus(false)
                Keys.onPressed: event => {
                    if (categoryView.menu.isContextMenuKey(event)) {
                        const current = appList.currentItem;
                        if (current) {
                            categoryView.menu.openOtherAppMenu(appList.apps, appList.currentIndex, current, current.width / 2, current.height / 2, true);
                        }
                        event.accepted = true;
                        return;
                    }
                    switch (event.key) {
                    case Qt.Key_Escape:
                    case Qt.Key_Backspace:
                        categoryView.close();
                        event.accepted = true;
                        break;
                    case Qt.Key_Up:
                        if (appList.currentIndex > 0) {
                            appList.decrementCurrentIndex();
                        } else {
                            categoryView.menu.focusSearch();
                        }
                        event.accepted = true;
                        break;
                    case Qt.Key_Down:
                        appList.incrementCurrentIndex();
                        event.accepted = true;
                        break;
                    case Qt.Key_Return:
                    case Qt.Key_Enter:
                    case Qt.Key_Space:
                        categoryView.menu.launchFrom(appList.apps, appList.currentIndex);
                        event.accepted = true;
                        break;
                    }
                }
            }
        }
    }
}
