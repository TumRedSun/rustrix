#![recursion_limit = "256"]

//! Rustrix — entry point.
//!
//! Boots the Tokio runtime, registers all QML singletons and types,
//! and starts the Qt UI event loop.

use cpp::cpp;
use cstr::cstr;
use qmetaobject::{qrc, QPointer, QObject, QmlEngine, qt_base_class};
use std::sync::{Arc, OnceLock};
use tokio::runtime::Runtime;

/// Global Tokio runtime, initialized once and never dependent on QML singleton
/// creation order. This eliminates the "Backend not initialized" panic that
/// occurred when `MatrixClient.autoLogin()` ran before the QML engine had
/// lazily created the `Backend` singleton.
static TOKIO_RUNTIME: OnceLock<Arc<Runtime>> = OnceLock::new();

/// Returns the shared Tokio runtime. Creates it on first call.
pub fn get_runtime() -> Arc<Runtime> {
    TOKIO_RUNTIME
        .get_or_init(|| Arc::new(Runtime::new().expect("failed to build Tokio runtime")))
        .clone()
}

mod singleton;
mod matrix_client;
mod auth;
mod room_model;
mod message_model;
mod file_transfer;
mod spaces;
mod profile;
mod theme;
mod avatar_cache;
mod member_model;
mod errors;
mod pending;
mod media_provider;
mod translations;

use crate::matrix_client::MatrixClient;
use crate::theme::Theme;

/// Module-level singleton storage for Backend.
static BACKEND_SINGLETON: singleton::QtSingleton<QPointer<Backend>> = singleton::QtSingleton::new();

// Embed the QML directory into the binary so the app is self-contained.
qrc! {
    pub qml_resources,
    "qml" as "/qml" {
        "main.qml",
        "LoginPage.qml",
        "LoadingScreen.qml",
        "ChatPage.qml",
        "SpacesPage.qml",
        "RoomsSidebar.qml",
        "MessageBubble.qml",
        "ProfilePage.qml",
        "SettingsPage.qml",
        "AppearancePage.qml",
        "SettingsOverlay.qml",
        "MemberListPanel.qml",
        "FileBrowserDialog.qml",
        "EmojiPicker.qml",
        "ReactionSendersPopup.qml",
    },
    "assets" as "/assets" {
        "logo.svg",
        "default-avatar.svg",
        "RustRix.png",
    }
}

/// Backend singleton exposed to QML as `Backend`.
///
/// Holds the shared Tokio runtime and the live MatrixClient handle.
#[derive(QObject, Default)]
pub struct Backend {
    base: qt_base_class!(trait QObject),
    runtime: Option<Arc<Runtime>>,
}

impl Backend {
    pub fn runtime(&self) -> &Arc<Runtime> {
        self.runtime.as_ref().expect("runtime initialized")
    }

    /// Global singleton accessor.
    /// Returns the QPointer stored when the QML engine created the singleton.
    pub fn get() -> QPointer<Backend> {
        BACKEND_SINGLETON.get_or_init(|| QPointer::default()).clone()
    }
}

impl qmetaobject::QSingletonInit for Backend {
    fn init(&mut self) {
        // Use the global runtime so Backend is just a thin QML-facing shell.
        // This guarantees the runtime exists regardless of QML singleton
        // creation order.
        if self.runtime.is_none() {
            self.runtime = Some(get_runtime());
        }
        // Store the QPointer for global access.
        BACKEND_SINGLETON.set(QPointer::from(&*self));
    }
}

// Qt headers for the cpp! fragments below (window icon setup).
cpp! {{
    #include <QtGui/QGuiApplication>
    #include <QtGui/QIcon>
}}

fn main() {
    env_logger::Builder::from_env(env_logger::Env::default().default_filter_or("info"))
        .format_timestamp_secs()
        .init();

    // Load embedded QML resources.
    qml_resources();

    let mut engine = QmlEngine::new();

    // Application-wide window / taskbar icon, embedded via the qrc asset
    // bundle above. QML's ApplicationWindow has no icon property, so this
    // is done here once for every window of the process.
    unsafe {
        cpp!([]
        {
            QGuiApplication::setWindowIcon(QIcon(QStringLiteral(":/assets/RustRix.png")));
        })
    };

    // The window title is set in main.qml ("Rustrix — <user_id>" / "Rustrix").
    // The binary is also named `rustrix`, so the WM_CLASS / Wayland app_id
    // (which is what taskbars like waybar display) defaults to "rustrix".
    // Together, these make the app show up as "Rustrix" everywhere.

    // Register singletons. qmetaobject 0.2 uses qml_register_singleton_type
    // with cstr!() and no &mut engine parameter.
    // The QML engine will create each singleton on first access and
    // call QSingletonInit::init(), which stores the QPointer and
    // performs any setup (e.g. starting the Tokio runtime for Backend).
    qmetaobject::qml_register_singleton_type::<Backend>(cstr!("MatrixClient"), 1, 0, cstr!("Backend"));
    qmetaobject::qml_register_singleton_type::<Theme>(cstr!("MatrixClient"), 1, 0, cstr!("Theme"));
    qmetaobject::qml_register_singleton_type::<MatrixClient>(cstr!("MatrixClient"), 1, 0, cstr!("MatrixClient"));

    // Register sub-model singletons.
    qmetaobject::qml_register_singleton_type::<room_model::RoomModel>(cstr!("MatrixClient"), 1, 0, cstr!("RoomModel"));
    qmetaobject::qml_register_singleton_type::<message_model::MessageModel>(cstr!("MatrixClient"), 1, 0, cstr!("MessageModel"));
    qmetaobject::qml_register_singleton_type::<spaces::SpaceModel>(cstr!("MatrixClient"), 1, 0, cstr!("SpaceModel"));
    qmetaobject::qml_register_singleton_type::<profile::ProfileManager>(cstr!("MatrixClient"), 1, 0, cstr!("ProfileManager"));
    qmetaobject::qml_register_singleton_type::<member_model::MemberModel>(cstr!("MatrixClient"), 1, 0, cstr!("MemberModel"));

    // Translations singleton — exposes Tr.tr(language, source) for
    // dynamic, restart-free language switching. QML calls it as
    // `Tr.tr(Theme.language, "Reply")` so the binding depends on
    // Theme.language (NOTIFY languageChanged) and re-evaluates when
    // the user picks a new language in Settings.
    qmetaobject::qml_register_singleton_type::<translations::Translations>(cstr!("MatrixClient"), 1, 0, cstr!("Tr"));

    engine.load_file("qrc:/qml/main.qml".into());
    engine.exec();
}
