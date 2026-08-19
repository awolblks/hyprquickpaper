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
        // FIXED LAYOUT
        //
        // The ListView itself never changes tile width.
        // Magnification happens only on the visual content inside each
        // delegate.
        // ------------------------------------------------------------

        spacing: configs.baseSpacing

        property real tileWidth:
            width / Math.max(1, configs.number_of_pictures) - 10

        property real step:
            tileWidth + spacing

        property real viewportCenterX:
            width / 2

        // The selected tile can move within this area before the strip
        // itself starts moving.
        property real centerZone:
            width * 0.30

        property real centerLeft:
            viewportCenterX - centerZone / 2

        property real centerRight:
            viewportCenterX + centerZone / 2

        // ------------------------------------------------------------
        // THERE IS ONLY ONE SELECTION
        //
        // Mouse and keyboard both modify this value.
        // ------------------------------------------------------------

        property int selectedIndex: 0

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
        // Keep selected wallpaper inside the center zone.
        //
        // It does NOT force the wallpaper to the exact center.
        // It only starts moving the strip once the selected wallpaper
        // leaves the center zone.
        // ------------------------------------------------------------

        function keepSelectedInCenterZone(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

            const center =
                item.x
                - contentX
                + item.width / 2

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
        // Unified selection function.
        //
        // BOTH mouse and keyboard use this.
        //
        // This is the important part that prevents the old problem
        // where the cursor selected one wallpaper while the keyboard
        // remembered another.
        // ------------------------------------------------------------

        function selectWallpaper(i) {
            const newIndex = clampIndex(i)

            if (newIndex === selectedIndex) {
                Qt.callLater(function() {
                    keepSelectedInCenterZone(newIndex)
                })

                return
            }

            selectedIndex = newIndex

            Qt.callLater(function() {
                keepSelectedInCenterZone(newIndex)
            })
        }

        // ------------------------------------------------------------
        // Keyboard / wheel navigation
        // ------------------------------------------------------------

        function moveSelection(delta) {
            selectWallpaper(selectedIndex + delta)
        }

        // ------------------------------------------------------------
        // Activate selected wallpaper
        // ------------------------------------------------------------

        function activateCurrent() {
            const path =
                folderModel.get(
                    selectedIndex,
                    "filePath"
                )

            Quickshell.execDetached([
                "bash",
                Quickshell.env("HOME")
                    + "/.config/hyprquickpaper/commands.sh",
                path
            ])

            Qt.quit()
        }

        // ------------------------------------------------------------
        // Smooth scrolling
        // ------------------------------------------------------------

        Behavior on contentX {
            NumberAnimation {
                id: scrollAnimation

                duration: configs.animDuration

                easing.type:
                    Easing.OutCubic
            }
        }

        // ------------------------------------------------------------
        // Delegate
        // ------------------------------------------------------------

        delegate: Item {
            id: delegateItem

            // FIXED width.
            //
            // Do NOT multiply this by scaleFactor.
            width: list.tileWidth
            height: list.height

            property bool selected:
                index === list.selectedIndex

            // Position of this tile's center on the screen.
            property real visualCenterX:
                x
                - list.contentX
                + width / 2

            property real distanceFromCenter:
                Math.abs(
                    visualCenterX
                    - list.viewportCenterX
                )

            // --------------------------------------------------------
            // Magnification
            //
            // This only affects the visual item below.
            // It does not affect ListView geometry.
            // --------------------------------------------------------

            property real scaleFactor: {
                const frac =
                    Math.min(
                        1,
                        distanceFromCenter
                        / list.viewportCenterX
                    )

                const t =
                    1
                    - frac
                    * frac
                    * (3 - 2 * frac)

                return configs.edgeScale
                    + (
                        configs.zoomScale
                        - configs.edgeScale
                    ) * t
            }

            Item {
                id: content

                anchors.centerIn: parent

                width: parent.width
                height: parent.height

                scale: delegateItem.scaleFactor

                transformOrigin:
                    Item.Center

                // ----------------------------------------------------
                // Wallpaper
                // ----------------------------------------------------

                Text {
                    id: alt

                    text: ""

                    color:
                        configs.border_color

                    anchors.centerIn: parent

                    font.pixelSize: 16

                    transform: Shear {
                        xFactor:
                            configs.skewFactor
                    }
                }

                Image {
                    id: img

                    anchors.fill: parent

                    opacity:
                        configs.opacity

                    fillMode:
                        Image.PreserveAspectCrop

                    asynchronous: true
                    cache: false
                    smooth: true

                    source:
                        "file://"
                        + configs.cache_path
                        + fileName

                    // Decode once at maximum expected size.
                    sourceSize.width:
                        delegateItem.width
                        * configs.zoomScale

                    sourceSize.height:
                        delegateItem.height

                    transform: Shear {
                        xFactor:
                            configs.skewFactor
                    }

                    Timer {
                        id: retryTimer

                        interval: 1000
                        repeat: false

                        onTriggered: {
                            const s =
                                img.source

                            img.source = ""

                            img.source = s
                        }
                    }

                    onStatusChanged: {
                        if (
                            status
                            === Image.Error
                        ) {
                            alt.text = "Caching"
                            retryTimer.start()
                        }
                    }
                }

                // ----------------------------------------------------
                // SINGLE HIGHLIGHT
                //
                // There is no separate hover border anymore.
                // Mouse and keyboard both manipulate selectedIndex.
                // ----------------------------------------------------

                Rectangle {
                    id: border

                    z: 10

                    anchors.fill:
                        parent

                    visible:
                        delegateItem.selected

                    color:
                        "transparent"

                    border.width: 2

                    border.color:
                        configs.border_color

                    transform: Shear {
                        xFactor:
                            configs.skewFactor
                    }
                }
            }

            // --------------------------------------------------------
            // Mouse
            // --------------------------------------------------------

            MouseArea {
                anchors.fill:
                    parent

                hoverEnabled:
                    true

                // Hover immediately becomes the current selection.
                //
                // This means that if you move the mouse to wallpaper 6
                // and then press Right, keyboard navigation starts from
                // wallpaper 6 rather than jumping back to an old
                // keyboard selection.
                onEntered: {
                    list.selectWallpaper(index)
                }

                onClicked: {
                    list.selectWallpaper(index)

                    Qt.callLater(function() {
                        list.activateCurrent()
                    })
                }

                onWheel: function(wheel) {
                    if (
                        wheel.angleDelta.y < 0
                    ) {
                        list.moveSelection(1)
                    } else if (
                        wheel.angleDelta.y > 0
                    ) {
                        list.moveSelection(-1)
                    }

                    wheel.accepted = true
                }
            }
        }

        // ------------------------------------------------------------
        // Keyboard
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
