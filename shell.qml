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

        // ---------------------------------------------------------
        // Spacing between the actual resting-size images.
        //
        // With baseSpacing = 0, the edge-scale images touch.
        // Positive values add a gap.
        // ---------------------------------------------------------
        spacing: configs.baseSpacing

        // ---------------------------------------------------------
        // The layout slot is based on the smallest visual size.
        //
        // The images themselves grow toward the center, but their
        // centers remain fixed. This keeps ListView geometry stable
        // and prevents the jumping/reversing bug.
        // ---------------------------------------------------------
        property real tileWidth:
            (width / configs.number_of_pictures - 10)
            * configs.edgeScale

        property real viewportCenterX:
            width / 2

        // The largest visual width.
        property real maxTileWidth:
            (width / configs.number_of_pictures - 10)
            * configs.zoomScale

        // Extra room at the beginning and end so that the first
        // and last image can reach the center of the screen.
        leftMargin:
            width / 2
            - tileWidth / 2

        rightMargin:
            width / 2
            - tileWidth / 2

        clip: true
        cacheBuffer: 400

        property int selectedIndex: 0

        function clampIndex(i) {
            return Math.max(0, Math.min(i, count - 1))
        }

        function clampX(x) {
            return Math.max(
                0,
                Math.min(x, contentWidth - width)
            )
        }

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

        // ---------------------------------------------------------
        // Move the selected item's center to the center of the
        // viewport.
        //
        // Delegate widths are fixed, so item.x never changes as a
        // consequence of magnification.
        // ---------------------------------------------------------
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

        function moveSelection(delta, speedMultiplier) {
            anim.v =
                configs.speed * speedMultiplier

            selectedIndex =
                clampIndex(
                    selectedIndex + delta
                )

            ensureVisibleAnimated(
                selectedIndex
            )
        }

        Behavior on contentX {
            SmoothedAnimation {
                id: anim

                property int v:
                    configs.speed

                duration:
                    configs.animDuration
            }
        }

        delegate: Item {
            id: delegateItem

            height: 500

            // -----------------------------------------------------
            // FIX #1:
            //
            // Delegate width NEVER changes while scrolling.
            //
            // This prevents ListView from changing item positions
            // while contentX is being animated.
            // -----------------------------------------------------
            width: list.tileWidth

            property bool active:
                index === list.selectedIndex

            // -----------------------------------------------------
            // Calculate magnification from distance to viewport
            // center.
            // -----------------------------------------------------
            property real scaleFactor: {
                const centerX =
                    x
                    - list.contentX
                    + width / 2

                const distance =
                    Math.abs(
                        centerX
                        - list.viewportCenterX
                    )

                const normalized =
                    Math.min(
                        1,
                        distance
                        / list.viewportCenterX
                    )

                // Smoothstep.
                const t =
                    1
                    - normalized
                    * normalized
                    * (3 - 2 * normalized)

                return configs.edgeScale
                    + (
                        configs.zoomScale
                        - configs.edgeScale
                    ) * t
            }

            // -----------------------------------------------------
            // FIX #2:
            //
            // The visual content grows around its center.
            //
            // At the edges:
            //
            //     width = tileWidth
            //
            // At the center:
            //
            //     width = tileWidth * zoomScale / edgeScale
            //
            // This keeps the resting images exactly tileWidth apart.
            // -----------------------------------------------------
            Item {
                id: content

                anchors.centerIn: parent

                width:
                    list.tileWidth
                    * delegateItem.scaleFactor
                    / configs.edgeScale

                height:
                    delegateItem.height

                // Since tileWidth already represents the
                // edgeScale-sized image, this scale produces:
                //
                // edge: 1.0
                // center: zoomScale / edgeScale
                //
                scale:
                    configs.edgeScale

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

                    // Decode at the largest size required.
                    sourceSize.width:
                        (
                            list.width
                            / configs.number_of_pictures
                            - 10
                        )
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
                            alt.text =
                                "Caching"

                            retryTimer.start()
                        }
                    }
                }

                Rectangle {
                    id: border

                    z: 10

                    anchors.fill:
                        parent

                    visible:
                        delegateItem.active

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

            MouseArea {
                anchors.fill:
                    parent

                hoverEnabled:
                    true

                onEntered: {
                    list.selectedIndex =
                        index
                }

                onClicked: {
                    list.activateCurrent()
                }

                onWheel:
                    function(wheel) {
                        list.flick(
                            -wheel.angleDelta.y * 8,
                            0
                        )

                        wheel.accepted = true
                    }
            }
        }

        Keys.onPressed:
            function(event) {
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
