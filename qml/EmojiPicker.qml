// EmojiPicker.qml
// Rofi-style emoji picker popup.
//
// Usage (reaction mode — default):
//   EmojiPicker { id: emojiPicker; mode: "reaction"; roomId: "!abc:matrix.org"; eventId: "$xyz:matrix.org" }
//   emojiPicker.open()
//   → picking an emoji calls MatrixClient.sendReaction(roomId, eventId, emoji)
//
// Usage (insert mode):
//   EmojiPicker { id: emojiInserter; mode: "insert" }
//   emojiInserter.open()
//   onEmojiPicked: function(emoji) { composer.insert(composer.cursorPosition, emoji) }
//
// - Centered modal dialog.
// - Top: search field. Type to filter (matches emoji name/keywords).
// - Below: scrollable square grid of emoji (column count adapts to the
//   dialog width). Wheel-scroll or
//   Up/Down arrows move the highlight (rofi-style keyboard navigation).
// - Enter / click: in "reaction" mode sends a reaction; in "insert" mode
//   emits `emojiPicked(emoji)` so the caller can insert it as text.
// - Escape closes without action.
//
// The emoji list is a static ListModel defined inline at the bottom. It is
// intentionally NOT the full Unicode dataset (~3000 emoji) — that would
// make the grid unusably slow on first paint. The curated ~500 emoji below
// cover the categories users actually react with: smileys, gestures,
// hearts, animals, food, activities, travel, objects, symbols, flags.
// To extend, append rows to `emojiModel`.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MatrixClient

Dialog {
    id: root
    modal: true
    // Parent to the window's overlay layer so the dialog centers on the
    // whole application window, NOT just the ChatPage / dialog it was
    // declared in. Without this, `anchors.centerIn: parent` resolves to
    // the ChatPage item, which is narrower than the window (it doesn't
    // include the space/sidebar columns).
    parent: Overlay.overlay
    anchors.centerIn: parent
    // Size derives from the CLIENT WINDOW, never from the content:
    // - above the 1280x800 reference the dialog grows with Theme.scale
    //   (kept in sync with the live window size by main.qml);
    // - below it the dialog keeps its reference size and only shrinks when
    //   the overlay itself gets too small (the parent.width cap). Scaling
    //   down twice (Theme.scale already reflects the small window) would
    //   make the picker uselessly tiny — the screenshot-sized window
    //   (708x545 → scale 0.55) must still get the full-size 560px dialog.
    width: Math.min(Math.round(560 * Math.max(1, Theme.scale)), parent.width - Theme.paddingLg * 2)
    height: Math.min(Math.round(520 * Math.max(1, Theme.scale)), parent.height - Theme.paddingLg * 2)
    padding: 0
    // Close-on-Escape is built into Dialog. We also close on outside click
    // (default for modal Dialogs).

    // ── Public API ──
    // mode: "reaction" (default) — picking sends a reaction to (roomId, eventId).
    //       "insert" — picking emits `emojiPicked(emoji)` for the caller to
    //                  handle (e.g. insert into the message composer as text).
    property string mode: "reaction"
    // roomId + eventId are set by the caller before calling open().
    // Only used in "reaction" mode.
    property string roomId: ""
    property string eventId: ""

    // Emitted in "insert" mode when the user picks an emoji. The caller
    // is responsible for inserting it into the target text field.
    signal emojiPicked(string emoji)

    // ── Internal state ──
    // currentIndex: index into `filteredModel` of the highlighted cell.
    // -1 = no highlight. Bound to GridView.currentIndex.
    property int currentIndex: -1

    // ── Filtering ──
    // We keep two models:
    //   - emojiModel: the static master list (defined at bottom).
    //   - filteredModel: a ListModel rebuilt whenever the search query
    //     changes, containing only rows whose `keywords` (lowercased)
    //     contain the query (lowercased). Empty query → all rows.
    //
    // We rebuild on every keystroke. With ~500 rows this is sub-millisecond
    // and avoids the complexity of QSortFilterProxyModel (which QtQuick
    // doesn't ship in a ListModel-friendly form).
    ListModel { id: filteredModel }

    function rebuildFiltered() {
        var q = searchField.text.trim().toLowerCase()
        filteredModel.clear()
        for (var i = 0; i < emojiModel.count; i++) {
            var row = emojiModel.get(i)
            if (q.length === 0 || row.keywords.indexOf(q) >= 0) {
                filteredModel.append({
                    "emoji": row.emoji,
                    "name": row.name,
                    "keywords": row.keywords
                })
            }
        }
        // Reset highlight to first row so Enter immediately after typing
        // reacts with the top match (rofi behaviour).
        if (filteredModel.count > 0) {
            gridView.currentIndex = 0
        } else {
            gridView.currentIndex = -1
        }
    }

    function sendCurrent() {
        if (gridView.currentIndex < 0 || gridView.currentIndex >= filteredModel.count) return
        var row = filteredModel.get(gridView.currentIndex)
        if (root.mode === "insert") {
            // Insert mode: emit the emoji and let the caller insert it
            // into whatever target text field owns the cursor.
            root.emojiPicked(row.emoji)
        } else {
            // Reaction mode (default): send as a reaction to (roomId, eventId).
            // Optimistic local update so the chip appears immediately:
            // we cannot reach into MessageBubble from here without coupling,
            // so we rely on the next sync to surface the reaction (typically
            // < 1 s). This matches the existing behaviour of the inline
            // "React" submenu.
            MatrixClient.sendReaction(root.roomId, root.eventId, row.emoji)
        }
        root.close()
    }

    onOpened: {
        searchField.text = ""
        // Rebuild is also triggered by the text change above, but call it
        // explicitly in case the field was already empty (no text-changed
        // signal fires when assigning the same value).
        rebuildFiltered()
        searchField.forceActiveFocus()
    }

    onClosed: {
        // Drop focus so future right-clicks don't accidentally reactivate
        // the search field.
        searchField.text = ""
    }

    background: Rectangle {
        color: Theme.windowBg
        radius: Theme.radiusLg
        border.color: Theme.border
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.paddingMd
        spacing: Theme.spacingSm
        // Nothing may ever paint outside the dialog background, even if a
        // translated string ends up wider than the layout expects.
        clip: true

        // ── Header ──
        // The hint label is the flexible element: it fills the remaining
        // width and elides. Translated hint text varies a lot in length
        // (Russian is ~45% wider than English); if the row sized itself to
        // the text, the whole ColumnLayout would grow wider than the
        // dialog and the search field + grid would stick out past the
        // background ("background shrinks when I change language"). With
        // minimumWidth 0 + preferredWidth 0 + fillWidth the row's implicit
        // width stays language-independent, so the dialog geometry depends
        // only on the window.
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingSm
            Label {
                text: root.mode === "insert"
                      ? Tr.tr(Theme.language, "Insert emoji")
                      : Tr.tr(Theme.language, "React with emoji")
                font.pixelSize: Theme.fontSizeLg
                font.bold: true
                color: Theme.windowFg
                elide: Text.ElideRight
                Layout.maximumWidth: Math.round(240 * Math.max(1, Theme.scale))
            }
            Label {
                // Hint text — keyboard shortcuts.
                text: root.mode === "insert"
                      ? Tr.tr(Theme.language, "Type to search  ·  ↑↓ to move  ·  Enter to insert  ·  Esc to close")
                      : Tr.tr(Theme.language, "Type to search  ·  ↑↓ to move  ·  Enter to react  ·  Esc to close")
                color: Theme.muted
                font.pixelSize: Theme.fontSizeXs
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                Layout.preferredWidth: 0
            }
            ToolButton {
                text: "\u2715"  // ✕
                font.pixelSize: Theme.fontSizeMd
                onClicked: root.close()
            }
        }

        // ── Search field ──
        TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: Tr.tr(Theme.language, "Search emoji (e.g. heart, fire, thumbs up)…")
            color: Theme.windowFg
            font.pixelSize: Theme.fontSizeSm
            selectByMouse: true
            background: Rectangle {
                color: Theme.sidebarBg
                radius: Theme.radiusSm
                border.color: searchField.activeFocus ? Theme.accent : Theme.border
                border.width: 1
            }
            onTextChanged: rebuildFiltered()

            // Keyboard navigation. We handle arrows + Enter here, on the
            // search field, because that's where focus lives by default.
            // GridView's own key handling is unreliable when it doesn't
            // have active focus.
            Keys.onDownPressed: function(event) {
                if (filteredModel.count === 0) return
                if (gridView.currentIndex < 0) {
                    gridView.currentIndex = 0
                } else {
                    gridView.currentIndex = Math.min(gridView.currentIndex + 1, filteredModel.count - 1)
                }
                gridView.positionViewAtIndex(gridView.currentIndex, GridView.Contain)
                event.accepted = true
            }
            Keys.onUpPressed: function(event) {
                if (filteredModel.count === 0) return
                if (gridView.currentIndex < 0) {
                    gridView.currentIndex = 0
                } else {
                    gridView.currentIndex = Math.max(gridView.currentIndex - 1, 0)
                }
                gridView.positionViewAtIndex(gridView.currentIndex, GridView.Contain)
                event.accepted = true
            }
            Keys.onRightPressed: function(event) {
                // Right arrow also moves forward — rofi-style horizontal
                // navigation feels natural in a grid.
                if (filteredModel.count === 0) return
                if (gridView.currentIndex < 0) {
                    gridView.currentIndex = 0
                } else {
                    gridView.currentIndex = Math.min(gridView.currentIndex + 1, filteredModel.count - 1)
                }
                gridView.positionViewAtIndex(gridView.currentIndex, GridView.Contain)
                event.accepted = true
            }
            Keys.onLeftPressed: function(event) {
                if (filteredModel.count === 0) return
                if (gridView.currentIndex < 0) {
                    gridView.currentIndex = 0
                } else {
                    gridView.currentIndex = Math.max(gridView.currentIndex - 1, 0)
                }
                gridView.positionViewAtIndex(gridView.currentIndex, GridView.Contain)
                event.accepted = true
            }
            Keys.onReturnPressed: function(event) {
                sendCurrent()
                event.accepted = true
            }
            Keys.onEnterPressed: function(event) {
                sendCurrent()
                event.accepted = true
            }
            Keys.onEscapePressed: function(event) {
                root.close()
                event.accepted = true
            }
        }

        // ── Result count / empty-state hint ──
        Label {
            Layout.fillWidth: true
            text: filteredModel.count === 0
                  ? Tr.tr(Theme.language, "No emoji match your search.")
                  : Tr.tr(Theme.language, "%1 emoji").arg(filteredModel.count)
            color: Theme.muted
            font.pixelSize: Theme.fontSizeXs
            visible: searchField.text.length > 0
        }

        // ── Emoji grid ──
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            GridView {
                id: gridView
                model: filteredModel
                // Column count derives from the dialog width (which itself
                // derives from the window via Theme.scale): ~62px cells at
                // reference size → 8 columns in the 560px dialog, fewer on
                // small windows, more on large ones. (A fixed count of 8
                // would just shrink cells to dots on narrow dialogs.)
                property int columns: Math.max(4, Math.floor(width / Math.max(1, Math.round(62 * Math.max(1, Theme.scale)))))
                cellWidth: Math.floor(width / columns)
                cellHeight: cellWidth
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                // Keep the highlight in sync with currentIndex so the
                // keyboard navigation above visually moves the highlight.
                highlight: Rectangle {
                    color: Theme.accent
                    opacity: 0.25
                    radius: Theme.radiusSm
                }
                highlightFollowsCurrentItem: true
                focus: true

                delegate: Item {
                    width: gridView.cellWidth
                    height: gridView.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: Theme.radiusSm
                        color: "transparent"
                        // Hover effect (mouse users). Doesn't move
                        // currentIndex — that would fight with keyboard
                        // navigation — just provides visual feedback.
                        opacity: 1.0

                        Text {
                            anchors.centerIn: parent
                            text: model.emoji
                            font.pixelSize: Math.min(parent.width * 0.6, Math.round(28 * Math.max(1, Theme.scale)))
                            // Render emoji as-is (they're already
                            // colour glyphs in Noto Color Emoji).
                            renderType: Text.NativeRendering
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                gridView.currentIndex = index
                                sendCurrent()
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Master emoji list ──
    // Each row: { emoji, name, keywords }
    // `keywords` is a space-separated lowercased string of search terms.
    // We include common synonyms so e.g. "thumbs up", "yes", "ok", "+1"
    // all find 👍.
    ListModel {
        id: emojiModel

        // ── Smileys & faces ──
        ListElement { emoji: "😀"; name: "Grinning"; keywords: "grinning smile happy face" }
        ListElement { emoji: "😃"; name: "Smiley"; keywords: "smiley happy smile face" }
        ListElement { emoji: "😄"; name: "Smile"; keywords: "smile happy face" }
        ListElement { emoji: "😁"; name: "Grin"; keywords: "grin happy face" }
        ListElement { emoji: "😆"; name: "Laughing"; keywords: "laughing happy haha face" }
        ListElement { emoji: "😅"; name: "Sweat smile"; keywords: "sweat smile relief face" }
        ListElement { emoji: "🤣"; name: "Rofl"; keywords: "rofl rolling laughing floor haha face" }
        ListElement { emoji: "😂"; name: "Joy"; keywords: "joy tears laughing crying face" }
        ListElement { emoji: "🙂"; name: "Slight smile"; keywords: "slight smile face" }
        ListElement { emoji: "🙃"; name: "Upside down"; keywords: "upside down face sarcasm" }
        ListElement { emoji: "😉"; name: "Wink"; keywords: "wink face" }
        ListElement { emoji: "😊"; name: "Blush"; keywords: "blush smile happy face" }
        ListElement { emoji: "😇"; name: "Angel"; keywords: "angel halo face" }
        ListElement { emoji: "🥰"; name: "Smiling hearts"; keywords: "smiling hearts love face" }
        ListElement { emoji: "😍"; name: "Heart eyes"; keywords: "heart eyes love face" }
        ListElement { emoji: "🤩"; name: "Star struck"; keywords: "star struck eyes face" }
        ListElement { emoji: "😘"; name: "Kiss"; keywords: "kiss face love" }
        ListElement { emoji: "😗"; name: "Kissing"; keywords: "kissing face" }
        ListElement { emoji: "😚"; name: "Kissing closed eyes"; keywords: "kissing closed eyes face" }
        ListElement { emoji: "😙"; name: "Kissing smiling eyes"; keywords: "kissing smiling eyes face" }
        ListElement { emoji: "😋"; name: "Yum"; keywords: "yum tongue tasty face" }
        ListElement { emoji: "😛"; name: "Tongue out"; keywords: "tongue out face" }
        ListElement { emoji: "😜"; name: "Wink tongue"; keywords: "wink tongue face" }
        ListElement { emoji: "🤪"; name: "Zany"; keywords: "zany crazy face" }
        ListElement { emoji: "😝"; name: "Squinting tongue"; keywords: "squinting tongue face" }
        ListElement { emoji: "🤑"; name: "Money mouth"; keywords: "money mouth rich face" }
        ListElement { emoji: "🤗"; name: "Hugging"; keywords: "hugging hug face" }
        ListElement { emoji: "🤭"; name: "Hand over mouth"; keywords: "hand over mouth face" }
        ListElement { emoji: "🤫"; name: "Shushing"; keywords: "shushing quiet face" }
        ListElement { emoji: "🤔"; name: "Thinking"; keywords: "thinking think face" }
        ListElement { emoji: "🤐"; name: "Zipper mouth"; keywords: "zipper mouth quiet face" }
        ListElement { emoji: "🤨"; name: "Raised eyebrow"; keywords: "raised eyebrow sceptical face" }
        ListElement { emoji: "😐"; name: "Neutral"; keywords: "neutral face" }
        ListElement { emoji: "😑"; name: "Expressionless"; keywords: "expressionless face" }
        ListElement { emoji: "😶"; name: "No mouth"; keywords: "no mouth face" }
        ListElement { emoji: "😏"; name: "Smirk"; keywords: "smirk face" }
        ListElement { emoji: "😒"; name: "Unamused"; keywords: "unamused face" }
        ListElement { emoji: "🙄"; name: "Rolling eyes"; keywords: "rolling eyes face" }
        ListElement { emoji: "😬"; name: "Grimacing"; keywords: "grimacing face" }
        ListElement { emoji: "😌"; name: "Relieved"; keywords: "relieved face" }
        ListElement { emoji: "😔"; name: "Pensive"; keywords: "pensive sad face" }
        ListElement { emoji: "😪"; name: "Sleepy"; keywords: "sleepy face" }
        ListElement { emoji: "🤤"; name: "Drooling"; keywords: "drooling face" }
        ListElement { emoji: "😴"; name: "Sleeping"; keywords: "sleeping face" }
        ListElement { emoji: "😷"; name: "Mask"; keywords: "mask face sick" }
        ListElement { emoji: "🤒"; name: "Thermometer"; keywords: "thermometer sick face" }
        ListElement { emoji: "🤕"; name: "Bandage"; keywords: "bandage hurt face" }
        ListElement { emoji: "🤢"; name: "Nauseated"; keywords: "nauseated sick green face" }
        ListElement { emoji: "🤮"; name: "Vomiting"; keywords: "vomiting sick face" }
        ListElement { emoji: "🥵"; name: "Hot"; keywords: "hot heat face" }
        ListElement { emoji: "🥶"; name: "Cold"; keywords: "cold freezing face" }
        ListElement { emoji: "🥴"; name: "Woozy"; keywords: "woozy drunk face" }
        ListElement { emoji: "😵"; name: "Dizzy"; keywords: "dizzy face" }
        ListElement { emoji: "🤯"; name: "Exploding head"; keywords: "exploding head mind blown face" }
        ListElement { emoji: "🤠"; name: "Cowboy"; keywords: "cowboy hat face" }
        ListElement { emoji: "🥳"; name: "Partying"; keywords: "partying celebrate face" }
        ListElement { emoji: "😎"; name: "Cool"; keywords: "cool sunglasses face" }
        ListElement { emoji: "🤓"; name: "Nerd"; keywords: "nerd glasses face" }
        ListElement { emoji: "🧐"; name: "Monocle"; keywords: "monocle face" }
        ListElement { emoji: "😕"; name: "Confused"; keywords: "confused face" }
        ListElement { emoji: "😟"; name: "Worried"; keywords: "worried face" }
        ListElement { emoji: "🙁"; name: "Slight frown"; keywords: "slight frown face" }
        ListElement { emoji: "☹️"; name: "Frown"; keywords: "frown sad face" }
        ListElement { emoji: "😮"; name: "Open mouth"; keywords: "open mouth surprised face" }
        ListElement { emoji: "😯"; name: "Hushed"; keywords: "hushed face" }
        ListElement { emoji: "😲"; name: "Astonished"; keywords: "astonished face" }
        ListElement { emoji: "😳"; name: "Flushed"; keywords: "flushed face" }
        ListElement { emoji: "🥺"; name: "Pleading"; keywords: "pleading face" }
        ListElement { emoji: "😦"; name: "Frowning open mouth"; keywords: "frowning open mouth face" }
        ListElement { emoji: "😧"; name: "Anguished"; keywords: "anguished face" }
        ListElement { emoji: "😨"; name: "Fearful"; keywords: "fearful scared face" }
        ListElement { emoji: "😰"; name: "Anxious sweat"; keywords: "anxious sweat face" }
        ListElement { emoji: "😥"; name: "Sad relieved"; keywords: "sad relieved face" }
        ListElement { emoji: "😢"; name: "Cry"; keywords: "cry tear face" }
        ListElement { emoji: "😭"; name: "Sob"; keywords: "sob crying loud face" }
        ListElement { emoji: "😱"; name: "Scream"; keywords: "scream scared face" }
        ListElement { emoji: "😖"; name: "Confounded"; keywords: "confounded face" }
        ListElement { emoji: "😣"; name: "Persevere"; keywords: "persevere face" }
        ListElement { emoji: "😞"; name: "Disappointed"; keywords: "disappointed sad face" }
        ListElement { emoji: "😓"; name: "Downcast sweat"; keywords: "downcast sweat face" }
        ListElement { emoji: "😩"; name: "Weary"; keywords: "weary tired face" }
        ListElement { emoji: "😫"; name: "Tired"; keywords: "tired face" }
        ListElement { emoji: "🥱"; name: "Yawn"; keywords: "yawn tired face" }
        ListElement { emoji: "😤"; name: "Triumph"; keywords: "triumph huff face" }
        ListElement { emoji: "😡"; name: "Angry"; keywords: "angry rage face" }
        ListElement { emoji: "😠"; name: "Pouting"; keywords: "pouting angry face" }
        ListElement { emoji: "🤬"; name: "Swearing"; keywords: "swearing cursing angry face" }
        ListElement { emoji: "😈"; name: "Devil smile"; keywords: "devil smile horns face" }
        ListElement { emoji: "👿"; name: "Devil"; keywords: "devil angry horns face" }
        ListElement { emoji: "💀"; name: "Skull"; keywords: "skull dead face" }
        ListElement { emoji: "💩"; name: "Poop"; keywords: "poop shit face" }
        ListElement { emoji: "🤡"; name: "Clown"; keywords: "clown face" }
        ListElement { emoji: "👹"; name: "Ogre"; keywords: "ogre monster face" }
        ListElement { emoji: "👺"; name: "Goblin"; keywords: "goblin face" }
        ListElement { emoji: "👻"; name: "Ghost"; keywords: "ghost face" }
        ListElement { emoji: "👽"; name: "Alien"; keywords: "alien face" }
        ListElement { emoji: "🤖"; name: "Robot"; keywords: "robot face" }
        ListElement { emoji: "😺"; name: "Cat smile"; keywords: "cat smile face" }
        ListElement { emoji: "😸"; name: "Cat grin"; keywords: "cat grin face" }
        ListElement { emoji: "😻"; name: "Cat heart eyes"; keywords: "cat heart eyes love face" }
        ListElement { emoji: "😼"; name: "Cat smirk"; keywords: "cat smirk face" }
        ListElement { emoji: "😽"; name: "Cat kiss"; keywords: "cat kiss face" }
        ListElement { emoji: "🙀"; name: "Cat scream"; keywords: "cat scream face" }
        ListElement { emoji: "😿"; name: "Cat cry"; keywords: "cat cry face" }
        ListElement { emoji: "😾"; name: "Cat pout"; keywords: "cat pout face" }

        // ── Gestures & body ──
        ListElement { emoji: "👋"; name: "Wave"; keywords: "wave hand hello hi bye" }
        ListElement { emoji: "🤚"; name: "Raised back hand"; keywords: "raised back hand stop" }
        ListElement { emoji: "🖐️"; name: "Hand fingers splayed"; keywords: "hand fingers splayed" }
        ListElement { emoji: "✋"; name: "Stop"; keywords: "stop hand raised" }
        ListElement { emoji: "🖖"; name: "Vulcan"; keywords: "vulcan live long spock" }
        ListElement { emoji: "👌"; name: "Ok"; keywords: "ok okay hand yes" }
        ListElement { emoji: "🤌"; name: "Pinched fingers"; keywords: "pinched fingers italian" }
        ListElement { emoji: "🤏"; name: "Pinching"; keywords: "pinching small" }
        ListElement { emoji: "✌️"; name: "Peace"; keywords: "peace victory two fingers" }
        ListElement { emoji: "🤞"; name: "Crossed fingers"; keywords: "crossed fingers luck hope" }
        ListElement { emoji: "🤟"; name: "Love you"; keywords: "love you hand" }
        ListElement { emoji: "🤘"; name: "Rock"; keywords: "rock horns hand" }
        ListElement { emoji: "🤙"; name: "Call me"; keywords: "call me hand" }
        ListElement { emoji: "👈"; name: "Point left"; keywords: "point left" }
        ListElement { emoji: "👉"; name: "Point right"; keywords: "point right" }
        ListElement { emoji: "👆"; name: "Point up"; keywords: "point up" }
        ListElement { emoji: "👇"; name: "Point down"; keywords: "point down" }
        ListElement { emoji: "☝️"; name: "Index up"; keywords: "index up one" }
        ListElement { emoji: "👍"; name: "Thumbs up"; keywords: "thumbs up yes like +1 approve" }
        ListElement { emoji: "👎"; name: "Thumbs down"; keywords: "thumbs down no dislike -1 disapprove" }
        ListElement { emoji: "✊"; name: "Fist"; keywords: "fist raised" }
        ListElement { emoji: "👊"; name: "Punch"; keywords: "punch fist bump" }
        ListElement { emoji: "🤛"; name: "Fist left"; keywords: "fist left" }
        ListElement { emoji: "🤜"; name: "Fist right"; keywords: "fist right" }
        ListElement { emoji: "👏"; name: "Clap"; keywords: "clap applause hands" }
        ListElement { emoji: "🙌"; name: "Raised hands"; keywords: "raised hands praise" }
        ListElement { emoji: "👐"; name: "Open hands"; keywords: "open hands" }
        ListElement { emoji: "🤲"; name: "Palms together"; keywords: "palms together pray" }
        ListElement { emoji: "🤝"; name: "Handshake"; keywords: "handshake deal agreement" }
        ListElement { emoji: "🙏"; name: "Pray"; keywords: "pray thanks please hands" }
        ListElement { emoji: "✍️"; name: "Writing"; keywords: "writing hand" }
        ListElement { emoji: "💅"; name: "Nail polish"; keywords: "nail polish manicure" }
        ListElement { emoji: "🤳"; name: "Selfie"; keywords: "selfie" }
        ListElement { emoji: "💪"; name: "Muscle"; keywords: "muscle strong arm flex" }
        ListElement { emoji: "🦵"; name: "Leg"; keywords: "leg" }
        ListElement { emoji: "🦶"; name: "Foot"; keywords: "foot" }
        ListElement { emoji: "👂"; name: "Ear"; keywords: "ear" }
        ListElement { emoji: "👃"; name: "Nose"; keywords: "nose" }
        ListElement { emoji: "🧠"; name: "Brain"; keywords: "brain mind" }
        ListElement { emoji: "🦷"; name: "Tooth"; keywords: "tooth" }
        ListElement { emoji: "👀"; name: "Eyes"; keywords: "eyes look" }
        ListElement { emoji: "👁️"; name: "Eye"; keywords: "eye" }
        ListElement { emoji: "👅"; name: "Tongue"; keywords: "tongue" }
        ListElement { emoji: "👄"; name: "Mouth"; keywords: "mouth lips" }

        // ── Hearts & symbols ──
        ListElement { emoji: "❤️"; name: "Red heart"; keywords: "red heart love" }
        ListElement { emoji: "🧡"; name: "Orange heart"; keywords: "orange heart love" }
        ListElement { emoji: "💛"; name: "Yellow heart"; keywords: "yellow heart love" }
        ListElement { emoji: "💚"; name: "Green heart"; keywords: "green heart love" }
        ListElement { emoji: "💙"; name: "Blue heart"; keywords: "blue heart love" }
        ListElement { emoji: "💜"; name: "Purple heart"; keywords: "purple heart love" }
        ListElement { emoji: "🖤"; name: "Black heart"; keywords: "black heart love" }
        ListElement { emoji: "🤍"; name: "White heart"; keywords: "white heart love" }
        ListElement { emoji: "🤎"; name: "Brown heart"; keywords: "brown heart love" }
        ListElement { emoji: "💔"; name: "Broken heart"; keywords: "broken heart sad love" }
        ListElement { emoji: "❣️"; name: "Heart exclamation"; keywords: "heart exclamation love" }
        ListElement { emoji: "💕"; name: "Two hearts"; keywords: "two hearts love" }
        ListElement { emoji: "💞"; name: "Revolving hearts"; keywords: "revolving hearts love" }
        ListElement { emoji: "💓"; name: "Heartbeat"; keywords: "heartbeat heart love" }
        ListElement { emoji: "💗"; name: "Growing heart"; keywords: "growing heart love" }
        ListElement { emoji: "💖"; name: "Sparkling heart"; keywords: "sparkling heart love" }
        ListElement { emoji: "💘"; name: "Heart arrow"; keywords: "heart arrow cupid love" }
        ListElement { emoji: "💝"; name: "Gift heart"; keywords: "gift heart love" }
        ListElement { emoji: "💟"; name: "Heart decoration"; keywords: "heart decoration love" }
        ListElement { emoji: "♥️"; name: "Heart suit"; keywords: "heart suit cards love" }
        ListElement { emoji: "💌"; name: "Love letter"; keywords: "love letter" }
        ListElement { emoji: "💤"; name: "Zzz"; keywords: "zzz sleep" }
        ListElement { emoji: "💢"; name: "Anger"; keywords: "anger" }
        ListElement { emoji: "💣"; name: "Bomb"; keywords: "bomb" }
        ListElement { emoji: "💥"; name: "Collision"; keywords: "collision explosion boom" }
        ListElement { emoji: "💦"; name: "Sweat droplets"; keywords: "sweat droplets water" }
        ListElement { emoji: "💨"; name: "Dash"; keywords: "dash wind fast" }
        ListElement { emoji: "🕳️"; name: "Hole"; keywords: "hole" }
        ListElement { emoji: "💬"; name: "Speech balloon"; keywords: "speech balloon chat" }
        ListElement { emoji: "👁️‍🗨️"; name: "Eye in bubble"; keywords: "eye speech bubble witness" }
        ListElement { emoji: "🗯️"; name: "Anger bubble"; keywords: "anger right bubble" }
        ListElement { emoji: "💭"; name: "Thought"; keywords: "thought balloon thinking" }

        // ── Animals & nature ──
        ListElement { emoji: "🐶"; name: "Dog face"; keywords: "dog puppy face" }
        ListElement { emoji: "🐱"; name: "Cat face"; keywords: "cat kitten face" }
        ListElement { emoji: "🐭"; name: "Mouse face"; keywords: "mouse face" }
        ListElement { emoji: "🐹"; name: "Hamster"; keywords: "hamster face" }
        ListElement { emoji: "🐰"; name: "Rabbit face"; keywords: "rabbit bunny face" }
        ListElement { emoji: "🦊"; name: "Fox"; keywords: "fox face" }
        ListElement { emoji: "🐻"; name: "Bear"; keywords: "bear face" }
        ListElement { emoji: "🐼"; name: "Panda"; keywords: "panda face" }
        ListElement { emoji: "🐨"; name: "Koala"; keywords: "koala face" }
        ListElement { emoji: "🐯"; name: "Tiger face"; keywords: "tiger face" }
        ListElement { emoji: "🦁"; name: "Lion"; keywords: "lion face" }
        ListElement { emoji: "🐮"; name: "Cow face"; keywords: "cow face" }
        ListElement { emoji: "🐷"; name: "Pig face"; keywords: "pig face" }
        ListElement { emoji: "🐸"; name: "Frog"; keywords: "frog face" }
        ListElement { emoji: "🐵"; name: "Monkey face"; keywords: "monkey face" }
        ListElement { emoji: "🐔"; name: "Chicken"; keywords: "chicken face" }
        ListElement { emoji: "🐧"; name: "Penguin"; keywords: "penguin" }
        ListElement { emoji: "🐦"; name: "Bird"; keywords: "bird" }
        ListElement { emoji: "🐤"; name: "Chick"; keywords: "chick baby bird" }
        ListElement { emoji: "🦆"; name: "Duck"; keywords: "duck" }
        ListElement { emoji: "🦅"; name: "Eagle"; keywords: "eagle" }
        ListElement { emoji: "🦉"; name: "Owl"; keywords: "owl" }
        ListElement { emoji: "bat"; name: "Bat"; keywords: "bat" }
        ListElement { emoji: "🐺"; name: "Wolf"; keywords: "wolf face" }
        ListElement { emoji: "🐗"; name: "Boar"; keywords: "boar pig" }
        ListElement { emoji: "🐴"; name: "Horse face"; keywords: "horse face" }
        ListElement { emoji: "🦄"; name: "Unicorn"; keywords: "unicorn" }
        ListElement { emoji: "🐝"; name: "Bee"; keywords: "bee" }
        ListElement { emoji: "🐛"; name: "Bug"; keywords: "bug worm" }
        ListElement { emoji: "🦋"; name: "Butterfly"; keywords: "butterfly" }
        ListElement { emoji: "🐌"; name: "Snail"; keywords: "snail" }
        ListElement { emoji: "🐞"; name: "Ladybug"; keywords: "ladybug" }
        ListElement { emoji: "🐜"; name: "Ant"; keywords: "ant" }
        ListElement { emoji: "🦗"; name: "Cricket"; keywords: "cricket" }
        ListElement { emoji: "🕷️"; name: "Spider"; keywords: "spider" }
        ListElement { emoji: "🦂"; name: "Scorpion"; keywords: "scorpion" }
        ListElement { emoji: "🦟"; name: "Mosquito"; keywords: "mosquito" }
        ListElement { emoji: "🦠"; name: "Microbe"; keywords: "microbe germ" }
        ListElement { emoji: "🐢"; name: "Turtle"; keywords: "turtle" }
        ListElement { emoji: "🐍"; name: "Snake"; keywords: "snake serpent" }
        ListElement { emoji: "🦎"; name: "Lizard"; keywords: "lizard" }
        ListElement { emoji: "🦖"; name: "T-rex"; keywords: "t-rex dinosaur" }
        ListElement { emoji: "🦕"; name: "Sauropod"; keywords: "sauropod dinosaur" }
        ListElement { emoji: "🐙"; name: "Octopus"; keywords: "octopus" }
        ListElement { emoji: "🦑"; name: "Squid"; keywords: "squid" }
        ListElement { emoji: "🦐"; name: "Shrimp"; keywords: "shrimp" }
        ListElement { emoji: "🦞"; name: "Lobster"; keywords: "lobster" }
        ListElement { emoji: "🦀"; name: "Crab"; keywords: "crab" }
        ListElement { emoji: "🐡"; name: "Blowfish"; keywords: "blowfish fish" }
        ListElement { emoji: "🐠"; name: "Tropical fish"; keywords: "tropical fish" }
        ListElement { emoji: "🐟"; name: "Fish"; keywords: "fish" }
        ListElement { emoji: "🐬"; name: "Dolphin"; keywords: "dolphin" }
        ListElement { emoji: "🐳"; name: "Spout whale"; keywords: "whale spout" }
        ListElement { emoji: "🐋"; name: "Whale"; keywords: "whale" }
        ListElement { emoji: "🦈"; name: "Shark"; keywords: "shark" }
        ListElement { emoji: "🐊"; name: "Crocodile"; keywords: "crocodile" }
        ListElement { emoji: "🐅"; name: "Tiger"; keywords: "tiger" }
        ListElement { emoji: "🐆"; name: "Leopard"; keywords: "leopard" }
        ListElement { emoji: "🦓"; name: "Zebra"; keywords: "zebra" }
        ListElement { emoji: "🦍"; name: "Gorilla"; keywords: "gorilla" }
        ListElement { emoji: "🦧"; name: "Orangutan"; keywords: "orangutan" }
        ListElement { emoji: "🐘"; name: "Elephant"; keywords: "elephant" }
        ListElement { emoji: "🦛"; name: "Hippo"; keywords: "hippo" }
        ListElement { emoji: "🦏"; name: "Rhino"; keywords: "rhino" }
        ListElement { emoji: "🐪"; name: "Camel"; keywords: "camel" }
        ListElement { emoji: "🐫"; name: "Two-hump camel"; keywords: "camel two hump" }
        ListElement { emoji: "🦒"; name: "Giraffe"; keywords: "giraffe" }
        ListElement { emoji: "🦘"; name: "Kangaroo"; keywords: "kangaroo" }
        ListElement { emoji: "🐃"; name: "Water buffalo"; keywords: "water buffalo" }
        ListElement { emoji: "🐂"; name: "Ox"; keywords: "ox" }
        ListElement { emoji: "🐄"; name: "Cow"; keywords: "cow" }
        ListElement { emoji: "🐎"; name: "Horse"; keywords: "horse" }
        ListElement { emoji: "🐖"; name: "Pig"; keywords: "pig" }
        ListElement { emoji: "🐏"; name: "Ram"; keywords: "ram" }
        ListElement { emoji: "🐑"; name: "Sheep"; keywords: "sheep" }
        ListElement { emoji: "🐐"; name: "Goat"; keywords: "goat" }
        ListElement { emoji: "🦙"; name: "Llama"; keywords: "llama" }
        ListElement { emoji: "🐕"; name: "Dog"; keywords: "dog" }
        ListElement { emoji: "🐩"; name: "Poodle"; keywords: "poodle dog" }
        ListElement { emoji: "🦮"; name: "Guide dog"; keywords: "guide dog" }
        ListElement { emoji: "🐈"; name: "Cat"; keywords: "cat" }
        ListElement { emoji: "🐓"; name: "Rooster"; keywords: "rooster" }
        ListElement { emoji: "🦃"; name: "Turkey"; keywords: "turkey" }
        ListElement { emoji: "🦚"; name: "Peacock"; keywords: "peacock" }
        ListElement { emoji: "🦜"; name: "Parrot"; keywords: "parrot" }
        ListElement { emoji: "🦢"; name: "Swan"; keywords: "swan" }
        ListElement { emoji: "🕊️"; name: "Dove"; keywords: "dove peace" }
        ListElement { emoji: "🐇"; name: "Rabbit"; keywords: "rabbit bunny" }
        ListElement { emoji: "🦝"; name: "Raccoon"; keywords: "raccoon" }
        ListElement { emoji: "🦨"; name: "Skunk"; keywords: "skunk" }
        ListElement { emoji: "🦡"; name: "Badger"; keywords: "badger" }
        ListElement { emoji: "🦦"; name: "Otter"; keywords: "otter" }
        ListElement { emoji: "🦥"; name: "Sloth"; keywords: "sloth" }
        ListElement { emoji: "🐁"; name: "Mouse"; keywords: "mouse" }
        ListElement { emoji: "🐀"; name: "Rat"; keywords: "rat" }
        ListElement { emoji: "🐿️"; name: "Chipmunk"; keywords: "chipmunk squirrel" }
        ListElement { emoji: "🦔"; name: "Hedgehog"; keywords: "hedgehog" }
        ListElement { emoji: "🐾"; name: "Paw prints"; keywords: "paw prints animal" }
        ListElement { emoji: "🐉"; name: "Dragon"; keywords: "dragon" }
        ListElement { emoji: "🐲"; name: "Dragon face"; keywords: "dragon face" }
        ListElement { emoji: "🌵"; name: "Cactus"; keywords: "cactus" }
        ListElement { emoji: "🎄"; name: "Christmas tree"; keywords: "christmas tree" }
        ListElement { emoji: "🌲"; name: "Evergreen"; keywords: "evergreen tree" }
        ListElement { emoji: "🌳"; name: "Deciduous"; keywords: "deciduous tree" }
        ListElement { emoji: "🌴"; name: "Palm"; keywords: "palm tree" }
        ListElement { emoji: "🌱"; name: "Seedling"; keywords: "seedling plant" }
        ListElement { emoji: "🌿"; name: "Herb"; keywords: "herb plant" }
        ListElement { emoji: "☘️"; name: "Shamrock"; keywords: "shamrock clover" }
        ListElement { emoji: "🍀"; name: "Four leaf"; keywords: "four leaf clover luck" }
        ListElement { emoji: "🍁"; name: "Maple leaf"; keywords: "maple leaf" }
        ListElement { emoji: "🍂"; name: "Fallen leaf"; keywords: "fallen leaf autumn" }
        ListElement { emoji: "🍃"; name: "Leaf"; keywords: "leaf wind" }
        ListElement { emoji: "🌺"; name: "Hibiscus"; keywords: "hibiscus flower" }
        ListElement { emoji: "🌸"; name: "Cherry blossom"; keywords: "cherry blossom flower" }
        ListElement { emoji: "🌼"; name: "Blossom"; keywords: "blossom flower" }
        ListElement { emoji: "🌷"; name: "Tulip"; keywords: "tulip flower" }
        ListElement { emoji: "🌹"; name: "Rose"; keywords: "rose flower love" }
        ListElement { emoji: "🥀"; name: "Wilted flower"; keywords: "wilted flower" }
        ListElement { emoji: "🌻"; name: "Sunflower"; keywords: "sunflower" }
        ListElement { emoji: "💐"; name: "Bouquet"; keywords: "bouquet flowers" }
        ListElement { emoji: "🍄"; name: "Mushroom"; keywords: "mushroom" }
        ListElement { emoji: "🌍"; name: "Globe Europe"; keywords: "globe earth europe" }
        ListElement { emoji: "🌎"; name: "Globe Americas"; keywords: "globe earth americas" }
        ListElement { emoji: "🌏"; name: "Globe Asia"; keywords: "globe earth asia" }
        ListElement { emoji: "🌕"; name: "Full moon"; keywords: "full moon" }
        ListElement { emoji: "🌙"; name: "Crescent moon"; keywords: "crescent moon" }
        ListElement { emoji: "🌙"; name: "Crescent moon"; keywords: "crescent moon night" }
        ListElement { emoji: "🌌"; name: "Milky way"; keywords: "milky way galaxy" }
        ListElement { emoji: "⭐"; name: "Star"; keywords: "star" }
        ListElement { emoji: "🌟"; name: "Glowing star"; keywords: "glowing star" }
        ListElement { emoji: "✨"; name: "Sparkles"; keywords: "sparkles shine" }
        ListElement { emoji: "⚡"; name: "Lightning"; keywords: "lightning bolt" }
        ListElement { emoji: "🔥"; name: "Fire"; keywords: "fire flame hot lit" }
        ListElement { emoji: "💧"; name: "Droplet"; keywords: "droplet water" }
        ListElement { emoji: "❄️"; name: "Snowflake"; keywords: "snowflake cold winter" }
        ListElement { emoji: "☀️"; name: "Sun"; keywords: "sun sunny" }
        ListElement { emoji: "🌤️"; name: "Sun cloud"; keywords: "sun behind cloud" }
        ListElement { emoji: "⛅"; name: "Partly cloudy"; keywords: "partly cloudy" }
        ListElement { emoji: "☁️"; name: "Cloud"; keywords: "cloud" }
        ListElement { emoji: "🌧️"; name: "Rain cloud"; keywords: "rain cloud" }
        ListElement { emoji: "⛈️"; name: "Thunder cloud"; keywords: "thunder rain cloud" }
        ListElement { emoji: "🌪️"; name: "Tornado"; keywords: "tornado" }
        ListElement { emoji: "🌫️"; name: "Fog"; keywords: "fog" }
        ListElement { emoji: "🌈"; name: "Rainbow"; keywords: "rainbow" }
        ListElement { emoji: "⛱️"; name: "Umbrella ground"; keywords: "umbrella on ground beach" }

        // ── Food & drink ──
        ListElement { emoji: "🍏"; name: "Green apple"; keywords: "green apple" }
        ListElement { emoji: "🍎"; name: "Red apple"; keywords: "red apple" }
        ListElement { emoji: "🍐"; name: "Pear"; keywords: "pear" }
        ListElement { emoji: "🍊"; name: "Orange"; keywords: "orange tangerine" }
        ListElement { emoji: "🍋"; name: "Lemon"; keywords: "lemon" }
        ListElement { emoji: "🍌"; name: "Banana"; keywords: "banana" }
        ListElement { emoji: "🍉"; name: "Watermelon"; keywords: "watermelon" }
        ListElement { emoji: "🍇"; name: "Grapes"; keywords: "grapes" }
        ListElement { emoji: "🍓"; name: "Strawberry"; keywords: "strawberry" }
        ListElement { emoji: "🍈"; name: "Melon"; keywords: "melon" }
        ListElement { emoji: "🍒"; name: "Cherries"; keywords: "cherries" }
        ListElement { emoji: "🍑"; name: "Peach"; keywords: "peach" }
        ListElement { emoji: "🥭"; name: "Mango"; keywords: "mango" }
        ListElement { emoji: "🍍"; name: "Pineapple"; keywords: "pineapple" }
        ListElement { emoji: "🥥"; name: "Coconut"; keywords: "coconut" }
        ListElement { emoji: "🥝"; name: "Kiwi"; keywords: "kiwi" }
        ListElement { emoji: "🍅"; name: "Tomato"; keywords: "tomato" }
        ListElement { emoji: "🍆"; name: "Eggplant"; keywords: "eggplant aubergine" }
        ListElement { emoji: "🥑"; name: "Avocado"; keywords: "avocado" }
        ListElement { emoji: "🥦"; name: "Broccoli"; keywords: "broccoli" }
        ListElement { emoji: "🥬"; name: "Leafy green"; keywords: "leafy green lettuce" }
        ListElement { emoji: "🥒"; name: "Cucumber"; keywords: "cucumber" }
        ListElement { emoji: "🌶️"; name: "Hot pepper"; keywords: "hot pepper chilli" }
        ListElement { emoji: "🌽"; name: "Corn"; keywords: "corn" }
        ListElement { emoji: "🥕"; name: "Carrot"; keywords: "carrot" }
        ListElement { emoji: "🧄"; name: "Garlic"; keywords: "garlic" }
        ListElement { emoji: "🧅"; name: "Onion"; keywords: "onion" }
        ListElement { emoji: "🥔"; name: "Potato"; keywords: "potato" }
        ListElement { emoji: "🍠"; name: "Sweet potato"; keywords: "sweet potato" }
        ListElement { emoji: "🥐"; name: "Croissant"; keywords: "croissant" }
        ListElement { emoji: "🍞"; name: "Bread"; keywords: "bread loaf" }
        ListElement { emoji: "🥖"; name: "Baguette"; keywords: "baguette bread" }
        ListElement { emoji: "🧀"; name: "Cheese"; keywords: "cheese" }
        ListElement { emoji: "🥚"; name: "Egg"; keywords: "egg" }
        ListElement { emoji: "🍳"; name: "Fried egg"; keywords: "fried egg cooking" }
        ListElement { emoji: "🧇"; name: "Waffle"; keywords: "waffle" }
        ListElement { emoji: "🥞"; name: "Pancakes"; keywords: "pancakes" }
        ListElement { emoji: "🥓"; name: "Bacon"; keywords: "bacon" }
        ListElement { emoji: "🍔"; name: "Burger"; keywords: "burger hamburger" }
        ListElement { emoji: "🍟"; name: "Fries"; keywords: "fries chips" }
        ListElement { emoji: "🍕"; name: "Pizza"; keywords: "pizza" }
        ListElement { emoji: "🌭"; name: "Hot dog"; keywords: "hot dog" }
        ListElement { emoji: "🥪"; name: "Sandwich"; keywords: "sandwich" }
        ListElement { emoji: "🌮"; name: "Taco"; keywords: "taco" }
        ListElement { emoji: "🌯"; name: "Burrito"; keywords: "burrito" }
        ListElement { emoji: "🥙"; name: "Pita"; keywords: "pita wrap" }
        ListElement { emoji: "🧆"; name: "Falafel"; keywords: "falafel" }
        ListElement { emoji: "🥗"; name: "Salad"; keywords: "salad green" }
        ListElement { emoji: "🍝"; name: "Spaghetti"; keywords: "spaghetti pasta" }
        ListElement { emoji: "🍜"; name: "Noodles"; keywords: "noodles ramen" }
        ListElement { emoji: "🍲"; name: "Pot of food"; keywords: "pot food stew" }
        ListElement { emoji: "🍛"; name: "Curry"; keywords: "curry rice" }
        ListElement { emoji: "🍣"; name: "Sushi"; keywords: "sushi" }
        ListElement { emoji: "🍱"; name: "Bento"; keywords: "bento box" }
        ListElement { emoji: "🥟"; name: "Dumpling"; keywords: "dumpling" }
        ListElement { emoji: "🍤"; name: "Fried shrimp"; keywords: "fried shrimp tempura" }
        ListElement { emoji: "🍙"; name: "Rice ball"; keywords: "rice ball onigiri" }
        ListElement { emoji: "🍚"; name: "Rice"; keywords: "rice bowl" }
        ListElement { emoji: "🍘"; name: "Rice cracker"; keywords: "rice cracker" }
        ListElement { emoji: "🍥"; name: "Fish cake"; keywords: "fish cake" }
        ListElement { emoji: "🥮"; name: "Moon cake"; keywords: "moon cake" }
        ListElement { emoji: "🍢"; name: "Oden"; keywords: "oden skewer" }
        ListElement { emoji: "🍡"; name: "Dango"; keywords: "dango" }
        ListElement { emoji: "🍧"; name: "Shaved ice"; keywords: "shaved ice" }
        ListElement { emoji: "🍨"; name: "Ice cream"; keywords: "ice cream" }
        ListElement { emoji: "🍦"; name: "Soft ice"; keywords: "soft ice cream" }
        ListElement { emoji: "🥧"; name: "Pie"; keywords: "pie" }
        ListElement { emoji: "🧁"; name: "Cupcake"; keywords: "cupcake" }
        ListElement { emoji: "🎂"; name: "Birthday cake"; keywords: "birthday cake" }
        ListElement { emoji: "🍰"; name: "Cake"; keywords: "cake slice" }
        ListElement { emoji: "🍮"; name: "Pudding"; keywords: "pudding custard" }
        ListElement { emoji: "🍭"; name: "Lollipop"; keywords: "lollipop" }
        ListElement { emoji: "🍬"; name: "Candy"; keywords: "candy" }
        ListElement { emoji: "🍫"; name: "Chocolate"; keywords: "chocolate bar" }
        ListElement { emoji: "🍿"; name: "Popcorn"; keywords: "popcorn" }
        ListElement { emoji: "🍩"; name: "Doughnut"; keywords: "doughnut donut" }
        ListElement { emoji: "🍪"; name: "Cookie"; keywords: "cookie" }
        ListElement { emoji: "🌰"; name: "Chestnut"; keywords: "chestnut" }
        ListElement { emoji: "🥜"; name: "Peanuts"; keywords: "peanuts" }
        ListElement { emoji: "🍯"; name: "Honey"; keywords: "honey pot" }
        ListElement { emoji: "🥛"; name: "Milk"; keywords: "milk glass" }
        ListElement { emoji: "☕"; name: "Coffee"; keywords: "coffee drink hot" }
        ListElement { emoji: "🍵"; name: "Tea"; keywords: "tea drink green" }
        ListElement { emoji: "🧃"; name: "Juice box"; keywords: "juice box" }
        ListElement { emoji: "🥤"; name: "Cup straw"; keywords: "cup straw soda" }
        ListElement { emoji: "🧋"; name: "Bubble tea"; keywords: "bubble tea boba" }
        ListElement { emoji: "🍶"; name: "Sake"; keywords: "sake" }
        ListElement { emoji: "🍺"; name: "Beer"; keywords: "beer mug" }
        ListElement { emoji: "🍻"; name: "Beers"; keywords: "beers cheers" }
        ListElement { emoji: "🥂"; name: "Clink glasses"; keywords: "clink glasses cheers" }
        ListElement { emoji: "🍷"; name: "Wine"; keywords: "wine glass" }
        ListElement { emoji: "🥃"; name: "Tumbler"; keywords: "tumbler whisky" }
        ListElement { emoji: "🍸"; name: "Cocktail"; keywords: "cocktail martini" }
        ListElement { emoji: "🍹"; name: "Tropical drink"; keywords: "tropical drink" }
        ListElement { emoji: "🍾"; name: "Champagne"; keywords: "champagne bottle pop" }
        ListElement { emoji: "🧊"; name: "Ice"; keywords: "ice cube" }
        ListElement { emoji: "🥄"; name: "Spoon"; keywords: "spoon" }
        ListElement { emoji: "🍴"; name: "Fork knife"; keywords: "fork knife" }
        ListElement { emoji: "🍽️"; name: "Plate"; keywords: "plate fork knife" }
        ListElement { emoji: "🥣"; name: "Bowl spoon"; keywords: "bowl spoon" }
        ListElement { emoji: "🥡"; name: "Takeout"; keywords: "takeout box" }
        ListElement { emoji: "🥢"; name: "Chopsticks"; keywords: "chopsticks" }

        // ── Activities & objects ──
        ListElement { emoji: "⚽"; name: "Soccer"; keywords: "soccer football ball" }
        ListElement { emoji: "🏀"; name: "Basketball"; keywords: "basketball ball" }
        ListElement { emoji: "🏈"; name: "Football"; keywords: "football american ball" }
        ListElement { emoji: "⚾"; name: "Baseball"; keywords: "baseball ball" }
        ListElement { emoji: "🥎"; name: "Softball"; keywords: "softball ball" }
        ListElement { emoji: "🎾"; name: "Tennis"; keywords: "tennis ball" }
        ListElement { emoji: "🏐"; name: "Volleyball"; keywords: "volleyball ball" }
        ListElement { emoji: "🏉"; name: "Rugby"; keywords: "rugby football ball" }
        ListElement { emoji: "🥏"; name: "Frisbee"; keywords: "frisbee flying disc" }
        ListElement { emoji: "🎱"; name: "Pool"; keywords: "pool billiards ball 8" }
        ListElement { emoji: "🏓"; name: "Ping pong"; keywords: "ping pong paddle" }
        ListElement { emoji: "🏸"; name: "Badminton"; keywords: "badminton" }
        ListElement { emoji: "🥅"; name: "Goal"; keywords: "goal net" }
        ListElement { emoji: "🏒"; name: "Hockey"; keywords: "hockey ice" }
        ListElement { emoji: "🏑"; name: "Field hockey"; keywords: "field hockey" }
        ListElement { emoji: "🥍"; name: "Lacrosse"; keywords: "lacrosse" }
        ListElement { emoji: "🏏"; name: "Cricket"; keywords: "cricket bat" }
        ListElement { emoji: "⛳"; name: "Golf"; keywords: "golf flag" }
        ListElement { emoji: "🏹"; name: "Bow"; keywords: "bow arrow archery" }
        ListElement { emoji: "🎣"; name: "Fishing"; keywords: "fishing pole" }
        ListElement { emoji: "🥊"; name: "Boxing glove"; keywords: "boxing glove" }
        ListElement { emoji: "🥋"; name: "Martial arts"; keywords: "martial arts uniform" }
        ListElement { emoji: "🎽"; name: "Running shirt"; keywords: "running shirt" }
        ListElement { emoji: "⛸️"; name: "Ice skate"; keywords: "ice skate" }
        ListElement { emoji: "🥌"; name: "Curling stone"; keywords: "curling stone" }
        ListElement { emoji: "🛷"; name: "Sled"; keywords: "sled" }
        ListElement { emoji: "🎿"; name: "Ski"; keywords: "ski skis" }
        ListElement { emoji: "⛷️"; name: "Skier"; keywords: "skier" }
        ListElement { emoji: "🏂"; name: "Snowboarder"; keywords: "snowboarder" }
        ListElement { emoji: "🤺"; name: "Fencer"; keywords: "fencer fencing" }
        ListElement { emoji: "🤼"; name: "Wrestlers"; keywords: "wrestlers" }
        ListElement { emoji: "🤸"; name: "Cartwheel"; keywords: "cartwheel" }
        ListElement { emoji: "🤽"; name: "Water polo"; keywords: "water polo" }
        ListElement { emoji: "🤾"; name: "Handball"; keywords: "handball" }
        ListElement { emoji: "🏌️"; name: "Golfer"; keywords: "golfer" }
        ListElement { emoji: "🏇"; name: "Horse racing"; keywords: "horse racing" }
        ListElement { emoji: "🧘"; name: "Lotus"; keywords: "lotus position meditation yoga" }
        ListElement { emoji: "🏄"; name: "Surfer"; keywords: "surfer surfing" }
        ListElement { emoji: "🏊"; name: "Swimmer"; keywords: "swimmer swimming" }
        ListElement { emoji: "🤿"; name: "Diving mask"; keywords: "diving mask snorkel" }
        ListElement { emoji: "🚣"; name: "Rowing"; keywords: "rowing boat" }
        ListElement { emoji: "🧗"; name: "Climber"; keywords: "climber" }
        ListElement { emoji: "🚵"; name: "Mountain bike"; keywords: "mountain bike cyclist" }
        ListElement { emoji: "🚴"; name: "Bike"; keywords: "bicycle cyclist" }
        ListElement { emoji: "🏆"; name: "Trophy"; keywords: "trophy win" }
        ListElement { emoji: "🥇"; name: "Gold"; keywords: "gold medal first" }
        ListElement { emoji: "🥈"; name: "Silver"; keywords: "silver medal second" }
        ListElement { emoji: "🥉"; name: "Bronze"; keywords: "bronze medal third" }
        ListElement { emoji: "🏅"; name: "Medal"; keywords: "medal sports" }
        ListElement { emoji: "🎖️"; name: "Military medal"; keywords: "military medal" }
        ListElement { emoji: "🏵️"; name: "Rosette"; keywords: "rosette" }
        ListElement { emoji: "🎗️"; name: "Ribbon"; keywords: "reminder ribbon" }
        ListElement { emoji: "🎫"; name: "Ticket"; keywords: "ticket admission" }
        ListElement { emoji: "🎟️"; name: "Admission"; keywords: "admission tickets" }
        ListElement { emoji: "🎪"; name: "Circus"; keywords: "circus tent" }
        ListElement { emoji: "🎭"; name: "Theatre"; keywords: "theatre masks" }
        ListElement { emoji: "🎨"; name: "Art"; keywords: "art palette paint" }
        ListElement { emoji: "🎬"; name: "Clapper"; keywords: "clapper board movie" }
        ListElement { emoji: "🎤"; name: "Microphone"; keywords: "microphone mic karaoke" }
        ListElement { emoji: "🎧"; name: "Headphones"; keywords: "headphones music" }
        ListElement { emoji: "🎼"; name: "Score"; keywords: "musical score" }
        ListElement { emoji: "🎹"; name: "Piano"; keywords: "piano keyboard" }
        ListElement { emoji: "🥁"; name: "Drum"; keywords: "drum" }
        ListElement { emoji: "🎷"; name: "Sax"; keywords: "saxophone" }
        ListElement { emoji: "🎺"; name: "Trumpet"; keywords: "trumpet" }
        ListElement { emoji: "🎸"; name: "Guitar"; keywords: "guitar" }
        ListElement { emoji: "🪕"; name: "Banjo"; keywords: "banjo" }
        ListElement { emoji: "🎻"; name: "Violin"; keywords: "violin" }
        ListElement { emoji: "🎲"; name: "Dice"; keywords: "dice game" }
        ListElement { emoji: "♟️"; name: "Chess pawn"; keywords: "chess pawn" }
        ListElement { emoji: "🎯"; name: "Bullseye"; keywords: "bullseye dart direct hit" }
        ListElement { emoji: "🎳"; name: "Bowling"; keywords: "bowling" }
        ListElement { emoji: "🎮"; name: "Game controller"; keywords: "video game controller" }
        ListElement { emoji: "🎰"; name: "Slot machine"; keywords: "slot machine" }
        ListElement { emoji: "🧩"; name: "Puzzle"; keywords: "puzzle piece" }

        // ── Travel & places ──
        ListElement { emoji: "🚗"; name: "Car"; keywords: "car" }
        ListElement { emoji: "🚕"; name: "Taxi"; keywords: "taxi cab" }
        ListElement { emoji: "🚙"; name: "SUV"; keywords: "suv car" }
        ListElement { emoji: "🚌"; name: "Bus"; keywords: "bus" }
        ListElement { emoji: "🚎"; name: "Trolleybus"; keywords: "trolleybus" }
        ListElement { emoji: "🏎️"; name: "Race car"; keywords: "racing car" }
        ListElement { emoji: "🚓"; name: "Police car"; keywords: "police car" }
        ListElement { emoji: "🚑"; name: "Ambulance"; keywords: "ambulance" }
        ListElement { emoji: "🚒"; name: "Fire engine"; keywords: "fire engine truck" }
        ListElement { emoji: "🚐"; name: "Minibus"; keywords: "minibus" }
        ListElement { emoji: "🛻"; name: "Pickup"; keywords: "pickup truck" }
        ListElement { emoji: "🚚"; name: "Truck"; keywords: "truck delivery" }
        ListElement { emoji: "🚛"; name: "Semi"; keywords: "semi truck lorry" }
        ListElement { emoji: "🚜"; name: "Tractor"; keywords: "tractor" }
        ListElement { emoji: "🏍️"; name: "Motorcycle"; keywords: "motorcycle" }
        ListElement { emoji: "🛵"; name: "Scooter"; keywords: "scooter" }
        ListElement { emoji: "🦽"; name: "Wheelchair"; keywords: "manual wheelchair" }
        ListElement { emoji: "🛺"; name: "Auto rickshaw"; keywords: "auto rickshaw" }
        ListElement { emoji: "🚲"; name: "Bike"; keywords: "bicycle bike" }
        ListElement { emoji: "🛴"; name: "Scooter"; keywords: "kick scooter" }
        ListElement { emoji: "🛹"; name: "Skateboard"; keywords: "skateboard" }
        ListElement { emoji: "🚏"; name: "Bus stop"; keywords: "bus stop" }
        ListElement { emoji: "🛣️"; name: "Motorway"; keywords: "motorway road" }
        ListElement { emoji: "🛤️"; name: "Railway track"; keywords: "railway track" }
        ListElement { emoji: "⛽"; name: "Fuel pump"; keywords: "fuel pump gas" }
        ListElement { emoji: "🚨"; name: "Police light"; keywords: "police car revolving light" }
        ListElement { emoji: "🚥"; name: "Traffic light"; keywords: "horizontal traffic light" }
        ListElement { emoji: "🚦"; name: "Vertical traffic light"; keywords: "vertical traffic light" }
        ListElement { emoji: "🛑"; name: "Stop sign"; keywords: "stop sign" }
        ListElement { emoji: "🚧"; name: "Construction"; keywords: "construction barrier" }
        ListElement { emoji: "⚓"; name: "Anchor"; keywords: "anchor" }
        ListElement { emoji: "⛵"; name: "Sailboat"; keywords: "sailboat" }
        ListElement { emoji: "🛶"; name: "Canoe"; keywords: "canoe" }
        ListElement { emoji: "🚤"; name: "Speedboat"; keywords: "speedboat" }
        ListElement { emoji: "🛳️"; name: "Passenger ship"; keywords: "passenger ship" }
        ListElement { emoji: "⛴️"; name: "Ferry"; keywords: "ferry" }
        ListElement { emoji: "🛥️"; name: "Motor boat"; keywords: "motor boat" }
        ListElement { emoji: "🚢"; name: "Ship"; keywords: "ship" }
        ListElement { emoji: "✈️"; name: "Airplane"; keywords: "airplane plane" }
        ListElement { emoji: "🛩️"; name: "Small airplane"; keywords: "small airplane" }
        ListElement { emoji: "🛫"; name: "Takeoff"; keywords: "airplane takeoff" }
        ListElement { emoji: "🛬"; name: "Landing"; keywords: "airplane landing" }
        ListElement { emoji: "🪂"; name: "Parachute"; keywords: "parachute" }
        ListElement { emoji: "💺"; name: "Seat"; keywords: "seat" }
        ListElement { emoji: "🚁"; name: "Helicopter"; keywords: "helicopter" }
        ListElement { emoji: "🚟"; name: "Suspension railway"; keywords: "suspension railway" }
        ListElement { emoji: "🚠"; name: "Cable car"; keywords: "mountain cableway" }
        ListElement { emoji: "🚡"; name: "Aerial tramway"; keywords: "aerial tramway" }
        ListElement { emoji: "🛰️"; name: "Satellite"; keywords: "satellite" }
        ListElement { emoji: "🚀"; name: "Rocket"; keywords: "rocket launch" }
        ListElement { emoji: "🛸"; name: "UFO"; keywords: "flying saucer" }
        ListElement { emoji: "🛎️"; name: "Bellhop"; keywords: "bellhop bell" }
        ListElement { emoji: "🧳"; name: "Luggage"; keywords: "luggage" }
        ListElement { emoji: ".hourglass"; name: "Hourglass"; keywords: "hourglass time" }

        // ── Objects, symbols, misc ──
        ListElement { emoji: "⌚"; name: "Watch"; keywords: "watch wrist" }
        ListElement { emoji: "📱"; name: "Phone"; keywords: "mobile phone" }
        ListElement { emoji: "💻"; name: "Laptop"; keywords: "laptop computer" }
        ListElement { emoji: "⌨️"; name: "Keyboard"; keywords: "keyboard" }
        ListElement { emoji: "🖥️"; name: "Desktop"; keywords: "desktop computer" }
        ListElement { emoji: "🖨️"; name: "Printer"; keywords: "printer" }
        ListElement { emoji: "🖱️"; name: "Mouse"; keywords: "computer mouse" }
        ListElement { emoji: "💽"; name: "Minidisc"; keywords: "minidisc" }
        ListElement { emoji: "💾"; name: "Floppy"; keywords: "floppy disk save" }
        ListElement { emoji: "💿"; name: "CD"; keywords: "cd optical disc" }
        ListElement { emoji: "📀"; name: "DVD"; keywords: "dvd" }
        ListElement { emoji: "📷"; name: "Camera"; keywords: "camera" }
        ListElement { emoji: "📸"; name: "Camera flash"; keywords: "camera flash" }
        ListElement { emoji: "📹"; name: "Video camera"; keywords: "video camera" }
        ListElement { emoji: "🎥"; name: "Movie camera"; keywords: "movie camera" }
        ListElement { emoji: "📽️"; name: "Projector"; keywords: "film projector" }
        ListElement { emoji: "🎞️"; name: "Film"; keywords: "film frames" }
        ListElement { emoji: "📞"; name: "Phone receiver"; keywords: "telephone receiver" }
        ListElement { emoji: "☎️"; name: "Telephone"; keywords: "telephone" }
        ListElement { emoji: "📟"; name: "Pager"; keywords: "pager" }
        ListElement { emoji: "📠"; name: "Fax"; keywords: "fax machine" }
        ListElement { emoji: "📺"; name: "TV"; keywords: "television tv" }
        ListElement { emoji: "📻"; name: "Radio"; keywords: "radio" }
        ListElement { emoji: "🎙️"; name: "Studio mic"; keywords: "studio microphone" }
        ListElement { emoji: "🎚️"; name: "Level slider"; keywords: "level slider" }
        ListElement { emoji: "🎛️"; name: "Knobs"; keywords: "control knobs" }
        ListElement { emoji: "🧭"; name: "Compass"; keywords: "compass" }
        ListElement { emoji: "⏰"; name: "Alarm"; keywords: "alarm clock" }
        ListElement { emoji: "⏱️"; name: "Stopwatch"; keywords: "stopwatch" }
        ListElement { emoji: "⏲️"; name: "Timer"; keywords: "timer clock" }
        ListElement { emoji: "🕰️"; name: "Mantelpiece clock"; keywords: "mantelpiece clock" }
        ListElement { emoji: "⌛"; name: "Hourglass done"; keywords: "hourglass done time" }
        ListElement { emoji: "🔋"; name: "Battery"; keywords: "battery" }
        ListElement { emoji: "🔌"; name: "Plug"; keywords: "electric plug" }
        ListElement { emoji: "💡"; name: "Bulb"; keywords: "light bulb idea" }
        ListElement { emoji: "🔦"; name: "Flashlight"; keywords: "flashlight" }
        ListElement { emoji: "🕯️"; name: "Candle"; keywords: "candle" }
        ListElement { emoji: "🪔"; name: "Diya lamp"; keywords: "diya lamp oil" }
        ListElement { emoji: "🧯"; name: "Extinguisher"; keywords: "fire extinguisher" }
        ListElement { emoji: "🛢️"; name: "Oil drum"; keywords: "oil drum" }
        ListElement { emoji: "💸"; name: "Money wings"; keywords: "money wings dollar" }
        ListElement { emoji: "💵"; name: "Dollar"; keywords: "dollar banknote" }
        ListElement { emoji: "💶"; name: "Euro"; keywords: "euro banknote" }
        ListElement { emoji: "💷"; name: "Pound"; keywords: "pound banknote" }
        ListElement { emoji: "💴"; name: "Yen"; keywords: "yen banknote" }
        ListElement { emoji: "💰"; name: "Money bag"; keywords: "money bag" }
        ListElement { emoji: "💳"; name: "Card"; keywords: "credit card" }
        ListElement { emoji: "💎"; name: "Gem"; keywords: "gem stone diamond" }
        ListElement { emoji: "⚖️"; name: "Balance"; keywords: "balance scale justice" }
        ListElement { emoji: "🧰"; name: "Toolbox"; keywords: "toolbox" }
        ListElement { emoji: "🔧"; name: "Wrench"; keywords: "wrench" }
        ListElement { emoji: "🔨"; name: "Hammer"; keywords: "hammer" }
        ListElement { emoji: "🛠️"; name: "Tools"; keywords: "hammer and wrench" }
        ListElement { emoji: "⚙️"; name: "Gear"; keywords: "gear settings" }
        ListElement { emoji: "🧱"; name: "Brick"; keywords: "brick" }
        ListElement { emoji: "⛓️"; name: "Chains"; keywords: "chains" }
        ListElement { emoji: "🧲"; name: "Magnet"; keywords: "magnet" }
        ListElement { emoji: "🔫"; name: "Water pistol"; keywords: "water pistol" }
        ListElement { emoji: "💣"; name: "Bomb"; keywords: "bomb" }
        ListElement { emoji: "🧨"; name: "Firecracker"; keywords: "firecracker" }
        ListElement { emoji: "🪓"; name: "Axe"; keywords: "axe" }
        ListElement { emoji: "🔪"; name: "Knife"; keywords: "knife" }
        ListElement { emoji: "🗡️"; name: "Dagger"; keywords: "dagger" }
        ListElement { emoji: "⚔️"; name: "Swords"; keywords: "crossed swords" }
        ListElement { emoji: "🛡️"; name: "Shield"; keywords: "shield" }
        ListElement { emoji: "🚬"; name: "Smoking"; keywords: "smoking cigarette" }
        ListElement { emoji: "⚰️"; name: "Coffin"; keywords: "coffin" }
        ListElement { emoji: "⚱️"; name: "Urn"; keywords: "funeral urn" }
        ListElement { emoji: "🏺"; name: "Amphora"; keywords: "amphora" }
        ListElement { emoji: "🔮"; name: "Crystal ball"; keywords: "crystal ball" }
        ListElement { emoji: "📿"; name: "Prayer beads"; keywords: "prayer beads" }
        ListElement { emoji: "🧿"; name: "Nazar"; keywords: "nazar amulet" }
        ListElement { emoji: "💈"; name: "Barber pole"; keywords: "barber pole" }
        ListElement { emoji: "⚗️"; name: "Alembic"; keywords: "alembic" }
        ListElement { emoji: "🔭"; name: "Telescope"; keywords: "telescope" }
        ListElement { emoji: "🔬"; name: "Microscope"; keywords: "microscope" }
        ListElement { emoji: "🕳️"; name: "Hole"; keywords: "hole" }
        ListElement { emoji: "💊"; name: "Pill"; keywords: "pill" }
        ListElement { emoji: "💉"; name: "Syringe"; keywords: "syringe needle" }
        ListElement { emoji: "🩸"; name: "Blood"; keywords: "drop of blood" }
        ListElement { emoji: "🩹"; name: "Bandaid"; keywords: "adhesive bandage" }
        ListElement { emoji: "🩺"; name: "Stethoscope"; keywords: "stethoscope" }
        ListElement { emoji: "🚪"; name: "Door"; keywords: "door" }
        ListElement { emoji: "🛏️"; name: "Bed"; keywords: "bed" }
        ListElement { emoji: "🛋️"; name: "Couch"; keywords: "couch and lamp" }
        ListElement { emoji: "🪑"; name: "Chair"; keywords: "chair" }
        ListElement { emoji: "🚽"; name: "Toilet"; keywords: "toilet" }
        ListElement { emoji: "🚿"; name: "Shower"; keywords: "shower" }
        ListElement { emoji: "🛁"; name: "Bathtub"; keywords: "bathtub" }
        ListElement { emoji: "🪒"; name: "Razor"; keywords: "razor" }
        ListElement { emoji: "🧴"; name: "Lotion"; keywords: "lotion bottle" }
        ListElement { emoji: "🧷"; name: "Safety pin"; keywords: "safety pin" }
        ListElement { emoji: "🧹"; name: "Broom"; keywords: "broom" }
        ListElement { emoji: "🧺"; name: "Basket"; keywords: "basket" }
        ListElement { emoji: "🧻"; name: "Paper"; keywords: "roll of paper" }
        ListElement { emoji: "🧼"; name: "Soap"; keywords: "soap" }
        ListElement { emoji: "🧽"; name: "Sponge"; keywords: "sponge" }
        ListElement { emoji: "🛒"; name: "Cart"; keywords: "shopping cart" }
        ListElement { emoji: "🎁"; name: "Gift"; keywords: "gift present" }
        ListElement { emoji: "🎈"; name: "Balloon"; keywords: "balloon" }
        ListElement { emoji: "🎉"; name: "Party"; keywords: "party popper celebrate" }
        ListElement { emoji: "🎊"; name: "Confetti"; keywords: "confetti ball" }
        ListElement { emoji: "🎀"; name: "Ribbon"; keywords: "ribbon" }
        ListElement { emoji: "🎗️"; name: "Ribbon"; keywords: "reminder ribbon" }
        ListElement { emoji: "🎟️"; name: "Tickets"; keywords: "admission tickets" }
        ListElement { emoji: "🎫"; name: "Ticket"; keywords: "ticket" }

        // ── Symbols & arrows ──
        ListElement { emoji: "✅"; name: "Check mark"; keywords: "check mark button yes ok done" }
        ListElement { emoji: "☑️"; name: "Check box"; keywords: "check box with check" }
        ListElement { emoji: "✔️"; name: "Check"; keywords: "check mark" }
        ListElement { emoji: "❌"; name: "Cross mark"; keywords: "cross mark no wrong x" }
        ListElement { emoji: "❎"; name: "Cross button"; keywords: "cross mark button" }
        ListElement { emoji: "➕"; name: "Plus"; keywords: "plus heavy" }
        ListElement { emoji: "➖"; name: "Minus"; keywords: "minus heavy" }
        ListElement { emoji: "➗"; name: "Divide"; keywords: "divide heavy" }
        ListElement { emoji: "✖️"; name: "Multiply"; keywords: "multiply heavy" }
        ListElement { emoji: "🟰"; name: "Equals"; keywords: "heavy equals sign" }
        ListElement { emoji: "♾️"; name: "Infinity"; keywords: "infinity" }
        ListElement { emoji: "❓"; name: "Question"; keywords: "question mark red" }
        ListElement { emoji: "❔"; name: "White question"; keywords: "white question mark" }
        ListElement { emoji: "❗"; name: "Exclamation"; keywords: "exclamation mark red" }
        ListElement { emoji: "❕"; name: "White exclamation"; keywords: "white exclamation mark" }
        ListElement { emoji: "‼️"; name: "Double bang"; keywords: "double exclamation" }
        ListElement { emoji: "⁉️"; name: "Bang question"; keywords: "exclamation question" }
        ListElement { emoji: "💯"; name: "Hundred"; keywords: "hundred points score 100" }
        ListElement { emoji: "🔢"; name: "Numbers"; keywords: "input numbers" }
        ListElement { emoji: "#️⃣"; name: "Hash"; keywords: "keycap hash" }
        ListElement { emoji: "*️⃣"; name: "Asterisk"; keywords: "keycap asterisk" }
        ListElement { emoji: "⏏️"; name: "Eject"; keywords: "eject symbol" }
        ListElement { emoji: "▶️"; name: "Play"; keywords: "play button" }
        ListElement { emoji: "⏸️"; name: "Pause"; keywords: "pause button" }
        ListElement { emoji: "⏯️"; name: "Play pause"; keywords: "play or pause button" }
        ListElement { emoji: "⏹️"; name: "Stop"; keywords: "stop button" }
        ListElement { emoji: "⏺️"; name: "Record"; keywords: "record button" }
        ListElement { emoji: "⏭️"; name: "Next"; keywords: "next track button" }
        ListElement { emoji: "⏮️"; name: "Previous"; keywords: "previous track button" }
        ListElement { emoji: "⏩"; name: "Fast forward"; keywords: "fast forward" }
        ListElement { emoji: "⏪"; name: "Rewind"; keywords: "fast rewind" }
        ListElement { emoji: "🔼"; name: "Up button"; keywords: "upwards button" }
        ListElement { emoji: "🔽"; name: "Down button"; keywords: "downwards button" }
        ListElement { emoji: "⏫"; name: "Double up"; keywords: "fast up button" }
        ListElement { emoji: "⏬"; name: "Double down"; keywords: "fast down button" }
        ListElement { emoji: "⬅️"; name: "Left arrow"; keywords: "left arrow" }
        ListElement { emoji: "➡️"; name: "Right arrow"; keywords: "right arrow" }
        ListElement { emoji: "⬆️"; name: "Up arrow"; keywords: "up arrow" }
        ListElement { emoji: "⬇️"; name: "Down arrow"; keywords: "down arrow" }
        ListElement { emoji: "↗️"; name: "Up-right"; keywords: "up-right arrow" }
        ListElement { emoji: "↘️"; name: "Down-right"; keywords: "down-right arrow" }
        ListElement { emoji: "↙️"; name: "Down-left"; keywords: "down-left arrow" }
        ListElement { emoji: "↖️"; name: "Up-left"; keywords: "up-left arrow" }
        ListElement { emoji: "↕️"; name: "Up-down"; keywords: "up-down arrow" }
        ListElement { emoji: "↔️"; name: "Left-right"; keywords: "left-right arrow" }
        ListElement { emoji: "↩️"; name: "Return"; keywords: "right arrow curving left return" }
        ListElement { emoji: "↪️"; name: "Forward"; keywords: "left arrow curving right" }
        ListElement { emoji: "⤴️"; name: "Up curve"; keywords: "right arrow curving up" }
        ListElement { emoji: "⤵️"; name: "Down curve"; keywords: "right arrow curving down" }
        ListElement { emoji: "🔀"; name: "Shuffle"; keywords: "shuffle tracks" }
        ListElement { emoji: "🔁"; name: "Repeat"; keywords: "repeat button" }
        ListElement { emoji: "🔂"; name: "Repeat one"; keywords: "repeat single button" }
        ListElement { emoji: "🔄"; name: "Anticlockwise"; keywords: "anticlockwise arrows button" }
        ListElement { emoji: "🔃"; name: "Clockwise"; keywords: "clockwise vertical arrows" }
        ListElement { emoji: "🎵"; name: "Note"; keywords: "musical note" }
        ListElement { emoji: "🎶"; name: "Notes"; keywords: "musical notes" }
        ListElement { emoji: "➰"; name: "Loop"; keywords: "curly loop" }
        ListElement { emoji: "➿"; name: "Double loop"; keywords: "double curly loop" }
        ListElement { emoji: "✅"; name: "Check"; keywords: "check mark" }
        ListElement { emoji: "🔱"; name: "Trident"; keywords: "trident emblem" }
        ListElement { emoji: "📛"; name: "Name badge"; keywords: "name badge" }
        ListElement { emoji: "🔰"; name: "Japanese symbol"; keywords: "japanese symbol for beginner" }
        ListElement { emoji: "⭕"; name: "Circle"; keywords: "hollow red circle" }
        ListElement { emoji: "🚫"; name: "Prohibited"; keywords: "prohibited no" }
        ListElement { emoji: "⛔"; name: "No entry"; keywords: "no entry" }
        ListElement { emoji: "🆔"; name: "ID"; keywords: "id button" }
        ListElement { emoji: "🆗"; name: "OK button"; keywords: "ok button" }
        ListElement { emoji: "🆕"; name: "New"; keywords: "new button" }
        ListElement { emoji: "🆖"; name: "NG"; keywords: "ng button" }
        ListElement { emoji: "🅿️"; name: "P"; keywords: "p button parking" }
        ListElement { emoji: "🆑"; name: "CL"; keywords: "cl button" }
        ListElement { emoji: "🆘"; name: "SOS"; keywords: "sos button help" }
        ListElement { emoji: "🆙"; name: "Up"; keywords: "up button" }
        ListElement { emoji: "🆚"; name: "VS"; keywords: "vs button" }
        ListElement { emoji: "🈁"; name: "Here"; keywords: "koko here" }
        ListElement { emoji: "🈂️"; name: "Service"; keywords: "sa service" }
        ListElement { emoji: "🈷️"; name: "Month"; keywords: "tsuki month" }
        ListElement { emoji: "🈶"; name: "Fee"; keywords: "yuuko fee paid" }
        ListElement { emoji: "🈯"; name: "Reserved"; keywords: "shitei reserved" }
        ListElement { emoji: "🉐"; name: "Bargain"; keywords: "toki bargain" }
        ListElement { emoji: "🈹"; name: "Discount"; keywords: "wari discount" }
        ListElement { emoji: "🈚"; name: "Free"; keywords: "nashi free" }
        ListElement { emoji: "🈲"; name: "Prohibited"; keywords: "kinshi prohibited" }
        ListElement { emoji: "🉑"; name: "Acceptable"; keywords: "ka acceptable" }
        ListElement { emoji: "🈸"; name: "Apply"; keywords: "kou apply" }
        ListElement { emoji: "🈴"; name: "Passing"; keywords: "goukaku passing" }
        ListElement { emoji: "🈳"; name: "Vacancy"; keywords: "aki vacancy" }
        ListElement { emoji: "㊗️"; name: "Congratulation"; keywords: "congratulation japanese" }
        ListElement { emoji: "㊙️"; name: "Secret"; keywords: "secret japanese" }
        ListElement { emoji: "🈺"; name: "Open"; keywords: "eigyo open business" }
        ListElement { emoji: "🈵"; name: "Full"; keywords: "man full" }
        ListElement { emoji: "🔴"; name: "Red circle"; keywords: "red circle" }
        ListElement { emoji: "🟠"; name: "Orange circle"; keywords: "orange circle" }
        ListElement { emoji: "🟡"; name: "Yellow circle"; keywords: "yellow circle" }
        ListElement { emoji: "🟢"; name: "Green circle"; keywords: "green circle" }
        ListElement { emoji: "🔵"; name: "Blue circle"; keywords: "blue circle" }
        ListElement { emoji: "🟣"; name: "Purple circle"; keywords: "purple circle" }
        ListElement { emoji: "🟤"; name: "Brown circle"; keywords: "brown circle" }
        ListElement { emoji: "⚫"; name: "Black circle"; keywords: "black circle" }
        ListElement { emoji: "⚪"; name: "White circle"; keywords: "white circle" }
        ListElement { emoji: "🟥"; name: "Red square"; keywords: "red square" }
        ListElement { emoji: "🟧"; name: "Orange square"; keywords: "orange square" }
        ListElement { emoji: "🟨"; name: "Yellow square"; keywords: "yellow square" }
        ListElement { emoji: "🟩"; name: "Green square"; keywords: "green square" }
        ListElement { emoji: "🟦"; name: "Blue square"; keywords: "blue square" }
        ListElement { emoji: "🟪"; name: "Purple square"; keywords: "purple square" }
        ListElement { emoji: "🟫"; name: "Brown square"; keywords: "brown square" }
        ListElement { emoji: "⬛"; name: "Black square"; keywords: "black large square" }
        ListElement { emoji: "⬜"; name: "White square"; keywords: "white large square" }
        ListElement { emoji: "◼️"; name: "Black medium square"; keywords: "black medium square" }
        ListElement { emoji: "◻️"; name: "White medium square"; keywords: "white medium square" }
        ListElement { emoji: "◾"; name: "Black small square"; keywords: "black small square" }
        ListElement { emoji: "◽"; name: "White small square"; keywords: "white small square" }
        ListElement { emoji: "▪️"; name: "Black mini square"; keywords: "black small square" }
        ListElement { emoji: "▫️"; name: "White mini square"; keywords: "white small square" }

        // ── Flags (a small selection) ──
        ListElement { emoji: "🏁"; name: "Checkered"; keywords: "checkered flag finish" }
        ListElement { emoji: "🚩"; name: "Triangular"; keywords: "triangular flag post" }
        ListElement { emoji: "🎌"; name: "Crossed flags"; keywords: "crossed flags" }
        ListElement { emoji: "🏴"; name: "Black flag"; keywords: "black flag" }
        ListElement { emoji: "🏳️"; name: "White flag"; keywords: "white flag" }
        ListElement { emoji: "🏳️‍🌈"; name: "Rainbow flag"; keywords: "rainbow flag pride" }
        ListElement { emoji: "🏳️‍⚧️"; name: "Trans flag"; keywords: "transgender flag" }
        ListElement { emoji: "🏴‍☠️"; name: "Pirate flag"; keywords: "pirate flag skull" }
    }
}
