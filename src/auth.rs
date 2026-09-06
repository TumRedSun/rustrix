//! Authentication helpers.
//!
//! `build_client` is the single entry point used by every login flow. It
//! constructs a `matrix_sdk::Client` with:
//!  - rustls (the only TLS backend in matrix-sdk 0.18+)
//!  - an optional **IPv6-only** HTTP transport (when `force_ipv6` is set)
//!  - a persistent SQLite store for state AND crypto keys
//!
//! ## Why the SQLite store is now enabled
//!
//! Previously the SQLite store was disabled because of a concern that
//! `build()` would create a new Olm identity that conflicts with
//! `restore_session()`. In matrix-sdk 0.18 this is NOT what happens:
//!
//!  1. `build()` opens (or creates) the SQLite DB at `store_path`.
//!  2. If the DB already has an OlmAccount, it is loaded as-is.
//!  3. If the DB is empty, a new Olm identity is created and persisted.
//!  4. `restore_session()` then sets the user_id/device_id/tokens from
//!     the saved session.json. The crypto identity is matched by
//!     user_id+device_id; if they match, keys are reused. If they
//!     don't match (e.g. session.json was copied from another device),
//!     the user must re-login.
//!
//! Without the SQLite store, every app restart creates a NEW Olm
//! identity, which means previously-received room keys are lost and
//! every historical encrypted message becomes `UnableToDecrypt`. That
//! is what produced the "38 system / 0 other" symptom in DMs.
//!
//! The IPv6 transport uses a custom `reqwest::dns::Resolve` implementation
//! backed by `hickory-resolver` that resolves only AAAA records and refuses
//! to dial IPv4 endpoints.

use anyhow::Result;
use matrix_sdk::Client;
use std::net::{IpAddr, Ipv6Addr, SocketAddr};
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

/// Returns the directory used for the SQLite state+crypto store.
///
/// Mirrors `MatrixClient::session_file_path` so session.json and the
/// crypto DB live side-by-side under the same project data dir.
fn store_dir() -> PathBuf {
    let base = directories::ProjectDirs::from("dev", "rustrix", "Rustrix")
        .map(|d| d.data_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("Rustrix"));
    std::fs::create_dir_all(&base).ok();
    base
}

pub async fn build_client(homeserver: &str, force_ipv6: bool) -> Result<Client> {
    // Normalize the homeserver input so users can type any of:
    //   matrix.org
    //   https://matrix.org
    //   192.168.1.10
    //   https://192.168.1.10:8448
    //   [::1]
    //   https://[::1]:8448
    //
    // `url::Url::parse` requires a scheme, so we prepend `https://` when
    // one is missing. We do NOT prepend `http://` because a bare hostname
    // almost always means "the user expects HTTPS" — and Matrix servers
    // should be using TLS anyway. Users who really want plaintext HTTP
    // can type `http://...` explicitly.
    let normalized = normalize_homeserver(homeserver);
    let hs: url::Url = normalized.parse()?;

    // Persistent SQLite store: holds room state, sync tokens, AND the
    // Olm/Megolm crypto identity (room keys, device keys, etc.).
    // Without this, every app launch creates a brand-new device and
    // every previously-encrypted message becomes unreadable.
    let store_path = store_dir();

    let mut builder = Client::builder()
        .homeserver_url(hs)
        .user_agent("Rustrix/0.1 (rust+qt)")
        .sqlite_store(store_path, None)
        .request_config(
            matrix_sdk::config::RequestConfig::default()
                .timeout(Duration::from_secs(30)),
        );

    if force_ipv6 {
        builder = builder.http_client(build_ipv6_only_http()?);
    }

    let client = builder.build().await?;
    Ok(client)
}

/// Normalize a user-typed homeserver string into something `url::Url::parse`
/// will accept.
///
/// Rules:
///  - If the input already starts with `http://` or `https://`, leave it
///    alone (the user was explicit).
///  - Otherwise, prepend `https://`. This lets users type bare domains
///    (`matrix.org`), bare IPv4 (`192.168.1.10`), and bare bracketed IPv6
///    (`[::1]`) without remembering to add a scheme.
///  - Whitespace is trimmed.
///
/// Port numbers are preserved as-is (e.g. `192.168.1.10:8448` →
/// `https://192.168.1.10:8448`).
fn normalize_homeserver(input: &str) -> String {
    let s = input.trim();
    if s.starts_with("http://") || s.starts_with("https://") {
        return s.to_string();
    }
    format!("https://{}", s)
}

/// Build a default reqwest client (no custom DNS resolver).
fn _build_default_http() -> Result<reqwest::Client> {
    Ok(reqwest::ClientBuilder::new()
        .timeout(Duration::from_secs(30))
        .pool_idle_timeout(Duration::from_secs(90))
        .user_agent("Rustrix/0.1 (rust+qt)")
        .build()?)
}

/// Build a reqwest client that only resolves AAAA records and refuses to
/// connect to non-IPv6 endpoints. This is what powers the "Force IPv6"
/// option in the connection settings.
///
/// In hickory-resolver 0.26+:
/// - `TokioAsyncResolver` was removed; use `TokioResolver`
/// - `builder_tokio()?.build()` returns `Result` (need `?` on both)
fn build_ipv6_only_http() -> Result<reqwest::Client> {
    let resolver = hickory_resolver::TokioResolver::builder_tokio()?.build()?;
    Ok(reqwest::ClientBuilder::new()
        .timeout(Duration::from_secs(45))
        .pool_idle_timeout(Duration::from_secs(120))
        .user_agent("Rustrix/0.1 (rust+qt, ipv6-only)")
        .dns_resolver(Arc::new(Ipv6OnlyResolver { resolver }))
        .build()?)
}

// ---------------------------------------------------------------------------
// Custom DNS resolver that only returns AAAA (IPv6) records.
// ---------------------------------------------------------------------------

/// A `reqwest::dns::Resolve` implementation that resolves only IPv6
/// addresses using `hickory-resolver`.
struct Ipv6OnlyResolver {
    resolver: hickory_resolver::TokioResolver,
}

impl reqwest::dns::Resolve for Ipv6OnlyResolver {
    fn resolve(&self, name: reqwest::dns::Name) -> reqwest::dns::Resolving {
        let resolver = self.resolver.clone();
        let host = name.as_str().to_owned();
        Box::pin(async move {
            let lookup = resolver
                .ipv6_lookup(&host)
                .await
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;

            // In hickory-resolver 0.26: Lookup no longer has .iter().
            // Use .answers() -> &[Record] and extract IPs from AAAA RData.
            use hickory_proto::rr::RData;
            let addrs: Vec<SocketAddr> = lookup
                .answers()
                .iter()
                .filter_map(|record| {
                    if let RData::AAAA(aaaa) = record.data {
                        Some(Ipv6Addr::from(aaaa.0))
                    } else {
                        None
                    }
                })
                .map(|ip| SocketAddr::new(IpAddr::V6(ip), 0))
                .collect();

            if addrs.is_empty() {
                // reqwest 0.13 expects Box<dyn Error + Send + Sync>
                let err: Box<dyn std::error::Error + Send + Sync> =
                    format!("no AAAA records for {}", host).into();
                return Err(err);
            }

            // reqwest will replace port 0 with the actual port from the URL.
            Ok(Box::new(addrs.into_iter()) as reqwest::dns::Addrs)
        })
    }
}
