# Rustrix

**Repository:** <https://github.com/TumRedSun/rustrix>

A **Matrix client for Linux** built with **Rust + Qt 6 / QML**, focused on
maximum visual customization and the everyday chat feature set.

![Rustrix](assets/RustRix.png)

## Features

### Protocol & connectivity
- **Token-based auto-login**: the last session's access token is stored on
  disk under `~/.local/share/Rustrix/session.json` and reused on the
  next launch — no password is ever stored.
- **Manual login** with username + password (against the homeserver's
  `/login` endpoint).
- **Manual token entry** for users who already have a working access token
  from another client (Element, FluffyChat, Cinny, etc.).
- **Flexible homeserver field**: the login form accepts a domain, an IPv4
  address or an `[IPv6]` literal (port optional) — happy-eyeballs resolution
  tries both A and AAAA records.
- **End-to-end encryption** via `matrix-sdk-crypto` (Olm/Megolm). Keys are
  persisted in a SQLite store under `~/.local/share/Rustrix/sqlite/`.

### Chat
- Send and receive **text messages** (Markdown supported via the SDK).
- Receive **formatted messages** (HTML).
- **Replies** — pick "Reply" in the message menu; the quoted original is
  rendered inside the reply bubble.
- **Emoji reactions** — pick "React…" (searchable emoji picker), toggle your
  own reaction by clicking a chip, right-click a chip to see who reacted.
- Send and receive **images** — inline preview in the bubble, click to open
  full-size.
- Send and receive **videos** — inline player with controls.
- Send and receive **audio** and **arbitrary files** — tiles with name,
  size, mime, and Download button.
- **Multi-file attachments** — queue multiple files + text, send them all
  together on Enter (Discord-style).
- **Hidden files** (dotfiles) are visible in the file picker.
- **Download any attachment** with a single click — files land in
  `~/Downloads/Rustrix/` with collision-safe naming.
- Live unread badges & highlight counts on the room list.
- Per-room last-event preview.
- **Incremental timeline updates** — incoming syncs patch the message model
  in place (insert / update single rows), so the chat never flickers.

### Spaces & rooms
- Hierarchical **Spaces → Rooms** view on the left sidebar (indented
  children, space/room iconography, unread counts).
- Flat **Rooms list** view for direct messages and standalone rooms.
- Each entry shows avatar, name, last event, and unread counter.
- **Member list panel** for the open room.

### Profile
- View & edit display name.
- Upload & set avatar (any image format supported by Qt).
- Set presence (online / unavailable / offline) with a status message.

### Appearance settings, WYSIWYG
The dedicated **Appearance** page in the settings overlay is built around a
live preview and human-readable controls; everything is saved to
`~/.config/Rustrix/theme.json` and restored on the next launch:

| Card | Contents |
|-------|-------|
| **Theme presets** | Material Dark, Solarized Dark, Tokyo Night, Nordic, Dracula, Gruvbox, Catppuccin Mocha, Sunset, Matrix Green — clickable cards with color dots, plus Export / Import / Reset |
| **Preview** | a miniature chat (bubbles, avatar, timestamps, composer with the real 📁 / 😀 / ↑ controls) bound to the live theme |
| **Interface colors** | window bg/fg, sidebar bg/fg, accent, accent-fg, border, muted, danger, success, warning |
| **Messages** | bubble bg/fg for both sides, corner radius, padding, max width %, tail on/off |
| **Text** | base & monospace font family; five text sizes with human labels and live "Aa" demos |
| **Avatars** | three sizes, corner radius, shape (circle / rounded / square) |
| **Interface** | compact mode, show timestamps, show avatars, animate bubbles, animation duration |
| **Advanced** (collapsed) | fine-grained radii, paddings, gaps, scrollbar width/radius |

Every color row has a swatch (click it for a color dialog) and a hex field,
sizes are sliders with the current value — change anything and the entire
UI updates live, no restart required.

### Interface language
Russian and English out of the box (more languages listed in Settings →
Language); switching applies immediately, no restart.

---

## Project layout

```
rustrix/
├── Cargo.toml            # dependencies & build profile
├── build.rs              # Qt discovery helper
├── src/
│   ├── main.rs           # entry point, qrc resources, registers QML types & singletons
│   ├── matrix_client.rs  # central QML-facing MatrixClient singleton + sync loop
│   ├── auth.rs           # client construction (homeserver normalization)
│   ├── room_model.rs     # QAbstractListModel for joined rooms
│   ├── message_model.rs  # QAbstractListModel for a room's timeline (incremental updates)
│   ├── member_model.rs   # QAbstractListModel for room members
│   ├── spaces.rs         # SpaceModel: spaces → rooms tree
│   ├── profile.rs        # ProfileManager: display name / avatar / presence
│   ├── file_transfer.rs  # upload & download of files/images/videos/audio
│   ├── media_provider.rs # image://matrix/ QML image provider (E2EE-aware)
│   ├── theme.rs          # Theme singleton with all visual knobs
│   ├── translations.rs   # Tr singleton: ru/en dictionaries, dynamic switch
│   ├── pending.rs        # Tokio → Qt event bridge (poll-based)
│   ├── avatar_cache.rs   # on-disk caches and downloads dir helpers
│   ├── singleton.rs      # QtSingleton helper storage
│   └── errors.rs         # shared error type
├── qml/
│   ├── main.qml          # root window + MainView (4-pane layout)
│   ├── LoginPage.qml     # password + token login forms
│   ├── LoadingScreen.qml # splash while the first sync runs
│   ├── ChatPage.qml      # header + message list + composer
│   ├── MessageBubble.qml # themed bubble for every event kind
│   ├── SpacesPage.qml    # spaces → rooms tree
│   ├── RoomsSidebar.qml  # flat room list
│   ├── MemberListPanel.qml # room member list
│   ├── SettingsOverlay.qml # settings: profile, appearance, connection, language
│   ├── EmojiPicker.qml   # searchable emoji grid (reactions + insert)
│   ├── ReactionSendersPopup.qml # who reacted to a message
│   ├── FileBrowserDialog.qml   # custom file picker with hidden-file toggle
│   ├── ProfilePage.qml   # display name / avatar / presence editor (legacy)
│   ├── SettingsPage.qml  # legacy, superseded by SettingsOverlay
│   └── AppearancePage.qml# legacy, superseded by SettingsOverlay
├── assets/
│   ├── RustRix.png       # application icon
│   ├── rustrix.desktop   # desktop entry for system launchers
│   ├── logo.svg
│   └── default-avatar.svg
└── scripts/
    ├── build.sh          # release build helper
    └── run.sh            # debug run helper
```

---

## Build prerequisites

### Debian / Ubuntu

```bash
sudo apt-get install -y \
  build-essential pkg-config \
  rustc cargo \
  qt6-base-dev qt6-declarative-dev qt6-svg-dev \
  libssl-dev libsqlite3-dev \
  qmake6
```

### Fedora

```bash
sudo dnf install -y \
  rust cargo \
  qt6-qtbase-devel qt6-qtdeclarative-devel qt6-qtsvg-devel \
  openssl-devel sqlite-devel
```

### Arch

```bash
sudo pacman -S --needed \
  rust \
  qt6-base qt6-declarative qt6-svg \
  openssl sqlite
```

### NixOS (ephemeral shell)

```bash
nix-shell -p rustc cargo qt6.full pkg-config openssl sqlite
```

---

## Building

```bash
# From the project root:
cargo run                          # debug build + run
cargo build --release              # optimized binary at target/release/rustrix
```

If `qmake` is not on `PATH`, point the build at it explicitly:

```bash
QMAKE=/usr/bin/qmake6 cargo build --release
```

The `scripts/build.sh` and `scripts/run.sh` helpers wrap these for convenience.

---

## Desktop icon & launcher

The QML and assets (including `assets/RustRix.png`) are embedded into the
binary via qrc, so the running app already has its window/taskbar icon.

To also get Rustrix in your system application menu:

```bash
install -Dm755 target/release/rustrix ~/.local/bin/rustrix
install -Dm644 assets/RustRix.png ~/.local/share/icons/hicolor/128x128/apps/rustrix.png
install -Dm644 assets/rustrix.desktop ~/.local/share/applications/rustrix.desktop
```

(For a system-wide install use `/usr/local/{bin,share/...}` instead.)

---

## First run

1. Launch the binary.
2. The login window appears. Either:
   - enter homeserver + username + password, **or**
   - switch to the **Token** tab and paste your access token (and user ID).
3. Click **Sign in**.
4. The session is stored on disk; subsequent launches auto-login.

## Where things live

| Path | Contents |
|------|----------|
| `~/.local/share/Rustrix/session.json` | Homeserver URL, user ID, device ID, access token |
| `~/.local/share/Rustrix/sqlite/` | Matrix SDK state (E2E keys, room state) |
| `~/.local/share/Rustrix/avatars/` | Downloaded avatar thumbnails |
| `~/.config/Rustrix/theme.json` | Custom appearance settings |
| `~/Downloads/Rustrix/` | All downloads from chats |

## Removing the saved session / logout

Either click **Logout** in the Settings page, or simply delete
`~/.local/share/Rustrix/session.json`. The SQLite store remains, so
E2E keys survive a re-login.

---

## Architecture notes

### Rust ↔ QML bridge

[qmetaobject](https://docs.rs/qmetaobject) provides pure-Rust Qt bindings
(no C++ glue). All `#[derive(QObject)]` structs are exposed to QML via
`register_type` (instantiable) or `register_singleton_type`
(globally-available) under the `MatrixClient` module URI.

### Async

A single Tokio runtime is owned by the `Backend` singleton. Every QML-callable
method on `MatrixClient` spawns a future onto it; results are returned via Qt
signals (`logged_in`, `sync_done`, `file_downloaded`, `last_error_changed`,
…) or through the poll-based pending-events bridge (`src/pending.rs`). The
UI thread never blocks.

### Homeserver addressing

`auth::normalize_homeserver()` accepts a domain, an IPv4 address or an
`[IPv6]` literal (with optional port) and builds the client's homeserver URL
from it. Standard happy-eyeballs resolution tries both A and AAAA records.

### Theming

The `Theme` singleton is a `#[derive(QObject)]` Rust struct whose state is
mirrored to a `ThemeState` (serde). Every setter writes through to
`~/.config/Rustrix/theme.json`. QML reads properties via the standard
property binding, so changes propagate instantly. Derived sizes (columns,
headers, buttons, dialogs) are computed from the live window size
(`Theme.scale`), so the layout adapts when the window is resized.

### Inline media

The `image://matrix/<media_source_json>` QML image provider fetches media
bytes through the Matrix SDK (which transparently decrypts E2EE files),
caches them under `<cache_dir>/Rustrix/media/`, and serves them to QML
`Image` components. Videos are played inline with `MediaPlayer` +
`VideoOutput`.

### Translations

`Tr.tr(Theme.language, "Source string")` looks the string up in a
compiled-in dictionary (Russian is fully translated). Because
`Theme.language` is a notifying property, switching the language
re-evaluates every translated label live.

---

## Known limitations / TODO

- Sliding Sync is not wired up; we use plain `/sync`. For large accounts,
  switching to `matrix_sdk_ui::sync_service` is recommended.
- No voice / video calls (MSC3401).
- No message *editing* UI (the edited flag is rendered; composing an edit
  is not implemented yet).
- Chat history back-pagination is limited to the initial window of recent
  messages.

## License

GPL-3.0-or-later.
