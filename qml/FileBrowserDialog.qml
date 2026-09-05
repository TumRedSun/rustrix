// FileBrowserDialog.qml — custom file picker with multi-select and hidden-file support.
//
// The stock QtQuick.Dialogs FileDialog doesn't expose a "show hidden files"
// toggle, and on most Linux desktops the native dialog hides dotfiles by
// default (Ctrl+H works in some file managers but not all). This custom
// dialog uses MatrixClient.listDirectory() (Rust std::fs::read_dir) so we
// have full control over what's shown.
//
// All visual chrome (backgrounds, buttons, checkboxes) uses explicit
// Theme.* colors so the dialog matches the dark app theme even on systems
// where the default Qt Quick Controls 2 style would otherwise paint a
// white background (which made filenames unreadable).
//
// Features:
//   - Multi-file selection (Discord-style attachment queue)
//   - Toggle to show/hide dotfiles
//   - Breadcrumb-style path navigation
//   - Keyboard: Esc closes, Enter on a file selects it, Backspace goes up
//
// Usage:
//   FileBrowserDialog {
//       id: fileBrowser
//       onFilesSelected: function(paths) { /* paths is a JS array of strings */ }
//   }
//   fileBrowser.open()

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MatrixClient

Dialog {
    id: dialog
    modal: true
    title: Tr.tr(Theme.language, "Choose files to send")
    // Size derives from the client window (grows with Theme.scale above the
    // reference, capped by the overlay size — see EmojiPicker.qml), so the
    // dialog also fits small windows instead of rendering at a fixed
    // 720x480.
    width: Math.min(Math.round(720 * Math.max(1, Theme.scale)), parent.width - Theme.paddingLg * 2)
    height: Math.min(Math.round(480 * Math.max(1, Theme.scale)), parent.height - Theme.paddingLg * 2)
    standardButtons: Dialog.Open | Dialog.Cancel
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // Force a themed background — the default Dialog background on a bare
    // Linux Qt setup is a flat white rectangle, which makes the
    // Theme.windowFg-colored labels (light gray) nearly invisible.
    background: Rectangle {
        color: Theme.windowBg
        border.color: Theme.border
        border.width: 1
        radius: Theme.radiusMd
    }

    // Signal emitted when the user clicks Open with at least one file selected.
    // `paths` is a JS array of absolute filesystem paths.
    signal filesSelected(var paths)

    property string currentPath: MatrixClient.homeDir()
    property bool showHidden: false
    property var selectedPaths: []   // JS array of strings
    property var entries: []         // Parsed JSON from listDirectory

    function open() {
        selectedPaths = []
        loadDir(currentPath)
        visible = true
    }

    function loadDir(path) {
        currentPath = path
        var json = MatrixClient.listDirectory(path, showHidden)
        try {
            entries = JSON.parse(json)
        } catch (e) {
            entries = []
            console.log("FileBrowserDialog: failed to parse JSON: " + e)
        }
        // Don't clear selection — user might want to keep selected files
        // from a previously-browsed directory.
    }

    function toggleSelected(path) {
        var idx = selectedPaths.indexOf(path)
        if (idx >= 0) {
            // Remove
            var copy = selectedPaths.slice()
            copy.splice(idx, 1)
            selectedPaths = copy
        } else {
            // Add
            var copy = selectedPaths.slice()
            copy.push(path)
            selectedPaths = copy
        }
    }

    function isSelected(path) {
        return selectedPaths.indexOf(path) >= 0
    }

    function goUp() {
        var p = currentPath
        if (p === "/" || p === "") return
        var idx = p.lastIndexOf("/")
        if (idx <= 0) {
            currentPath = "/"
            loadDir("/")
        } else {
            var parent = p.substring(0, idx)
            loadDir(parent)
        }
    }

    function pathPartName(p) {
        var idx = p.lastIndexOf("/")
        if (idx < 0) return p
        return p.substring(idx + 1)
    }

    onAccepted: {
        if (selectedPaths.length > 0) {
            filesSelected(selectedPaths)
        }
    }

    onOpened: loadDir(currentPath)

    // ── Reusable themed button component ──
    // QtQuick.Controls' default Button uses the system palette, which on
    // bare Linux is white-on-grey. We override background + contentItem
    // to use Theme colors so the button matches the dark app theme.
    component ThemedButton: Button {
        id: themedBtn
        background: Rectangle {
            color: themedBtn.down ? Theme.accent
                  : (themedBtn.hovered ? Qt.lighter(Theme.sidebarBg, 1.4)
                                       : Theme.sidebarBg)
            border.color: themedBtn.down ? Theme.accent : Theme.border
            border.width: 1
            radius: Theme.radiusSm
            implicitWidth: 36
            implicitHeight: 32
        }
        contentItem: Label {
            text: themedBtn.text
            color: themedBtn.down ? Theme.accentFg : Theme.sidebarFg
            font.pixelSize: Theme.fontSizeMd
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // ── Reusable themed checkbox ──
    // Default CheckBox has a white indicator that's invisible on the dark
    // background. We replace the indicator with a Theme-colored rectangle.
    component ThemedCheckBox: CheckBox {
        id: themedCb
        indicator: Rectangle {
            implicitWidth: 18
            implicitHeight: 18
            x: themedCb.leftPadding
            y: parent.height / 2 - height / 2
            radius: 3
            color: themedCb.checked ? Theme.accent : Theme.sidebarBg
            border.color: themedCb.checked ? Theme.accent : Theme.border
            border.width: 1
            Label {
                anchors.centerIn: parent
                text: themedCb.checked ? "\u2713" : ""  // ✓
                color: Theme.accentFg
                font.pixelSize: 14
                font.bold: true
            }
        }
        contentItem: Label {
            text: themedCb.text
            color: Theme.sidebarFg
            font.pixelSize: Theme.fontSizeSm
            verticalAlignment: Text.AlignVCenter
            leftPadding: themedCb.indicator.width + themedCb.spacing
        }
    }

    contentItem: ColumnLayout {
        spacing: 8

        // ── Path bar ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            ThemedButton {
                text: Tr.tr(Theme.language, "\u2191")  // ↑
                onClicked: goUp()
                ToolTip.text: Tr.tr(Theme.language, "Go to parent directory")
                ToolTip.visible: hovered
            }
            ThemedButton {
                text: Tr.tr(Theme.language, "/")
                onClicked: loadDir("/")
                ToolTip.text: Tr.tr(Theme.language, "Go to filesystem root")
                ToolTip.visible: hovered
            }
            ThemedButton {
                text: Tr.tr(Theme.language, "\uD83C\uDFE0")  // 🏠
                onClicked: loadDir(MatrixClient.homeDir())
                ToolTip.text: Tr.tr(Theme.language, "Go to home directory")
                ToolTip.visible: hovered
            }

            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 32
                clip: true
                Label {
                    text: dialog.currentPath
                    color: Theme.muted
                    font.pixelSize: Theme.fontSizeSm
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // Show hidden files toggle
            ThemedCheckBox {
                text: Tr.tr(Theme.language, "Hidden")
                checked: dialog.showHidden
                onToggled: {
                    dialog.showHidden = checked
                    loadDir(dialog.currentPath)
                }
                ToolTip.text: Tr.tr(Theme.language, "Show files and directories starting with '.'")
                ToolTip.visible: hovered
            }
        }

        // ── File list ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            ListView {
                id: listView
                model: dialog.entries
                spacing: 1

                delegate: Rectangle {
                    width: listView.width
                    height: 32
                    color: {
                        if (isSelected(fullPath)) return Theme.accent
                        if (mouseArea.containsMouse) return Theme.sidebarBg
                        return "transparent"
                    }

                    property string fullPath: dialog.currentPath + "/" + modelData.name

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Label {
                            text: modelData.is_dir ? "\uD83D\uDCC1" : "\uD83D\uDCC4"  // 📁 / 📄
                            font.pixelSize: Theme.fontSizeMd
                            Layout.preferredWidth: 20
                            color: isSelected(fullPath) ? Theme.accentFg : Theme.sidebarFg
                        }
                        Label {
                            text: modelData.name
                            color: isSelected(fullPath) ? Theme.accentFg
                                  : (modelData.is_dir ? Theme.sidebarFg : Theme.windowFg)
                            font.pixelSize: Theme.fontSizeSm
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                        Label {
                            text: modelData.is_dir ? "" : formatBytes(modelData.size)
                            color: isSelected(fullPath) ? Theme.accentFg : Theme.muted
                            font.pixelSize: Theme.fontSizeXs
                            visible: !modelData.is_dir
                        }
                        // Selection checkbox
                        ThemedCheckBox {
                            checked: isSelected(fullPath)
                            visible: !modelData.is_dir
                            onClicked: toggleSelected(fullPath)
                        }
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onDoubleClicked: {
                            if (modelData.is_dir) {
                                loadDir(fullPath)
                            } else {
                                toggleSelected(fullPath)
                            }
                        }
                        onClicked: {
                            if (modelData.is_dir) {
                                loadDir(fullPath)
                            } else {
                                toggleSelected(fullPath)
                            }
                        }
                    }
                }
            }
        }

        // ── Selection summary ──
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            color: Theme.sidebarBg
            radius: Theme.radiusSm

            Label {
                anchors.centerIn: parent
                text: dialog.selectedPaths.length === 0
                      ? Tr.tr(Theme.language, "No files selected")
                      : Tr.tr(Theme.language, "%n file(s) selected", "", dialog.selectedPaths.length)
                color: Theme.muted
                font.pixelSize: Theme.fontSizeSm
            }
        }
    }

    // Override default button rendering for the standard Open/Cancel buttons
    // (they live in the footer, which Dialog auto-creates from standardButtons).
    // Without this they appear with the system theme (white background).
    footer: DialogButtonBox {
        background: Rectangle {
            color: Theme.sidebarBg
            border.color: Theme.border
            border.width: 1
        }
        standardButtons: dialog.standardButtons

        // Theme each button that DialogButtonBox auto-creates.
        delegate: Button {
            flat: false
            background: Rectangle {
                color: parent.down ? Theme.accent
                      : (parent.hovered ? Qt.lighter(Theme.sidebarBg, 1.4)
                                        : Theme.sidebarBg)
                border.color: parent.down ? Theme.accent : Theme.border
                border.width: 1
                radius: Theme.radiusSm
            }
            contentItem: Label {
                text: parent.text
                color: parent.down ? Theme.accentFg : Theme.sidebarFg
                font.pixelSize: Theme.fontSizeMd
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    function formatBytes(b) {
        if (b < 1024) return b + " B"
        if (b < 1024 * 1024) return (b / 1024).toFixed(1) + " KB"
        if (b < 1024 * 1024 * 1024) return (b / 1024 / 1024).toFixed(1) + " MB"
        return (b / 1024 / 1024 / 1024).toFixed(1) + " GB"
    }
}
