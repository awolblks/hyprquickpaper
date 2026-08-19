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

        /*
         * IMPORTANT:
         *
         * The ListView geometry stays fixed.
         * baseSpacing therefore controls the actual slot spacing,
         * while the visual wallpaper width is handled separately.
         */
        spacing: configs.baseSpacing

        property real tileWidth:
            width / Math.max(1, configs.number_of_pictures)

        property real viewportCenterX:
            width / 2

        property int selectedIndex: 0

        /*
         * How far the selected wallpaper can move before the strip
         * itself starts moving.
         */
        property real centerZone:
            width * 0.30

        property real centerLeft:
            viewportCenterX - centerZone / 2

        property real centerRight:
            viewportCenterX + centerZone / 2

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

        function selectWallpaper(i) {
            selectedIndex = clampIndex(i)
        }

        // ------------------------------------------------------------
        // Keyboard scrolling
        // ------------------------------------------------------------

        function keepSelectedInCenterZone(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

            /*
             * Use the FIXED slot center.
             * The visual scaling has no influence on scrolling.
             */
            const center =
                item.x
                - contentX
                + tileWidth / 2

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

        function moveSelection(delta) {
            const newIndex =
                clampIndex(selectedIndex + delta)

            if (newIndex === selectedIndex)
                return

            selectedIndex = newIndex

            Qt.callLater(function() {
                keepSelectedInCenterZone(newIndex)
            })
        }

        // ------------------------------------------------------------
        // Activate wallpaper
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
                duration: configs.animDuration
                easing.type: Easing.OutCubic
            }
        }

        // ------------------------------------------------------------
        // Wallpaper delegate
        // ------------------------------------------------------------

        delegate: Item {
            id: delegateItem

            /*
             * FIXED SLOT.
             *
             * This never changes with scale.
             */
            width: list.tileWidth
            height: list.height

            property bool selected:
                index === list.selectedIndex

            /*
             * Fixed slot center on the screen.
             */
            property real slotCenterX:
                x
                - list.contentX
                + width / 2

            property real distanceFromCenter:
                Math.abs(
                    slotCenterX
                    - list.viewportCenterX
                )

            /*
             * Distance from center:
             *
             * 0 = center
             * 1 = edge
             */
            property real normalizedDistance: {
                return Math.min(
                    1,
                    distanceFromCenter
                    / list.viewportCenterX
                )
            }

            /*
             * Hard-coded smoothstep curve.
             *
             * No curve parameter in the config.
             */
            property real scaleFactor: {
                const d =
                    normalizedDistance

                const t =
                    1
                    - d * d
                    * (3 - 2 * d)

                return configs.edgeScale
                    + (
                        configs.zoomScale
                        - configs.edgeScale
                    ) * t
            }

            // --------------------------------------------------------
            // Visual wallpaper
            // --------------------------------------------------------

            Item {
                id: visual

                anchors.centerIn:
                    parent

                /*
                 * The important part:
                 *
                 * The ListView slot remains tileWidth.
                 *
                 * The visual width compensates for the scale so the
                 * wallpaper doesn't become physically tiny at the
                 * edges.
                 *
                 * The 1.0 here means the wallpaper fills its slot.
                 */
                width:
                    delegateItem.width
                    / delegateItem.scaleFactor

                height:
                    delegateItem.height

                scale:
                    delegateItem.scaleFactor

                transformOrigin:
                    Item.Center

                // ----------------------------------------------------
                // Wallpaper fallback text
                // ----------------------------------------------------

                Text {
                    id: alt

                    text: ""

                    color:
                        configs.border_color

                    anchors.centerIn:
                        parent

                    font.pixelSize: 16

                    transform: Shear {
                        xFactor:
                            configs.skewFactor
                    }
                }

                // ----------------------------------------------------
                // Wallpaper image
                // ----------------------------------------------------

                Image {
                    id: img

                    anchors.fill:
                        parent

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

                    /*
                     * Decode based on the actual visual width.
                     */
                    sourceSize.width:
                        visual.width

                    sourceSize.height:
                        visual.height

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
                            status === Image.Error
                        ) {
                            alt.text = "Caching"
                            retryTimer.start()
                        }
                    }
                }

                // ----------------------------------------------------
                // Single selection border
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

                    border.width:
                        2

                    border.color:
                        configs.border_color

                    transform: Shear {
                        xFactor:
                            configs.skewFactor
                    }
                }
            }

            // --------------------------------------------------------
            // Mouse interaction
            // --------------------------------------------------------

            MouseArea {
                anchors.fill:
                    parent

                hoverEnabled:
                    true

                /*
                 * Hover changes selection only.
                 * It does NOT move the strip.
                 */
                onEntered: {
                    list.selectWallpaper(index)
                }

                onClicked: {
                    list.selectWallpaper(index)
                    list.activateCurrent()
                }

                /*
                 * Wheel navigation behaves like keyboard navigation.
                 */
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
