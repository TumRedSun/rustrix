//! `MessageModel` — chronological list of events in a room.

use qmetaobject::*;
use std::cell::RefCell;

/// Module-level singleton storage for MessageModel.
static SINGLETON: crate::singleton::QtSingleton<QPointer<MessageModel>> =
    crate::singleton::QtSingleton::new();

#[derive(Default, Clone, qmetaobject::SimpleListItem)]
pub struct MessageEntry {
    pub event_id: QString,
    pub sender: QString,
    pub sender_display: QString,
    pub avatar_url: QString,
    pub body: QString,           // plain text fallback
    pub body_html: QString,      // rendered HTML for rich content
    pub ts: i64,                 // epoch millis
    pub is_own: bool,
    pub kind: QString,           // "text" | "image" | "video" | "file" | "audio" | "system" | "encrypted"
    pub mxc_url: QString,        // mxc:// for media messages (empty if encrypted)
    pub media_source_json: QString, // Serialized MediaSource (Plain or Encrypted) for proper download
    pub file_name: QString,
    pub file_size: i64,
    pub mime_type: QString,
    pub reply_to: QString,
    /// Reactions for this message, encoded as a JSON array string.
    ///
    /// Format:
    ///   [{"key":"👍","count":2,"includes_me":true,
    ///     "senders":[{"user_id":"@a:b","display_name":"Alice"},
    ///                 {"user_id":"@b:b","display_name":"Bob"}]},
    ///    ...]
    ///
    /// QML parses this with JSON.parse() and renders a chip per entry
    /// showing emoji + count. LMB on a chip toggles our own reaction;
    /// RMB opens a popup listing senders.
    ///
    /// Empty string means "no reactions".
    pub reactions: QString,
    pub edited: bool,
    pub pending: bool,
    pub failed: bool,
}

#[derive(QObject, Default)]
pub struct MessageModel {
    base: qt_base_class!(trait QAbstractListModel),
    entries: RefCell<Vec<MessageEntry>>,
    /// Tracks which room's messages are currently displayed so that
    /// stale async responses (from a previous room) can be discarded.
    current_room_id: RefCell<Option<String>>,

    count: qt_property!(i64; READ count NOTIFY count_changed),
    count_changed: qt_signal!(),

    /// Emitted when the room's history is fully (re)loaded.
    historyLoaded: qt_signal!(room_id: QString),
    /// Emitted when a single new event was appended.
    eventAppended: qt_signal!(event_id: QString),

    /// Remove a single event from the local model by event_id. This is
    /// the "Hide for me" action from the message context menu — purely
    /// visual, doesn't touch the server. The event reappears on the next
    /// full reload (sync / room switch) because we don't persist the
    /// hidden state.
    hideEvent: qt_method!(fn(&mut self, event_id: QString)),
}

/// Helper to extract a URL string from a MediaSource enum.
fn media_source_url(source: &matrix_sdk::ruma::events::room::MediaSource) -> Option<&str> {
    match source {
        matrix_sdk::ruma::events::room::MediaSource::Plain(uri) => Some(uri.as_str()),
        matrix_sdk::ruma::events::room::MediaSource::Encrypted(file) => Some(file.url.as_str()),
    }
}

/// Serialize a `MediaSource` to JSON so QML can pass it back to
/// `download_media` for proper download (works for both Plain and
/// Encrypted media — encrypted sources carry the key/IV/hashes needed
/// for decryption).
fn serialize_media_source(source: &matrix_sdk::ruma::events::room::MediaSource) -> String {
    serde_json::to_string(source).unwrap_or_default()
}

impl MessageModel {
    pub fn count(&self) -> i64 {
        self.entries.borrow().len() as i64
    }

    /// Pure async data fetching — does NOT take `&self` so the future is `Send`.
    /// Returns the parsed message entries; the caller is responsible for
    /// applying them to the model on the Qt thread (e.g. via queued_callback).
    pub async fn fetch_messages(
        client: matrix_sdk::Client,
        room_id: String,
    ) -> crate::errors::AppResult<Vec<MessageEntry>> {
        ::log::info!("fetch_messages: loading messages for room={}", room_id);
        let rid: ruma::OwnedRoomId = room_id
            .parse()
            .map_err(|e: ruma::IdParseError| crate::errors::AppError::Other(e.to_string()))?;
        let room = client
            .get_room(&rid)
            .ok_or_else(|| crate::errors::AppError::RoomNotFound(room_id.clone()))?;

        let me = client
            .user_id()
            .map(|u| u.to_owned())
            .ok_or(crate::errors::AppError::NotLoggedIn)?;

        // Build a HashMap of user_id -> (display_name, avatar_url) from
        // the room's member cache so we can populate sender_display and
        // avatar_url for each message.
        let mut member_map: std::collections::HashMap<String, (String, String)> = std::collections::HashMap::new();
        match room.members(matrix_sdk::RoomMemberships::ACTIVE).await {
            Ok(members) => {
                for member in members {
                    let uid = member.user_id().to_string();
                    let display_name = member.display_name().unwrap_or("").to_string();
                    let avatar = member.avatar_url().map(|u| u.to_string()).unwrap_or_default();
                    member_map.insert(uid, (display_name, avatar));
                }
                ::log::info!("fetch_messages: loaded {} room members for display name lookup", member_map.len());
            }
            Err(e) => {
                ::log::warn!("fetch_messages: failed to load room members: {e}");
            }
        }

        let mut messages: Vec<MessageEntry> = Vec::new();

        // ── Use matrix-sdk-ui Timeline for proper E2EE decryption ──
        // The room.messages() API returns raw encrypted events that the SDK
        // cannot decrypt retroactively. The Timeline API from matrix-sdk-ui
        // handles decryption automatically by integrating with the crypto
        // machine that processes room keys received via sync.
        //
        // We create a temporary Timeline, paginate backwards, read the
        // (now decrypted) items, then drop the Timeline.
        use matrix_sdk_ui::timeline::{TimelineItemKind, TimelineBuilder};

        let timeline = match TimelineBuilder::new(&room).build().await {
            Ok(t) => {
                ::log::info!("fetch_messages: Timeline created for room={}", room_id);
                t
            }
            Err(e) => {
                ::log::warn!("fetch_messages: Timeline::build failed: {e} — falling back to room.messages()");
                // Fallback: use old room.messages() path (won't decrypt E2EE)
                return Self::fetch_messages_fallback(client, room_id, room.clone(), me.clone(), member_map).await;
            }
        };

        // Paginate backwards to load history
        match timeline.paginate_backwards(50).await {
            Ok(_hit_end) => ::log::info!("fetch_messages: Timeline pagination OK"),
            Err(e) => ::log::warn!("fetch_messages: Timeline pagination error: {e}"),
        }

        // Read items from the timeline
        let items = timeline.items().await;
        ::log::info!("fetch_messages: Timeline returned {} items", items.len());

        for item in items.iter() {
            let event_item = match item.kind() {
                TimelineItemKind::Event(ev) => ev,
                TimelineItemKind::Virtual(_) => continue,
            };

            let event_id_str = event_item.event_id()
                .map(|id| id.to_string())
                .unwrap_or_default();
            let sender_str = event_item.sender().to_string();
            let is_own = event_item.is_own();

            // Timestamp
            let ts_val = i64::try_from(event_item.timestamp().0).unwrap_or(0);

            // Display name and avatar from profile
            let (display_name, avatar_url) = {
                let profile = event_item.sender_profile();
                match profile {
                    matrix_sdk_ui::timeline::TimelineDetails::Ready(p) => {
                        let dn = p.display_name.as_deref().unwrap_or("").to_string();
                        let av = p.avatar_url.as_ref().map(|u| u.to_string()).unwrap_or_default();
                        (dn, av)
                    }
                    _ => member_map
                        .get(&sender_str)
                        .map(|(dn, av)| (dn.clone(), av.clone()))
                        .unwrap_or_default(),
                }
            };

            let mut entry = MessageEntry {
                event_id: QString::from(event_id_str.as_str()),
                ts: ts_val,
                sender: QString::from(sender_str.as_str()),
                sender_display: QString::from(display_name.as_str()),
                avatar_url: QString::from(avatar_url.as_str()),
                is_own,
                ..Default::default()
            };

            // Extract message content from TimelineItemContent
            use matrix_sdk_ui::timeline::TimelineItemContent;
            match event_item.content() {
                TimelineItemContent::MsgLike(msg_like) => {
                    use matrix_sdk_ui::timeline::MsgLikeKind;
                    match &msg_like.kind {
                        MsgLikeKind::Message(msg) => {
                            use matrix_sdk::ruma::events::room::message::MessageType;
                            // ── Extract reply target ──
                            // The reply info and the reactions live on the
                            // outer `MsgLikeContent` (the wrapper around
                            // `MsgLikeKind`), not on `Message` itself — both
                            // are public fields on `msg_like`. We read them
                            // here, inside the `Message` arm, so the QML side
                            // gets a reply quote + reaction chips for normal
                            // text/image/etc. messages.
                            //
                            // `in_reply_to` is `Option<InReplyToDetails>`.
                            // `InReplyToDetails` does NOT impl `Display`, so
                            // we read its `event_id: OwnedEventId` field and
                            // stringify *that* (OwnedEventId impls Display).
                            if let Some(replied_to) = &msg_like.in_reply_to {
                                entry.reply_to =
                                    QString::from(replied_to.event_id.to_string().as_str());
                            }
                            // ── Extract reactions ──
                            // `msg_like.reactions` is `ReactionsByKeyBySender`,
                            // which derefs to `IndexMap<String,
                            // IndexMap<OwnedUserId, ReactionInfo>>`. We
                            // build a JSON array of objects, one per
                            // reaction key, each containing:
                            //   - key: the emoji string
                            //   - count: number of senders
                            //   - includes_me: whether the current user reacted
                            //   - senders: array of {user_id, display_name}
                            //
                            // Display names come from member_map (populated
                            // at the top of fetch_messages). The QML side
                            // parses this JSON and renders chips with
                            // count + LMB-toggle + RMB-popup behavior.
                            {
                                let reactions = &msg_like.reactions;
                                if !reactions.is_empty() {
                                    let me_id_str = me.to_string();
                                    let mut json_items: Vec<String> = Vec::new();
                                    for (key, senders) in reactions.iter() {
                                        let mut sender_list: Vec<String> = Vec::new();
                                        let mut includes_me = false;
                                        for (uid, _info) in senders.iter() {
                                            let uid_str = uid.to_string();
                                            if uid_str == me_id_str {
                                                includes_me = true;
                                            }
                                            let display = member_map
                                                .get(&uid_str)
                                                .map(|(dn, _)| dn.clone())
                                                .filter(|dn| !dn.is_empty())
                                                .unwrap_or_else(|| uid_str.clone());
                                            sender_list.push(format!(
                                                "{{\"user_id\":{},\"display_name\":{}}}",
                                                serde_json::to_string(&uid_str).unwrap_or_else(|_| "\"\"".into()),
                                                serde_json::to_string(&display).unwrap_or_else(|_| "\"\"".into())
                                            ));
                                        }
                                        json_items.push(format!(
                                            "{{\"key\":{},\"count\":{},\"includes_me\":{},\"senders\":[{}]}}",
                                            serde_json::to_string(key).unwrap_or_else(|_| "\"\"".into()),
                                            sender_list.len(),
                                            if includes_me { "true" } else { "false" },
                                            sender_list.join(",")
                                        ));
                                    }
                                    if !json_items.is_empty() {
                                        let json = format!("[{}]", json_items.join(","));
                                        entry.reactions = QString::from(json.as_str());
                                        ::log::debug!(
                                            "fetch_messages: event {} has {} reaction keys: {}",
                                            event_id_str, json_items.len(), json
                                        );
                                    }
                                }
                            }
                            match msg.msgtype() {
                                MessageType::Text(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(t.body.as_str());
                                    if let Some(formatted) = &t.formatted {
                                        entry.body_html = QString::from(formatted.body.as_str());
                                    }
                                }
                                MessageType::Emote(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(format!("* {}", t.body));
                                }
                                MessageType::Notice(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(t.body.as_str());
                                }
                                MessageType::Image(t) => {
                                    entry.kind = QString::from("image");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("image/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::Video(t) => {
                                    entry.kind = QString::from("video");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("video/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::File(t) => {
                                    entry.kind = QString::from("file");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("application/octet-stream")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::Audio(t) => {
                                    entry.kind = QString::from("audio");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("audio/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                _ => {
                                    entry.kind = QString::from("system");
                                    entry.body = QString::from("(unsupported message type)");
                                }
                            }
                        }
                        MsgLikeKind::Sticker(s) => {
                            entry.kind = QString::from("image");
                            entry.body = QString::from(s.content().body.as_str());
                            entry.mxc_url = QString::from(
                                match &s.content().source {
                                    matrix_sdk::ruma::events::sticker::StickerMediaSource::Plain(uri) => uri.as_str(),
                                    matrix_sdk::ruma::events::sticker::StickerMediaSource::Encrypted(_) => "",
                                    _ => "",
                                }
                            );
                        }
                        MsgLikeKind::Redacted => {
                            entry.kind = QString::from("system");
                            entry.body = QString::from("(message deleted)");
                        }
                        MsgLikeKind::UnableToDecrypt(_) => {
                            // Use a dedicated "encrypted" kind so the QML
                            // delegate can render it differently from a
                            // regular system notice — same centered
                            // muted italic line, but with explicit
                            // "decryption pending" wording so the user
                            // understands WHY the message is blank.
                            //
                            // The most common cause of mass UnableToDecrypt
                            // is the Olm identity bootstrap problem:
                            // session.json was created before the SQLite
                            // crypto store was enabled, so the device_id
                            // in session.json doesn't match the new Olm
                            // identity in the DB. The fix is to log out
                            // and log back in fresh.
                            entry.kind = QString::from("encrypted");
                            entry.is_own = false;
                            entry.body = QString::from("");
                        }
                        _ => {
                            entry.kind = QString::from("system");
                            entry.body = QString::from("(event)");
                        }
                    }
                }
                TimelineItemContent::MembershipChange(m) => {
                    use matrix_sdk_ui::timeline::MembershipChange as MCh;
                    entry.kind = QString::from("system");
                    // Build a human-readable sentence instead of dumping
                    // the raw user_id. Prefer the display name when we
                    // have one; fall back to the user_id.
                    let who = m.display_name()
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| m.user_id().to_string());
                    let verb = match m.change() {
                        Some(MCh::Joined) => "joined",
                        Some(MCh::Left) => "left",
                        Some(MCh::Banned) => "was banned",
                        Some(MCh::Unbanned) => "was unbanned",
                        Some(MCh::Kicked) => "was kicked",
                        Some(MCh::Invited) => "was invited",
                        Some(MCh::KickedAndBanned) => "was kicked and banned",
                        Some(MCh::InvitationAccepted) => "accepted the invite",
                        Some(MCh::InvitationRejected) => "rejected the invite",
                        Some(MCh::InvitationRevoked) => "had their invite revoked",
                        Some(MCh::Knocked) => "knocked",
                        Some(MCh::KnockAccepted) => "had their knock accepted",
                        Some(MCh::KnockRetracted) => "retracted their knock",
                        Some(MCh::KnockDenied) => "had their knock denied",
                        _ => "changed membership",
                    };
                    entry.body = QString::from(format!("{} {}", who, verb));
                }
                TimelineItemContent::ProfileChange(p) => {
                    entry.kind = QString::from("system");
                    // Build a readable description of the profile change.
                    // Only describe the display name change for now (the
                    // most common case); avatar changes are too noisy in
                    // a DM and would flood the timeline.
                    let who = display_name.clone();
                    if let Some(dn_change) = p.displayname_change() {
                        let new_dn = dn_change.new.as_deref().unwrap_or("");
                        let old_dn = dn_change.old.as_deref().unwrap_or("");
                        if !new_dn.is_empty() && old_dn.is_empty() {
                            entry.body = QString::from(format!("{} set their display name to \"{}\"", who, new_dn));
                        } else if !new_dn.is_empty() {
                            entry.body = QString::from(format!("{} changed their display name to \"{}\"", who, new_dn));
                        } else {
                            entry.body = QString::from(format!("{} removed their display name", who));
                        }
                    } else {
                        entry.body = QString::from(format!("{} updated their profile", who));
                    }
                }
                _ => {
                    entry.kind = QString::from("system");
                    entry.body = QString::from("(event)");
                }
            }

            messages.push(entry);
        }

        let own_c = messages.iter().filter(|m| m.is_own).count();
        let enc_c = messages.iter().filter(|m| m.kind.to_string() == "encrypted").count();
        let system_c = messages.iter().filter(|m| m.kind.to_string() == "system").count();
        let other_c = messages.iter().filter(|m| {
            !m.is_own
                && m.kind.to_string() != "system"
                && m.kind.to_string() != "encrypted"
        }).count();
        let img_c = messages.iter().filter(|m| m.kind.to_string() == "image").count();
        ::log::info!(
            "fetch_messages: parsed {} messages for room={} (own={}, other={}, system={}, encrypted={}, images={})",
            messages.len(), room_id, own_c, other_c, system_c, enc_c, img_c
        );

        Ok(messages)
    }


    /// Fallback: fetch messages using room.messages() without Timeline decryption.
    /// Used when Timeline::build() fails (e.g., missing features).
    async fn fetch_messages_fallback(
        _client: matrix_sdk::Client,
        room_id: String,
        room: matrix_sdk::Room,
        me: ruma::OwnedUserId,
        member_map: std::collections::HashMap<String, (String, String)>,
    ) -> crate::errors::AppResult<Vec<MessageEntry>> {
        let mut messages: Vec<MessageEntry> = Vec::new();
        let mut options = matrix_sdk::room::MessagesOptions::backward();
        options.limit = 50u32.into();
        let result = room.messages(options).await?;

        let mut taken: Vec<_> = result.chunk.into_iter().take(50).collect();
        taken.reverse();

        for timeline_event in taken {
            use matrix_sdk::deserialized_responses::TimelineEventKind;
            use matrix_sdk::ruma::events::AnySyncTimelineEvent;

            let any_event: AnySyncTimelineEvent = match timeline_event.kind {
                TimelineEventKind::PlainText { event } => {
                    match event.deserialize() { Ok(e) => e, Err(_) => continue }
                }
                TimelineEventKind::UnableToDecrypt { event, .. } => {
                    match event.deserialize() { Ok(e) => e, Err(_) => continue }
                }
                TimelineEventKind::Decrypted(decrypted) => {
                    match decrypted.event.cast::<AnySyncTimelineEvent>().deserialize() {
                        Ok(e) => e, Err(_) => continue,
                    }
                }
            };

            let event_id_str = any_event.event_id().to_string();
            let sender_str = any_event.sender().to_string();
            let ts_val = u64::from(any_event.origin_server_ts().0) as i64;
            let is_own = any_event.sender() == me;

            let (display_name, avatar_url) = member_map
                .get(&sender_str)
                .map(|(dn, av)| (dn.clone(), av.clone()))
                .unwrap_or_default();

            let mut entry = MessageEntry {
                event_id: QString::from(event_id_str.as_str()),
                ts: ts_val,
                sender: QString::from(sender_str.as_str()),
                sender_display: QString::from(display_name.as_str()),
                avatar_url: QString::from(avatar_url.as_str()),
                is_own,
                ..Default::default()
            };

            use matrix_sdk::ruma::events::AnySyncMessageLikeEvent;
            match &any_event {
                AnySyncTimelineEvent::MessageLike(msg_like) => {
                    match msg_like {
                        AnySyncMessageLikeEvent::RoomMessage(msg) => {
                            let Some(original) = msg.as_original() else { continue };
                            use matrix_sdk::ruma::events::room::message::MessageType;
                            match &original.content.msgtype {
                                MessageType::Text(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(t.body.as_str());
                                    if let Some(formatted) = &t.formatted {
                                        entry.body_html = QString::from(formatted.body.as_str());
                                    }
                                }
                                MessageType::Emote(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(format!("* {}", t.body));
                                }
                                MessageType::Notice(t) => {
                                    entry.kind = QString::from("text");
                                    entry.body = QString::from(t.body.as_str());
                                }
                                MessageType::Image(t) => {
                                    entry.kind = QString::from("image");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("image/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::Video(t) => {
                                    entry.kind = QString::from("video");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("video/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::File(t) => {
                                    entry.kind = QString::from("file");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("application/octet-stream")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                MessageType::Audio(t) => {
                                    entry.kind = QString::from("audio");
                                    entry.mxc_url = QString::from(media_source_url(&t.source).unwrap_or(""));
                                    entry.media_source_json = QString::from(serialize_media_source(&t.source).as_str());
                                    entry.body = QString::from(t.body.as_str());
                                    entry.file_name = QString::from(t.body.as_str());
                                    entry.mime_type = QString::from(
                                        t.info.as_ref().and_then(|i| i.mimetype.as_deref()).unwrap_or("audio/*")
                                    );
                                    entry.file_size = t.info.as_ref()
                                        .and_then(|i| i.size)
                                        .map(|s| u64::from(s) as i64)
                                        .unwrap_or(0);
                                }
                                _ => {
                                    entry.kind = QString::from("system");
                                    entry.body = QString::from("(unsupported message type)");
                                }
                            }
                        }
                        AnySyncMessageLikeEvent::RoomEncrypted(_) => {
                            entry.kind = QString::from("system");
                            entry.is_own = false;
                            entry.body = QString::from("🔒 Encrypted message (decryption pending)");
                        }
                        _ => continue,
                    }
                }
                AnySyncTimelineEvent::State(_) => continue,
            }

            messages.push(entry);
        }

        let own_c = messages.iter().filter(|m| m.is_own).count();
        ::log::info!(
            "fetch_messages_fallback: parsed {} messages for room={} (own={})",
            messages.len(), room_id, own_c
        );
        Ok(messages)
    }

    /// Apply a pre-fetched list of entries on the Qt thread.
    /// Must only be called from the Qt event loop (e.g. inside a queued_callback).
    ///
    /// If `current_room_id` is set and differs from `room_id`, the
    /// response is discarded — the user has since switched to a
    /// different room and these entries are stale.
    ///
    /// ── Incremental update (flicker fix) ──
    /// A full begin_reset_model makes the ListView destroy and re-create
    /// every visible delegate, which shows as a one-frame flash of the
    /// whole chat on every sync-triggered reload. The common reload
    /// outcomes are handled with granular model signals instead:
    ///   1. identical content                          → no signals at all
    ///   2. same rows, some changed (edit / reaction)  → dataChanged per row
    ///   3. new messages prepended (newest-first list) → insertRows at the
    ///      top + dataChanged for changed shared rows
    /// Anything else (order shuffle, middle removals, first load, room
    /// switch) falls back to the old full reset.
    pub fn apply_entries(&mut self, mut entries: Vec<MessageEntry>, room_id: &str) {
        // Guard against stale responses: if the user navigated to a
        // different room while the fetch was in flight, skip.
        let current = self.current_room_id.borrow().clone();
        if let Some(ref cur) = current {
            if cur != room_id {
                ::log::warn!(
                    "apply_entries: discarding stale response for {} (current: {})",
                    room_id, cur
                );
                return;
            }
        }
        // Reverse to newest-first order so that the ListView with
        // BottomToTop direction shows the newest message at the bottom
        // (index 0 = bottom in BottomToTop).
        entries.reverse();

        let old_len = self.entries.borrow().len();

        // Case 1: same ids in the same order → in-place row updates only.
        if old_len == entries.len() {
            let identical = {
                let old = self.entries.borrow();
                old.iter().zip(entries.iter()).all(|(a, b)| a.event_id == b.event_id)
            };
            if identical {
                let changed: Vec<usize> = {
                    let old = self.entries.borrow();
                    (0..entries.len())
                        .filter(|&i| !Self::rows_equal(&old[i], &entries[i]))
                        .collect()
                };
                if changed.is_empty() {
                    ::log::info!(
                        "apply_entries: {} rows identical — model untouched",
                        entries.len()
                    );
                    return;
                }
                {
                    let mut cur = self.entries.borrow_mut();
                    for &i in &changed {
                        cur[i] = entries[i].clone();
                    }
                }
                for &i in &changed {
                    let idx = self.row_index(i as i32);
                    self.data_changed(idx, idx);
                }
                ::log::info!(
                    "apply_entries: updated {} of {} rows in place (no reset)",
                    changed.len(),
                    entries.len()
                );
                return;
            }
        }

        // Case 2: the old rows are a contiguous suffix of the new rows —
        // new messages were prepended to the newest-first list (the normal
        // "new message arrived" reload). Insert them without touching the
        // shared rows' delegates.
        if entries.len() > old_len {
            let is_suffix = {
                let old = self.entries.borrow();
                entries[entries.len() - old_len..]
                    .iter()
                    .zip(old.iter())
                    .all(|(b, a)| b.event_id == a.event_id)
            };
            if is_suffix {
                let k = entries.len() - old_len;
                // Changed shared rows, in NEW indices (shifted by k).
                let changed_shared: Vec<usize> = {
                    let old = self.entries.borrow();
                    (0..old_len)
                        .filter(|&i| !Self::rows_equal(&old[i], &entries[k + i]))
                        .map(|i| k + i)
                        .collect()
                };
                let first_load = old_len == 0;
                self.begin_insert_rows(0, k as i32 - 1);
                *self.entries.borrow_mut() = entries;
                self.end_insert_rows();
                for &i in &changed_shared {
                    let idx = self.row_index(i as i32);
                    self.data_changed(idx, idx);
                }
                self.count_changed();
                // Only the very first load needs the "pin to bottom" nudge
                // (onHistoryLoaded in QML). For live appends the ListView
                // already shows the inserted bottom rows when the user is
                // at the bottom, and keeps their scroll position when they
                // are reading history.
                if first_load {
                    self.historyLoaded(QString::from(room_id));
                }
                ::log::info!(
                    "apply_entries: inserted {} new rows ({} shared rows updated, no reset)",
                    k,
                    changed_shared.len()
                );
                return;
            }
        }

        // Case 3: fallback — full reset (first load with mismatched
        // content, room switch, reshuffle, middle removals).
        let own_count = entries.iter().filter(|m| m.is_own).count();
        let other_count = entries.iter().filter(|m| !m.is_own && m.kind.to_string() != "system").count();
        let system_count = entries.iter().filter(|m| m.kind.to_string() == "system").count();
        ::log::info!(
            "MessageModel::apply_entries: reset with {} messages for room={} (own={}, other={}, system={}), replacing {} existing",
            entries.len(), room_id, own_count, other_count, system_count, old_len
        );
        self.begin_reset_model();
        *self.entries.borrow_mut() = entries;
        self.end_reset_model();
        self.count_changed();
        self.historyLoaded(QString::from(room_id));
        ::log::info!("MessageModel::apply_entries: model reset complete, count={}", self.entries.borrow().len());
    }

    /// True when two rows render identically (all QML-visible fields equal).
    fn rows_equal(a: &MessageEntry, b: &MessageEntry) -> bool {
        a.event_id == b.event_id
            && a.sender == b.sender
            && a.sender_display == b.sender_display
            && a.avatar_url == b.avatar_url
            && a.body == b.body
            && a.body_html == b.body_html
            && a.ts == b.ts
            && a.is_own == b.is_own
            && a.kind == b.kind
            && a.mxc_url == b.mxc_url
            && a.media_source_json == b.media_source_json
            && a.file_name == b.file_name
            && a.file_size == b.file_size
            && a.mime_type == b.mime_type
            && a.reply_to == b.reply_to
            && a.reactions == b.reactions
            && a.edited == b.edited
            && a.pending == b.pending
            && a.failed == b.failed
    }

    /// Set which room's messages are currently displayed.
    /// Called from `MatrixClient::loadRoomMessages` before the
    /// async fetch starts, so stale responses can be detected.
    pub fn set_current_room(&mut self, room_id: &str) {
        ::log::info!("MessageModel::set_current_room: {}", room_id);
        *self.current_room_id.borrow_mut() = Some(room_id.to_owned());
    }
}

/// Build a role-names HashMap from a SimpleListItem's Vec<QByteArray>.
fn role_names_from_vec(names: Vec<QByteArray>) -> std::collections::HashMap<i32, QByteArray> {
    names.into_iter().enumerate()
        .map(|(i, name)| (qmetaobject::USER_ROLE + i as i32, name))
        .collect()
}

impl MessageModel {
    /// Global singleton accessor.
    /// Returns the QPointer stored when the QML engine created the singleton.
    pub fn get() -> QPointer<MessageModel> {
        SINGLETON.get_or_init(|| QPointer::default()).clone()
    }

    /// Alias matching the naming convention used by MatrixClient.
    pub fn singleton_ptr() -> QPointer<MessageModel> {
        Self::get()
    }

    /// Returns the room_id currently being displayed, if any.
    /// Used by the sync loop to auto-reload messages after each cycle.
    pub fn current_room_id(&self) -> Option<String> {
        self.current_room_id.borrow().clone()
    }

    /// Remove a single event from the local model by event_id. This is
    /// the "Hide for me" action from the message context menu — purely
    /// visual, doesn't touch the server. The event reappears on the next
    /// full reload (sync / room switch) because we don't persist the
    /// hidden state.
    pub fn hideEvent(&mut self, event_id: QString) {
        let target = event_id.to_string();
        let idx = self
            .entries
            .borrow()
            .iter()
            .position(|e| e.event_id.to_string() == target);
        if let Some(i) = idx {
            // Single-row removal — a full model reset here made the whole
            // chat flash for one frame.
            self.begin_remove_rows(i as i32, i as i32);
            self.entries.borrow_mut().remove(i);
            self.end_remove_rows();
            self.count_changed();
            ::log::info!("hideEvent: removed event_id={} (row {})", target, i);
        }
    }
}

impl qmetaobject::QSingletonInit for MessageModel {
    fn init(&mut self) {
        SINGLETON.set(QPointer::from(&*self));
    }
}

impl qmetaobject::QAbstractListModel for MessageModel {
    fn row_count(&self) -> i32 {
        self.entries.borrow().len() as i32
    }
    fn data(&self, index: qmetaobject::QModelIndex, role: i32) -> qmetaobject::QVariant {
        let i = index.row() as usize;
        let entries = self.entries.borrow();
        if i >= entries.len() {
            return QVariant::default();
        }
        entries[i].get(role - qmetaobject::USER_ROLE)
    }
    fn role_names(&self) -> std::collections::HashMap<i32, QByteArray> {
        role_names_from_vec(MessageEntry::names())
    }
}
