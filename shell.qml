import Quickshell
import Quickshell.Io
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Wayland

PanelWindow {
    id: main

    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprquickpaper/config.json"
        watchChanges: true
        onFileChanged: reload()

        JsonAdapter {
            id: configs

            property string wallpaper_path
            property string cache_path
            property int number_of_pictures
            property string border_color
            property real opacity

            // ---- Easy-to-edit settings ----
            property int speed
            property int animDuration
            property real zoomScale
            property real edgeScale
            property real skewFactor
            property int baseSpacing
            // --------------------------------
        }
    }

    implicitHeight: 500
    implicitWidth: Screen.width
    color: "transparent"

    aboveWindows: true
    exclusionMode: "Ignore"
    exclusiveZone: 1

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Component.onCompleted: {
        Quickshell.execDetached([
            "bash",
            Quickshell.shellPath("cache.sh"),
            Quickshell.shellDir
        ])
    }

    FolderListModel {
        id: folderModel

        folder: "file://" + configs.wallpaper_path
        showDirs: false
        nameFilters: ["*.png", "*.jpg"]
        sortField: FolderListModel.Name
    }

    ListView {
        id: list

        anchors.fill: parent
        focus: true

        model: folderModel
        orientation: ListView.Horizontal

        spacing: configs.baseSpacing

        // Extra space at both ends allows the first and last wallpaper
        // to be moved all the way to the center of the screen.
        //
        // Account for the largest visual size of the tile.
        leftMargin: width / 2 - tileWidth * configs.zoomScale / 2
        rightMargin: width / 2 - tileWidth * configs.zoomScale / 2

        clip: true
        cacheBuffer: 400

        property int selectedIndex: 0

        // Fixed layout width.
        //
        // IMPORTANT:
        // This must NOT change with the magnification.
        // Changing delegate width while contentX is moving can cause
        // the ListView to recalculate item positions and jump backwards.
        property real tileWidth:
            width / configs.number_of_pictures - 10

        property real viewportCenterX:
            width / 2

        function clampIndex(i) {
            return Math.max(0, Math.min(i, count - 1))
        }

        function clampX(x) {
            return Math.max(0, Math.min(x, contentWidth - width))
        }

        function activateCurrent() {
            const path = folderModel.get(selectedIndex, "filePath")

            Quickshell.execDetached([
                "bash",
                Quickshell.env("HOME") + "/.config/hyprquickpaper/commands.sh",
                path
            ])

            Qt.quit()
        }

        // Move the selected item's actual center to the center
        // of the viewport.
        //
        // Since delegate widths are now fixed, item.x remains stable
        // while contentX is animated.
        function ensureVisibleAnimated(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

            const itemCenter =
                item.x + item.width / 2

            const targetX =
                itemCenter - width / 2

            contentX = clampX(targetX)
        }

        // Moves the selection by `delta` tiles.
        function moveSelection(delta, speedMultiplier) {
            anim.v = configs.speed * speedMultiplier

            selectedIndex =
                clampIndex(selectedIndex + delta)

            ensureVisibleAnimated(selectedIndex)
        }

        Behavior on contentX {
            SmoothedAnimation {
                id: anim

                property int v: configs.speed

                duration: configs.animDuration
            }
        }

        delegate: Item {
            id: delegateItem

            height: 500

            // The selected item.
            property bool active:
                index === list.selectedIndex

            // -------------------------------------------------
            // FIX:
            // Keep the ListView delegate width constant.
            // -------------------------------------------------
            readonly property real baseWidth:
                list.tileWidth

            width: baseWidth

            // -------------------------------------------------
            // Dock-style magnification
            // -------------------------------------------------
            //
            // This calculates how close the item is to the
            // center of the viewport.
            //
            // Unlike the old implementation, this value only
            // changes the visual scale and NOT the ListView
            // geometry.
            property real scaleFactor: {
                const centerX =
                    x - list.contentX + width / 2

                const frac =
                    Math.min(
                        1,
                        Math.abs(
                            centerX - list.viewportCenterX
                        ) / list.viewportCenterX
                    )

                const t =
                    1 - frac * frac * (3 - 2 * frac)

                return configs.edgeScale
                    + (
                        configs.zoomScale
                        - configs.edgeScale
                    ) * t
            }

            Item {
                id: content

                anchors.centerIn: parent

                // Keep the actual content at the fixed base size.
                width: delegateItem.baseWidth
                height: delegateItem.height

                // -------------------------------------------------
                // IMPORTANT:
                // Scale the visual content instead of changing
                // the ListView delegate width.
                // -------------------------------------------------
                scale: delegateItem.scaleFactor

                Text {
                    id: alt

                    text: ""

                    color: configs.border_color

                    anchors.centerIn: parent

                    font.pixelSize: 16

                    transform: Shear {
                        xFactor: configs.skewFactor
                    }
                }

                Image {
                    id: img

                    anchors.fill: parent

                    opacity: configs.opacity

                    fillMode: Image.PreserveAspectCrop

                    asynchronous: true
                    cache: false
                    smooth: true

                    source:
                        "file://"
                        + configs.cache_path
                        + fileName

                    // Decode once at the largest size the image
                    // will ever be displayed instead of changing
                    // sourceSize during the animation.
                    sourceSize.width:
                        delegateItem.baseWidth
                        * configs.zoomScale

                    sourceSize.height:
                        delegateItem.height

                    transform: Shear {
                        xFactor: configs.skewFactor
                    }

                    Timer {
                        id: retryTimer

                        interval: 1000
                        repeat: false

                        onTriggered: {
                            const s = img.source

                            img.source = ""
                            img.source = s
                        }
                    }

                    onStatusChanged: {
                        if (status === Image.Error) {
                            alt.text = "Caching"
                            retryTimer.start()
                        }
                    }
                }

                Rectangle {
                    id: border

                    z: 10

                    anchors.fill: parent

                    visible:
                        delegateItem.active

                    color: "transparent"

                    border.width: 2
                    border.color:
                        configs.border_color

                    transform: Shear {
                        xFactor: configs.skewFactor
                    }
                }
            }

            MouseArea {
                anchors.fill: parent

                hoverEnabled: true

                onEntered: {
                    list.selectedIndex = index
                }

                onClicked: {
                    list.activateCurrent()
                }

                onWheel: function(wheel) {
                    list.flick(
                        -wheel.angleDelta.y * 8,
                        0
                    )

                    wheel.accepted = true
                }
            }
        }

        Keys.onPressed: function(event) {
            const big =
                configs.number_of_pictures

            switch (event.key) {
            case Qt.Key_Right:
            case Qt.Key_J:
                moveSelection(1, 1)
                break

            case Qt.Key_K:
            case Qt.Key_Left:
                moveSelection(-1, 1)
                break

            case Qt.Key_D:
                moveSelection(big, big)
                break

            case Qt.Key_U:
                moveSelection(-big, big)
                break

            case Qt.Key_Space:
            case Qt.Key_Return:
                activateCurrent()
                break

            case Qt.Key_Escape:
                Qt.quit()
                break

            default:
                return
            }

            event.accepted = true
        }
    }
}
