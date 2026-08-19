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

        clip: true
        cacheBuffer: 400

        // ------------------------------------------------------------
        // Layout
        //
        // Delegates themselves have a FIXED width.
        //
        // This is important. Magnification happens visually inside
        // the delegate, so changing scale can never change ListView
        // geometry or cause contentX to move underneath us.
        // ------------------------------------------------------------

        spacing: configs.baseSpacing

        property real tileWidth:
            width / Math.max(1, configs.number_of_pictures) - 10

        property real step:
            tileWidth + spacing

        property real viewportCenterX:
            width / 2

        // The selected wallpaper is allowed to live inside this zone
        // without moving the strip.
        //
        // 0.30 means the zone occupies roughly the middle 30% of the
        // screen.
        property real centerZone:
            width * 0.30

        property real centerLeft:
            viewportCenterX - centerZone / 2

        property real centerRight:
            viewportCenterX + centerZone / 2

        property int selectedIndex: 0
        property int hoveredIndex: -1

        // ------------------------------------------------------------
        // Helpers
        // ------------------------------------------------------------

        function clampIndex(i) {
            return Math.max(0, Math.min(i, count - 1))
        }

        function maxContentX() {
            return Math.max(0, contentWidth - width)
        }

        function clampX(x) {
            return Math.max(0, Math.min(x, maxContentX()))
        }

        function itemCenterOnScreen(i) {
            const item = itemAtIndex(i)

            if (!item)
                return viewportCenterX

            return item.x - contentX + item.width / 2
        }

        // ------------------------------------------------------------
        // Move the strip just enough to keep the selected item inside
        // the center zone.
        //
        // Unlike the previous version, this doesn't try to force the
        // item exactly into the middle.
        // ------------------------------------------------------------

        function keepSelectedInCenterZone(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

            const center = item.x - contentX + item.width / 2

            let targetX = contentX

            if (center < centerLeft) {
                targetX += center - centerLeft
            } else if (center > centerRight) {
                targetX += center - centerRight
            } else {
                return
            }

            contentX = clampX(targetX)
        }

        // ------------------------------------------------------------
        // Keyboard navigation
        //
        // Selection moves one wallpaper at a time.
        // The strip only starts moving when the selected wallpaper
        // leaves the center zone.
        // ------------------------------------------------------------

        function moveSelection(delta) {
            const newIndex =
                clampIndex(selectedIndex + delta)

            if (newIndex === selectedIndex)
                return

            selectedIndex = newIndex

            // Wait until ListView has updated the delegate positions.
            Qt.callLater(function() {
                keepSelectedInCenterZone(newIndex)
            })
        }

        // ------------------------------------------------------------
        // Mouse hover
        //
        // Hover changes the highlighted wallpaper but does NOT force
        // keyboard selection to change.
        //
        // If the hovered wallpaper is outside the useful area, we move
        // the strip toward it.
        // ------------------------------------------------------------

        function hoverWallpaper(i) {
            hoveredIndex = i

            const item = itemAtIndex(i)

            if (!item)
                return

            const center =
                item.x - contentX + item.width / 2

            // Give the mouse a little more freedom than keyboard
            // selection before moving the strip.
            const hoverLeft = width * 0.10
            const hoverRight = width * 0.90

            let targetX = contentX

            if (center < hoverLeft) {
                targetX += center - hoverLeft
            } else if (center > hoverRight) {
                targetX += center - hoverRight
            }

            if (targetX !== contentX)
                contentX = clampX(targetX)
        }

        // ------------------------------------------------------------
        // Activation
        // ------------------------------------------------------------

        function activateCurrent() {
            const path =
                folderModel.get(selectedIndex, "filePath")

            Quickshell.execDetached([
                "bash",
                Quickshell.env("HOME")
                    + "/.config/hyprquickpaper/commands.sh",
                path
            ])

            Qt.quit()
        }

        // ------------------------------------------------------------
        // Smooth strip movement
        // ------------------------------------------------------------

        Behavior on contentX {
            NumberAnimation {
                id: scrollAnimation

                duration: configs.animDuration
                easing.type: Easing.OutCubic
            }
        }

        // ------------------------------------------------------------
        // Delegates
        // ------------------------------------------------------------

        delegate: Item {
            id: delegateItem

            // FIXED layout width.
            //
            // Never change this according to scaleFactor.
            // This keeps ListView's geometry stable.
            width: list.tileWidth
            height: list.height

            property bool selected:
                index === list.selectedIndex

            property bool hovered:
                index === list.hoveredIndex

            // --------------------------------------------------------
            // Calculate visual magnification from the tile's position.
            // --------------------------------------------------------

            property real visualCenterX:
                x - list.contentX + width / 2

            property real distanceFromCenter:
                Math.abs(
                    visualCenterX
                    - list.viewportCenterX
                )

            property real scaleFactor: {
                const frac =
                    Math.min(
                        1,
                        distanceFromCenter
                        / list.viewportCenterX
                    )

                const t =
                    1 - frac * frac * (3 - 2 * frac)

                return configs.edgeScale
                    + (configs.zoomScale - configs.edgeScale) * t
            }

            // --------------------------------------------------------
            // Visual tile
            //
            // Scale is applied here, not to the ListView delegate.
            // --------------------------------------------------------

            Item {
                id: content

                anchors.centerIn: parent

                width: parent.width
                height: parent.height

                scale: delegateItem.scaleFactor

                // Prevent the visual tile from extending vertically
                // beyond the window.
                transformOrigin: Item.Center

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

                    // Decode once at the largest size we expect to show.
                    sourceSize.width:
                        delegateItem.width
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

                // ----------------------------------------------------
                // Selected border
                // ----------------------------------------------------

                Rectangle {
                    id: selectedBorder

                    z: 10

                    anchors.fill: parent

                    visible: delegateItem.selected

                    color: "transparent"

                    border.width: 2
                    border.color: configs.border_color

                    transform: Shear {
                        xFactor: configs.skewFactor
                    }
                }

                // ----------------------------------------------------
                // Hover border
                //
                // This is deliberately separate from selection so the
                // cursor can always tell you which wallpaper it is over.
                // ----------------------------------------------------

                Rectangle {
                    id: hoverBorder

                    z: 11

                    anchors.fill: parent

                    visible:
                        delegateItem.hovered
                        && !delegateItem.selected

                    color: "transparent"

                    border.width: 2

                    // Slightly more subtle than the selected border.
                    border.color: configs.border_color

                    opacity: 0.65

                    transform: Shear {
                        xFactor: configs.skewFactor
                    }
                }
            }

            // --------------------------------------------------------
            // Mouse interaction
            // --------------------------------------------------------

            MouseArea {
                anchors.fill: parent

                hoverEnabled: true

                onEntered: {
                    list.hoverWallpaper(index)
                }

                onExited: {
                    if (list.hoveredIndex === index)
                        list.hoveredIndex = -1
                }

                onClicked: {
                    list.selectedIndex = index

                    Qt.callLater(function() {
                        list.keepSelectedInCenterZone(index)
                    })

                    list.activateCurrent()
                }

                onWheel: function(wheel) {
                    if (wheel.angleDelta.y < 0) {
                        list.moveSelection(1)
                    } else if (wheel.angleDelta.y > 0) {
                        list.moveSelection(-1)
                    }

                    wheel.accepted = true
                }
            }
        }

        // ------------------------------------------------------------
        // Keyboard controls
        // ------------------------------------------------------------

        Keys.onPressed: function(event) {
            const big =
                Math.max(
                    1,
                    configs.number_of_pictures
                )

            switch (event.key) {
            case Qt.Key_Right:
            case Qt.Key_J:
                moveSelection(1)
                break

            case Qt.Key_Left:
            case Qt.Key_K:
                moveSelection(-1)
                break

            case Qt.Key_D:
                moveSelection(big)
                break

            case Qt.Key_U:
                moveSelection(-big)
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
