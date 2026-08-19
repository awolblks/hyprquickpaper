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
        leftMargin: width / 2 - tileWidth / 2
        rightMargin: width / 2 - tileWidth / 2

        clip: true
        cacheBuffer: 400

        property int selectedIndex: 0
        property real tileWidth: width / configs.number_of_pictures - 10
        property real viewportCenterX: width / 2

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

        // Move the selected item's actual center to the center of the viewport.
        //
        // We deliberately use item.x and item.width instead of calculating
        // the position from the index. This is important because delegate
        // widths change according to the magnification curve.
        function ensureVisibleAnimated(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

            const itemCenter = item.x + item.width / 2
            const targetX = itemCenter - width / 2

            contentX = clampX(targetX)
        }

        // Moves the selection by `delta` tiles.
        function moveSelection(delta, speedMultiplier) {
            anim.v = configs.speed * speedMultiplier

            selectedIndex = clampIndex(selectedIndex + delta)

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

            property bool active: index === list.selectedIndex

            // Base (unscaled) slot width.
            // This is intentionally independent from the delegate's actual
            // width because actual width depends on scaleFactor.
            readonly property real baseWidth: list.tileWidth

            // --- Dock-style magnification ---
            //
            // Calculate scale from the delegate's current on-screen position.
            property real scaleFactor: {
                const centerX =
                    x - list.contentX + baseWidth / 2

                const frac =
                    Math.min(
                        1,
                        Math.abs(centerX - list.viewportCenterX)
                        / list.viewportCenterX
                    )

                const t =
                    1 - frac * frac * (3 - 2 * frac)

                return configs.edgeScale
                    + (configs.zoomScale - configs.edgeScale) * t
            }

            // The delegate's actual layout width changes with magnification.
            width: baseWidth * scaleFactor

            Item {
                id: content

                anchors.centerIn: parent

                width: parent.width

                // Prevent the image from becoming taller than the window.
                height:
                    delegateItem.height
                    * Math.min(1, delegateItem.scaleFactor)

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

                    source: "file://" + configs.cache_path + fileName

                    // Decode once at the largest size the image will ever
                    // be displayed instead of changing sourceSize during
                    // the animation.
                    sourceSize.width:
                        delegateItem.baseWidth * configs.zoomScale

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

                    visible: delegateItem.active

                    color: "transparent"

                    border.width: 2
                    border.color: configs.border_color

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
                    list.flick(-wheel.angleDelta.y * 8, 0)
                    wheel.accepted = true
                }
            }
        }

        Keys.onPressed: function(event) {
            const big = configs.number_of_pictures

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
