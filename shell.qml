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
            shellDir
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

        // This now controls the actual horizontal gap.
        //
        // 0 = tiles sit directly next to each other.
        // Positive values add horizontal space.
        spacing: configs.baseSpacing

        // Base horizontal width of each wallpaper.
        //
        // IMPORTANT:
        // edgeScale is NOT applied here.
        //
        // This means edgeScale can be 0.3 without making the
        // wallpapers 70% narrower.
        property real tileWidth:
            width / configs.number_of_pictures - 10

        property real viewportCenterX:
            width / 2

        // Extra space at both ends allows the first and last
        // wallpaper to be moved to the center.
        leftMargin:
            width / 2 - tileWidth / 2

        rightMargin:
            width / 2 - tileWidth / 2

        clip: true
        cacheBuffer: 400

        property int selectedIndex: 0

        function clampIndex(i) {
            return Math.max(
                0,
                Math.min(i, count - 1)
            )
        }

        function clampX(x) {
            return Math.max(
                0,
                Math.min(
                    x,
                    Math.max(0, contentWidth - width)
                )
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

        // Move the selected item's center to the center
        // of the viewport.
        //
        // Delegate widths never change, so this remains stable
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

            // -----------------------------------------------------
            // FIX:
            //
            // The delegate width is fixed.
            //
            // This is important because changing delegate width
            // while ListView is animating contentX can make the
            // ListView jump in the opposite direction.
            // -----------------------------------------------------
            width: list.tileWidth
            height: 500

            property bool active:
                index === list.selectedIndex

            // -----------------------------------------------------
            // Calculate magnification based on distance from
            // the center of the viewport.
            //
            // This produces:
            //
            // edge  -> edgeScale
            // center -> zoomScale
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

                // Smoothstep curve.
                //
                // 0 = center
                // 1 = edge
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

            Item {
                id: content

                anchors.centerIn: parent

                // -------------------------------------------------
                // IMPORTANT:
                //
                // The content always occupies the full horizontal
                // tile width.
                //
                // We do NOT scale this item's width.
                // -------------------------------------------------
                width: delegateItem.width
                height: delegateItem.height

                // -------------------------------------------------
                // Independent X/Y scaling.
                //
                // X:
                //   1.0 at the edges
                //   zoomScale at the center
                //
                // Y:
                //   edgeScale at the edges
                //   zoomScale at the center
                //
                // Therefore edgeScale = 0.3 makes the image short
                // without making it narrow.
                // -------------------------------------------------
                transform: Scale {
                    origin.x:
                        content.width / 2

                    origin.y:
                        content.height / 2

                    xScale:
                        Math.max(
                            1.0,
                            delegateItem.scaleFactor
                        )

                    yScale:
                        delegateItem.scaleFactor
                }

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

                    // Decode at the largest size needed.
                    sourceSize.width:
                        delegateItem.width
                        * configs.zoomScale

                    sourceSize.height:
                        delegateItem.height
                        * configs.zoomScale

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
