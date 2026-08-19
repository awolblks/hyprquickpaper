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
         * The ListView has fixed slots.
         *
         * Scaling a wallpaper NEVER changes the ListView geometry.
         */
        spacing: configs.baseSpacing

        property real tileWidth:
            width / Math.max(1, configs.number_of_pictures)

        property real viewportCenterX:
            width / 2

        property int selectedIndex: 0

        /*
         * This determines how much of the viewport a selected
         * wallpaper is allowed to wander through before the strip
         * itself moves.
         *
         * It is deliberately independent of the visual scale.
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
        //
        // The selected wallpaper's FIXED SLOT is what determines
        // scrolling. The visual scale has no influence on it.
        // ------------------------------------------------------------

        function keepSelectedInCenterZone(i) {
            const item = itemAtIndex(i)

            if (!item)
                return

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
        // Smooth keyboard scrolling
        // ------------------------------------------------------------

        Behavior on contentX {
            NumberAnimation {
                duration: configs.animDuration
                easing.type: Easing.OutCubic
            }
        }

        // ------------------------------------------------------------
        // Wallpaper
        // ------------------------------------------------------------

        delegate: Item {
            id: delegateItem

            /*
             * FIXED SLOT.
             *
             * This is the most important part.
             *
             * The ListView always has exactly the same geometry,
             * regardless of whether the wallpaper is at the center
             * or at the edge.
             */
            width: list.tileWidth
            height: list.height

            property bool selected:
                index === list.selectedIndex

            /*
             * Fixed center of this slot on the screen.
             */
            property real slotCenterX:
                x
                - list.contentX
                + width / 2

            /*
             * Distance from the actual screen center.
             */
            property real distanceFromCenter:
                Math.abs(
                    slotCenterX
                    - list.viewportCenterX
                )

            /*
             * Normalized distance.
             *
             * 0 = exact center
             * 1 = screen edge
             */
            property real normalizedDistance: {
                return Math.min(
                    1,
                    distanceFromCenter
                    / list.viewportCenterX
                )
            }

            /*
             * Smoothstep curve.
             *
             * This is deliberately NOT configurable.
             *
             * It simply gives us:
             *
             * center -> zoomScale
             * edge   -> edgeScale
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

            /*
             * The visual wallpaper is centered on the FIXED slot
             * center. It does not participate in ListView geometry.
             */
            Item {
                id: visual

                width:
                    delegateItem.width

                height:
                    delegateItem.height

                anchors.centerIn:
                    parent

                scale:
                    delegateItem.scaleFactor

                transformOrigin:
                    Item.Center

                // ----------------------------------------------------
                // Fallback text
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
                // Wallpaper
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
                     * Decode at the largest size needed.
                     *
                     * This is independent of the animated visual
                     * scale, so scrolling does not repeatedly
                     * trigger image decoding.
                     */
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
                            status === Image.Error
                        ) {
                            alt.text = "Caching"
                            retryTimer.start()
                        }
                    }
                }

                // ----------------------------------------------------
                // SINGLE HIGHLIGHT
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

                /*
                 * Hover ONLY changes selection.
                 *
                 * It does NOT modify contentX.
                 */
                onEntered: {
                    list.selectWallpaper(index)
                }

                onClicked: {
                    list.selectWallpaper(index)
                    list.activateCurrent()
                }

                /*
                 * Wheel behaves like keyboard navigation.
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
