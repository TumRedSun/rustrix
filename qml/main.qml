// main.qml — root window: Discord-style 4-column layout with overlay modals.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import MatrixClient

ApplicationWindow {
    id: root
    visible: true
    // The window/taskbar icon is set from main.rs via
    // QGuiApplication::setWindowIcon() (QML's ApplicationWindow has no
    // icon property), sourced from the embedded qrc asset bundle.
    width: 1280
    height: 800
    minimumWidth: 720
    minimumHeight: 480
    title: MatrixClient.userId.length > 0
           ? Tr.tr(Theme.language, "Rustrix — %1").arg(MatrixClient.userId)
           : Tr.tr(Theme.language, "Rustrix")
    color: Theme.windowBg

    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSizeMd

    // ── Sync live window dimensions into Theme ──
    // Every window-relative size property in Theme (colSpacesW,
    // headerH, iconBtnSize, dialogMdW, …) is derived from
    // min(appWidth/1280, appHeight/800). Writing them here fires
    // Theme.scaleChanged, which makes every binding that reads any
    // derived size re-evaluate immediately, so the whole UI scales
    // with the window. Doing this in onWidthChanged / onHeightChanged
    // (rather than only once in Component.onCompleted) means
    // resizing the window also re-scales the UI live.
    //
    // Why this fixes the "background shifts on language change" bug:
    // every fixed-pixel size in the QML UI is now a function of the
    // window size (which doesn't change when the user picks a
    // different language), not of the translated text content (which
    // does change length and used to push backgrounds out of place).
    onWidthChanged:  Theme.appWidth  = root.width
    onHeightChanged: Theme.appHeight = root.height
    // Also set once at startup so the very first frame already has
    // the correct scale (onWidthChanged / onHeightChanged only fire
    // when the value changes after construction, and the initial
    // 1280×800 happens to match Qt's default ApplicationWindow size
    // without firing a "change").
    Component.onCompleted: {
        Theme.appWidth  = root.width
        Theme.appHeight = root.height

        // Reload persisted theme from disk BEFORE applyPreset. This
        // guarantees the user's saved language is loaded into
        // ThemeState while QML bindings are already listening for
        // languageChanged — so the very first render uses the right
        // language instead of falling back to English.
        Theme.loadFromDisk()

        // Force a fresh re-read of every Theme-driven property so changes
        // the user made via the Settings dialog (in a previous session)
        // propagate even if QML cached a stale value during the initial
        // singleton construction race.
        Theme.applyPreset(Theme.preset)

        // Force QML to eagerly create ALL the singleton models RIGHT
        // NOW. qmetaobject creates singletons lazily on first reference,
        // but the sync loop running on Tokio may push ApplyRooms /
        // ApplySpaces / RefreshProfile events into the pending queue
        // before QML ever touches RoomModel, SpaceModel, etc. If the
        // singleton hasn't been created yet, pollPending() logs
        // "QPointer is null, dropping N entries" and the data is lost
        // until the next sync cycle. Touching each model's `count`
        // property here forces singleton creation before autoLogin()
        // kicks off the sync.
        // eslint-disable-next-line no-unused-expressions
        RoomModel.count
        MessageModel.count
        SpaceModel.count
        ProfileManager.userId
        MemberModel.count

        MatrixClient.autoLogin()
        // Start the UI tick timer unconditionally. This drains the
        // pending-events queue (the reliable Tokio→Qt bridge that
        // replaces qmetaobject's broken queued_callback when created
        // from a Tokio worker thread) and also checks whether the
        // loading screen should transition to the main view.
        uiTickTimer.start()
    }

    // ── Hidden clipboard helper ──
    // qmetaobject 0.2 doesn't expose QClipboard directly. We use a hidden
    // TextEdit that we set the text on, select all, and call copy(). This
    // pushes the text onto the system clipboard without needing a Rust-side
    // binding. Triggered whenever MatrixClient.copyText emits textCopied.
    TextEdit {
        id: clipboardHelper
        visible: false
        readOnly: true
    }
    Connections {
        target: MatrixClient
        function onTextCopied(text) {
            clipboardHelper.text = text
            clipboardHelper.selectAll()
            clipboardHelper.copy()
            clipboardHelper.deselect()
        }
    }

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: loginPage
    }

    Component { id: loginPage; LoginPage {} }
    Component { id: loadingScreen; LoadingScreen {} }

    // ────────────────────── MainView (Discord-style 4-column) ──────────────────────
    Component {
        id: mainView

        Rectangle {
            id: mainViewRoot
            objectName: "mainViewRoot"
            color: Theme.windowBg
            property string activeSpaceId: ""
            property string activeRoomId: ""
            property string activeSpaceName: ""
            // "home" = DMs, "space" = rooms of selected space
            property string sidebarMode: "home"

            // ── Chat navigation history (mouse back/forward) ──
            // Maintains a sliding-window history of recently-opened
            // rooms (capped at 20), like a browser. The "present" pointer
            // is `chatHistoryIndex`. Clicking a room pushes a new entry
            // at index+1 and discards any forward history (matches
            // browser semantics: navigating back then clicking a link
            // erases the forward history). Pressing the mouse back /
            // forward buttons just moves the pointer without pushing.
            property var chatHistory: []
            property int chatHistoryIndex: -1
            // Guard flag: while we change activeRoomId from the
            // back/forward handlers, we don't want onActiveRoomIdChanged
            // to push a new history entry (which would split the line).
            property bool _navigatingFromHistory: false

            function pushChatHistory(roomId) {
                if (roomId.length === 0) return
                if (_navigatingFromHistory) return
                // Truncate any forward history (entries after current index).
                if (chatHistoryIndex + 1 < chatHistory.length) {
                    chatHistory = chatHistory.slice(0, chatHistoryIndex + 1)
                }
                // Avoid duplicate consecutive entries (e.g. clicking the
                // already-active room shouldn't pollute the history).
                if (chatHistory.length > 0 && chatHistory[chatHistory.length - 1] === roomId) {
                    chatHistoryIndex = chatHistory.length - 1
                    return
                }
                chatHistory.push(roomId)
                // Cap at 20 — drop the oldest entry.
                if (chatHistory.length > 20) {
                    chatHistory = chatHistory.slice(chatHistory.length - 20)
                }
                chatHistoryIndex = chatHistory.length - 1
            }

            function navigateChatBack() {
                if (chatHistoryIndex > 0) {
                    chatHistoryIndex--
                    _navigatingFromHistory = true
                    activeRoomId = chatHistory[chatHistoryIndex]
                    _navigatingFromHistory = false
                    // Show a toast so the user sees the navigation happened
                    // (otherwise it can feel like nothing happened when the
                    // target room has the same name as the current one).
                    root.showToast(Tr.tr(Theme.language, "Back"))
                }
            }

            function navigateChatForward() {
                if (chatHistoryIndex >= 0 && chatHistoryIndex < chatHistory.length - 1) {
                    chatHistoryIndex++
                    _navigatingFromHistory = true
                    activeRoomId = chatHistory[chatHistoryIndex]
                    _navigatingFromHistory = false
                    root.showToast(Tr.tr(Theme.language, "Forward"))
                }
            }

            // Full-window mouse-area that captures the back / forward
            // mouse buttons (typically mouse buttons 8 & 9). It only
            // accepts those buttons, so regular left/right clicks pass
            // through to the underlying UI (room list, message bubbles,
            // composer, etc.) unimpeded.
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.BackButton | Qt.ForwardButton
                propagateComposedEvents: true
                onClicked: function(mouse) {
                    if (mouse.button === Qt.BackButton) {
                        mainViewRoot.navigateChatBack()
                    } else if (mouse.button === Qt.ForwardButton) {
                        mainViewRoot.navigateChatForward()
                    }
                    // Don't accept — let it propagate (harmless if nothing
                    // else handles it, and avoids swallowing the event in
                    // case a child widget also wants it).
                    mouse.accepted = false
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── Column 1: Space icons (narrow, like Discord server icons) ──
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Theme.colSpacesW
                    color: Theme.sidebarBg

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Home / DMs button
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.headerChatH
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: mainViewRoot.sidebarMode === "home" ? Theme.radiusSm : 0
                                color: mainViewRoot.sidebarMode === "home" ? Theme.accent : "transparent"
                                opacity: mainViewRoot.sidebarMode === "home" ? 0.2 : 0
                            }
                            Label {
                                anchors.centerIn: parent
                                text: "\u2302"  // ⌂ house
                                font.pixelSize: Theme.fontSizeXl
                                color: mainViewRoot.sidebarMode === "home" ? Theme.accentFg : Theme.sidebarFg
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    mainViewRoot.sidebarMode = "home"
                                    mainViewRoot.activeSpaceId = ""
                                    mainViewRoot.activeSpaceName = ""
                                }
                            }
                        }

                        // Separator
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            color: Theme.border
                        }

                        // Space icon list
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                id: spaceIconList
                                model: SpaceModel
                                spacing: 4

                                delegate: Item {
                                    width: ListView.view.width
                                    height: Theme.spaceIconSize
                                    visible: model.kind === "space"

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        radius: Theme.radiusSm
                                        color: mainViewRoot.activeSpaceId === model.id
                                               ? Theme.accent : Theme.windowBg
                                        opacity: mainViewRoot.activeSpaceId === model.id ? 0.25 : 1.0

                                        // Unread indicator dot
                                        Rectangle {
                                            visible: model.unread > 0 && mainViewRoot.activeSpaceId !== model.id
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 2
                                            width: Math.round(Theme.colorSwatchSize / 3); height: Math.round(Theme.colorSwatchSize / 3)
                                            radius: Math.round(Theme.colorSwatchSize / 6)
                                            color: model.highlight > 0 ? Theme.danger : Theme.accent
                                        }
                                    }

                                    Label {
                                        anchors.centerIn: parent
                                        text: model.name.length > 0 ? model.name.charAt(0).toUpperCase() : "?"
                                        color: mainViewRoot.activeSpaceId === model.id ? Theme.accentFg : Theme.sidebarFg
                                        font.pixelSize: Theme.fontSizeLg
                                        font.bold: true
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            mainViewRoot.activeSpaceId = model.id
                                            mainViewRoot.activeSpaceName = model.name
                                            mainViewRoot.sidebarMode = "space"
                                            MatrixClient.loadRoomMembers(model.id)
                                        }
                                    }
                                }
                            }
                        }

                        // Separator
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            color: Theme.border
                        }

                        // Settings button at bottom
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.headerH
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: Theme.radiusSm
                                color: settingsOverlay.visible ? Theme.accent : "transparent"
                                opacity: settingsOverlay.visible ? 0.2 : 0
                            }
                            Label {
                                anchors.centerIn: parent
                                text: "\u2699"  // ⚙ gear
                                font.pixelSize: Theme.fontSizeXl
                                color: settingsOverlay.visible ? Theme.accentFg : Theme.sidebarFg
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: settingsOverlay.visible = !settingsOverlay.visible
                            }
                        }
                    }
                }

                // ── Column 2: Room list (DMs or space rooms) ──
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Theme.colRoomsW
                    color: Qt.darker(Theme.sidebarBg, 1.05)

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        // Header: back arrow + title
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.headerH
                            color: "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.paddingSm
                                anchors.rightMargin: Theme.paddingSm
                                spacing: Theme.spacingSm

                                ToolButton {
                                    text: "\u25C0"  // ◀
                                    font.pixelSize: Theme.fontSizeMd
                                    visible: mainViewRoot.sidebarMode === "space"
                                    onClicked: {
                                        mainViewRoot.sidebarMode = "home"
                                        mainViewRoot.activeSpaceId = ""
                                        mainViewRoot.activeSpaceName = ""
                                    }
                                }

                                Label {
                                    Layout.fillWidth: true
                                    text: mainViewRoot.sidebarMode === "home"
                                          ? Tr.tr(Theme.language, "Direct Messages")
                                          : Tr.tr(Theme.language, "Rooms")
                                    color: Theme.sidebarFg
                                    font.pixelSize: Theme.fontSizeMd
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                // No manual refresh button: the room list
                                // refreshes automatically after every sync
                                // cycle (and on a backup timer in main.qml).

                                // "+" button — opens the user search dialog.
                                // In DM mode it lets you start a new DM;
                                // we keep it in both modes so users can start
                                // a DM from anywhere.
                                ToolButton {
                                    text: "\u2795"  // ➕
                                    font.pixelSize: Theme.fontSizeMd
                                    onClicked: {
                                        userSearchDialog.open()
                                    }
                                }
                            }
                        }

                        // Search/filter field
                        TextField {
                            id: roomSearch
                            Layout.fillWidth: true
                            Layout.leftMargin: Theme.paddingSm
                            Layout.rightMargin: Theme.paddingSm
                            Layout.bottomMargin: Theme.spacingSm
                            placeholderText: Tr.tr(Theme.language, "Search\u2026")
                            color: Theme.sidebarFg
                            font.pixelSize: Theme.fontSizeSm
                            background: Rectangle {
                                color: Theme.sidebarBg
                                radius: Theme.radiusSm
                                border.color: Theme.border
                                border.width: 1
                            }
                        }

                        // Room list (filters based on sidebarMode)
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            ListView {
                                id: roomList
                                model: RoomModel
                                spacing: 2

                                delegate: Item {
                                    width: ListView.view.width
                                    // Filter rules:
                                    //   - In "home" (DM) mode:
                                    //       show direct rooms that have ≥1 message
                                    //       OR the room the user has explicitly
                                    //       navigated to (so a freshly-created
                                    //       DM is reachable even before its
                                    //       first message arrives).
                                    //   - In "space" mode: show non-direct
                                    //       rooms.
                                    property bool showItem: mainViewRoot.sidebarMode === "home"
                                            ? model.is_direct
                                            : !model.is_direct
                                    height: showItem ? Theme.roomRowH : 0
                                    visible: showItem

                                    Rectangle {
                                        anchors.fill: parent
                                        color: mainViewRoot.activeRoomId === model.room_id ? Theme.accent : "transparent"
                                        opacity: mainViewRoot.activeRoomId === model.room_id ? 0.18 : 0
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.paddingSm
                                        // Leave room for the × close button on DMs
                                        anchors.rightMargin: (model.is_direct && mainViewRoot.sidebarMode === "home")
                                                              ? Theme.paddingSm + Theme.colorSwatchSize
                                                              : Theme.paddingSm
                                        spacing: Theme.spacingSm

                                        Rectangle {
                                            Layout.preferredWidth: Theme.avatarListMd
                                            Layout.preferredHeight: Theme.avatarListMd
                                            radius: model.is_direct
                                                    ? Theme.avatarListMd / 2  // circle for DMs
                                                    : Theme.radiusSm  // rounded for rooms
                                            color: model.is_direct ? Theme.success : Theme.accent
                                            opacity: 0.3
                                            Label {
                                                anchors.centerIn: parent
                                                text: model.name.length > 0 ? model.name.charAt(0).toUpperCase() : "#"
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
                                                text: model.name.length > 0 ? model.name : model.room_id
                                                color: Theme.sidebarFg
                                                elide: Text.ElideRight
                                                font.pixelSize: Theme.fontSizeSm
                                                font.bold: model.has_unread
                                            }
                                            Label {
                                                Layout.fillWidth: true
                                                visible: model.last_event.length > 0
                                                text: model.last_event
                                                color: Theme.muted
                                                elide: Text.ElideRight
                                                font.pixelSize: Theme.fontSizeXs
                                            }
                                        }

                                        // Unread badge
                                        Rectangle {
                                            visible: model.unread_count > 0
                                            Layout.preferredWidth: Math.max(Theme.colorSwatchSize - 4, unreadLbl.implicitWidth + Theme.paddingXs)
                                            Layout.preferredHeight: Theme.colorSwatchSize - 4
                                            radius: (Theme.colorSwatchSize - 4) / 2
                                            color: model.highlight_count > 0 ? Theme.danger : Theme.accent
                                            Label {
                                                id: unreadLbl
                                                anchors.centerIn: parent
                                                text: model.unread_count
                                                color: Theme.accentFg
                                                font.pixelSize: Theme.fontSizeXs
                                                font.bold: true
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            // Only set activeRoomId here. ChatPage.qml's
                                            // onRoomIdChanged handler takes care of calling
                                            // loadRoomMessages — that's the single source
                                            // of truth for "when does this room's messages
                                            // get loaded". Calling loadRoomMessages from
                                            // here too would cause duplicate fetches every
                                            // time the user clicks a room.
                                            mainViewRoot.activeRoomId = model.room_id
                                        }
                                    }

                                    // × close button for DMs — placed AFTER MouseArea
                                    // so it sits on top in z-order and captures its
                                    // own clicks.  Only visible in the DM sidebar.
                                    Item {
                                        visible: model.is_direct && mainViewRoot.sidebarMode === "home"
                                        anchors.right: parent.right
                                        anchors.rightMargin: Theme.paddingSm
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.colorSwatchSize
                                        height: Theme.colorSwatchSize

                                        Label {
                                            anchors.centerIn: parent
                                            text: "\u2715"  // ✕
                                            color: Theme.muted
                                            font.pixelSize: Theme.fontSizeXs
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                leaveRoomDialog.roomId = model.room_id
                                                leaveRoomDialog.roomName = model.name.length > 0 ? model.name : model.room_id
                                                leaveRoomDialog.open()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Column 3: Chat area ──
                ChatPage {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    roomId: mainViewRoot.activeRoomId
                    onGoBack: mainViewRoot.activeRoomId = ""
                }

                // Reload messages for the active room after each sync cycle
                // so new messages appear in real-time without re-clicking.
                Connections {
                    target: MatrixClient
                    function onSyncDone(payload) {
                        // Refresh room list after every sync so new DMs/rooms
                        // appear immediately without manual button press.
                        MatrixClient.refreshRooms()
                        // NOTE: Do NOT call loadRoomMessages here.
                        // Reloading on every sync cycle causes:
                        //   - duplicate fetches (one per sync, ~every 30s)
                        //   - UI flicker (model gets reset → list scrolls to top)
                        //   - wasted bandwidth
                        // ChatPage.qml's onRoomIdChanged is the single
                        // trigger for loading a room's messages.
                    }
                }

                // Backup timer: refresh rooms every 10s even if
                // onSyncDone signal is missed (queued_callback can be
                // unreliable across Tokio→Qt).
                Timer {
                    interval: 10000
                    running: MatrixClient.userId.length > 0
                    repeat: true
                    onTriggered: MatrixClient.refreshRooms()
                }

                // ── Column 4: Member list (right sidebar) ──
                MemberListPanel {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Theme.colMembersW
                    visible: mainViewRoot.sidebarMode === "space" && mainViewRoot.activeSpaceId.length > 0
                    spaceId: mainViewRoot.activeSpaceId
                    spaceName: mainViewRoot.activeSpaceName
                }
            }

            // When a room is selected, close settings overlay and push
            // it onto the chat-history stack (for mouse back/forward
            // navigation). The `_navigatingFromHistory` flag inside
            // pushChatHistory suppresses duplicate pushes when we're
            // moving the pointer from the back/forward handlers.
            onActiveRoomIdChanged: {
                if (activeRoomId.length > 0) {
                    settingsOverlay.visible = false
                    pushChatHistory(activeRoomId)
                }
            }
        }
    }

    // ────────────────────── Settings Overlay (modal with dimmed background) ──────────────────────
    Rectangle {
        id: settingsOverlay
        visible: false
        anchors.fill: parent
        color: "transparent"
        z: 100  // above everything

        // ESC closes the settings overlay. Dialog-based popups
        // (userSearchDialog, leaveRoomDialog, renameDialog, etc.) already
        // close on ESC via Qt's default `Popup.CloseOnEscape` policy;
        // this Shortcut covers the settings overlay, which is a plain
        // Rectangle (not a Dialog) and so doesn't get that behavior
        // automatically. The Shortcut is only enabled while the overlay
        // is visible so it doesn't shadow ESC handling elsewhere.
        Shortcut {
            sequence: "Escape"
            enabled: settingsOverlay.visible
            onActivated: settingsOverlay.visible = false
        }

        // Dim background
        MouseArea {
            anchors.fill: parent
            onClicked: settingsOverlay.visible = false
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.6
        }

        // Settings panel (centered, like Discord).
        // Sized to nearly fill the window so users with big screens / lots
        // of theme settings don't have to scroll the panel itself — only
        // the inner ScrollView scrolls.
        Rectangle {
            id: settingsPanel
            width: parent.width  - Theme.paddingLg * 2
            height: parent.height - Theme.paddingLg * 2
            anchors.centerIn: parent
            color: Theme.windowBg
            radius: Theme.radiusLg
            border.color: Theme.border
            border.width: 1

            // Prevent clicks from closing when inside the panel
            MouseArea {
                anchors.fill: parent
                onClicked: function(mouse) { mouse.accepted = true }
            }

            SettingsOverlay {
                anchors.fill: parent
                anchors.margins: 1  // keep the rounded border visible
                onCloseSettings: settingsOverlay.visible = false
            }
        }

        // Prevent interaction with underlying UI while overlay is open
        MouseArea {
            anchors.fill: parent
            visible: settingsOverlay.visible
            onClicked: {}  // swallow all clicks
            z: -1
        }
    }

    // ────────────────────── User Search Dialog ──────────────────────
    // Centered modal for finding users to start DMs with.
    // User flow:
    //   1. Type a (partial) username in the search field.
    //   2. MatrixClient.searchUsers() emits usersSearchDone(json).
    //   3. The JSON is parsed into a ListModel and rendered below.
    //   4. Each row has a "message" icon on the right — clicking it calls
    //      MatrixClient.openDirectMessage(userId), which emits dmOpened(rid).
    //   5. dmOpened sets activeRoomId and closes the dialog. Until the first
    //      real message is sent, the room stays unpinned in the DM sidebar
    //      (see RoomModel filter in the roomList delegate).
    Dialog {
        id: userSearchDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(Theme.dialogLgW + 60, parent.width  - Theme.paddingLg * 2)
        height: Math.min(Theme.dialogLgW + 20, parent.height - Theme.paddingLg * 2)
        background: Rectangle {
            color: Theme.windowBg
            radius: Theme.radiusLg
            border.color: Theme.border
            border.width: 1
        }

        // Hold the parsed search results.
        ListModel { id: userSearchResults }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.paddingMd
            spacing: Theme.spacingSm

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSm
                Label {
                    text: Tr.tr(Theme.language, "Find user")
                    font.pixelSize: Theme.fontSizeLg
                    font.bold: true
                    color: Theme.windowFg
                }
                Item { Layout.fillWidth: true }
                ToolButton {
                    text: "\u2715"  // ✕
                    font.pixelSize: Theme.fontSizeMd
                    onClicked: userSearchDialog.close()
                }
            }

            // Search input — queries fire after every keystroke (debounced
            // via a small Timer so we don't spam the server).
            TextField {
                id: userSearchField
                Layout.fillWidth: true
                placeholderText: Tr.tr(Theme.language, "Type a username (e.g. @alice:matrix.org)…")
                color: Theme.windowFg
                font.pixelSize: Theme.fontSizeSm
                onTextChanged: userSearchTimer.restart()
                background: Rectangle {
                    color: Theme.sidebarBg
                    radius: Theme.radiusSm
                    border.color: Theme.border
                    border.width: 1
                }
            }

            // Results list.
            ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ListView {
                    id: userSearchList
                    model: userSearchResults
                    spacing: 2

                    delegate: Item {
                        width: ListView.view.width
                        height: Theme.roomRowH

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 2
                            radius: Theme.radiusSm
                            color: userSearchList.currentIndex === index ? Theme.accent : "transparent"
                            opacity: userSearchList.currentIndex === index ? 0.15 : 0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.paddingSm
                            anchors.rightMargin: Theme.paddingSm
                            spacing: Theme.spacingSm

                            // Avatar (uses mxc:// via avatar_cache if available,
                            // otherwise shows the first letter of the display name).
                            Rectangle {
                                Layout.preferredWidth: Theme.avatarListMd + 4
                                Layout.preferredHeight: Theme.avatarListMd + 4
                                radius: (Theme.avatarListMd + 4) / 2
                                color: Theme.accent
                                opacity: 0.3
                                Label {
                                    anchors.centerIn: parent
                                    text: {
                                        var dn = model.display_name || model.user_id
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
                                    text: model.display_name.length > 0 ? model.display_name : Tr.tr(Theme.language, "(no display name)")
                                    color: Theme.windowFg
                                    font.pixelSize: Theme.fontSizeSm
                                    font.bold: true
                                    elide: Text.ElideRight
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: model.user_id
                                    color: Theme.muted
                                    font.pixelSize: Theme.fontSizeXs
                                    elide: Text.ElideRight
                                }
                            }

                            // Message icon — click to open the DM.
                            ToolButton {
                                text: "\u2709"  // ✉
                                font.pixelSize: Theme.fontSizeLg
                                Layout.preferredWidth: Theme.iconBtnSize
                                onClicked: {
                                    MatrixClient.openDirectMessage(model.user_id)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // Click on the row (not the buttons) selects it.
                            onClicked: userSearchList.currentIndex = index
                        }
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                visible: userSearchResults.count === 0 && userSearchField.text.length > 0
                text: Tr.tr(Theme.language, "No users found. Try the full Matrix ID (e.g. @alice:matrix.org).")
                color: Theme.muted
                font.pixelSize: Theme.fontSizeXs
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Timer {
            id: userSearchTimer
            interval: 300
            onTriggered: {
                var q = userSearchField.text.trim()
                if (q.length === 0) {
                    userSearchResults.clear()
                    return
                }
                MatrixClient.searchUsers(q)
            }
        }

        onOpened: {
            userSearchField.text = ""
            userSearchResults.clear()
            userSearchField.forceActiveFocus()
        }
    }

    // ────────────────────── Confirm Leave Room Dialog ──────────────────────
    Dialog {
        id: leaveRoomDialog
        modal: true
        anchors.centerIn: parent
        width: Math.min(Theme.dialogMdW + 60, parent.width - Theme.paddingLg * 2)
        background: Rectangle {
            color: Theme.windowBg
            radius: Theme.radiusMd
            border.color: Theme.border
            border.width: 1
        }
        property string roomId: ""
        property string roomName: ""
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.paddingMd
            spacing: Theme.spacingSm
            Label {
                text: Tr.tr(Theme.language, "Close conversation?")
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                color: Theme.windowFg
            }
            Label {
                Layout.fillWidth: true
                text: leaveRoomDialog.roomName.length > 0
                      ? Tr.tr(Theme.language, "This will leave \"%1\". Your and the other participant's messages will no longer be visible to you in this client (the history remains on the server).").arg(leaveRoomDialog.roomName)
                      : Tr.tr(Theme.language, "This will leave the room. Your and the other participant's messages will no longer be visible to you in this client.")
                color: Theme.windowFg
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeSm
            }
            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Button {
                    text: Tr.tr(Theme.language, "Cancel")
                    onClicked: leaveRoomDialog.close()
                }
                Button {
                    text: Tr.tr(Theme.language, "Close")
                    background: Rectangle { color: Theme.danger; radius: Theme.radiusSm }
                    contentItem: Label { text: parent.text; color: Theme.accentFg }
                    onClicked: {
                        if (leaveRoomDialog.roomId.length > 0) {
                            MatrixClient.leaveRoom(leaveRoomDialog.roomId)
                        }
                        leaveRoomDialog.close()
                    }
                }
            }
        }
    }

    // ── Toast ──
    Rectangle {
        id: toast
        property string text
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.paddingLg + Theme.paddingSm
        color: text.length > 0 ? Theme.accent : "transparent"
        radius: Theme.radiusMd
        visible: text.length > 0
        opacity: 0.95
        width: toastLabel.implicitWidth + Theme.paddingLg * 2
        height: toastLabel.implicitHeight + Theme.paddingMd
        Label {
            id: toastLabel
            anchors.centerIn: parent
            text: toast.text
            color: Theme.accentFg
            font.pixelSize: Theme.fontSizeSm
        }
        Timer { id: toastTimer; interval: 3000; onTriggered: toast.text = "" }
    }

    Connections {
        target: MatrixClient
        function onLastErrorChanged() {
            var err = MatrixClient.lastError;
            if (err && err.length > 0) {
                toast.text = err;
                toastTimer.start();
            }
        }
        function onLoggedIn(userId) {
            stack.replace(null, loadingScreen);
            // uiTickTimer is started unconditionally from
            // Component.onCompleted, so we don't need to start it here.
            // Keep loadingTransitionTimer.start() as a legacy backup.
            loadingTransitionTimer.start();
        }
        function onLoggedOut() {
            stack.replace(null, loginPage);
            settingsOverlay.visible = false;
        }
        function onFileDownloaded(roomId, mxc, localPath) {
            root.showToast(Tr.tr(Theme.language, "Downloaded to %1").arg(localPath));
        }
        // Search results arrived — parse JSON into userSearchResults.
        function onUsersSearchDone(resultsJson) {
            userSearchResults.clear()
            try {
                var arr = JSON.parse(resultsJson)
                for (var i = 0; i < arr.length; i++) {
                    userSearchResults.append(arr[i])
                }
            } catch (e) {
                console.warn("users_search_done: bad JSON", e)
            }
        }
        // DM opened — switch to the room and close the search dialog.
        function onDmOpened(roomId) {
            if (roomId.length === 0) return
            mainViewRoot.sidebarMode = "home"
            mainViewRoot.activeRoomId = roomId
            MatrixClient.loadRoomMessages(roomId)
            userSearchDialog.close()
        }
        // Room left — clear active room if it was the one we left.
        function onRoomLeft(roomId) {
            if (mainViewRoot.activeRoomId === roomId) {
                mainViewRoot.activeRoomId = ""
            }
            root.showToast(Tr.tr(Theme.language, "Conversation closed"))
        }
    }

    // ── UI tick timer ──
    // Runs every 100 ms for the entire lifetime of the app.
    //
    // 1. Calls MatrixClient.pollPending() to drain the pending-events
    //    queue. This is the reliable replacement for
    //    qmetaobject::queued_callback for events that originate on the
    //    Tokio runtime (sync loop, finish_login, etc.). Without this,
    //    Qt property changes and signal emissions triggered from Tokio
    //    never reach QML, and the loading screen never transitions.
    //
    // 2. If we're still on the loading screen, checks whether sync has
    //    completed (MatrixClient.ready || RoomModel.count > 0) and
    //    transitions to the main view.
    //
    // 100 ms is fast enough that the loading screen disappears promptly
    // after sync (user-perceived delay < 100 ms) and slow enough that
    // the overhead is negligible.
    Timer {
        id: uiTickTimer
        interval: 100
        repeat: true
        onTriggered: {
            // 1. Drain pending events from Tokio.
            MatrixClient.pollPending()

            // 2. Check loading-screen transition.
            if (stack.currentItem === null) return
            if (stack.currentItem.objectName === "mainViewRoot") return
            if (MatrixClient.ready || RoomModel.count > 0) {
                stack.replace(null, mainView)
                // Keep the timer running — it's still needed to drain
                // pending events from the sync loop after login.
            }
        }
    }

    // ── Loading-screen transition timer (legacy, kept as backup) ──
    // Polls every 500 ms: when rooms appear (initial sync done) or
    // MatrixClient.ready becomes true, replaces the loading screen
    // with the main view.  This is more reliable than depending on
    // Rust queued_callback / signal delivery which has been flaky.
    //
    // NOTE: uiTickTimer (above) now handles both pollPending() and
    // the loading-screen transition. This timer is retained as a
    // backup and is no longer started by onLoggedIn — uiTickTimer
    // is started unconditionally from Component.onCompleted.
    Timer {
        id: loadingTransitionTimer
        interval: 500
        repeat: true
        onTriggered: {
            // Only act while we're on the loading screen
            if (stack.currentItem === null) return
            if (stack.currentItem.objectName === "mainViewRoot") return
            // Transition when sync is done (rooms loaded or ready flag set)
            if (MatrixClient.ready || RoomModel.count > 0) {
                stack.replace(null, mainView)
                loadingTransitionTimer.stop()
            }
        }
    }

    // Re-apply the theme when any of its NOTIFY signals fire. QML bindings
    // *should* update automatically, but qmetaobject's getter-based
    // properties occasionally need a nudge — this forces every property
    // to be re-read from the ThemeState RefCell.
    Connections {
        target: Theme
        function onThemeChanged() {
            // No-op: the bindings re-evaluate automatically. This handler
            // exists only so the Connections object compiles.
        }
    }

    function showToast(text) {
        toast.text = text;
        toastTimer.start();
    }
}
