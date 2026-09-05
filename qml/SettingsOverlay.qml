// SettingsOverlay.qml — Combined settings panel (profile, appearance, connection, language, account).
// Used as the content of the modal overlay in main.qml.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import MatrixClient

Item {
    id: settingsRoot
    signal closeSettings()

    // Display-only palettes for the preset cards (mirror of theme.rs
    // presets). Used to render the color dots on each preset card —
    // editing themes still happens exclusively through the Theme
    // singleton, this map is never written anywhere.
    readonly property var presetPalettes: ({
        "Material Dark":    ["#1e1e1e", "#252525", "#7c4dff", "#3a3a3a"],
        "Solarized Dark":   ["#002b36", "#073642", "#268bd2", "#586e75"],
        "Tokyo Night":      ["#1a1b26", "#16161e", "#7aa2f7", "#414868"],
        "Nordic":           ["#2e3440", "#3b4252", "#88c0d0", "#4c566a"],
        "Dracula":          ["#282a36", "#21222c", "#bd93f9", "#6272a4"],
        "Gruvbox":          ["#282828", "#3c3836", "#fabd2f", "#665c54"],
        "Catppuccin Mocha": ["#1e1e2e", "#181825", "#cba6f7", "#585b70"],
        "Sunset":           ["#2d1b2e", "#3d2645", "#ef7b45", "#5a3a5e"],
        "Matrix Green":     ["#0a0e0a", "#0d130d", "#00c853", "#1f4d2a"]
    })

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Left: navigation tabs ──
        // Rounded only on its left edge (top-left + bottom-left) so it
        // follows the outer panel's rounded corners instead of painting
        // over them with a square edge.
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.settingsNavW
            color: Theme.sidebarBg
            radius: Theme.radiusLg

            // Cover the right-side rounded corners so the sidebar meets
            // the content panel with a straight edge.
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.paddingSm
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    Layout.topMargin: Theme.paddingSm
                    Layout.bottomMargin: Theme.paddingMd
                    text: Tr.tr(Theme.language, "Settings")
                    color: Theme.sidebarFg
                    font.pixelSize: Theme.fontSizeXl
                    font.bold: true
                    elide: Text.ElideRight
                }

                // Tab buttons
                component TabButton: AbstractButton {
                    id: tabBtn
                    property bool isActive: false
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.tabBtnH
                    hoverEnabled: true
                    background: Rectangle {
                        radius: Theme.radiusSm
                        color: tabBtn.isActive ? Theme.accent : (tabBtn.hovered ? Qt.lighter(Theme.sidebarBg, 1.15) : "transparent")
                        opacity: tabBtn.isActive ? 0.2 : 1.0
                    }
                    contentItem: Label {
                        text: tabBtn.text
                        color: tabBtn.isActive ? Theme.accentFg : Theme.sidebarFg
                        font.pixelSize: Theme.fontSizeMd
                        font.bold: tabBtn.isActive
                        leftPadding: Theme.paddingSm
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                TabButton {
                    text: Tr.tr(Theme.language, "My Profile")
                    isActive: settingsStack.currentIndex === 0
                    onClicked: settingsStack.currentIndex = 0
                }
                TabButton {
                    text: Tr.tr(Theme.language, "Appearance")
                    isActive: settingsStack.currentIndex === 1
                    onClicked: settingsStack.currentIndex = 1
                }
                TabButton {
                    text: Tr.tr(Theme.language, "Connection")
                    isActive: settingsStack.currentIndex === 2
                    onClicked: settingsStack.currentIndex = 2
                }
                TabButton {
                    text: Tr.tr(Theme.language, "Language")
                    isActive: settingsStack.currentIndex === 3
                    onClicked: settingsStack.currentIndex = 3
                }

                Item { Layout.fillHeight: true }

                // Close button
                TabButton {
                    text: Tr.tr(Theme.language, "Close")
                    isActive: false
                    onClicked: settingsRoot.closeSettings()
                }
            }
        }

        // ── Right: settings content ──
        // Rounded only on its right edge (top-right + bottom-right) so it
        // follows the outer panel's rounded corners instead of painting
        // over them with a square edge.
        Rectangle {
            Layout.fillHeight: true
            Layout.fillWidth: true
            color: Theme.windowBg
            radius: Theme.radiusLg

            // Cover the left-side rounded corners so the content meets
            // the sidebar with a straight edge.
            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.radius
                color: parent.color
            }

            StackLayout {
                id: settingsStack
                anchors.fill: parent
                currentIndex: 0

                // ── Page 0: My Profile ──
                ScrollView {
                    id: profileScroll
                    clip: true
                    ColumnLayout {
                        // Bind to the ScrollView width, NOT parent.width —
                        // the content item's width follows the column's own
                        // implicit width, which used to squeeze the whole
                        // page into a ~350px column with overlapping rows.
                        width: profileScroll.availableWidth - Theme.paddingLg * 2
                        x: Theme.paddingLg
                        spacing: Theme.spacingMd

                        Label {
                            Layout.topMargin: Theme.paddingMd
                            text: Tr.tr(Theme.language, "Your Profile")
                            color: Theme.windowFg
                            font.pixelSize: Theme.fontSizeXl
                            font.bold: true
                        }

                        // Banner with upload
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.bannerH
                            radius: Theme.radiusMd
                            color: Theme.accent
                            opacity: ProfileManager.bannerUrl.length > 0 ? 1.0 : 0.15
                            clip: true

                            // Banner image (only shown when a banner has been set).
                            // fillMode=PreserveAspectCrop gives a Discord-style cover.
                            Image {
                                anchors.fill: parent
                                source: ProfileManager.bannerUrl
                                fillMode: Image.PreserveAspectCrop
                                horizontalAlignment: Qt.AlignHCenter
                                verticalAlignment: Qt.AlignVCenter
                                visible: ProfileManager.bannerUrl.length > 0
                                asynchronous: true
                                cache: false  // always re-read the cached file
                            }

                            // Hint label only when there's no banner yet.
                            Label {
                                anchors.centerIn: parent
                                text: Tr.tr(Theme.language, "Click to set profile banner")
                                color: Theme.sidebarFg
                                font.pixelSize: Theme.fontSizeSm
                                visible: ProfileManager.bannerUrl.length === 0
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: bannerDialog.open()
                            }
                        }

                        FileDialog {
                            id: bannerDialog
                            title: Tr.tr(Theme.language, "Choose a banner image")
                            nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.svg *.bmp *.gif)"]
                            onAccepted: {
                                var p = bannerDialog.currentFile.toString()
                                if (p.startsWith("file://")) p = p.substring(7)
                                MatrixClient.setBanner(p)
                            }
                        }

                        // Avatar with upload button
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Theme.spacingMd

                            Rectangle {
                                Layout.preferredWidth: Theme.avatarProfile
                                Layout.preferredHeight: Theme.avatarProfile
                                radius: Theme.avatarProfile / 2
                                color: Theme.accent
                                opacity: 0.3

                                Label {
                                    anchors.centerIn: parent
                                    text: MatrixClient.userId.length > 0 ? MatrixClient.userId.charAt(1).toUpperCase() : "?"
                                    color: Theme.accentFg
                                    font.pixelSize: Theme.fontSizeXl * 2
                                    font.bold: true
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: avatarDialog.open()
                                }
                            }
                        }

                        FileDialog {
                            id: avatarDialog
                            title: Tr.tr(Theme.language, "Choose a new avatar")
                            nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.svg)"]
                            onAccepted: {
                                var p = avatarDialog.currentFile.toString()
                                if (p.startsWith("file://")) p = p.substring(7)
                                MatrixClient.setAvatar(p)
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: ProfileManager.userId
                            color: Theme.muted
                            font.pixelSize: Theme.fontSizeSm
                        }

                        // Display name editor
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            Label { text: Tr.tr(Theme.language, "Name"); color: Theme.windowFg }
                            TextField {
                                id: dnField
                                Layout.fillWidth: true
                                Layout.minimumWidth: Math.round(120 * Math.max(1, Theme.scale))
                                text: ProfileManager.displayName
                                color: Theme.windowFg
                                selectByMouse: true
                                background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm; border.color: dnField.activeFocus ? Theme.accent : Theme.border; border.width: 1 }
                            }
                            ThemeButton {
                                kind: "accent"
                                text: Tr.tr(Theme.language, "Save")
                                onClicked: MatrixClient.setDisplayName(dnField.text)
                            }
                        }

                        // Presence
                        Label { text: Tr.tr(Theme.language, "Presence"); color: Theme.windowFg; font.bold: true }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingSm
                            ThemeCombo {
                                id: presenceBox
                                model: ["online", "unavailable", "offline"]
                                Layout.preferredWidth: Theme.comboBoxSmW
                            }
                            TextField {
                                id: statusField
                                Layout.fillWidth: true
                                Layout.minimumWidth: Math.round(140 * Math.max(1, Theme.scale))
                                placeholderText: Tr.tr(Theme.language, "Status (optional)")
                                color: Theme.windowFg
                                selectByMouse: true
                                background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm; border.color: statusField.activeFocus ? Theme.accent : Theme.border; border.width: 1 }
                            }
                            ThemeButton {
                                kind: "accent"
                                text: Tr.tr(Theme.language, "Set")
                                onClicked: ProfileManager.setPresence(presenceBox.currentText, statusField.text)
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: 32 }
                    }
                }

                // ── Page 1: Appearance ──
                // Redesigned: preset cards + live preview + per-topic cards
                // with sliders. Every size still comes from the client
                // window (Theme.scale) and every label from Tr, so the page
                // behaves like the rest of the app. The low-level knobs
                // (radius/padding/spacing grids, scrollbars) moved into the
                // collapsed "Advanced" card — still all there, just out of
                // the way.
                ScrollView {
                    id: appearanceScroll
                    clip: true

                    ColumnLayout {
                        // Bind to the ScrollView width, NOT parent.width —
                        // the content item's width follows the column's own
                        // implicit width, which used to squeeze the whole
                        // page into a narrow column with overlapping rows.
                        width: appearanceScroll.availableWidth - Theme.paddingLg * 2
                        x: Theme.paddingLg
                        spacing: Theme.spacingMd

                        Label {
                            Layout.topMargin: Theme.paddingMd
                            text: Tr.tr(Theme.language, "Appearance")
                            color: Theme.windowFg
                            font.pixelSize: Theme.fontSizeXl
                            font.bold: true
                        }

                        // ── Presets ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Theme presets")
                            Layout.fillWidth: true

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(190 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingSm
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                PresetCard { presetName: "Material Dark" }
                                PresetCard { presetName: "Solarized Dark" }
                                PresetCard { presetName: "Tokyo Night" }
                                PresetCard { presetName: "Nordic" }
                                PresetCard { presetName: "Dracula" }
                                PresetCard { presetName: "Gruvbox" }
                                PresetCard { presetName: "Catppuccin Mocha" }
                                PresetCard { presetName: "Sunset" }
                                PresetCard { presetName: "Matrix Green" }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Theme.spacingSm
                                spacing: Theme.spacingSm

                                ThemeButton {
                                    text: Tr.tr(Theme.language, "Export")
                                    onClicked: {
                                        exportDialog.text = Theme.exportJson()
                                        exportDialog.open()
                                    }
                                }
                                ThemeButton {
                                    text: Tr.tr(Theme.language, "Import")
                                    onClicked: importDialog.open()
                                }
                                ThemeButton {
                                    text: Tr.tr(Theme.language, "Reset")
                                    onClicked: Theme.reset()
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: Tr.tr(Theme.language, "Pick a ready-made theme, then fine-tune anything below.")
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.maximumWidth: Math.round(420 * Math.max(1, Theme.scale))
                                }
                            }
                        }

                        // ── Live preview ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Preview")
                            Layout.fillWidth: true

                            // A miniature chat mock. Every element is bound to
                            // the live Theme properties, so tweaking anything
                            // below updates it instantly — no need to imagine
                            // what "radius LG" does.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(230 * Math.max(1, Theme.scale))
                                color: Theme.windowBg
                                radius: Theme.radiusLg
                                border.color: Theme.border
                                border.width: 1
                                clip: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.paddingMd
                                    spacing: Theme.spacingMd

                                    // Mini sidebar (shows sidebarBg).
                                    Rectangle {
                                        Layout.preferredWidth: Math.round(64 * Math.max(1, Theme.scale))
                                        Layout.fillHeight: true
                                        radius: Theme.radiusSm
                                        color: Theme.sidebarBg

                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.top: parent.top
                                            anchors.topMargin: Theme.paddingSm
                                            width: parent.width / 2
                                            height: width
                                            radius: Theme.avatarShape === "square" ? Theme.radiusSm
                                                  : Theme.avatarShape === "rounded" ? Theme.radiusMd
                                                  : width / 2
                                            color: Theme.accent
                                            opacity: 0.7
                                        }
                                    }

                                    // Messages column.
                                    ColumnLayout {
                                        id: msgCol
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        spacing: Theme.spacingMd

                                        // Incoming message.
                                        RowLayout {
                                            id: inMsgRow
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: Theme.spacingSm

                                            Rectangle {
                                                visible: Theme.showAvatars
                                                Layout.preferredWidth: Theme.avatarSizeSm
                                                Layout.preferredHeight: Theme.avatarSizeSm
                                                radius: Theme.avatarShape === "square" ? Theme.radiusSm : width / 2
                                                color: Theme.accent
                                                opacity: 0.35
                                                Label {
                                                    anchors.centerIn: parent
                                                    text: "A"
                                                    color: Theme.accentFg
                                                    font.pixelSize: Theme.fontSizeSm
                                                    font.bold: true
                                                }
                                            }

                                            // Bubble width derives from the text's
                                            // own implicit width (single source of
                                            // truth — deriving the width from the
                                            // inner column's implicit width made
                                            // the layouts rearrange recursively).
                                            Rectangle {
                                                id: inBubble
                                                readonly property real maxW: (msgCol.width
                                                    - (Theme.showAvatars ? Theme.avatarSizeSm + Theme.spacingSm : 0)) * Theme.bubbleMaxWidthPct / 100
                                                Layout.alignment: Qt.AlignTop
                                                Layout.maximumWidth: maxW
                                                Layout.preferredWidth: Math.min(inText.implicitWidth + Theme.bubblePaddingH * 2, maxW)
                                                Layout.preferredHeight: Theme.bubblePaddingV * 2
                                                                       + inText.implicitHeight
                                                                       + (Theme.showTimestamps ? tsIn.implicitHeight + Theme.spacingXs : 0)
                                                color: Theme.bubbleBgThem
                                                radius: Theme.bubbleRadius

                                                Text {
                                                    id: inText
                                                    x: Theme.bubblePaddingH
                                                    y: Theme.bubblePaddingV
                                                    width: parent.width - Theme.bubblePaddingH * 2
                                                    text: Tr.tr(Theme.language, "Hello! This is how your theme looks.")
                                                    color: Theme.bubbleFgThem
                                                    font.pixelSize: Theme.fontSizeSm
                                                    wrapMode: Text.Wrap
                                                }
                                                Text {
                                                    id: tsIn
                                                    visible: Theme.showTimestamps
                                                    text: "14:02"
                                                    color: Theme.muted
                                                    font.pixelSize: Theme.fontSizeXs
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Theme.bubblePaddingH
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: Theme.bubblePaddingV
                                                }
                                            }
                                        }

                                        // Own message (right-aligned).
                                        RowLayout {
                                            id: outMsgRow
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignTop
                                            spacing: Theme.spacingSm

                                            Item { Layout.fillWidth: true }

                                            Rectangle {
                                                id: outBubble
                                                readonly property real maxW: msgCol.width * Theme.bubbleMaxWidthPct / 100
                                                Layout.alignment: Qt.AlignTop
                                                Layout.maximumWidth: maxW
                                                Layout.preferredWidth: Math.min(outText.implicitWidth + Theme.bubblePaddingH * 2, maxW)
                                                Layout.preferredHeight: Theme.bubblePaddingV * 2
                                                                       + outText.implicitHeight
                                                                       + (Theme.showTimestamps ? tsOut.implicitHeight + Theme.spacingXs : 0)
                                                color: Theme.bubbleBgMe
                                                radius: Theme.bubbleRadius

                                                Text {
                                                    id: outText
                                                    x: Theme.bubblePaddingH
                                                    y: Theme.bubblePaddingV
                                                    width: parent.width - Theme.bubblePaddingH * 2
                                                    text: Tr.tr(Theme.language, "Looks good! Keep tweaking.")
                                                    color: Theme.bubbleFgMe
                                                    font.pixelSize: Theme.fontSizeSm
                                                    wrapMode: Text.Wrap
                                                }
                                                Text {
                                                    id: tsOut
                                                    visible: Theme.showTimestamps
                                                    text: "14:03"
                                                    color: Theme.bubbleFgMe
                                                    opacity: 0.6
                                                    font.pixelSize: Theme.fontSizeXs
                                                    anchors.right: parent.right
                                                    anchors.rightMargin: Theme.bubblePaddingH
                                                    anchors.bottom: parent.bottom
                                                    anchors.bottomMargin: Theme.bubblePaddingV
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        // Composer mock.
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Math.max(Theme.iconBtnSize, composerRow.implicitHeight + Theme.paddingSm * 2)
                                            radius: Theme.radiusSm
                                            color: Theme.sidebarBg
                                            border.color: Theme.border
                                            border.width: 1

                                            RowLayout {
                                                id: composerRow
                                                anchors.fill: parent
                                                anchors.margins: Theme.paddingSm
                                                spacing: Theme.spacingSm

                                                Label {
                                                    Layout.fillWidth: true
                                                    text: Tr.tr(Theme.language, "Message…")
                                                    color: Theme.muted
                                                    font.pixelSize: Theme.fontSizeSm
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    Layout.preferredWidth: Theme.iconBtnSize * 0.6
                                                    Layout.preferredHeight: Theme.iconBtnSize * 0.6
                                                    Layout.alignment: Qt.AlignVCenter
                                                    radius: width / 2
                                                    color: Theme.accent
                                                    Label {
                                                        anchors.centerIn: parent
                                                        text: "→"
                                                        color: Theme.accentFg
                                                        font.pixelSize: Theme.fontSizeSm
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // ── Interface colors ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Interface colors")
                            Layout.fillWidth: true

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(350 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingMd
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                ColorRow { label: Tr.tr(Theme.language, "Window bg");   bind: "windowBg" }
                                ColorRow { label: Tr.tr(Theme.language, "Window fg");   bind: "windowFg" }
                                ColorRow { label: Tr.tr(Theme.language, "Sidebar bg");  bind: "sidebarBg" }
                                ColorRow { label: Tr.tr(Theme.language, "Sidebar fg");  bind: "sidebarFg" }
                                ColorRow { label: Tr.tr(Theme.language, "Accent");      bind: "accent" }
                                ColorRow { label: Tr.tr(Theme.language, "Accent fg");   bind: "accentFg" }
                                ColorRow { label: Tr.tr(Theme.language, "Border");      bind: "border" }
                                ColorRow { label: Tr.tr(Theme.language, "Muted");       bind: "muted" }
                                ColorRow { label: Tr.tr(Theme.language, "Danger");      bind: "danger" }
                                ColorRow { label: Tr.tr(Theme.language, "Success");     bind: "success" }
                                ColorRow { label: Tr.tr(Theme.language, "Warning");     bind: "warning" }
                            }
                        }

                        // ── Messages ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Messages")
                            Layout.fillWidth: true

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(350 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingMd
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                ColorRow { label: Tr.tr(Theme.language, "Bubble own bg");    bind: "bubbleBgMe" }
                                ColorRow { label: Tr.tr(Theme.language, "Bubble own fg");    bind: "bubbleFgMe" }
                                ColorRow { label: Tr.tr(Theme.language, "Bubble other bg");  bind: "bubbleBgThem" }
                                ColorRow { label: Tr.tr(Theme.language, "Bubble other fg");  bind: "bubbleFgThem" }

                                SliderRow { label: Tr.tr(Theme.language, "Bubble corner radius"); bind: "bubbleRadius";   fromVal: 0; toVal: 32 }
                                SliderRow { label: Tr.tr(Theme.language, "Padding horizontal");   bind: "bubblePaddingH"; fromVal: 0; toVal: 32 }
                                SliderRow { label: Tr.tr(Theme.language, "Padding vertical");     bind: "bubblePaddingV"; fromVal: 0; toVal: 24 }
                                SliderRow { label: Tr.tr(Theme.language, "Max width");            bind: "bubbleMaxWidthPct"; fromVal: 30; toVal: 100; suffix: "%" }
                            }

                            ThemeSwitch {
                                text: Tr.tr(Theme.language, "Bubble tail")
                                checked: Theme.bubbleTail
                                onToggled: Theme.bubbleTail = checked
                            }
                        }

                        // ── Text ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Text")
                            Layout.fillWidth: true

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(350 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingMd
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                StringRow { label: Tr.tr(Theme.language, "Font family"); bind: "fontFamily" }
                                StringRow { label: Tr.tr(Theme.language, "Monospace font"); bind: "fontFamilyMono" }

                                SliderRow {
                                    label: Tr.tr(Theme.language, "Small text (timestamps, statuses)")
                                    bind: "fontSizeXs"; fromVal: 6; toVal: 32; demoText: "Aa"
                                }
                                SliderRow {
                                    label: Tr.tr(Theme.language, "Body text")
                                    bind: "fontSizeSm"; fromVal: 6; toVal: 32; demoText: "Aa"
                                }
                                SliderRow {
                                    label: Tr.tr(Theme.language, "Controls (buttons, fields)")
                                    bind: "fontSizeMd"; fromVal: 6; toVal: 32; demoText: "Aa"
                                }
                                SliderRow {
                                    label: Tr.tr(Theme.language, "Headings")
                                    bind: "fontSizeLg"; fromVal: 6; toVal: 40; demoText: "Aa"
                                }
                                SliderRow {
                                    label: Tr.tr(Theme.language, "Large headings")
                                    bind: "fontSizeXl"; fromVal: 6; toVal: 64; demoText: "Aa"
                                }
                            }
                        }

                        // ── Avatars ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Avatars")
                            Layout.fillWidth: true

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(350 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingMd
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                SliderRow { label: Tr.tr(Theme.language, "Small size");  bind: "avatarSizeSm"; fromVal: 16; toVal: 96; suffix: " px" }
                                SliderRow { label: Tr.tr(Theme.language, "Medium size"); bind: "avatarSizeMd"; fromVal: 16; toVal: 128; suffix: " px" }
                                SliderRow { label: Tr.tr(Theme.language, "Large size");  bind: "avatarSizeLg"; fromVal: 16; toVal: 256; suffix: " px" }
                                SliderRow { label: Tr.tr(Theme.language, "Avatar corner radius"); bind: "avatarRadius"; fromVal: 0; toVal: 128 }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm
                                    Label {
                                        text: Tr.tr(Theme.language, "Shape")
                                        color: Theme.windowFg
                                        font.pixelSize: Theme.fontSizeSm
                                    }
                                    ThemeCombo {
                                        model: ["circle", "rounded", "square"]
                                        currentIndex: model.indexOf(Theme.avatarShape)
                                        onActivated: Theme.avatarShape = currentText
                                    }
                                    Item { Layout.fillWidth: true }
                                }
                            }
                        }

                        // ── Interface (behavior) ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Interface")
                            Layout.fillWidth: true

                            ThemeSwitch {
                                text: Tr.tr(Theme.language, "Compact mode")
                                checked: Theme.compactMode
                                onToggled: Theme.compactMode = checked
                            }
                            ThemeSwitch {
                                text: Tr.tr(Theme.language, "Show timestamps")
                                checked: Theme.showTimestamps
                                onToggled: Theme.showTimestamps = checked
                            }
                            ThemeSwitch {
                                text: Tr.tr(Theme.language, "Show avatars")
                                checked: Theme.showAvatars
                                onToggled: Theme.showAvatars = checked
                            }
                            ThemeSwitch {
                                text: Tr.tr(Theme.language, "Animate bubbles")
                                checked: Theme.animateBubbles
                                onToggled: Theme.animateBubbles = checked
                            }
                            SliderRow {
                                label: Tr.tr(Theme.language, "Animation duration")
                                bind: "animationDurationMs"; fromVal: 0; toVal: 500; suffix: " ms"
                            }
                        }

                        // ── Advanced (collapsed) ──
                        SectionCard {
                            title: Tr.tr(Theme.language, "Advanced")
                            collapsible: true
                            expanded: false
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: Tr.tr(Theme.language, "Fine-grained geometry knobs. Most people never need these — radius, padding and spacing below affect every corner of the app.")
                                color: Theme.muted
                                font.pixelSize: Theme.fontSizeXs
                                wrapMode: Text.Wrap
                            }

                            GridLayout {
                                columns: Math.max(1, Math.floor(width / Math.max(1, Math.round(350 * Math.max(1, Theme.scale)))))
                                columnSpacing: Theme.spacingMd
                                rowSpacing: Theme.spacingSm
                                Layout.fillWidth: true

                                IntRow { label: Tr.tr(Theme.language, "Corner radius · small");  bind: "radiusSm"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Corner radius · cards");  bind: "radiusMd"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Corner radius · panels"); bind: "radiusLg"; minValue: 0; maxValue: 64 }

                                IntRow { label: Tr.tr(Theme.language, "Inner padding · XS"); bind: "paddingXs"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Inner padding · SM"); bind: "paddingSm"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Inner padding · MD"); bind: "paddingMd"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Inner padding · LG"); bind: "paddingLg"; minValue: 0; maxValue: 64 }

                                IntRow { label: Tr.tr(Theme.language, "Gaps · XS"); bind: "spacingXs"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Gaps · SM"); bind: "spacingSm"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Gaps · MD"); bind: "spacingMd"; minValue: 0; maxValue: 64 }
                                IntRow { label: Tr.tr(Theme.language, "Gaps · LG"); bind: "spacingLg"; minValue: 0; maxValue: 64 }

                                IntRow { label: Tr.tr(Theme.language, "Scrollbar width");  bind: "scrollbarSize";   minValue: 2; maxValue: 32 }
                                IntRow { label: Tr.tr(Theme.language, "Scrollbar radius"); bind: "scrollbarRadius"; minValue: 0; maxValue: 16 }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: 32 }
                    }
                }

                // ── Page 2: Connection ──
                ScrollView {
                    id: connectionScroll
                    clip: true
                    ColumnLayout {
                        width: connectionScroll.availableWidth - Theme.paddingLg * 2
                        x: Theme.paddingLg
                        spacing: Theme.spacingMd

                        Label {
                            Layout.topMargin: Theme.paddingMd
                            text: Tr.tr(Theme.language, "Connection & Behavior")
                            color: Theme.windowFg
                            font.pixelSize: Theme.fontSizeXl
                            font.bold: true
                        }

                        // Account info
                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: accountCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: accountCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: 4

                                Label { text: Tr.tr(Theme.language, "Account"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }
                                Label { text: Tr.tr(Theme.language, "User ID: %1").arg(MatrixClient.userId); color: Theme.windowFg }
                                Label { text: Tr.tr(Theme.language, "Status: %1").arg(MatrixClient.ready ? Tr.tr(Theme.language, "Ready") : Tr.tr(Theme.language, "Not connected")); color: Theme.windowFg }
                            }
                        }

                        // Network
                        // IPv6-only toggle removed: the client now uses
                        // the default resolver which tries both A and AAAA
                        // records (happy-eyeballs). Homeservers can be
                        // specified by domain, IPv4, or [IPv6] in the
                        // login form.
                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: netCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: netCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: Theme.spacingSm

                                Label { text: Tr.tr(Theme.language, "Network"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }
                                Label {
                                    text: Tr.tr(Theme.language, "Homeserver accepts domain, IPv4, or [IPv6] (port optional). Both A and AAAA records are tried.")
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeXs
                                    Layout.fillWidth: true
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        // Diagnostics
                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: diagCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: diagCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: Theme.spacingSm

                                Label { text: Tr.tr(Theme.language, "Diagnostics"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }

                                Label {
                                    text: Tr.tr(Theme.language, "Last error: %1").arg(MatrixClient.lastError.length === 0 ? "\u2014" : MatrixClient.lastError)
                                    color: MatrixClient.lastError.length === 0 ? Theme.windowFg : Theme.danger
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }

                                Button {
                                    text: Tr.tr(Theme.language, "Refresh rooms & spaces")
                                    onClicked: MatrixClient.refreshRooms()
                                    background: Rectangle { color: parent.hovered ? Qt.lighter(Theme.sidebarBg, 1.3) : Theme.sidebarBg; radius: Theme.radiusSm; border.color: Theme.border; border.width: 1 }
                                    contentItem: Label { text: parent.text; color: Theme.windowFg; font.pixelSize: Theme.fontSizeSm; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                    leftPadding: Theme.paddingSm; rightPadding: Theme.paddingSm
                                    topPadding: Theme.paddingXs; bottomPadding: Theme.paddingXs
                                }
                            }
                        }

                        // ── Account actions ──
                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: actionCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: actionCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: Theme.spacingSm

                                Label { text: Tr.tr(Theme.language, "Account Actions"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    ThemeButton {
                                        kind: "warning"
                                        text: Tr.tr(Theme.language, "Logout")
                                        onClicked: {
                                            MatrixClient.logout()
                                            settingsRoot.closeSettings()
                                        }
                                    }

                                    ThemeButton {
                                        kind: "danger"
                                        text: Tr.tr(Theme.language, "Delete Account")
                                        onClicked: deleteConfirm.open()
                                    }
                                }

                                Label {
                                    text: Tr.tr(Theme.language, "Warning: Deleting your account is irreversible. All data will be permanently removed from the server.")
                                    color: Theme.danger
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                    visible: false
                                }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: 64 }
                    }
                }

                // ── Page 3: Language ──
                ScrollView {
                    id: languageScroll
                    clip: true
                    ColumnLayout {
                        width: languageScroll.availableWidth - Theme.paddingLg * 2
                        x: Theme.paddingLg
                        spacing: Theme.spacingMd

                        Label {
                            Layout.topMargin: Theme.paddingMd
                            text: Tr.tr(Theme.language, "Language")
                            color: Theme.windowFg
                            font.pixelSize: Theme.fontSizeXl
                            font.bold: true
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: langCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: langCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: Theme.spacingSm

                                Label { text: Tr.tr(Theme.language, "Interface Language"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.spacingSm

                                    Label {
                                        text: Tr.tr(Theme.language, "Language")
                                        color: Theme.windowFg
                                    }

                                    ThemeCombo {
                                        id: langCombo
                                        model: JSON.parse(Theme.availableLanguages())
                                        currentIndex: {
                                            var langs = JSON.parse(Theme.availableLanguages())
                                            var idx = langs.indexOf(Theme.language)
                                            return idx >= 0 ? idx : 0
                                        }
                                        onActivated: Theme.language = currentText
                                    }
                                }

                                Label {
                                    text: Tr.tr(Theme.language, "Language changes apply immediately — no restart needed.")
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeXs
                                    wrapMode: Text.Wrap
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // Language map (display names)
                        Rectangle {
                            Layout.fillWidth: true
                            color: Theme.sidebarBg
                            radius: Theme.radiusMd
                            Layout.preferredHeight: mapCol.implicitHeight + Theme.paddingMd * 2

                            ColumnLayout {
                                id: mapCol
                                anchors.fill: parent
                                anchors.margins: Theme.paddingMd
                                spacing: 4

                                Label { text: Tr.tr(Theme.language, "Available Languages"); color: Theme.accent; font.pixelSize: Theme.fontSizeMd; font.bold: true }

                                GridLayout {
                                    columns: 3
                                    rowSpacing: 4
                                    columnSpacing: Theme.spacingSm
                                    Layout.fillWidth: true

                                    component LangLabel: Label {
                                        property string code
                                        text: {
                                            switch(code) {
                                                case "en": return "English"
                                                case "ru": return "\u0420\u0443\u0441\u0441\u043A\u0438\u0439"
                                                case "de": return "Deutsch"
                                                case "fr": return "Fran\u00E7ais"
                                                case "es": return "Espa\u00F1ol"
                                                case "pt": return "Portugu\u00EAs"
                                                case "ja": return "\u65E5\u672C\u8A9E"
                                                case "zh": return "\u4E2D\u6587"
                                                case "ko": return "\uD55C\uAD6D\uC5B4"
                                                case "it": return "Italiano"
                                                case "pl": return "Polski"
                                                case "uk": return "\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430"
                                                default: return code
                                            }
                                        }
                                        color: Theme.windowFg
                                        font.pixelSize: Theme.fontSizeSm
                                    }

                                    LangLabel { code: "en" }
                                    LangLabel { code: "ru" }
                                    LangLabel { code: "de" }
                                    LangLabel { code: "fr" }
                                    LangLabel { code: "es" }
                                    LangLabel { code: "pt" }
                                    LangLabel { code: "ja" }
                                    LangLabel { code: "zh" }
                                    LangLabel { code: "ko" }
                                    LangLabel { code: "it" }
                                    LangLabel { code: "pl" }
                                    LangLabel { code: "uk" }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.preferredHeight: 64 }
                    }
                }
            }
        }
    }

    // ─── Delete account confirmation dialog ───
    Dialog {
        id: deleteConfirm
        title: Tr.tr(Theme.language, "Delete Account")
        modal: true
        anchors.centerIn: parent
        width: Math.min(Theme.dialogMdW + 60, parent.width - Theme.paddingLg * 2)
        standardButtons: Dialog.Yes | Dialog.No
        background: Rectangle {
            color: Theme.windowBg
            radius: Theme.radiusMd
            border.color: Theme.border
            border.width: 1
        }
        contentItem: ColumnLayout {
            spacing: Theme.spacingSm
            Label {
                text: Tr.tr(Theme.language, "Are you sure you want to delete your account? This action is IRREVERSIBLE.")
                color: Theme.danger
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
            Label {
                text: Tr.tr(Theme.language, "All your data will be permanently removed from the server.")
                color: Theme.windowFg
                wrapMode: Text.Wrap
                Layout.fillWidth: true
            }
        }
        onAccepted: {
            MatrixClient.deleteAccount()
            settingsRoot.closeSettings()
        }
    }

    // ─── Inline components (themed base controls + setting rows) ───

    // Themed button — replaces both the unstyled default Button (light
    // gray, jarring on the dark theme) and the ad-hoc `background:
    // Rectangle { color: Theme.accent }` buttons that had no padding and
    // hugged their text.
    component ThemeButton: Button {
        id: themeBtn
        property string kind: "normal"   // normal | accent | danger | warning
        leftPadding: Theme.paddingSm
        rightPadding: Theme.paddingSm
        topPadding: Theme.paddingXs
        bottomPadding: Theme.paddingXs
        background: Rectangle {
            radius: Theme.radiusSm
            border.width: themeBtn.kind === "normal" ? 1 : 0
            border.color: Theme.border
            color: {
                var base
                if (themeBtn.kind === "accent") base = Theme.accent
                else if (themeBtn.kind === "danger") base = Theme.danger
                else if (themeBtn.kind === "warning") base = Theme.warning
                else base = Theme.sidebarBg
                return themeBtn.hovered ? Qt.lighter(base, 1.15) : base
            }
        }
        contentItem: Label {
            text: themeBtn.text
            color: themeBtn.kind === "normal" ? Theme.windowFg : Theme.accentFg
            font.pixelSize: Theme.fontSizeSm
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    // Themed switch — the default Basic-style indicator is white/blue and
    // ignores the theme entirely.
    component ThemeSwitch: Switch {
        id: themeSwitch
        indicator: Rectangle {
            implicitWidth: Math.round(40 * Math.max(1, Theme.scale))
            implicitHeight: Math.round(22 * Math.max(1, Theme.scale))
            radius: height / 2
            color: themeSwitch.checked ? Theme.accent : Theme.sidebarBg
            border.color: themeSwitch.checked ? Theme.accent : Theme.border
            border.width: 1

            Rectangle {
                x: themeSwitch.checked ? parent.width - width - 2 : 2
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 4
                height: parent.height - 4
                radius: width / 2
                color: themeSwitch.checked ? Theme.accentFg : Theme.muted

                Behavior on x { NumberAnimation { duration: Theme.animationDurationMs; easing.type: Easing.OutQuad } }
            }
        }
        contentItem: Label {
            text: themeSwitch.text
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            verticalAlignment: Text.AlignVCenter
            // Offset past the custom indicator — without this the label
            // paints under the switch knob.
            leftPadding: Math.round(40 * Math.max(1, Theme.scale)) + Theme.spacingSm
        }
    }

    // Themed combo box — default Basic style is light-gray on dark theme.
    component ThemeCombo: ComboBox {
        id: themeCombo
        implicitWidth: Math.round(160 * Math.max(1, Theme.scale))
        font.pixelSize: Theme.fontSizeSm
        background: Rectangle {
            color: Theme.sidebarBg
            radius: Theme.radiusSm
            border.color: themeCombo.activeFocus ? Theme.accent : Theme.border
            border.width: 1
        }
        contentItem: Label {
            text: themeCombo.displayText
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            verticalAlignment: Text.AlignVCenter
            leftPadding: Theme.paddingSm
            rightPadding: Theme.iconBtnSize * 0.4
        }
        indicator: Label {
            text: "▾"
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSm
            anchors.right: parent.right
            anchors.rightMargin: Theme.paddingSm
            anchors.verticalCenter: parent.verticalCenter
        }
        // Explicit Component wrapper: some Qt 6.x versions refuse to
        // auto-wrap delegate objects declared inside an inline component.
        delegate: Component {
            ItemDelegate {
                id: comboDelegate
                width: themeCombo.width
                contentItem: Label {
                    text: comboDelegate.text
                    color: comboDelegate.highlighted ? Theme.accentFg : Theme.windowFg
                    font.pixelSize: Theme.fontSizeSm
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.paddingSm
                }
                highlighted: themeCombo.highlightedIndex === index
                background: Rectangle {
                    color: comboDelegate.highlighted ? Theme.accent : "transparent"
                    opacity: comboDelegate.highlighted ? 0.35 : 1.0
                }
            }
        }
        popup: Popup {
            y: themeCombo.height - 1
            width: themeCombo.width
            padding: 1
            background: Rectangle {
                color: Theme.windowBg
                radius: Theme.radiusSm
                border.color: Theme.border
                border.width: 1
            }
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: themeCombo.popup.visible ? themeCombo.delegateModel : null
                currentIndex: themeCombo.highlightedIndex
            }
        }
    }

    // Collapsible settings section card. Content is declared as direct
    // children; they are laid out by an inner ColumnLayout so the card's
    // implicit height always matches its content (the old GroupBox +
    // anchors.fill pattern collapsed and overlapped).
    component SectionCard: Rectangle {
        id: sectionCard
        property string title
        property bool collapsible: false
        property bool expanded: true
        default property alias contentItems: cardContent.data

        Layout.fillWidth: true
        implicitHeight: cardColumn.implicitHeight + Theme.paddingMd * 2
        color: Theme.sidebarBg
        radius: Theme.radiusMd

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.paddingMd
            spacing: Theme.spacingSm

            AbstractButton {
                id: cardHeader
                Layout.fillWidth: true
                hoverEnabled: sectionCard.collapsible
                enabled: sectionCard.collapsible
                onClicked: sectionCard.expanded = !sectionCard.expanded
                implicitHeight: cardTitle.implicitHeight

                contentItem: Item {
                    RowLayout {
                        anchors.fill: parent
                        spacing: Theme.spacingSm

                        Label {
                            id: cardTitle
                            text: sectionCard.title
                            color: Theme.windowFg
                            font.pixelSize: Theme.fontSizeLg
                            font.bold: true
                        }
                        Item { Layout.fillWidth: true }
                        Label {
                            text: sectionCard.expanded ? "▾" : "▸"
                            color: Theme.muted
                            font.pixelSize: Theme.fontSizeLg
                            visible: sectionCard.collapsible
                        }
                    }
                }
            }

            // The card content. ColumnLayout (not anchors!) so the header
            // + content heights drive the card's implicit height.
            ColumnLayout {
                id: cardContent
                visible: sectionCard.expanded
                Layout.fillWidth: true
                spacing: Theme.spacingSm
            }
        }
    }

    // Label + slider + numeric value row. Sliders replace the old SpinBox
    // walls for user-facing settings — dragging gives instant feedback and
    // the effect is visible in the preview card above.
    component SliderRow: RowLayout {
        property string label
        property string bind
        property int fromVal: 0
        property int toVal: 100
        property int step: 1
        property string suffix: ""
        property string demoText: ""

        Layout.fillWidth: true
        spacing: Theme.spacingMd

        Label {
            text: label
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: Math.round(90 * Math.max(1, Theme.scale))
        }

        Slider {
            id: slider
            // Fills the leftover cell width instead of a fixed width — a
            // fixed 230*scale made each row's minimum wider than its grid
            // cell at 3 columns on 1920px screens, so the whole grid
            // overflowed the right edge of the window.
            Layout.fillWidth: true
            Layout.minimumWidth: Math.round(130 * Math.max(1, Theme.scale))
            Layout.maximumWidth: Math.round(460 * Math.max(1, Theme.scale))
            Layout.alignment: Qt.AlignVCenter
            from: fromVal
            to: toVal
            stepSize: step
            value: Theme[bind]
            onMoved: Theme[bind] = value

            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: Theme.border

                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Theme.accent
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + slider.availableHeight / 2 - height / 2
                width: Math.round(16 * Math.max(1, Theme.scale))
                height: width
                radius: width / 2
                color: Theme.accent
                border.color: Theme.accentFg
                border.width: 1
            }
        }

        Label {
            // Optional live "Aa" demo at exactly this font size.
            text: demoText
            visible: demoText.length > 0
            color: Theme.windowFg
            font.pixelSize: Math.min(Theme[bind], 40)
            Layout.preferredWidth: Math.round(34 * Math.max(1, Theme.scale))
            horizontalAlignment: Text.AlignHCenter
        }

        Label {
            text: Math.round(Theme[bind]) + suffix
            color: Theme.muted
            font.pixelSize: Theme.fontSizeSm
            Layout.preferredWidth: Math.round(52 * Math.max(1, Theme.scale))
            horizontalAlignment: Text.AlignRight
        }
    }

    // Preset card: name + color dots. Clicking applies the preset.
    component PresetCard: AbstractButton {
        id: presetCard
        property string presetName
        readonly property bool isActive: Theme.preset === presetName
        readonly property var pal: settingsRoot.presetPalettes[presetName] || []

        Layout.fillWidth: true
        implicitHeight: presetNameLabel.implicitHeight + presetDots.implicitHeight + Theme.paddingSm * 2 + Theme.spacingXs
        hoverEnabled: true

        background: Rectangle {
            radius: Theme.radiusSm
            color: presetCard.isActive ? Theme.accent : (presetCard.hovered ? Qt.lighter(Theme.sidebarBg, 1.25) : Theme.windowBg)
            opacity: presetCard.isActive ? 0.25 : 1.0
            border.color: presetCard.isActive ? Theme.accent : Theme.border
            border.width: presetCard.isActive ? 2 : 1
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingXs

            Label {
                id: presetNameLabel
                text: presetCard.presetName
                color: Theme.windowFg
                font.pixelSize: Theme.fontSizeSm
                font.bold: presetCard.isActive
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.leftMargin: Theme.paddingSm
                Layout.topMargin: Theme.paddingSm
            }

            RowLayout {
                id: presetDots
                Layout.fillWidth: true
                Layout.leftMargin: Theme.paddingSm
                Layout.bottomMargin: Theme.paddingSm
                spacing: Theme.spacingXs

                Repeater {
                    model: presetCard.pal.length
                    Rectangle {
                        Layout.preferredWidth: Math.round(18 * Math.max(1, Theme.scale))
                        Layout.preferredHeight: width
                        radius: width / 2
                        color: presetCard.pal[index]
                        border.color: Theme.border
                        border.width: 1
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        onClicked: Theme.applyPreset(presetName)
    }

    component ColorRow: RowLayout {
        property string label
        property string bind
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: label
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: Math.round(90 * Math.max(1, Theme.scale))
        }

        // Swatch doubles as the picker button — one obvious click target
        // instead of a mystery 🎨 button per row.
        Rectangle {
            Layout.preferredWidth: Theme.colorSwatchSize
            Layout.preferredHeight: Theme.colorSwatchSize
            radius: Theme.radiusSm
            color: Theme[bind]
            border.color: mouse.containsMouse ? Theme.accent : Theme.border
            border.width: 1

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    picker.targetBind = bind
                    picker.selectedColor = Theme[bind]
                    picker.open()
                }
            }
        }

        TextField {
            id: hexField
            Layout.preferredWidth: Math.round(92 * Math.max(1, Theme.scale))
            text: Theme[bind]
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            selectByMouse: true
            onEditingFinished: {
                var v = text.trim()
                if (/^#[0-9a-fA-F]{3,8}$/.test(v)) {
                    Theme[bind] = v
                } else {
                    text = Theme[bind]
                }
            }
            background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm; border.color: hexField.activeFocus ? Theme.accent : Theme.border; border.width: 1 }
        }
    }

    component StringRow: RowLayout {
        property string label
        property string bind
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: label
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            Layout.preferredWidth: Math.round(150 * Math.max(1, Theme.scale))
        }
        TextField {
            id: stringField
            Layout.fillWidth: true
            Layout.minimumWidth: 120
            text: Theme[bind]
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            selectByMouse: true
            onEditingFinished: Theme[bind] = text
            background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm; border.color: stringField.activeFocus ? Theme.accent : Theme.border; border.width: 1 }
        }
    }

    // Integer row: label + themed SpinBox + live preview. Used in the
    // collapsed "Advanced" section for the fine-grained geometry knobs.
    component IntRow: RowLayout {
        property string label
        property string bind
        property int minValue: 0
        property int maxValue: 100
        Layout.fillWidth: true
        spacing: Theme.spacingSm

        Label {
            text: label
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            elide: Text.ElideRight
            Layout.fillWidth: true
            Layout.minimumWidth: Math.round(90 * Math.max(1, Theme.scale))
        }

        SpinBox {
            id: spin
            Layout.preferredWidth: Theme.spinBoxW
            from: minValue
            to: maxValue
            value: Theme[bind]
            onValueModified: Theme[bind] = value
            editable: true
            font.pixelSize: Theme.fontSizeSm

            background: Rectangle {
                color: Theme.sidebarBg
                radius: Theme.radiusSm
                border.color: spin.activeFocus ? Theme.accent : Theme.border
                border.width: 1
            }
            contentItem: TextInput {
                text: spin.textFromValue(spin.value, spin.locale)
                font.pixelSize: Theme.fontSizeSm
                color: Theme.windowFg
                selectionColor: Theme.accent
                selectedTextColor: Theme.accentFg
                horizontalAlignment: Qt.AlignHCenter
                verticalAlignment: Qt.AlignVCenter
                readOnly: !spin.editable
                validator: spin.validator
                inputMethodHints: Qt.ImhFormattedNumbersOnly
                onEditingFinished: {
                    var v = parseInt(text)
                    if (!isNaN(v)) { if (v < spin.from) v = spin.from; if (v > spin.to) v = spin.to; spin.value = v }
                }
            }
            up.indicator: Rectangle {
                x: parent.mirrored ? 0 : parent.width - width
                height: parent.height / 2
                width: Math.round(18 * Math.max(1, Theme.scale))
                color: spin.up.pressed ? Theme.accent : "transparent"
                Label { anchors.centerIn: parent; text: "▲"; color: Theme.muted; font.pixelSize: Theme.fontSizeXs }
            }
            down.indicator: Rectangle {
                x: parent.mirrored ? 0 : parent.width - width
                y: parent.height / 2
                height: parent.height / 2
                width: Math.round(18 * Math.max(1, Theme.scale))
                color: spin.down.pressed ? Theme.accent : "transparent"
                Label { anchors.centerIn: parent; text: "▼"; color: Theme.muted; font.pixelSize: Theme.fontSizeXs }
            }
        }

        // Live preview — adapts to the property being edited.
        Rectangle {
            id: previewBox
            Layout.fillWidth: true
            Layout.minimumWidth: Math.round(44 * Math.max(1, Theme.scale))
            Layout.maximumWidth: Math.round(110 * Math.max(1, Theme.scale))
            Layout.preferredHeight: Theme.previewBoxH
            color: Theme.sidebarBg
            radius: Theme.radiusSm
            border.color: Theme.border
            border.width: 1
            opacity: 0.75

            // The actual preview element — chosen based on the bind name.
            // We use simple substring matching on the bind name to pick
            // the right visualization. This keeps the component generic
            // instead of needing a separate row type for each property.
            Item {
                anchors.fill: parent
                anchors.margins: 4

                // Radius preview: a rectangle with that corner radius,
                // sized to fit the preview box (a fixed 24px square used to
                // overflow the box when the row was tight and paint over
                // the SpinBox arrows).
                Rectangle {
                    visible: bind.indexOf("adius") >= 0 || bind === "avatarRadius" || bind === "scrollbarRadius"
                    anchors.centerIn: parent
                    width: Math.min(24, parent.width, parent.height)
                    height: width
                    radius: Math.min(Theme[bind], width / 2)
                    color: Theme.accent
                }

                // Padding preview: inner box inset by half the padding value.
                Rectangle {
                    visible: bind.indexOf("adding") >= 0
                    anchors.fill: parent
                    color: "transparent"
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width - Math.min(Theme[bind], parent.width / 2)
                        height: parent.height - Math.min(Theme[bind], parent.height / 2)
                        color: Theme.accent
                        opacity: 0.5
                    }
                }

                // Spacing preview: two dots separated by the spacing value.
                Item {
                    visible: bind.indexOf("pacing") >= 0
                    anchors.fill: parent
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        width: 8; height: 8; radius: 4; color: Theme.accent
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(0, Math.min(8 + Theme[bind], parent.width - 8))
                        width: 8; height: 8; radius: 4; color: Theme.accent
                    }
                }

                // Font size preview: shows "Aa" at that font size.
                Text {
                    visible: bind.indexOf("ontSize") >= 0 || bind.indexOf("imationDuration") >= 0
                    anchors.centerIn: parent
                    text: "Aa"
                    color: Theme.windowFg
                    font.pixelSize: Math.min(Theme[bind], 28)
                }

                // Size preview (avatarSize*): a circle/box of that size
                // (capped to fit the preview box on both axes).
                Rectangle {
                    visible: bind.indexOf("avatarSize") >= 0 || bind.indexOf("crollbarSize") >= 0
                    anchors.centerIn: parent
                    width: Math.min(Theme[bind], parent.width, parent.height)
                    height: Math.min(Theme[bind], parent.width, parent.height)
                    radius: bind === "avatarSizeSm" || bind === "avatarSizeMd" || bind === "avatarSizeLg" ? width / 2 : 2
                    color: Theme.accent
                    opacity: 0.6
                }

                // Bubble max width % preview: a horizontal bar fill.
                Rectangle {
                    visible: bind.indexOf("axWidth") >= 0
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width * Theme[bind] / 100
                    height: 8
                    color: Theme.accent
                    radius: 2
                }

                // Width preview (scrollbarSize): handled above by Size branch.
            }
        }
    }

    ColorDialog {
        id: picker
        property string targetBind: ""
        onAccepted: {
            Theme[targetBind] = picker.selectedColor.toString()
        }
    }

    Dialog {
        id: exportDialog
        title: Tr.tr(Theme.language, "Theme JSON")
        modal: true
        anchors.centerIn: parent
        width: Math.min(Theme.dialogLgW + 60, parent.width - Theme.paddingLg * 2)
        property string text: ""
        background: Rectangle {
            color: Theme.windowBg
            radius: Theme.radiusMd
            border.color: Theme.border
            border.width: 1
        }
        contentItem: ScrollView {
            TextArea {
                text: exportDialog.text
                readOnly: true
                wrapMode: TextArea.Wrap
                color: Theme.windowFg
                background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm }
            }
        }
        standardButtons: Dialog.Close
    }

    Dialog {
        id: importDialog
        title: Tr.tr(Theme.language, "Paste theme JSON")
        modal: true
        anchors.centerIn: parent
        width: Math.min(Theme.dialogLgW + 60, parent.width - Theme.paddingLg * 2)
        background: Rectangle {
            color: Theme.windowBg
            radius: Theme.radiusMd
            border.color: Theme.border
            border.width: 1
        }
        contentItem: TextArea {
            id: importField
            wrapMode: TextArea.Wrap
            color: Theme.windowFg
            background: Rectangle { color: Theme.sidebarBg; radius: Theme.radiusSm }
        }
        standardButtons: Dialog.Ok | Dialog.Cancel
        onAccepted: {
            if (!Theme.importJson(importField.text)) {
                ApplicationWindow.window.showToast(Tr.tr(Theme.language, "Invalid JSON"))
            }
            importField.text = ""
        }
    }

    Component.onCompleted: ProfileManager.refresh()
}
