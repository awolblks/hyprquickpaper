delegate: Item {
    id: delegateItem

    height: 500

    property bool active:
        index === list.selectedIndex

    // Width of the visual tile at maximum magnification.
    readonly property real maxWidth:
        list.tileWidth * configs.zoomScale

    // Keep ListView geometry fixed.
    //
    // This is the width occupied by each tile in the list.
    width: maxWidth

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

        // The content is always the maximum size and is then
        // visually scaled down.
        width: list.tileWidth
        height: delegateItem.height

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

            sourceSize.width:
                list.tileWidth * configs.zoomScale

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
