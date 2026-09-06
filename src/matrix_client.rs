//! `MatrixClient` — the central QML-facing singleton.
//!
//! Wraps `matrix_sdk::Client` and exposes:
//!  - token-based auto-login (`loginWithToken`)
//!  - password login (`loginWithPassword`)
//!  - IPv6-capable transport (forced via a custom reqwest builder)
//!  - room list, message sending, file/image/video upload & download
//!  - spaces hierarchy
//!  - profile read/write
//!
//! All async work happens on the shared Tokio runtime held by `Backend`.
//! Results are pushed to QML via Qt signals, so the UI thread never blocks.

use qmetaobject::*;
use std::cell::RefCell;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::sync::Mutex;

use crate::errors::AppResult;
use crate::room_model::{RoomModel, RoomEntry};
use crate::message_model::{MessageModel, MessageEntry};
use crate::spaces::{SpaceModel, SpaceEntry};
use crate::member_model::{MemberModel, MemberEntry};

/// Module-level singleton storage for MatrixClient.
static MATRIXCLIENT_SINGLETON: crate::singleton::QtSingleton<QPointer<MatrixClient>> =
    crate::singleton::QtSingleton::new();

/// Server-side configuration that survives restarts.
#[derive(serde::Serialize, serde::Deserialize, Clone, Default)]
pub struct SessionStore {
    pub homeserver: String,
    pub user_id: String,
    pub device_id: String,
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub force_ipv6: bool,
}

#[derive(QObject, Default)]
#[allow(non_snake_case)]
pub struct MatrixClient {
    base: qt_base_class!(trait QObject),

    inner: RefCell<Option<Arc<Mutex<matrix_sdk::Client>>>>,
    session: RefCell<Option<SessionStore>>,
    #[allow(dead_code)]
    session_path: RefCell<Option<PathBuf>>,

    /// True when fully synced and ready.
    ready: qt_property!(bool; NOTIFY readyChanged),
    /// True while a network call is in flight.
    busy: qt_property!(bool; NOTIFY busyChanged),
    /// True when server is unreachable — offline mode.
    offline: qt_property!(bool; NOTIFY offlineChanged),
    /// Current user MXID, "" if logged out.
    userId: qt_property!(QString; NOTIFY userIdChanged),
    /// Last error message surfaced to the UI.
    lastError: qt_property!(QString; NOTIFY lastErrorChanged),

    readyChanged: qt_signal!(),
    busyChanged: qt_signal!(),
    offlineChanged: qt_signal!(),
    userIdChanged: qt_signal!(),
    lastErrorChanged: qt_signal!(),

    /// Emitted with a JSON payload whenever a sync cycle completes.
    syncDone: qt_signal!(payload: QString),
    /// Emitted when login completes successfully.
    loggedIn: qt_signal!(user_id: QString),
    /// Emitted on logout.
    loggedOut: qt_signal!(),
    /// Emitted when a media download finishes. The third arg is the local
    /// filesystem path the file was saved to.
    fileDownloaded: qt_signal!(room_id: QString, mxc: QString, local_path: QString),
    /// Emitted when an inline media preview is ready. The first arg is
    /// the source JSON that was passed to `requestMedia` (so QML can
    /// match the response to the request), the second is the local file
    /// path (no `file://` prefix — QML adds it).
    mediaReady: qt_signal!(source_json: QString, local_path: QString),
    /// Emitted when an inline media preview fetch fails. The arg is the
    /// source JSON that was requested + the error message.
    mediaError: qt_signal!(source_json: QString, error: QString),
    /// Emitted after `setBanner` finishes copying the image to the cache dir.
    /// The argument is the `file://` URL of the new banner.
    bannerSet: qt_signal!(url: QString),
    /// Emitted when a user search completes. The argument is a JSON string:
    /// `[{user_id, display_name, avatar_url}, …]` (limited to 20 results).
    usersSearchDone: qt_signal!(results_json: QString),
    /// Emitted after `openDirectMessage` succeeds (or reuses an existing DM).
    /// The argument is the room id to switch to.
    dmOpened: qt_signal!(room_id: QString),
    /// Emitted after `leaveRoom` succeeds. The argument is the room id that
    /// was left/removed.
    roomLeft: qt_signal!(room_id: QString),
    /// Emitted when `copyText` is called. main.qml listens for this and
    /// uses a hidden TextEdit to actually put the text on the clipboard
    /// (qmetaobject 0.2 doesn't expose QClipboard directly).
    textCopied: qt_signal!(text: QString),
    /// Emitted when a reply is being composed (user clicked "Reply" in the
    /// message context menu). The argument is the event_id of the message
    /// being replied to. main.qml / ChatPage listens for this and shows a
    /// reply banner above the composer.
    replyStarted: qt_signal!(room_id: QString, event_id: QString, body: QString),

    // QML-callable method declarations
    autoLogin: qt_method!(fn(&self)),
    loginWithPassword: qt_method!(fn(&self, homeserver: QString, username: QString, password: QString, force_ipv6: bool)),
    loginWithToken: qt_method!(fn(&self, homeserver: QString, user_id: QString, device_id: QString, access_token: QString, force_ipv6: bool)),
    logout: qt_method!(fn(&self)),
    deleteAccount: qt_method!(fn(&self)),
    sendText: qt_method!(fn(&self, room_id: QString, body: QString)),
    sendFile: qt_method!(fn(&self, room_id: QString, local_path: QString, display_name: QString, mime: QString, kind: QString)),
    downloadMedia: qt_method!(fn(&self, room_id: QString, mxc: QString, suggested_name: QString)),
    /// Asynchronously fetch a media file by its serialized `MediaSource`
    /// JSON and write it to the on-disk cache. When ready (or on error),
    /// emits `mediaReady(sourceJson, localPath)` / `mediaError(sourceJson, err)`.
    /// QML uses this to populate inline image previews and video players
    /// for both plain and E2EE-encrypted media.
    requestMedia: qt_method!(fn(&self, source_json: QString, mime: QString)),
    /// List the contents of a local directory. Returns a JSON array of
    /// entries: `[{"name": "foo.txt", "is_dir": false, "size": 1234}, …]`.
    /// Used by the custom FileBrowserDialog (which supports showing
    /// dotfiles — the stock Qt FileDialog doesn't).
    listDirectory: qt_method!(fn(&self, path: QString, include_hidden: bool) -> QString),
    /// Returns the user's home directory path (without `file://` prefix).
    homeDir: qt_method!(fn(&self) -> QString),
    setDisplayName: qt_method!(fn(&self, name: QString)),
    setAvatar: qt_method!(fn(&self, local_path: QString)),
    setBanner: qt_method!(fn(&self, local_path: QString)),
    setForceIpv6: qt_method!(fn(&self, on: bool)),
    loadRoomMessages: qt_method!(fn(&self, room_id: QString)),
    loadRoomMembers: qt_method!(fn(&self, room_id: QString)),
    refreshRooms: qt_method!(fn(&self)),
    /// Search users by (partial) username/display name.
    /// Emits `usersSearchDone` with a JSON payload.
    searchUsers: qt_method!(fn(&self, query: QString)),
    /// Create (or open) a direct-message room with `user_id`.
    /// Emits `dmOpened(roomId)` when ready.
    openDirectMessage: qt_method!(fn(&self, user_id: QString)),
    /// Leave (and forget) a room. On success emits `roomLeft(roomId)`.
    leaveRoom: qt_method!(fn(&self, room_id: QString)),

    /// Send a reply (m.relates_to = "m.reference") to the given event_id.
    /// The reply body is sent as a new text message with the reply metadata
    /// attached, so the receiver's client can render it threaded under the
    /// original message.
    sendReply: qt_method!(fn(&self, room_id: QString, event_id: QString, body: QString)),
    /// Send an emoji reaction to an event. `emoji` should be a single grapheme
    /// (e.g. "👍"). Idempotent — sending the same emoji twice from the same
    /// user is a no-op per the Matrix spec.
    sendReaction: qt_method!(fn(&self, room_id: QString, event_id: QString, emoji: QString)),
    /// Toggle the current user's reaction to an event. If we have already
    /// reacted with `emoji`, that reaction is redacted (removed). If we
    /// haven't, a new reaction is sent. This is the Discord-style LMB
    /// behavior on a reaction chip.
    toggleReaction: qt_method!(fn(&self, room_id: QString, event_id: QString, emoji: QString)),
    /// Redact (delete) an event. For own messages this fully removes the
    /// content; for other users' messages Matrix only lets us redact our
    /// own — we emulate "hide for me" on the QML side via the model filter.
    /// `reason` is optional (pass empty string to skip).
    redactEvent: qt_method!(fn(&self, room_id: QString, event_id: QString, reason: QString)),
    /// Copy the given text to the system clipboard. Implemented natively
    /// because QML's `TextEdit.copy()` only works when the text is selected
    /// in that exact TextEdit — the context menu wants to copy arbitrary
    /// message bodies without requiring a prior selection gesture.
    copyText: qt_method!(fn(&self, text: QString)),
    /// Save a string to a user-chosen file path. Emits `fileDownloaded`
    /// when done, so the QML context menu can show a "Saved!" toast.
    saveTextToFile: qt_method!(fn(&self, text: QString, suggested_name: QString)),

    /// Drain the pending-events queue and apply each event on the Qt
    /// main thread. Called from a QML `Timer` every 100 ms.
    ///
    /// This replaces `qmetaobject::queued_callback` for events that
    /// originate on the Tokio runtime — `queued_callback` created on a
    /// Tokio worker thread captures a null `QPointer<QThread>` and
    /// silently drops every invocation. See `src/pending.rs` for the
    /// full rationale.
    pollPending: qt_method!(fn(&mut self)),
}

impl MatrixClient {
    fn session_file_path() -> PathBuf {
        let base = directories::ProjectDirs::from("dev", "rustrix", "Rustrix")
            .map(|d| d.data_dir().to_path_buf())
            .unwrap_or_else(|| std::env::temp_dir().join("Rustrix"));
        std::fs::create_dir_all(&base).ok();
        base.join("session.json")
    }

    fn set_busy(&mut self, on: bool) {
        self.busy = on;
        self.busyChanged();
    }

    fn set_error(&mut self, msg: impl Into<String>) {
        self.lastError = QString::from(msg.into().as_str());
        self.lastErrorChanged();
    }

    fn set_ready(&mut self, on: bool) {
        self.ready = on;
        self.readyChanged();
    }

    fn set_offline(&mut self, on: bool) {
        if self.offline != on {
            self.offline = on;
            self.offlineChanged();
            if on {
                ::log::warn!("MatrixClient: entering OFFLINE mode");
            } else {
                ::log::info!("MatrixClient: back ONLINE");
            }
        }
    }

    fn set_user_id(&mut self, id: impl Into<String>) {
        self.userId = QString::from(id.into().as_str());
        self.userIdChanged();
    }

    /// Public wrapper to emit the `file_downloaded` signal from outside this module.
    pub fn emit_file_downloaded(&self, room_id: QString, mxc: QString, local_path: QString) {
        self.fileDownloaded(room_id, mxc, local_path);
    }

    /// Public wrapper to emit the `media_ready` signal.
    pub fn emit_media_ready(&self, source_json: QString, local_path: QString) {
        self.mediaReady(source_json, local_path);
    }

    /// Public wrapper to emit the `media_error` signal.
    pub fn emit_media_error(&self, source_json: QString, error: QString) {
        self.mediaError(source_json, error);
    }

    /// Public wrapper to emit the `banner_set` signal from outside this module.
    pub fn emit_banner_set(&self, url: QString) {
        self.bannerSet(url);
    }

    /// Public wrapper to emit the `users_search_done` signal.
    pub fn emit_users_search_done(&self, json: QString) {
        self.usersSearchDone(json);
    }

    /// Public wrapper to emit the `dm_opened` signal.
    pub fn emit_dm_opened(&self, room_id: QString) {
        self.dmOpened(room_id);
    }

    /// Public wrapper to emit the `room_left` signal.
    pub fn emit_room_left(&self, room_id: QString) {
        self.roomLeft(room_id);
    }

    /// Public wrapper to emit the `text_copied` signal.
    pub fn emit_text_copied(&self, text: QString) {
        self.textCopied(text);
    }

    /// Public wrapper to emit the `reply_started` signal.
    pub fn emit_reply_started(&self, room_id: QString, event_id: QString, body: QString) {
        self.replyStarted(room_id, event_id, body);
    }

    /// Public wrapper to emit the `sync_done` signal from outside this module.
    pub fn emit_sync_done(&self, payload: QString) {
        self.syncDone(payload);
    }

    /// Public wrapper to emit the `logged_in` signal from outside this module.
    pub fn emit_logged_in(&self, user_id: QString) {
        self.loggedIn(user_id);
    }

    /// Public wrapper to emit the `logged_out` signal from outside this module.
    pub fn emit_logged_out(&self) {
        self.loggedOut();
    }

    /// Drain the pending-events queue and apply each event on the Qt
    /// main thread. Called from a QML `Timer` every 100 ms.
    ///
    /// This is the reliable replacement for `qmetaobject::queued_callback`
    /// for events that originate on the Tokio runtime.
    pub fn pollPending(&mut self) {
        let events = crate::pending::drain();
        if events.is_empty() {
            return;
        }
        ::log::debug!("pollPending: processing {} pending events", events.len());
        for ev in events {
            match ev {
                crate::pending::PendingEvent::SetUserId(id) => {
                    self.set_user_id(id);
                }
                crate::pending::PendingEvent::SetBusy(b) => {
                    self.set_busy(b);
                }
                crate::pending::PendingEvent::SetReady(b) => {
                    self.set_ready(b);
                }
                crate::pending::PendingEvent::SetOffline(b) => {
                    self.set_offline(b);
                }
                crate::pending::PendingEvent::SetError(msg) => {
                    self.set_error(msg);
                }
                crate::pending::PendingEvent::EmitLoggedIn(uid) => {
                    ::log::info!("pollPending: emitting loggedIn user_id={}", uid);
                    self.emit_logged_in(QString::from(uid.as_str()));
                }
                crate::pending::PendingEvent::EmitSyncDone => {
                    self.emit_sync_done(QString::from("{}"));
                }
                crate::pending::PendingEvent::EmitLoggedOut => {
                    self.emit_logged_out();
                }
                crate::pending::PendingEvent::ApplyRooms(entries) => {
                    let n = entries.len();
                    if let Some(r) = RoomModel::get().as_pinned() {
                        ::log::info!("pollPending: applying {} room entries", n);
                        r.borrow_mut().apply_entries(entries);
                    } else {
                        ::log::warn!("pollPending: RoomModel QPointer is null, dropping {} room entries", n);
                    }
                }
                crate::pending::PendingEvent::ApplySpaces(entries) => {
                    let n = entries.len();
                    if let Some(s) = SpaceModel::get().as_pinned() {
                        ::log::info!("pollPending: applying {} space entries", n);
                        s.borrow_mut().apply_entries(entries);
                    } else {
                        ::log::warn!("pollPending: SpaceModel QPointer is null, dropping {} space entries", n);
                    }
                }
                crate::pending::PendingEvent::RefreshProfile => {
                    if let Some(pm) = crate::profile::ProfileManager::get().as_pinned() {
                        pm.borrow().refresh();
                    }
                }
            }
        }
    }

    /// Spawn a future on the Tokio runtime. Errors are forwarded to the UI
    /// via a `queued_callback` so the `QPointer` is never sent across threads
    /// (QPointer is !Send).
    fn spawn<F, T>(&self, fut: F)
    where
        F: std::future::Future<Output = AppResult<T>> + Send + 'static,
        T: Send + 'static,
    {
        let qptr = QPointer::from(&*self);
        let error_cb = qmetaobject::queued_callback(move |msg: String| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow_mut().set_error(msg);
            }
        });
        let rt = crate::get_runtime();
        rt.spawn(async move {
            match fut.await {
                Ok(_) => {}
                Err(e) => {
                    ::log::warn!("async error: {e}");
                    error_cb(e.to_string());
                }
            }
        });
    }
}

// QML-callable methods.
#[allow(non_snake_case)]
impl MatrixClient {
    /// Try to resume a saved session (auto-login via stored session data).
    /// Called from QML on startup.
    pub fn autoLogin(&self) {
        let path = Self::session_file_path();
        ::log::info!("autoLogin: looking for saved session at {:?}", path);
        match std::fs::read_to_string(&path) {
            Ok(body) => match serde_json::from_str::<SessionStore>(&body) {
                Ok(sess) => {
                    ::log::info!("autoLogin: found session for user={} homeserver={}", sess.user_id, sess.homeserver);
                    let homeserver = sess.homeserver.clone();
                    let user_id = sess.user_id.clone();
                    let device_id = sess.device_id.clone();
                    let access_token = sess.access_token.clone();
                    let ipv6 = sess.force_ipv6;
                    self.spawn(async move {
                        ::log::info!("autoLogin: starting session restore");
                        Self::do_restore_session_with_full(
                            homeserver, user_id, device_id, access_token, ipv6,
                        ).await
                    });
                }
                Err(e) => {
                    if let Some(this) = QPointer::from(&*self).as_pinned() {
                        this.borrow_mut().set_error(format!("session corrupt: {e}"));
                    }
                }
            },
            Err(_) => {
                // No saved session — user needs to log in manually.
                if let Some(this) = QPointer::from(&*self).as_pinned() {
                    this.borrow_mut().set_ready(false);
                }
            }
        }
    }

    pub fn loginWithPassword(
        &self,
        homeserver: QString,
        username: QString,
        password: QString,
        force_ipv6: bool,
    ) {
        let homeserver = homeserver.to_string();
        let username = username.to_string();
        let password = password.to_string();
        {
            if let Some(this) = QPointer::from(&*self).as_pinned() {
                this.borrow_mut().set_busy(true);
            }
        }
        self.spawn(async move {
            Self::do_password_login(homeserver, username, password, force_ipv6).await
        });
    }

    pub fn loginWithToken(
        &self,
        homeserver: QString,
        user_id: QString,
        device_id: QString,
        access_token: QString,
        force_ipv6: bool,
    ) {
        let homeserver = homeserver.to_string();
        let user_id = user_id.to_string();
        let device_id = device_id.to_string();
        let access_token = access_token.to_string();
        {
            if let Some(this) = QPointer::from(&*self).as_pinned() {
                this.borrow_mut().set_busy(true);
            }
        }
        self.spawn(async move {
            Self::do_restore_session_with_full(homeserver, user_id, device_id, access_token, force_ipv6).await
        });
    }

    pub fn logout(&self) {
        let path = Self::session_file_path();
        let _ = std::fs::remove_file(&path);
        let client_arc = self.inner.borrow().clone();
        let qptr = QPointer::from(&*self);
        let logout_cb = qmetaobject::queued_callback(move |_: ()| {
            if let Some(this) = qptr.as_pinned() {
                let mut mc = this.borrow_mut();
                *mc.inner.borrow_mut() = None;
                *mc.session.borrow_mut() = None;
                mc.set_user_id(String::new());
                mc.set_ready(false);
                mc.emit_logged_out();
            }
        });
        let rt = crate::get_runtime();
        rt.spawn(async move {
            if let Some(c) = client_arc {
                let _ = c.lock().await.logout().await;
            }
            logout_cb(());
            let _: AppResult<()> = Ok(());
        });
    }

    pub fn sendText(&self, room_id: QString, body: QString) {
        let room_id = room_id.to_string();
        let body = body.to_string();
        // After sending, reload messages for this room so the sent
        // message appears immediately (instead of waiting for next sync).
        let reload_room_id = room_id.clone();
        let reload_room_id_for_cb = reload_room_id.clone();
        let model = MessageModel::get();
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        let reload_cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &reload_room_id_for_cb);
            }
        });
        self.spawn(async move {
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = room_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let room = c
                .get_room(&rid)
                .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;
            room.send(matrix_sdk::ruma::events::room::message::RoomMessageEventContent::text_markdown(body))
                .await?;
            drop(c);
            // Reload messages after sending
            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            match MessageModel::fetch_messages(client, reload_room_id).await {
                Ok(entries) => reload_cb(entries),
                Err(e) => ::log::warn!("sendText: reload after send failed: {e}"),
            }
            AppResult::Ok(())
        });
    }

    pub fn sendFile(&self, room_id: QString, local_path: QString, display_name: QString, mime: QString, kind: QString) {
        let room_id = room_id.to_string();
        let path = local_path.to_string();
        let display_name = display_name.to_string();
        let mime = mime.to_string();
        let kind = kind.to_string();
        // After sending, reload messages for this room so the sent
        // file appears immediately (mirrors how sendText works). Without
        // this the user had to switch rooms to see their own attachment.
        let reload_room_id = room_id.clone();
        let reload_room_id_for_cb = reload_room_id.clone();
        let model = MessageModel::get();
        let reload_cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &reload_room_id_for_cb);
            }
        });
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        self.spawn(async move {
            crate::file_transfer::send_attachment(room_id, path, display_name, mime, kind).await?;
            // Reload messages after sending
            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            match MessageModel::fetch_messages(client, reload_room_id).await {
                Ok(entries) => reload_cb(entries),
                Err(e) => ::log::warn!("sendFile: reload after send failed: {e}"),
            }
            AppResult::Ok(())
        });
    }

    pub fn downloadMedia(&self, room_id: QString, media_source_json: QString, suggested_name: QString) {
        let room_id = room_id.to_string();
        let media_source_json = media_source_json.to_string();
        let name = suggested_name.to_string();
        self.spawn(async move {
            crate::file_transfer::download_media(room_id, media_source_json, name).await
        });
    }

    /// Send a text reply to a specific event_id.
    ///
    /// Uses `Room::make_reply_event` to build a proper Matrix reply with
    /// `m.relates_to: m.reference` pointing at the original event. Other
    /// clients (Element, FluffyChat) render the replied-to message as a
    /// quote above the reply.
    pub fn sendReply(&self, room_id: QString, event_id: QString, body: QString) {
        let room_id = room_id.to_string();
        let event_id = event_id.to_string();
        let body = body.to_string();
        let reload_room_id = room_id.clone();
        let reload_room_id_for_cb = reload_room_id.clone();
        let model = MessageModel::get();
        let reload_cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &reload_room_id_for_cb);
            }
        });
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        self.spawn(async move {
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = room_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let room = c
                .get_room(&rid)
                .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;
            let evt_id: ruma::OwnedEventId = event_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;

            // Build a text content (without relation — make_reply_event
            // attaches the reply relation for us) and a Reply descriptor
            // that says "don't enforce a thread, just a plain reply".
            use matrix_sdk::ruma::events::room::message::{
                RoomMessageEventContentWithoutRelation,
            };
            use matrix_sdk::room::reply::{Reply, EnforceThread};
            let content = RoomMessageEventContentWithoutRelation::text_markdown(body);
            let reply = Reply {
                event_id: evt_id,
                enforce_thread: EnforceThread::MaybeThreaded,
                // Use the SDK's default AddMentions::No — we don't want to
                // ping the original sender just because we replied.
                add_mentions: matrix_sdk::ruma::events::room::message::AddMentions::No,
            };
            let reply_content = room.make_reply_event(content, reply).await
                .map_err(|e| crate::errors::AppError::Other(format!("reply build failed: {e}")))?;
            room.send(reply_content).await?;
            drop(c);

            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            match MessageModel::fetch_messages(client, reload_room_id).await {
                Ok(entries) => reload_cb(entries),
                Err(e) => ::log::warn!("sendReply: reload after send failed: {e}"),
            }
            AppResult::Ok(())
        });
    }

    /// Send an emoji reaction (m.reaction) to an event.
    /// Per the Matrix spec, reactions are m.reaction events whose
    /// `m.relates_to` has `rel_type: m.annotation`, `event_id: <target>`,
    /// and `key: <emoji>`. Reactions render below the original message
    /// in Element / Discord-like UIs.
    pub fn sendReaction(&self, room_id: QString, event_id: QString, emoji: QString) {
        let room_id = room_id.to_string();
        let event_id = event_id.to_string();
        let emoji = emoji.to_string();
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        self.spawn(async move {
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = room_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let room = c
                .get_room(&rid)
                .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;
            let evt_id: ruma::OwnedEventId = event_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;

            use matrix_sdk::ruma::events::reaction::ReactionEventContent;
            use matrix_sdk::ruma::events::relation::Annotation;
            let reaction = ReactionEventContent::new(Annotation::new(evt_id, emoji));
            room.send(reaction).await?;
            AppResult::Ok(())
        });
    }

    /// Toggle the current user's reaction to an event.
    ///
    /// Implementation:
    ///   1. Build a fresh Timeline for the room.
    ///   2. Walk the timeline items to find the EventTimelineItem whose
    ///      event_id matches `event_id`.
    ///   3. Read its `msg_like.reactions` (a `ReactionsByKeyBySender`).
    ///   4. Look up the entry for `emoji`. If it exists and contains the
    ///      current user, extract the reaction's event_id from
    ///      `ReactionStatus::RemoteToRemote(OwnedEventId)` and `room.redact()`
    ///      that reaction event.
    ///   5. Otherwise, send a new `m.reaction` event.
    ///   6. After either branch, reload messages so the chip updates.
    ///
    /// Local-echo reactions (`LocalToRemote`, `LocalToLocal`) don't have a
    /// remote event_id we can redact — for those we just send another
    /// reaction and let the server deduplicate. In practice this only
    /// matters for the ~100ms window between clicking react and the
    /// server acknowledging it.
    pub fn toggleReaction(&self, room_id: QString, event_id: QString, emoji: QString) {
        let room_id = room_id.to_string();
        let event_id = event_id.to_string();
        let emoji = emoji.to_string();
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        let reload_room_id = room_id.clone();
        let reload_room_id_for_cb = reload_room_id.clone();
        let model = MessageModel::get();
        let reload_cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &reload_room_id_for_cb);
            }
        });
        self.spawn(async move {
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = room_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let room = c
                .get_room(&rid)
                .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;
            let target_evt_id: ruma::OwnedEventId = event_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let me_uid = c
                .user_id()
                .map(|u| u.to_owned())
                .ok_or(crate::errors::AppError::NotLoggedIn)?;

            // Build a timeline to read the current reaction state for the
            // target event. We don't paginate (we only care about items
            // already in the timeline — typically the last 50 messages
            // are sufficient; reactions on older messages are rare and
            // toggling them just sends a new reaction, which is harmless).
            use matrix_sdk_ui::timeline::{TimelineBuilder, TimelineItemKind, TimelineItemContent};
            let timeline = match TimelineBuilder::new(&room).build().await {
                Ok(t) => t,
                Err(e) => {
                    ::log::warn!("toggleReaction: Timeline build failed: {e} — sending reaction anyway");
                    // Fallback: just send a new reaction (no toggle).
                    use matrix_sdk::ruma::events::reaction::ReactionEventContent;
                    use matrix_sdk::ruma::events::relation::Annotation;
                    let reaction = ReactionEventContent::new(Annotation::new(target_evt_id.clone(), emoji));
                    room.send(reaction).await?;
                    drop(c);
                    let client: matrix_sdk::Client = {
                        let c2 = client_arc.lock().await;
                        c2.clone()
                    };
                    match MessageModel::fetch_messages(client, reload_room_id).await {
                        Ok(entries) => reload_cb(entries),
                        Err(e) => ::log::warn!("toggleReaction: reload failed: {e}"),
                    }
                    return AppResult::Ok(());
                }
            };

            // Walk items to find the target event.
            let items = timeline.items().await;
            let mut found_reaction_evt_id: Option<ruma::OwnedEventId> = None;
            for item in items.iter() {
                let event_item = match item.kind() {
                    TimelineItemKind::Event(ev) => ev,
                    TimelineItemKind::Virtual(_) => continue,
                };
                let Some(this_evt_id) = event_item.event_id() else { continue };
                if this_evt_id != &target_evt_id { continue; }
                // Found the target — inspect its reactions.
                let TimelineItemContent::MsgLike(msg_like) = event_item.content() else { break };
                let reactions = &msg_like.reactions;
                if let Some(senders) = reactions.get(&emoji) {
                    if let Some(info) = senders.get(&me_uid) {
                        // We have reacted — extract the reaction event id.
                        use matrix_sdk_ui::timeline::ReactionStatus;
                        match &info.status {
                            ReactionStatus::RemoteToRemote(rid) => {
                                found_reaction_evt_id = Some(rid.clone());
                            }
                            _ => {
                                ::log::debug!(
                                    "toggleReaction: our reaction to {} with {} is local-echo (status: {:?}); sending fresh reaction",
                                    event_id, emoji, info.status
                                );
                            }
                        }
                    }
                }
                break;
            }

            if let Some(reaction_evt_id) = found_reaction_evt_id {
                ::log::info!(
                    "toggleReaction: redacting our reaction event {} for target {}",
                    reaction_evt_id, event_id
                );
                room.redact(&reaction_evt_id, None, None).await?;
            } else {
                ::log::info!(
                    "toggleReaction: sending new reaction {} to {}",
                    emoji, event_id
                );
                use matrix_sdk::ruma::events::reaction::ReactionEventContent;
                use matrix_sdk::ruma::events::relation::Annotation;
                let reaction = ReactionEventContent::new(Annotation::new(target_evt_id.clone(), emoji));
                room.send(reaction).await?;
            }

            drop(c);
            let client: matrix_sdk::Client = {
                let c2 = client_arc.lock().await;
                c2.clone()
            };
            match MessageModel::fetch_messages(client, reload_room_id).await {
                Ok(entries) => reload_cb(entries),
                Err(e) => ::log::warn!("toggleReaction: reload failed: {e}"),
            }
            AppResult::Ok(())
        });
    }

    /// Redact (delete) an event. Only the event's sender OR a room
    /// moderator/admin can redact — for other users' messages in a DM this
    /// will fail server-side. The QML context menu hides the "Delete" entry
    /// for non-own messages and shows "Hide for me" instead, which is a
    /// purely local filter (no round-trip).
    pub fn redactEvent(&self, room_id: QString, event_id: QString, reason: QString) {
        let room_id = room_id.to_string();
        let event_id = event_id.to_string();
        let reason_str = reason.to_string();
        let reload_room_id = room_id.clone();
        let reload_room_id_for_cb = reload_room_id.clone();
        let model = MessageModel::get();
        let reload_cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &reload_room_id_for_cb);
            }
        });
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        self.spawn(async move {
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = room_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let room = c
                .get_room(&rid)
                .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;
            let evt_id: ruma::OwnedEventId = event_id.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            let reason_opt = if reason_str.is_empty() { None } else { Some(reason_str.as_str()) };
            room.redact(&evt_id, reason_opt, None).await?;
            drop(c);

            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            match MessageModel::fetch_messages(client, reload_room_id).await {
                Ok(entries) => reload_cb(entries),
                Err(e) => ::log::warn!("redactEvent: reload after redact failed: {e}"),
            }
            AppResult::Ok(())
        });
    }

    /// Copy text to the system clipboard.
    ///
    /// qmetaobject 0.2 doesn't expose QClipboard directly, so we emit a
    /// `textCopied(text)` signal — main.qml listens for it and uses a hidden
    /// TextEdit to actually set the clipboard contents (Qt's TextEdit.copy()
    /// copies selected text; we use `selectAll()` + `copy()`).
    pub fn copyText(&self, text: QString) {
        self.textCopied(text);
    }

    /// Save arbitrary text content to a file in the downloads directory.
    /// Used by the message context menu "Save" entry for text messages
    /// (where there's no media to download but the user wants the text
    /// as a .txt file).
    pub fn saveTextToFile(&self, text: QString, suggested_name: QString) {
        let text_bytes = text.to_string().into_bytes();
        let name = suggested_name.to_string();
        self.spawn(async move {
            let dir = crate::avatar_cache::downloads_dir();
            std::fs::create_dir_all(&dir)?;
            let safe = name.chars()
                .filter(|c| !matches!(c, '/' | '\\' | '\0' | ':' | '*' | '?' | '"' | '<' | '>' | '|'))
                .collect::<String>();
            let final_name = if safe.trim().is_empty() {
                format!("message-{}.txt", uuid::Uuid::new_v4())
            } else if !safe.ends_with(".txt") {
                format!("{}.txt", safe)
            } else {
                safe
            };
            let path = dir.join(final_name);
            std::fs::write(&path, &text_bytes)?;
            let p = path.to_string_lossy().to_string();
            // Build the QPointer INSIDE the async block — QPointer holds a
            // raw `*const MatrixClient`, which is not `Send`. Capturing it
            // across the spawn boundary (declared before `self.spawn`) would
            // make the future `!Send` and fail the compile-time check in
            // `MatrixClient::spawn`. Creating it here on the worker thread
            // and immediately using it via `queued_callback` (which schedules
            // the actual emit on the Qt main thread) is the same pattern
            // `requestMedia` uses.
            let qptr = Self::singleton_ptr();
            let cb = qmetaobject::queued_callback(move |_: ()| {
                if let Some(this) = qptr.as_pinned() {
                    this.borrow_mut().emit_file_downloaded(
                        QString::from(""),
                        QString::from(""),
                        QString::from(p.as_str()),
                    );
                }
            });
            cb(());
            AppResult::Ok(())
        });
    }

    /// Fetch a media file by its serialized `MediaSource` JSON, write it
    /// to the cache, and emit `mediaReady` / `mediaError`.
    ///
    /// If the file is already cached, we still emit `mediaReady` (on the
    /// Qt thread) so QML can populate the Image/Video source. This makes
    /// the API uniform: QML always calls requestMedia and listens for
    /// mediaReady, regardless of cache state.
    pub fn requestMedia(&self, source_json: QString, mime: QString) {
        let source_json_str = source_json.to_string();
        let mime_str = mime.to_string();

        // Cache-hit fast path: emit immediately on the Qt thread, no spawn.
        if let Some(path) = crate::media_provider::try_cache(&source_json_str, &mime_str) {
            let qptr = Self::singleton_ptr();
            let sj = source_json_str.clone();
            let p = path.to_string_lossy().to_string();
            let cb = qmetaobject::queued_callback(move |_: ()| {
                if let Some(this) = qptr.as_pinned() {
                    this.borrow_mut().emit_media_ready(
                        QString::from(sj.as_str()),
                        QString::from(p.as_str()),
                    );
                }
            });
            cb(());
            return;
        }

        // Cache miss: spawn a fetch on the Tokio runtime.
        let sj_for_cb = source_json_str.clone();
        self.spawn(async move {
            match crate::media_provider::fetch_media_bytes(&source_json_str).await {
                Ok(bytes) => {
                    match crate::media_provider::write_cache(&source_json_str, &mime_str, &bytes) {
                        Ok(path) => {
                            let qptr = crate::MatrixClient::singleton_ptr();
                            let p = path.to_string_lossy().to_string();
                            let sj2 = source_json_str.clone();
                            let cb = qmetaobject::queued_callback(move |_: ()| {
                                if let Some(this) = qptr.as_pinned() {
                                    this.borrow_mut().emit_media_ready(
                                        QString::from(sj2.as_str()),
                                        QString::from(p.as_str()),
                                    );
                                }
                            });
                            cb(());
                        }
                        Err(e) => {
                            ::log::warn!("requestMedia: cache write failed: {e}");
                            Self::emit_media_err(&sj_for_cb, &format!("cache write: {e}"));
                        }
                    }
                }
                Err(e) => {
                    ::log::warn!("requestMedia: fetch failed: {e}");
                    Self::emit_media_err(&sj_for_cb, &format!("fetch: {e}"));
                }
            }
            AppResult::Ok(())
        });
    }

    fn emit_media_err(source_json: &str, err: &str) {
        let qptr = Self::singleton_ptr();
        let sj = source_json.to_string();
        let e = err.to_string();
        let cb = qmetaobject::queued_callback(move |_: ()| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow_mut().emit_media_error(
                    QString::from(sj.as_str()),
                    QString::from(e.as_str()),
                );
            }
        });
        cb(());
    }

    /// List the contents of a local directory. Returns a JSON array of
    /// objects: `[{"name": "foo", "is_dir": true, "size": 0}, …]`.
    /// Directories come first, then files, both alphabetically.
    /// On error, returns `[]`.
    pub fn listDirectory(&self, path: QString, include_hidden: bool) -> QString {
        let path_str = path.to_string();
        let p = std::path::Path::new(&path_str);
        let entries = match std::fs::read_dir(p) {
            Ok(e) => e,
            Err(e) => {
                ::log::warn!("listDirectory: failed to read {path_str}: {e}");
                return QString::from("[]");
            }
        };

        let mut dirs: Vec<(String, u64)> = Vec::new();
        let mut files: Vec<(String, u64)> = Vec::new();
        for entry in entries.flatten() {
            let name = match entry.file_name().to_str() {
                Some(s) => s.to_string(),
                None => continue,
            };
            // Hidden = starts with '.' (but exclude "." and ".." which
            // are special — read_dir already excludes them on Unix).
            if !include_hidden && name.starts_with('.') {
                continue;
            }
            let meta = match entry.metadata() {
                Ok(m) => m,
                Err(_) => continue,
            };
            let size = meta.len();
            if meta.is_dir() {
                dirs.push((name, size));
            } else {
                files.push((name, size));
            }
        }
        dirs.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));
        files.sort_by(|a, b| a.0.to_lowercase().cmp(&b.0.to_lowercase()));

        // Build JSON manually (avoid pulling in serde_json for this).
        let mut out = String::from("[");
        for (name, size) in dirs.iter() {
            // Escape backslash and double-quote in the name.
            let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
            out.push_str(&format!("{{\"name\":\"{}\",\"is_dir\":true,\"size\":{}}},", escaped, size));
        }
        for (name, size) in files.iter() {
            let escaped = name.replace('\\', "\\\\").replace('"', "\\\"");
            out.push_str(&format!("{{\"name\":\"{}\",\"is_dir\":false,\"size\":{}}},", escaped, size));
        }
        // Remove trailing comma if any entries were added.
        if out.ends_with(',') {
            out.pop();
        }
        out.push(']');
        QString::from(out.as_str())
    }

    /// Returns the user's home directory path.
    pub fn homeDir(&self) -> QString {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/".to_string());
        QString::from(home.as_str())
    }

    pub fn setDisplayName(&self, name: QString) {
        let name = name.to_string();
        self.spawn(async move {
            let client_arc = Self::require_client().await?;
            let c = client_arc.lock().await;
            c.account().set_display_name(Some(&name)).await?;
            AppResult::Ok(())
        });
    }

    pub fn setAvatar(&self, local_path: QString) {
        let path = local_path.to_string();
        self.spawn(async move {
            let client_arc = Self::require_client().await?;
            crate::file_transfer::set_avatar(client_arc, path).await
        });
    }

    /// Set the user's profile banner (stored locally — Matrix has no standard
    /// banner field). After the file is copied to the cache directory we nudge
    /// `ProfileManager` so its `bannerUrl` property updates and the QML
    /// `Image` binding reloads.
    pub fn setBanner(&self, local_path: QString) {
        let path = local_path.to_string();
        let qptr = QPointer::from(&*self);
        let done_cb = qmetaobject::queued_callback(move |url: String| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow().emit_banner_set(QString::from(url.as_str()));
                // Refresh ProfileManager so bannerUrl updates in QML.
                let pm = crate::profile::ProfileManager::get();
                if let Some(pm) = pm.as_pinned() {
                    pm.borrow().refresh();
                }
            }
        });
        self.spawn(async move {
            let url = crate::file_transfer::set_banner(path).await?;
            done_cb(url);
            AppResult::Ok(())
        });
    }

    pub fn setForceIpv6(&self, on: bool) {
        if let Some(s) = self.session.borrow_mut().as_mut() {
            s.force_ipv6 = on;
            self.persist_session();
        }
    }

    pub fn loadRoomMessages(&self, room_id: QString) {
        let room_id_str = room_id.to_string();
        ::log::info!("loadRoomMessages: room={} (current model count={})", room_id_str, MessageModel::get().as_pinned().map(|m| m.borrow().count()).unwrap_or(-1));
        let model = MessageModel::get();
        // Mark this room as the current target so stale responses
        // from a previous room are discarded by apply_entries.
        if let Some(m) = model.as_pinned() {
            m.borrow_mut().set_current_room(&room_id_str);
        }
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        let rid_for_signal = room_id_str.clone();
        let cb = qmetaobject::queued_callback(move |entries: Vec<MessageEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries, &rid_for_signal);
            }
        });
        self.spawn(async move {
            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            let entries = MessageModel::fetch_messages(client, room_id_str).await?;
            cb(entries);
            AppResult::Ok(())
        });
    }

    pub fn refreshRooms(&self) {
        ::log::info!("refreshRooms: starting room refresh");
        let rooms_ptr = RoomModel::get();
        let spaces_ptr = SpaceModel::get();
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => {
                ::log::warn!("refreshRooms: no client available, skipping");
                return;
            }
        };
        let rooms_cb = qmetaobject::queued_callback(move |entries: Vec<RoomEntry>| {
            ::log::info!("refreshRooms: applying {} room entries to RoomModel", entries.len());
            if let Some(r) = rooms_ptr.as_pinned() {
                r.borrow_mut().apply_entries(entries);
            } else {
                ::log::warn!("refreshRooms: RoomModel QPointer is null, dropping entries");
            }
        });
        let spaces_cb = qmetaobject::queued_callback(move |entries: Vec<SpaceEntry>| {
            if let Some(s) = spaces_ptr.as_pinned() {
                s.borrow_mut().apply_entries(entries);
            }
        });
        self.spawn(async move {
            let client: matrix_sdk::Client = {
                let c = client_arc.lock().await;
                c.clone()
            };
            let room_entries = RoomModel::fetch_rooms(client.clone()).await?;
            rooms_cb(room_entries);
            let space_entries = SpaceModel::fetch_spaces(client).await?;
            spaces_cb(space_entries);
            AppResult::Ok(())
        });
    }

    /// Deactivate (permanently delete) the current account.
    /// This is irreversible — the server will remove all account data.
    pub fn deleteAccount(&self) {
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        let qptr = QPointer::from(&*self);
        let deleted_cb = qmetaobject::queued_callback(move |_: ()| {
            if let Some(this) = qptr.as_pinned() {
                let mut mc = this.borrow_mut();
                *mc.inner.borrow_mut() = None;
                *mc.session.borrow_mut() = None;
                mc.set_user_id(String::new());
                mc.set_ready(false);
                mc.emit_logged_out();
            }
        });
        self.spawn(async move {
            let c = client_arc.lock().await;
            // Matrix v3 account deactivation endpoint
            use matrix_sdk::ruma::api::client::account::deactivate::v3::Request as DeactivateRequest;
            let request = DeactivateRequest::new();
            c.send(request).await?;
            drop(c);
            // Remove saved session
            let path = Self::session_file_path();
            let _ = std::fs::remove_file(&path);
            deleted_cb(());
            AppResult::Ok(())
        });
    }

    /// Load members for a room/space and populate MemberModel.
    pub fn loadRoomMembers(&self, room_id: QString) {
        let room_id_str = room_id.to_string();
        let model = MemberModel::get();
        let client_arc = match self.inner.borrow().clone() {
            Some(c) => c,
            None => return,
        };
        let cb = qmetaobject::queued_callback(move |entries: Vec<MemberEntry>| {
            if let Some(m) = model.as_pinned() {
                m.borrow_mut().apply_entries(entries);
            }
        });
        self.spawn(async move {
            let entries = MemberModel::fetch_members(client_arc, room_id_str).await?;
            cb(entries);
            AppResult::Ok(())
        });
    }

    /// Search users by (partial) username/display name using the
    /// `/_matrix/client/v3/user_directory/search` endpoint.
    ///
    /// Emits `usersSearchDone(json)` with up to 20 results:
    ///   `[{"user_id":"@alice:…","display_name":"Alice","avatar_url":"mxc://…"}, …]`
    /// `avatar_url` is omitted when the user has no avatar.
    pub fn searchUsers(&self, query: QString) {
        let q = query.to_string();
        if q.trim().is_empty() {
            // Empty query → empty results so the dialog can hide the list.
            let qptr = QPointer::from(&*self);
            let empty_cb = qmetaobject::queued_callback(move |_: ()| {
                if let Some(this) = qptr.as_pinned() {
                    this.borrow().emit_users_search_done(QString::from("[]"));
                }
            });
            empty_cb(());
            return;
        }
        let qptr = QPointer::from(&*self);
        let results_cb = qmetaobject::queued_callback(move |json: String| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow().emit_users_search_done(QString::from(json.as_str()));
            }
        });
        self.spawn(async move {
            let client_arc = Self::require_client().await?;
            let c = client_arc.lock().await;
            use matrix_sdk::ruma::api::client::user_directory::search_users::v3::Request as SearchUsersRequest;
            // The Request::new() takes the search_term as its only argument.
            let mut req = SearchUsersRequest::new(q);
            req.limit = 20u32.into();
            let resp = c.send(req).await?;
            // Serialize to JSON manually so QML can JSON.parse it.
            let mut arr = String::from("[");
            for (i, u) in resp.results.iter().enumerate() {
                if i > 0 { arr.push(','); }
                arr.push_str("{\"user_id\":");
                arr.push_str(&serde_json::to_string(&u.user_id.to_string())?);
                arr.push_str(",\"display_name\":");
                let dn = u.display_name.as_deref().unwrap_or("");
                arr.push_str(&serde_json::to_string(dn)?);
                arr.push_str(",\"avatar_url\":");
                let av = u.avatar_url.as_ref().map(|u| u.to_string()).unwrap_or_default();
                arr.push_str(&serde_json::to_string(&av)?);
                arr.push('}');
            }
            arr.push(']');
            results_cb(arr);
            AppResult::Ok(())
        });
    }

    /// Open (or create) a direct-message room with `user_id`.
    ///
    /// 1. If we already share a DM room with this user, switch to it.
    /// 2. Otherwise call `/_matrix/client/v3/createRoom` with `is_direct:true`
    ///    and invite the user.
    ///
    /// Emits `dmOpened(roomId)` on success.
    pub fn openDirectMessage(&self, user_id: QString) {
        let target = user_id.to_string();
        let qptr = QPointer::from(&*self);
        let opened_cb = qmetaobject::queued_callback(move |room_id: String| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow().emit_dm_opened(QString::from(room_id.as_str()));
            }
        });
        self.spawn(async move {
            let client_arc = Self::require_client().await?;
            let c = client_arc.lock().await;

            // Parse target user id.
            let target_uid: ruma::OwnedUserId = target.parse().map_err(|e: ruma::IdParseError|
                crate::errors::AppError::Other(e.to_string()))?;

            // Look for an existing DM room with this user.
            // A room is a DM if `room.is_dm()` returns true and `direct_targets()`
            // contains the target user id.
            let mut found_room: Option<String> = None;
            for room in c.rooms() {
                if room.state() != matrix_sdk::RoomState::Joined {
                    continue;
                }
                if room.is_space() {
                    continue;
                }
                let targets = room.direct_targets();
                if targets.iter().any(|t| t == &target_uid) {
                    found_room = Some(room.room_id().to_string());
                    break;
                }
            }

            if let Some(rid) = found_room {
                drop(c);
                opened_cb(rid);
                return AppResult::Ok(());
            }

            // No existing DM — create a new one.
            use matrix_sdk::ruma::api::client::room::create_room::v3::Request as CreateRoomRequest;
            use matrix_sdk::ruma::api::client::room::create_room::v3::RoomPreset;

            let mut req = CreateRoomRequest::new();
            req.is_direct = true;
            // ruma 0.16 create_room::v3::Request uses `invite: Vec<UserId>`,
            // not `invited_users`.
            req.invite.push(target_uid.clone());
            // `preset` is Option<RoomPreset>; `visibility` is already private
            // by default in the ruma builder, so we don't need to set it.
            req.preset = Some(RoomPreset::PrivateChat);

            // Mark the room as a DM via the `m.direct` account-data event.
            // matrix-sdk exposes this through client.account().set_direct().
            // We set is_direct=true on the create request (above) and also
            // mark the account-data below after the room is created.

            // Set a friendly initial name based on the other user's MXID.
            let initial_name = format!("DM with {}", target_uid);
            req.name = Some(initial_name);

            let resp = c.send(req).await?;
            // ruma's create_room::v3::Response has `room_id` as a public
            // field (not a method), so we access it directly.
            let new_room_id = resp.room_id.clone();
            let new_room_id_str = new_room_id.to_string();

            // Mark this room as a DM in our own account_data so
            // room.is_dm() / direct_targets() return true for it on the
            // next refresh. Uses the built-in mark_as_dm() which
            // correctly handles fetching the existing m.direct event,
            // merging, and re-uploading.
            let _ = c.account().mark_as_dm(
                &new_room_id,
                &[target_uid.clone()],
            ).await;
            drop(c);

            opened_cb(new_room_id_str);
            AppResult::Ok(())
        });
    }

    /// Leave (and forget) a room.
    ///
    /// Calls `/_matrix/client/v3/rooms/{roomId}/leave`. On success emits
    /// `roomLeft(roomId)` and refreshes the room list so the room disappears
    /// from the sidebar.
    pub fn leaveRoom(&self, room_id: QString) {
        let rid_str = room_id.to_string();
        let qptr = QPointer::from(&*self);
        let left_cb = qmetaobject::queued_callback(move |rid: String| {
            if let Some(this) = qptr.as_pinned() {
                this.borrow().emit_room_left(QString::from(rid.as_str()));
                this.borrow().refreshRooms();
            }
        });
        self.spawn(async move {
            let client_arc = Self::require_client().await?;
            let c = client_arc.lock().await;
            let rid: ruma::OwnedRoomId = rid_str.parse()
                .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
            if let Some(room) = c.get_room(&rid) {
                room.leave().await?;
            } else {
                // Already gone — treat as success.
            }
            drop(c);
            left_cb(rid_str);
            AppResult::Ok(())
        });
    }
}

// Internal helpers (not exposed to QML).
impl MatrixClient {
    pub fn singleton_ptr() -> QPointer<MatrixClient> {
        Self::get()
    }

    pub fn get() -> QPointer<MatrixClient> {
        MATRIXCLIENT_SINGLETON.get_or_init(|| QPointer::default()).clone()
    }

    /// Get the client Arc from the singleton, for use in async contexts
    /// where we can't hold a reference to self across an await point.
    pub async fn require_client() -> AppResult<Arc<Mutex<matrix_sdk::Client>>> {
        let qptr = Self::singleton_ptr();
        let pinned = qptr.as_pinned().ok_or(crate::errors::AppError::NotLoggedIn)?;
        let result = pinned.borrow().inner.borrow().clone()
            .ok_or(crate::errors::AppError::NotLoggedIn);
        result
    }

    fn persist_session(&self) {
        if let Some(s) = self.session.borrow().as_ref() {
            let path = Self::session_file_path();
            if let Ok(json) = serde_json::to_string_pretty(s) {
                let _ = std::fs::write(path, json);
            }
        }
    }

    fn make_matrix_session(
        user_id: &str,
        device_id: &str,
        access_token: String,
        refresh_token: Option<String>,
    ) -> AppResult<matrix_sdk::authentication::matrix::MatrixSession> {
        use matrix_sdk::authentication::matrix::MatrixSession;
        use matrix_sdk::{SessionMeta, SessionTokens};

        Ok(MatrixSession {
            meta: SessionMeta {
                user_id: user_id
                    .parse()
                    .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?,
                device_id: device_id.into(),
            },
            tokens: SessionTokens {
                access_token,
                refresh_token,
            },
        })
    }

    /// Restore session with all fields known.
    async fn do_restore_session_with_full(
        homeserver: String,
        user_id: String,
        device_id: String,
        access_token: String,
        force_ipv6: bool,
    ) -> AppResult<()> {
        // NOTE: We must NOT call `set_busy(true)` directly here. This
        // function runs on a Tokio worker thread, and Qt property
        // mutations / signal emissions from non-Qt threads do not
        // reliably propagate to QML. Instead, push a pending event
        // that will be applied on the Qt main thread by
        // `MatrixClient::pollPending()` (driven by a QML Timer).
        crate::pending::push(crate::pending::PendingEvent::SetBusy(true));

        let client = crate::auth::build_client(&homeserver, force_ipv6).await?;

        let session = Self::make_matrix_session(
            &user_id,
            &device_id,
            access_token.clone(),
            None,
        )?;
        client.restore_session(session).await?;

        let s = SessionStore {
            homeserver,
            user_id,
            device_id,
            access_token: client.access_token().unwrap_or_default(),
            refresh_token: None,
            force_ipv6,
        };

        Self::finish_login(client, &s).await
    }

    async fn do_password_login(
        homeserver: String,
        username: String,
        password: String,
        force_ipv6: bool,
    ) -> AppResult<()> {
        // See note in `do_restore_session_with_full`: must not call
        // `set_busy` directly from this Tokio context.
        crate::pending::push(crate::pending::PendingEvent::SetBusy(true));

        let client = crate::auth::build_client(&homeserver, force_ipv6).await?;

        client
            .matrix_auth()
            .login_username(&username, &password)
            .initial_device_display_name("Rustrix")
            .await?;

        let session_meta = client.session_meta()
            .ok_or(crate::errors::AppError::Other("no session after login".into()))?;
        let tokens = client.session_tokens()
            .ok_or(crate::errors::AppError::Other("no session tokens after login".into()))?;

        let s = SessionStore {
            homeserver,
            user_id: session_meta.user_id.to_string(),
            device_id: session_meta.device_id.to_string(),
            access_token: tokens.access_token,
            refresh_token: tokens.refresh_token,
            force_ipv6,
        };

        Self::finish_login(client, &s).await
    }

    async fn finish_login(
        client: matrix_sdk::Client,
        sess: &SessionStore,
    ) -> AppResult<()> {
        ::log::info!("finish_login: user={} device={}", sess.user_id, sess.device_id);
        let arc = Arc::new(Mutex::new(client));

        // Store the matrix_sdk::Client and SessionStore on the singleton.
        //
        // These two fields are interior-mutable `RefCell<Option<...>>`, not
        // `qt_property!`s — so writing them does NOT emit any Qt signal and
        // is safe to do from the Tokio thread (the `borrow_mut()` on the
        // RefCell is a runtime check, not a Qt-thread check). All other
        // Qt-side state changes (set_user_id, set_busy, set_ready,
        // emit_logged_in) are pushed to the pending-events queue and
        // applied on the Qt main thread by `MatrixClient::pollPending()`.
        //
        // We scope the `QPointer`/`QPinned` borrow so it is dropped before
        // we await anything later in this function.
        {
            let qptr = Self::singleton_ptr();
            if let Some(this) = qptr.as_pinned() {
                let mc = this.borrow();
                *mc.inner.borrow_mut() = Some(arc.clone());
                *mc.session.borrow_mut() = Some(sess.clone());
                mc.persist_session();
            }
        }

        // Push Qt-side state changes onto the pending-events queue.
        // `pollPending()` (called by a QML Timer every 100 ms) will drain
        // these and apply them on the Qt main thread, where signal
        // emissions actually propagate to QML.
        crate::pending::push(crate::pending::PendingEvent::SetUserId(sess.user_id.clone()));
        crate::pending::push(crate::pending::PendingEvent::SetBusy(true));
        crate::pending::push(crate::pending::PendingEvent::SetReady(false));
        crate::pending::push(crate::pending::PendingEvent::EmitLoggedIn(sess.user_id.clone()));
        ::log::info!("finish_login: queued loggedIn/set_busy/set_ready events for Qt thread");

        // NOTE: Do NOT call refreshRooms() here. The SDK's internal room
        // state is empty before the first sync. The sync loop below calls
        // RoomModel::fetch_rooms() after each cycle, which is when rooms
        // are actually available.

        // Clone the matrix_sdk::Client out of the Arc<Mutex<…>> before
        // starting the sync loop. `matrix_sdk::Client` is internally
        // `Arc`-backed and `Send + Sync`, so the clone shares state.
        // Holding the outer Mutex during sync() would block every other
        // code path that needs the client.
        let client_clone = {
            let c = arc.lock().await;
            c.clone()
        };

        // Track whether this is the first successful sync, so we can
        // push `SetReady(true)` + `SetBusy(false)` only once.
        let first_sync = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(true));

        let rt = crate::get_runtime();
        rt.spawn(async move {
            let mut sync_token: Option<String> = None;
            let mut sync_cycle: u32 = 0;
            // Count of consecutive sync_once failures. Reset to 0 on any
            // success. Used to suppress transient offline flicker — see
            // the error branch below.
            let mut consecutive_sync_failures: u32 = 0;
            // ── Rooms/spaces fetch throttle ──
            // The matrix-sdk sync_once long-poll returns every time the
            // server has new events (often, when the user is actively
            // chatting). Re-running fetch_rooms + fetch_spaces after every
            // cycle made the Tokio worker spin through every joined room
            // (calling room.display_name().await for each), then push the
            // full entry list to Qt which calls beginResetModel() on the
            // RoomModel — that's what held one core at ~20% CPU every time
            // the user sent a message.
            //
            // We now throttle: only fetch_rooms/fetch_spaces if at least
            // 30 s have passed since the last fetch. Initial sync always
            // fetches (handled below outside the loop). For active chat
            // this still means at most one full refresh per 30 s — the
            // sidebar will catch new-room / new-unread changes with a
            // small delay, which is fine; per-message updates arrive via
            // the timeline reload in ChatPage (syncReloadTimer, 400 ms).
            let mut last_fetch_at: Option<std::time::Instant> = None;
            let fetch_min_interval = std::time::Duration::from_secs(30);

            // ── Initial sync with retry ──
            let max_initial_retries: u32 = 5;
            for attempt in 1..=max_initial_retries {
                ::log::info!("sync: initial sync attempt {}/{}", attempt, max_initial_retries);
                let initial_settings = matrix_sdk::config::SyncSettings::default()
                    .timeout(std::time::Duration::from_secs(10));
                match client_clone.sync_once(initial_settings).await {
                    Ok(response) => {
                        sync_token = Some(response.next_batch);
                        ::log::info!("sync: initial sync OK on attempt {}, next_batch present={}", attempt, sync_token.is_some());
                        // Fetch rooms/spaces on Tokio, push the entries to
                        // the pending queue, and let pollPending() apply
                        // them on the Qt thread.
                        match RoomModel::fetch_rooms(client_clone.clone()).await {
                            Ok(room_entries) => {
                                ::log::info!("sync: fetched {} rooms after initial sync", room_entries.len());
                                crate::pending::push(
                                    crate::pending::PendingEvent::ApplyRooms(room_entries)
                                );
                            }
                            Err(e) => ::log::warn!("sync: fetch_rooms after initial sync error: {e}"),
                        }
                        match SpaceModel::fetch_spaces(client_clone.clone()).await {
                            Ok(space_entries) => {
                                crate::pending::push(
                                    crate::pending::PendingEvent::ApplySpaces(space_entries)
                                );
                            }
                            Err(e) => ::log::warn!("sync: fetch_spaces after initial sync error: {e}"),
                        }
                        // Stamp the throttle so the main loop doesn't
                        // immediately re-fetch right after initial sync.
                        last_fetch_at = Some(std::time::Instant::now());
                        // Emit syncDone so ChatPage can reload messages.
                        crate::pending::push(crate::pending::PendingEvent::EmitSyncDone);
                        // On the very first sync, mark ready + clear busy.
                        if first_sync.swap(false, std::sync::atomic::Ordering::SeqCst) {
                            ::log::info!("sync: first sync done — queueing ready=true, busy=false");
                            crate::pending::push(crate::pending::PendingEvent::SetReady(true));
                            crate::pending::push(crate::pending::PendingEvent::SetBusy(false));
                        }
                        crate::pending::push(crate::pending::PendingEvent::RefreshProfile);
                        crate::pending::push(crate::pending::PendingEvent::SetOffline(false));
                        break; // success — exit retry loop
                    }
                    Err(e) => {
                        let backoff = std::time::Duration::from_secs(5 * attempt as u64);
                        ::log::warn!("sync: initial sync attempt {} failed: {e} — retrying in {:?}", attempt, backoff);
                        if attempt < max_initial_retries {
                            tokio::time::sleep(backoff).await;
                        }
                    }
                }
            }

            // ── Main sync loop ──
            loop {
                sync_cycle += 1;
                let mut sync_settings = matrix_sdk::config::SyncSettings::default()
                    .timeout(std::time::Duration::from_secs(30));
                if let Some(token) = sync_token.take() {
                    sync_settings = sync_settings.token(token);
                }
                ::log::debug!("sync_once: starting cycle #{}", sync_cycle);
                let start = std::time::Instant::now();
                let result = client_clone.sync_once(sync_settings).await;
                let elapsed = start.elapsed();
                match result {
                    Ok(response) => {
                        sync_token = Some(response.next_batch);
                        // Reset the consecutive-failure counter — the
                        // server is alive, so any prior offline flag
                        // should be cleared (pushed below).
                        consecutive_sync_failures = 0;
                        ::log::info!(
                            "sync_once: cycle #{} OK in {:.1}s, next_batch token present={}",
                            sync_cycle, elapsed.as_secs_f64(), sync_token.is_some()
                        );
                        // ── Throttled room/space list refresh ──
                        // See the comment on `last_fetch_at` above: a full
                        // fetch_rooms / fetch_spaces pass after every
                        // sync_once was the #1 cause of 20 % CPU usage
                        // during active chat. We skip the refresh if less
                        // than `fetch_min_interval` (30 s) has passed
                        // since the last refresh. Per-message UI updates
                        // still arrive via ChatPage's syncReloadTimer
                        // (which fires on the syncDone signal below).
                        let should_fetch = match last_fetch_at {
                            None => true,
                            Some(t) => t.elapsed() >= fetch_min_interval,
                        };
                        if should_fetch {
                            match RoomModel::fetch_rooms(client_clone.clone()).await {
                                Ok(room_entries) => {
                                    ::log::info!("sync: fetched {} rooms after cycle #{}", room_entries.len(), sync_cycle);
                                    crate::pending::push(
                                        crate::pending::PendingEvent::ApplyRooms(room_entries)
                                    );
                                }
                                Err(e) => ::log::warn!("sync: fetch_rooms error after cycle #{}: {e}", sync_cycle),
                            }
                            match SpaceModel::fetch_spaces(client_clone.clone()).await {
                                Ok(space_entries) => {
                                    crate::pending::push(
                                        crate::pending::PendingEvent::ApplySpaces(space_entries)
                                    );
                                }
                                Err(e) => ::log::warn!("sync: fetch_spaces error after cycle #{}: {e}", sync_cycle),
                            }
                            last_fetch_at = Some(std::time::Instant::now());
                        } else {
                            ::log::debug!(
                                "sync: skipping fetch_rooms/spaces on cycle #{} (throttled, {:?} since last fetch)",
                                sync_cycle,
                                last_fetch_at.map(|t| t.elapsed()).unwrap_or_default()
                            );
                        }
                        crate::pending::push(crate::pending::PendingEvent::EmitSyncDone);
                        crate::pending::push(crate::pending::PendingEvent::RefreshProfile);
                        crate::pending::push(crate::pending::PendingEvent::SetOffline(false));
                    }
                    Err(e) => {
                        // ── Less aggressive offline detection ──
                        // The matrix-sdk long-poll sync uses a 30s server
                        // timeout. When the network blips or the server
                        // takes slightly longer, sync_once returns an
                        // error — but that's NOT actually "offline": the
                        // next sync cycle will succeed. We were flipping
                        // the offline flag on every transient error,
                        // which made the chat composer flash "Offline"
                        // even though the server was alive.
                        //
                        // Now we only mark offline after 3 CONSECUTIVE
                        // failures (≈15s of dead network), and we never
                        // mark offline for timeout-class errors at all
                        // (they're expected behaviour of long-poll).
                        let err_str = format!("{e}").to_lowercase();
                        let is_timeout = err_str.contains("timeout")
                            || err_str.contains("timed out")
                            || err_str.contains("operation timed")
                            || err_str.contains("request timed");
                        consecutive_sync_failures = consecutive_sync_failures.saturating_add(1);
                        if !is_timeout && consecutive_sync_failures >= 3 {
                            crate::pending::push(crate::pending::PendingEvent::SetOffline(true));
                        } else if is_timeout {
                            // Timeouts are expected; don't toggle offline
                            // at all — log only.
                            ::log::info!("sync_once: timeout on cycle #{} ({}s) — ignoring, server likely alive", sync_cycle, elapsed.as_secs());
                        }
                        let backoff_secs = std::cmp::min(5 * 2u64.pow(std::cmp::min(sync_cycle, 4)), 60);
                        ::log::warn!("sync_once: cycle #{} error after {:.1}s: {e} — retry in {}s (consecutive failures: {}{})",
                            sync_cycle, elapsed.as_secs_f64(), backoff_secs, consecutive_sync_failures,
                            if is_timeout { " [timeout — not marking offline]" } else { "" });
                        tokio::time::sleep(std::time::Duration::from_secs(backoff_secs)).await;
                    }
                }
            }
        });

        Ok(())
    }
}

impl qmetaobject::QSingletonInit for MatrixClient {
    fn init(&mut self) {
        // Store the QPointer for global access from async contexts.
        MATRIXCLIENT_SINGLETON.set(QPointer::from(&*self));
    }
}
