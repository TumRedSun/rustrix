// ReactionSendersPopup.qml
//
// Modal popup listing who reacted to a message with a specific emoji.
// Opens when the user right-clicks a reaction chip in MessageBubble.
//
// Behavior:
//   - Centered on the whole application window (parent: Overlay.overlay)
//   - Title shows the emoji + total count
//   - Scrollable list of senders with avatar (initials) + display_name + user_id
//   - Escape / outside click closes
//
// Usage:
//   ReactionSendersPopup { id: rsp }
//   rsp.emoji = "👍"
//   rsp.senders = [{"user_id":"@a:m.org","display_name":"Alice"}, ...]
//   rsp.open()

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MatrixClient

Dialog {
    id: root
    modal: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Size derives from the client window (grows with Theme.scale above the
    // reference, capped by the overlay size — see EmojiPicker.qml).
    width: Math.min(Math.round(440 * Math.max(1, Theme.scale)), parent.width - Theme.paddingLg * 2)
    height: Math.min(Math.round(420 * Math.max(1, Theme.scale)), parent.height - Theme.paddingLg * 2)
    padding: 0

    // ── Public API ──
    // The emoji being inspected.
    property string emoji: ""
    // Senders array — pass an array of {user_id, display_name} objects
    // (the QML side already has this from MessageEntry.reactions JSON).
    property var senders: []

    background: Rectangle {
        color: Theme.windowBg
        radius: Theme.radiusLg
        border.color: Theme.border
        border.width: 1
    }

    onOpened: {
        // No search field here — the list is short (typically 1-10 people).
        // Just focus the close button so Escape works immediately.
        closeButton.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.paddingMd
        spacing: Theme.spacingSm

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm

            Text {
                text: root.emoji
                font.pixelSize: Theme.fontSizeXl
                renderType: Text.NativeRendering
            }
            Label {
                text: Tr.tr(Theme.language, "Reactions")
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                color: Theme.windowFg
            }
            Item { Layout.fillWidth: true }
            Label {
                text: root.senders.length
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSm
            }
            ToolButton {
                id: closeButton
                text: "\u2715"  // ✕
                font.pixelSize: Theme.fontSizeMd
                onClicked: root.close()
            }
        }

        // ── Separator ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.border
        }

        // ── Senders list ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: sendersList
                model: root.senders
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                delegate: Item {
                    width: sendersList.width
                    height: 48

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusSm
                        color: mouseArea.containsMouse ? Theme.accent : "transparent"
                        opacity: mouseArea.containsMouse ? 0.12 : 1.0

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.paddingSm
                            anchors.rightMargin: Theme.paddingSm
                            spacing: Theme.spacingSm

                            // Avatar with initials (we don't have avatar URLs
                            // here — they're not part of the reactions JSON
                            // to keep payload small; user_id-based initials
                            // are fine for a popup that's open for seconds).
                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 16
                                color: Theme.accent
                                opacity: 0.3
                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        var dn = modelData.display_name || modelData.user_id
                                        return dn.length > 0 ? dn.charAt(0).toUpperCase() : "?"
                                    }
                                    color: Theme.accentFg
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: true
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.display_name.length > 0
                                          ? modelData.display_name
                                          : Tr.tr(Theme.language, "(no display name)")
                                    color: Theme.windowFg
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: modelData.user_id
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeXs
                                    elide: Text.ElideRight
                                }
                            }

                            // Small emoji echo on the right (so the popup
                            // visually confirms which emoji you're inspecting
                            // even when scrolled).
                            Text {
                                text: root.emoji
                                font.pixelSize: Theme.fontSizeMd
                                renderType: Text.NativeRendering
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }

                        MouseArea {
                            id: mouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // No click action — this popup is informational.
                            // Click anywhere outside the list to close (the
                            // Dialog's modal scrim handles that).
                            onClicked: {}
                        }
                    }
                }
            }
        }

        // ── Footer hint ──
        Label {
            Layout.fillWidth: true
            text: Tr.tr(Theme.language, "Left-click this reaction in the chat to toggle your own.")
            color: Theme.muted
            font.pixelSize: Theme.fontSizeXs
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
