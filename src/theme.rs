//! `Theme` — fully customizable appearance.
//!
//! All visual knobs (colors, fonts, paddings, corner radii, message bubble
//! shapes, etc.) are exposed as QML properties AND persisted to disk so
//! they survive restarts. A built-in set of presets ("Material Dark",
//! "Solarized", "Tokyo Night", "Nordic", "Dracula", "Gruvbox", "Catppuccin",
//! "Sunset", "Matrix Green", "Custom") lets users switch instantly.

use qmetaobject::*;
use serde::{Deserialize, Serialize};
use std::cell::RefCell;
use std::path::PathBuf;

use paste::paste;

/// Module-level singleton storage for Theme.
static THEME_SINGLETON: crate::singleton::QtSingleton<QPointer<Theme>> =
    crate::singleton::QtSingleton::new();

#[derive(QObject, Default)]
#[allow(dead_code)]
#[allow(non_snake_case)]
pub struct Theme {
    base: qt_base_class!(trait QObject),

    // --- Identification ---
    /// Active preset name. Setting this to a known preset overrides every
    /// field below. Setting to "Custom" keeps the current colors.
    preset: qt_property!(QString; NOTIFY presetChanged READ preset WRITE set_preset),

    // --- Window chrome ---
    windowBg: qt_property!(QString; NOTIFY windowBgChanged READ window_bg WRITE set_window_bg),
    windowFg: qt_property!(QString; NOTIFY windowFgChanged READ window_fg WRITE set_window_fg),
    sidebarBg: qt_property!(QString; NOTIFY sidebarBgChanged READ sidebar_bg WRITE set_sidebar_bg),
    sidebarFg: qt_property!(QString; NOTIFY sidebarFgChanged READ sidebar_fg WRITE set_sidebar_fg),
    accent: qt_property!(QString; NOTIFY accentChanged READ accent WRITE set_accent),
    accentFg: qt_property!(QString; NOTIFY accentFgChanged READ accent_fg WRITE set_accent_fg),
    danger: qt_property!(QString; NOTIFY dangerChanged READ danger WRITE set_danger),
    success: qt_property!(QString; NOTIFY successChanged READ success WRITE set_success),
    warning: qt_property!(QString; NOTIFY warningChanged READ warning WRITE set_warning),
    muted: qt_property!(QString; NOTIFY mutedChanged READ muted WRITE set_muted),
    border: qt_property!(QString; NOTIFY borderChanged READ border WRITE set_border),

    // --- Typography ---
    fontFamily: qt_property!(QString; NOTIFY fontFamilyChanged READ font_family WRITE set_font_family),
    fontFamilyMono: qt_property!(QString; NOTIFY fontFamilyMonoChanged READ font_family_mono WRITE set_font_family_mono),
    fontSizeXs: qt_property!(i32; NOTIFY fontSizeXsChanged READ font_size_xs WRITE set_font_size_xs),
    fontSizeSm: qt_property!(i32; NOTIFY fontSizeSmChanged READ font_size_sm WRITE set_font_size_sm),
    fontSizeMd: qt_property!(i32; NOTIFY fontSizeMdChanged READ font_size_md WRITE set_font_size_md),
    fontSizeLg: qt_property!(i32; NOTIFY fontSizeLgChanged READ font_size_lg WRITE set_font_size_lg),
    fontSizeXl: qt_property!(i32; NOTIFY fontSizeXlChanged READ font_size_xl WRITE set_font_size_xl),

    // --- Geometry ---
    radiusSm: qt_property!(i32; NOTIFY radiusSmChanged READ radius_sm WRITE set_radius_sm),
    radiusMd: qt_property!(i32; NOTIFY radiusMdChanged READ radius_md WRITE set_radius_md),
    radiusLg: qt_property!(i32; NOTIFY radiusLgChanged READ radius_lg WRITE set_radius_lg),
    paddingXs: qt_property!(i32; NOTIFY paddingXsChanged READ padding_xs WRITE set_padding_xs),
    paddingSm: qt_property!(i32; NOTIFY paddingSmChanged READ padding_sm WRITE set_padding_sm),
    paddingMd: qt_property!(i32; NOTIFY paddingMdChanged READ padding_md WRITE set_padding_md),
    paddingLg: qt_property!(i32; NOTIFY paddingLgChanged READ padding_lg WRITE set_padding_lg),
    spacingXs: qt_property!(i32; NOTIFY spacingXsChanged READ spacing_xs WRITE set_spacing_xs),
    spacingSm: qt_property!(i32; NOTIFY spacingSmChanged READ spacing_sm WRITE set_spacing_sm),
    spacingMd: qt_property!(i32; NOTIFY spacingMdChanged READ spacing_md WRITE set_spacing_md),
    spacingLg: qt_property!(i32; NOTIFY spacingLgChanged READ spacing_lg WRITE set_spacing_lg),

    // --- Message bubbles ---
    bubbleBgMe: qt_property!(QString; NOTIFY bubbleBgMeChanged READ bubble_bg_me WRITE set_bubble_bg_me),
    bubbleBgThem: qt_property!(QString; NOTIFY bubbleBgThemChanged READ bubble_bg_them WRITE set_bubble_bg_them),
    bubbleFgMe: qt_property!(QString; NOTIFY bubbleFgMeChanged READ bubble_fg_me WRITE set_bubble_fg_me),
    bubbleFgThem: qt_property!(QString; NOTIFY bubbleFgThemChanged READ bubble_fg_them WRITE set_bubble_fg_them),
    bubbleRadius: qt_property!(i32; NOTIFY bubbleRadiusChanged READ bubble_radius WRITE set_bubble_radius),
    bubblePaddingH: qt_property!(i32; NOTIFY bubblePaddingHChanged READ bubble_padding_h WRITE set_bubble_padding_h),
    bubblePaddingV: qt_property!(i32; NOTIFY bubblePaddingVChanged READ bubble_padding_v WRITE set_bubble_padding_v),
    bubbleTail: qt_property!(bool; NOTIFY bubbleTailChanged READ bubble_tail WRITE set_bubble_tail),
    bubbleMaxWidthPct: qt_property!(i32; NOTIFY bubbleMaxWidthPctChanged READ bubble_max_width_pct WRITE set_bubble_max_width_pct),

    // --- Avatars ---
    avatarSizeSm: qt_property!(i32; NOTIFY avatarSizeSmChanged READ avatar_size_sm WRITE set_avatar_size_sm),
    avatarSizeMd: qt_property!(i32; NOTIFY avatarSizeMdChanged READ avatar_size_md WRITE set_avatar_size_md),
    avatarSizeLg: qt_property!(i32; NOTIFY avatarSizeLgChanged READ avatar_size_lg WRITE set_avatar_size_lg),
    avatarRadius: qt_property!(i32; NOTIFY avatarRadiusChanged READ avatar_radius WRITE set_avatar_radius),
    avatarShape: qt_property!(QString; NOTIFY avatarShapeChanged READ avatar_shape WRITE set_avatar_shape), // "circle" | "rounded" | "square"

    // --- Scrollbars & misc ---
    scrollbarSize: qt_property!(i32; NOTIFY scrollbarSizeChanged READ scrollbar_size WRITE set_scrollbar_size),
    scrollbarRadius: qt_property!(i32; NOTIFY scrollbarRadiusChanged READ scrollbar_radius WRITE set_scrollbar_radius),
    compactMode: qt_property!(bool; NOTIFY compactModeChanged READ compact_mode WRITE set_compact_mode),
    showTimestamps: qt_property!(bool; NOTIFY showTimestampsChanged READ show_timestamps WRITE set_show_timestamps),
    showAvatars: qt_property!(bool; NOTIFY showAvatarsChanged READ show_avatars WRITE set_show_avatars),
    animateBubbles: qt_property!(bool; NOTIFY animateBubblesChanged READ animate_bubbles WRITE set_animate_bubbles),
    animationDurationMs: qt_property!(i32; NOTIFY animationDurationMsChanged READ animation_duration_ms WRITE set_animation_duration_ms),

    // --- Language ---
    language: qt_property!(QString; NOTIFY languageChanged READ language WRITE set_language),

    // --- Window-relative sizing ---
    // The application window's current dimensions, written from QML
    // (main.qml syncs these on every onWidthChanged / onHeightChanged).
    // They are NOT part of ThemeState and are NOT persisted to disk —
    // they exist only so that derived size properties (colSpacesW,
    // headerH, iconBtnSize, etc.) can scale with the live window size.
    //
    // The whole point of this group is to make UI element sizes
    // depend on the window dimensions rather than on translated text
    // content. Translated strings can be much longer (or shorter)
    // than English, which used to cause layouts to "shift" when the
    // user changed language. By deriving every fixed-pixel size from
    // `min(appWidth/1280, appHeight/800)`, the layout stays stable
    // across languages and scales gracefully when the user resizes
    // the window.
    appWidth: qt_property!(i32; NOTIFY appWidthChanged READ app_width WRITE set_app_width),
    appHeight: qt_property!(i32; NOTIFY appHeightChanged READ app_height WRITE set_app_height),
    scale: qt_property!(f64; NOTIFY scaleChanged READ scale),

    // Derived window-relative sizes (all read-only, all driven by `scale`).
    // Every fixed pixel size that appears in the QML UI has a matching
    // property here, so QML never uses a raw integer for layout — it
    // always goes through Theme.<name>. This makes the UI scale
    // uniformly with the window.
    colSpacesW:    qt_property!(i32; NOTIFY scaleChanged READ col_spaces_w),
    colRoomsW:     qt_property!(i32; NOTIFY scaleChanged READ col_rooms_w),
    colMembersW:   qt_property!(i32; NOTIFY scaleChanged READ col_members_w),
    headerH:       qt_property!(i32; NOTIFY scaleChanged READ header_h),
    headerChatH:   qt_property!(i32; NOTIFY scaleChanged READ header_chat_h),
    tabBtnH:       qt_property!(i32; NOTIFY scaleChanged READ tab_btn_h),
    iconBtnSize:   qt_property!(i32; NOTIFY scaleChanged READ icon_btn_size),
    settingsNavW:  qt_property!(i32; NOTIFY scaleChanged READ settings_nav_w),
    dialogMdW:     qt_property!(i32; NOTIFY scaleChanged READ dialog_md_w),
    dialogLgW:     qt_property!(i32; NOTIFY scaleChanged READ dialog_lg_w),
    avatarProfile: qt_property!(i32; NOTIFY scaleChanged READ avatar_profile),
    bannerH:       qt_property!(i32; NOTIFY scaleChanged READ banner_h),
    comboBoxMdW:   qt_property!(i32; NOTIFY scaleChanged READ combo_box_md_w),
    comboBoxSmW:   qt_property!(i32; NOTIFY scaleChanged READ combo_box_sm_w),
    comboBoxXsW:   qt_property!(i32; NOTIFY scaleChanged READ combo_box_xs_w),
    spinBoxW:      qt_property!(i32; NOTIFY scaleChanged READ spin_box_w),
    colorSwatchSize: qt_property!(i32; NOTIFY scaleChanged READ color_swatch_size),
    replyBannerH:  qt_property!(i32; NOTIFY scaleChanged READ reply_banner_h),
    previewBoxH:   qt_property!(i32; NOTIFY scaleChanged READ preview_box_h),
    avatarListMd:  qt_property!(i32; NOTIFY scaleChanged READ avatar_list_md),
    roomRowH:      qt_property!(i32; NOTIFY scaleChanged READ room_row_h),
    spaceIconSize: qt_property!(i32; NOTIFY scaleChanged READ space_icon_size),

    // --- Signals ---
    presetChanged: qt_signal!(),
    windowBgChanged: qt_signal!(),
    windowFgChanged: qt_signal!(),
    sidebarBgChanged: qt_signal!(),
    sidebarFgChanged: qt_signal!(),
    accentChanged: qt_signal!(),
    accentFgChanged: qt_signal!(),
    dangerChanged: qt_signal!(),
    successChanged: qt_signal!(),
    warningChanged: qt_signal!(),
    mutedChanged: qt_signal!(),
    borderChanged: qt_signal!(),
    fontFamilyChanged: qt_signal!(),
    fontFamilyMonoChanged: qt_signal!(),
    fontSizeXsChanged: qt_signal!(),
    fontSizeSmChanged: qt_signal!(),
    fontSizeMdChanged: qt_signal!(),
    fontSizeLgChanged: qt_signal!(),
    fontSizeXlChanged: qt_signal!(),
    radiusSmChanged: qt_signal!(),
    radiusMdChanged: qt_signal!(),
    radiusLgChanged: qt_signal!(),
    paddingXsChanged: qt_signal!(),
    paddingSmChanged: qt_signal!(),
    paddingMdChanged: qt_signal!(),
    paddingLgChanged: qt_signal!(),
    spacingXsChanged: qt_signal!(),
    spacingSmChanged: qt_signal!(),
    spacingMdChanged: qt_signal!(),
    spacingLgChanged: qt_signal!(),
    bubbleBgMeChanged: qt_signal!(),
    bubbleBgThemChanged: qt_signal!(),
    bubbleFgMeChanged: qt_signal!(),
    bubbleFgThemChanged: qt_signal!(),
    bubbleRadiusChanged: qt_signal!(),
    bubblePaddingHChanged: qt_signal!(),
    bubblePaddingVChanged: qt_signal!(),
    bubbleTailChanged: qt_signal!(),
    bubbleMaxWidthPctChanged: qt_signal!(),
    avatarSizeSmChanged: qt_signal!(),
    avatarSizeMdChanged: qt_signal!(),
    avatarSizeLgChanged: qt_signal!(),
    avatarRadiusChanged: qt_signal!(),
    avatarShapeChanged: qt_signal!(),
    scrollbarSizeChanged: qt_signal!(),
    scrollbarRadiusChanged: qt_signal!(),
    compactModeChanged: qt_signal!(),
    showTimestampsChanged: qt_signal!(),
    showAvatarsChanged: qt_signal!(),
    animateBubblesChanged: qt_signal!(),
    animationDurationMsChanged: qt_signal!(),
    languageChanged: qt_signal!(),

    // Window-relative sizing signals.
    appWidthChanged: qt_signal!(),
    appHeightChanged: qt_signal!(),
    // Single shared NOTIFY signal for every derived size property
    // (colSpacesW, headerH, iconBtnSize, etc.). Firing this one
    // signal makes QML re-evaluate every binding that reads any
    // derived size, which is exactly what we want when the window
    // is resized.
    scaleChanged: qt_signal!(),

    /// Fired after `apply_preset` or `load_from_disk` finishes; QML uses it
    /// to rebind bound expressions.
    themeChanged: qt_signal!(),

    // QML-callable method declarations (qt_method! is a function-like macro
    // in qmetaobject 0.2; the actual bodies live in the impl block below).
    applyPreset: qt_method!(fn(&self, name: QString)),
    reset: qt_method!(fn(&self)),
    exportJson: qt_method!(fn(&self) -> QString),
    importJson: qt_method!(fn(&self, json: QString) -> bool),
    availablePresets: qt_method!(fn(&self) -> QString),
    availableLanguages: qt_method!(fn(&self) -> QString),
    // Reload theme.json from disk. QML calls this explicitly in
    // Component.onCompleted (BEFORE applyPreset) to be 100% sure the
    // persisted language is loaded even if QSingletonInit::init ran
    // too early for QML bindings to have registered. This is the
    // robust fix for "language is English on startup, only applies
    // after I re-click it in settings".
    loadFromDisk: qt_method!(fn(&self)),

    state: RefCell<ThemeState>,

    // Live window dimensions, written from QML. Kept OUTSIDE
    // ThemeState so they are NOT persisted to theme.json (the
    // persisted value would be stale on the next launch and could
    // briefly feed wrong sizes into bindings before QML overwrites
    // it with the real window size).
    app_size: RefCell<(i32, i32)>,
}

#[derive(Default, Serialize, Deserialize, Clone)]
struct ThemeState {
    preset: String,
    window_bg: String,
    window_fg: String,
    sidebar_bg: String,
    sidebar_fg: String,
    accent: String,
    accent_fg: String,
    danger: String,
    success: String,
    warning: String,
    muted: String,
    border: String,
    font_family: String,
    font_family_mono: String,
    font_size_xs: i32,
    font_size_sm: i32,
    font_size_md: i32,
    font_size_lg: i32,
    font_size_xl: i32,
    radius_sm: i32,
    radius_md: i32,
    radius_lg: i32,
    padding_xs: i32,
    padding_sm: i32,
    padding_md: i32,
    padding_lg: i32,
    spacing_xs: i32,
    spacing_sm: i32,
    spacing_md: i32,
    spacing_lg: i32,
    bubble_bg_me: String,
    bubble_bg_them: String,
    bubble_fg_me: String,
    bubble_fg_them: String,
    bubble_radius: i32,
    bubble_padding_h: i32,
    bubble_padding_v: i32,
    bubble_tail: bool,
    bubble_max_width_pct: i32,
    avatar_size_sm: i32,
    avatar_size_md: i32,
    avatar_size_lg: i32,
    avatar_radius: i32,
    avatar_shape: String,
    scrollbar_size: i32,
    scrollbar_radius: i32,
    compact_mode: bool,
    show_timestamps: bool,
    show_avatars: bool,
    animate_bubbles: bool,
    animation_duration_ms: i32,
    language: String,
}

fn path() -> PathBuf {
    let base = directories::ProjectDirs::from("dev", "rustrix", "Rustrix")
        .map(|d| d.config_dir().to_path_buf())
        .unwrap_or_else(|| std::env::temp_dir().join("Rustrix"));
    std::fs::create_dir_all(&base).ok();
    base.join("theme.json")
}

#[allow(non_snake_case)]
impl Theme {
    fn file_path() -> PathBuf { path() }

    pub fn load_from_disk(&self) {
        if let Ok(json) = std::fs::read_to_string(Self::file_path()) {
            if let Ok(s) = serde_json::from_str::<ThemeState>(&json) {
                *self.state.borrow_mut() = s;
            } else {
                self.apply_defaults();
            }
        } else {
            self.apply_defaults();
        }
        self.fire_all_signals();
    }

    pub fn save_to_disk(&self) {
        let s = self.state.borrow().clone();
        if let Ok(json) = serde_json::to_string_pretty(&s) {
            let _ = std::fs::write(Self::file_path(), json);
        }
    }

    fn apply_defaults(&self) {
        // Preserve the current language when resetting to defaults —
        // the user explicitly chose a language and "Reset theme" should
        // only reset visual properties, not flip the UI back to English.
        let saved_language = self.state.borrow().language.clone();
        let mut defaults = preset("Material Dark");
        defaults.language = saved_language;
        *self.state.borrow_mut() = defaults;
    }

    fn fire_all_signals(&self) {
        let _ = self.presetChanged();
        let _ = self.windowBgChanged();
        let _ = self.windowFgChanged();
        let _ = self.sidebarBgChanged();
        let _ = self.sidebarFgChanged();
        let _ = self.accentChanged();
        let _ = self.accentFgChanged();
        let _ = self.dangerChanged();
        let _ = self.successChanged();
        let _ = self.warningChanged();
        let _ = self.mutedChanged();
        let _ = self.borderChanged();
        let _ = self.fontFamilyChanged();
        let _ = self.fontFamilyMonoChanged();
        let _ = self.fontSizeXsChanged();
        let _ = self.fontSizeSmChanged();
        let _ = self.fontSizeMdChanged();
        let _ = self.fontSizeLgChanged();
        let _ = self.fontSizeXlChanged();
        let _ = self.radiusSmChanged();
        let _ = self.radiusMdChanged();
        let _ = self.radiusLgChanged();
        let _ = self.paddingXsChanged();
        let _ = self.paddingSmChanged();
        let _ = self.paddingMdChanged();
        let _ = self.paddingLgChanged();
        let _ = self.spacingXsChanged();
        let _ = self.spacingSmChanged();
        let _ = self.spacingMdChanged();
        let _ = self.spacingLgChanged();
        let _ = self.bubbleBgMeChanged();
        let _ = self.bubbleBgThemChanged();
        let _ = self.bubbleFgMeChanged();
        let _ = self.bubbleFgThemChanged();
        let _ = self.bubbleRadiusChanged();
        let _ = self.bubblePaddingHChanged();
        let _ = self.bubblePaddingVChanged();
        let _ = self.bubbleTailChanged();
        let _ = self.bubbleMaxWidthPctChanged();
        let _ = self.avatarSizeSmChanged();
        let _ = self.avatarSizeMdChanged();
        let _ = self.avatarSizeLgChanged();
        let _ = self.avatarRadiusChanged();
        let _ = self.avatarShapeChanged();
        let _ = self.scrollbarSizeChanged();
        let _ = self.scrollbarRadiusChanged();
        let _ = self.compactModeChanged();
        let _ = self.showTimestampsChanged();
        let _ = self.showAvatarsChanged();
        let _ = self.animateBubblesChanged();
        let _ = self.animationDurationMsChanged();
        let _ = self.languageChanged();
        // Re-derive window-relative sizes. The actual app_size hasn't
        // changed, but firing scaleChanged forces every binding that
        // reads a derived size (colSpacesW, headerH, iconBtnSize, …)
        // to re-evaluate. This matters after load_from_disk /
        // applyPreset, where ThemeState was just wholesale replaced
        // and QML bindings may be holding stale values.
        let _ = self.scaleChanged();
        self.themeChanged();
    }

    pub fn applyPreset(&self, name: QString) {
        // Preserve the current language across preset switches.
        // `preset()` hardcodes `language: "en"` in the returned ThemeState,
        // so without this preservation, switching presets (or the
        // `Theme.applyPreset(Theme.preset)` call in main.qml's
        // Component.onCompleted) would silently reset the user's chosen
        // interface language back to English on every startup.
        let saved_language = self.state.borrow().language.clone();
        let mut s = preset(&name.to_string());
        s.language = saved_language;
        *self.state.borrow_mut() = s;
        self.fire_all_signals();
        self.save_to_disk();
    }

    pub fn reset(&self) {
        self.apply_defaults();
        self.fire_all_signals();
        self.save_to_disk();
    }

    pub fn exportJson(&self) -> QString {
        let s = self.state.borrow().clone();
        QString::from(serde_json::to_string_pretty(&s).unwrap_or_default().as_str())
    }

    pub fn importJson(&self, json: QString) -> bool {
        match serde_json::from_str::<ThemeState>(&json.to_string()) {
            Ok(s) => {
                *self.state.borrow_mut() = s;
                self.fire_all_signals();
                self.save_to_disk();
                true
            }
            Err(_) => false,
        }
    }

    // --- List of available presets, for QML dropdowns ---
    pub fn availablePresets(&self) -> QString {
        QString::from(
            r#"["Material Dark","Solarized Dark","Tokyo Night","Nordic","Dracula","Gruvbox","Catppuccin Mocha","Sunset","Matrix Green"]"#,
        )
    }

    // --- List of available languages, for QML dropdowns ---
    pub fn availableLanguages(&self) -> QString {
        QString::from(
            r#"["en","ru","de","fr","es","pt","ja","zh","ko","it","pl","uk"]"#,
        )
    }

    /// QML-callable wrapper around `load_from_disk`. main.qml calls
    /// this in Component.onCompleted BEFORE `Theme.applyPreset(...)` so
    /// the persisted language is definitely loaded into ThemeState
    /// before any bindings evaluate. This fixes the bug where the UI
    /// started in English even though the user had picked Russian in
    /// a previous session — QSingletonInit::init() does call
    /// load_from_disk, but it runs so early in singleton construction
    /// that QML bindings haven't subscribed to languageChanged yet,
    /// so the signal is missed. Calling loadFromDisk again here, after
    /// the QML scene is fully built, guarantees the language signal
    /// fires while bindings are listening.
    pub fn loadFromDisk(&self) {
        self.load_from_disk();
    }

    // --- Getters / setters ---
    // All getters/setters are implemented manually below because the state
    // is held in a `RefCell` and qmetaobject's `qt_property!` macro expects
    // field-style access. Each setter writes through to the RefCell, emits
    // the corresponding `*_changed` signal, and persists the new state to
    // disk.
}

// String accessors
impl Theme {
    pub fn preset(&self) -> QString { QString::from(self.state.borrow().preset.as_str()) }
    pub fn set_preset(&self, v: QString) {
        let name = v.to_string();
        // Preserve current language (see applyPreset for rationale).
        let saved_language = self.state.borrow().language.clone();
        let mut s = preset(&name);
        s.language = saved_language;
        *self.state.borrow_mut() = s;
        self.fire_all_signals();
        self.save_to_disk();
    }
    pub fn window_bg(&self) -> QString { QString::from(self.state.borrow().window_bg.as_str()) }
    pub fn set_window_bg(&self, v: QString) { self.state.borrow_mut().window_bg = v.to_string(); self.windowBgChanged(); self.save_to_disk(); }
    pub fn window_fg(&self) -> QString { QString::from(self.state.borrow().window_fg.as_str()) }
    pub fn set_window_fg(&self, v: QString) { self.state.borrow_mut().window_fg = v.to_string(); self.windowFgChanged(); self.save_to_disk(); }
    pub fn sidebar_bg(&self) -> QString { QString::from(self.state.borrow().sidebar_bg.as_str()) }
    pub fn set_sidebar_bg(&self, v: QString) { self.state.borrow_mut().sidebar_bg = v.to_string(); self.sidebarBgChanged(); self.save_to_disk(); }
    pub fn sidebar_fg(&self) -> QString { QString::from(self.state.borrow().sidebar_fg.as_str()) }
    pub fn set_sidebar_fg(&self, v: QString) { self.state.borrow_mut().sidebar_fg = v.to_string(); self.sidebarFgChanged(); self.save_to_disk(); }
    pub fn accent(&self) -> QString { QString::from(self.state.borrow().accent.as_str()) }
    pub fn set_accent(&self, v: QString) { self.state.borrow_mut().accent = v.to_string(); self.accentChanged(); self.save_to_disk(); }
    pub fn accent_fg(&self) -> QString { QString::from(self.state.borrow().accent_fg.as_str()) }
    pub fn set_accent_fg(&self, v: QString) { self.state.borrow_mut().accent_fg = v.to_string(); self.accentFgChanged(); self.save_to_disk(); }
    pub fn danger(&self) -> QString { QString::from(self.state.borrow().danger.as_str()) }
    pub fn set_danger(&self, v: QString) { self.state.borrow_mut().danger = v.to_string(); self.dangerChanged(); self.save_to_disk(); }
    pub fn success(&self) -> QString { QString::from(self.state.borrow().success.as_str()) }
    pub fn set_success(&self, v: QString) { self.state.borrow_mut().success = v.to_string(); self.successChanged(); self.save_to_disk(); }
    pub fn warning(&self) -> QString { QString::from(self.state.borrow().warning.as_str()) }
    pub fn set_warning(&self, v: QString) { self.state.borrow_mut().warning = v.to_string(); self.warningChanged(); self.save_to_disk(); }
    pub fn muted(&self) -> QString { QString::from(self.state.borrow().muted.as_str()) }
    pub fn set_muted(&self, v: QString) { self.state.borrow_mut().muted = v.to_string(); self.mutedChanged(); self.save_to_disk(); }
    pub fn border(&self) -> QString { QString::from(self.state.borrow().border.as_str()) }
    pub fn set_border(&self, v: QString) { self.state.borrow_mut().border = v.to_string(); self.borderChanged(); self.save_to_disk(); }
    pub fn font_family(&self) -> QString { QString::from(self.state.borrow().font_family.as_str()) }
    pub fn set_font_family(&self, v: QString) { self.state.borrow_mut().font_family = v.to_string(); self.fontFamilyChanged(); self.save_to_disk(); }
    pub fn font_family_mono(&self) -> QString { QString::from(self.state.borrow().font_family_mono.as_str()) }
    pub fn set_font_family_mono(&self, v: QString) { self.state.borrow_mut().font_family_mono = v.to_string(); self.fontFamilyMonoChanged(); self.save_to_disk(); }
    pub fn bubble_bg_me(&self) -> QString { QString::from(self.state.borrow().bubble_bg_me.as_str()) }
    pub fn set_bubble_bg_me(&self, v: QString) { self.state.borrow_mut().bubble_bg_me = v.to_string(); self.bubbleBgMeChanged(); self.save_to_disk(); }
    pub fn bubble_bg_them(&self) -> QString { QString::from(self.state.borrow().bubble_bg_them.as_str()) }
    pub fn set_bubble_bg_them(&self, v: QString) { self.state.borrow_mut().bubble_bg_them = v.to_string(); self.bubbleBgThemChanged(); self.save_to_disk(); }
    pub fn bubble_fg_me(&self) -> QString { QString::from(self.state.borrow().bubble_fg_me.as_str()) }
    pub fn set_bubble_fg_me(&self, v: QString) { self.state.borrow_mut().bubble_fg_me = v.to_string(); self.bubbleFgMeChanged(); self.save_to_disk(); }
    pub fn bubble_fg_them(&self) -> QString { QString::from(self.state.borrow().bubble_fg_them.as_str()) }
    pub fn set_bubble_fg_them(&self, v: QString) { self.state.borrow_mut().bubble_fg_them = v.to_string(); self.bubbleFgThemChanged(); self.save_to_disk(); }
    pub fn avatar_shape(&self) -> QString { QString::from(self.state.borrow().avatar_shape.as_str()) }
    pub fn set_avatar_shape(&self, v: QString) { self.state.borrow_mut().avatar_shape = v.to_string(); self.avatarShapeChanged(); self.save_to_disk(); }
    pub fn language(&self) -> QString { QString::from(self.state.borrow().language.as_str()) }
    pub fn set_language(&self, v: QString) { self.state.borrow_mut().language = v.to_string(); self.languageChanged(); self.save_to_disk(); }
}

// Integer accessors
macro_rules! int_accessors {
    ($($name:ident, $sig:ident);* $(;)?) => {
        paste! {
        $(
        impl Theme {
            pub fn $name(&self) -> i32 { self.state.borrow().$name }
            pub fn [<set_ $name>](&self, v: i32) {
                self.state.borrow_mut().$name = v;
                self.$sig();
                self.save_to_disk();
            }
        }
        )*
        }
    };
}

int_accessors! {
    font_size_xs, fontSizeXsChanged;
    font_size_sm, fontSizeSmChanged;
    font_size_md, fontSizeMdChanged;
    font_size_lg, fontSizeLgChanged;
    font_size_xl, fontSizeXlChanged;
    radius_sm, radiusSmChanged;
    radius_md, radiusMdChanged;
    radius_lg, radiusLgChanged;
    padding_xs, paddingXsChanged;
    padding_sm, paddingSmChanged;
    padding_md, paddingMdChanged;
    padding_lg, paddingLgChanged;
    spacing_xs, spacingXsChanged;
    spacing_sm, spacingSmChanged;
    spacing_md, spacingMdChanged;
    spacing_lg, spacingLgChanged;
    bubble_radius, bubbleRadiusChanged;
    bubble_padding_h, bubblePaddingHChanged;
    bubble_padding_v, bubblePaddingVChanged;
    bubble_max_width_pct, bubbleMaxWidthPctChanged;
    avatar_size_sm, avatarSizeSmChanged;
    avatar_size_md, avatarSizeMdChanged;
    avatar_size_lg, avatarSizeLgChanged;
    avatar_radius, avatarRadiusChanged;
    scrollbar_size, scrollbarSizeChanged;
    scrollbar_radius, scrollbarRadiusChanged;
    animation_duration_ms, animationDurationMsChanged;
}

// Bool accessors
macro_rules! bool_accessors {
    ($($name:ident, $sig:ident);* $(;)?) => {
        paste! {
        $(
        impl Theme {
            pub fn $name(&self) -> bool { self.state.borrow().$name }
            pub fn [<set_ $name>](&self, v: bool) {
                self.state.borrow_mut().$name = v;
                self.$sig();
                self.save_to_disk();
            }
        }
        )*
        }
    };
}

bool_accessors! {
    bubble_tail, bubbleTailChanged;
    compact_mode, compactModeChanged;
    show_timestamps, showTimestampsChanged;
    show_avatars, showAvatarsChanged;
    animate_bubbles, animateBubblesChanged;
}

impl Theme {
    /// Global singleton accessor.
    #[allow(dead_code)]
    pub fn get() -> QPointer<Theme> {
        THEME_SINGLETON.get_or_init(|| QPointer::default()).clone()
    }

    // ── Window-relative sizing ──
    //
    // Reference design size is 1280×800 (the default ApplicationWindow
    // size in main.qml). `scale` is `min(appWidth/1280, appHeight/800)`,
    // clamped to [0.5, 3.0] so the UI doesn't become unusably tiny on
    // very small windows or absurdly large on 4K monitors. All derived
    // sizes are `(reference_px * scale).round() as i32`.
    //
    // QML writes appWidth / appHeight from main.qml's onWidthChanged /
    // onHeightChanged handlers; that fires scaleChanged, which makes
    // every binding that reads any derived size re-evaluate.

    pub fn app_width(&self) -> i32 { self.app_size.borrow().0 }
    pub fn app_height(&self) -> i32 { self.app_size.borrow().1 }

    pub fn set_app_width(&self, v: i32) {
        let prev = *self.app_size.borrow();
        if prev.0 == v { return; }
        self.app_size.borrow_mut().0 = v;
        let _ = self.appWidthChanged();
        let _ = self.scaleChanged();
    }

    pub fn set_app_height(&self, v: i32) {
        let prev = *self.app_size.borrow();
        if prev.1 == v { return; }
        self.app_size.borrow_mut().1 = v;
        let _ = self.appHeightChanged();
        let _ = self.scaleChanged();
    }

    /// Uniform scale factor relative to the 1280×800 reference.
    /// Returns 1.0 if the window size hasn't been set yet (so the UI
    /// still renders correctly during the very first frame, before
    /// main.qml's Component.onCompleted has run).
    pub fn scale(&self) -> f64 {
        let (w, h) = *self.app_size.borrow();
        if w <= 0 || h <= 0 {
            return 1.0;
        }
        let s = (w as f64 / 1280.0).min(h as f64 / 800.0);
        s.clamp(0.5, 3.0)
    }

    /// Convenience: scaled integer for a single reference pixel size.
    fn scaled(&self, reference: f64) -> i32 {
        (reference * self.scale()).round() as i32
    }

    // Column widths.
    pub fn col_spaces_w(&self) -> i32 { self.scaled(72.0) }   // server-icon sidebar
    pub fn col_rooms_w(&self) -> i32 { self.scaled(240.0) }   // room list
    pub fn col_members_w(&self) -> i32 { self.scaled(220.0) } // member list (right)

    // Header heights.
    pub fn header_h(&self) -> i32 { self.scaled(48.0) }       // sidebar headers
    pub fn header_chat_h(&self) -> i32 { self.scaled(56.0) }  // chat header

    // Buttons.
    pub fn tab_btn_h(&self) -> i32 { self.scaled(40.0) }      // settings tab button
    pub fn icon_btn_size(&self) -> i32 { self.scaled(40.0) }  // square icon button (📁 😀 ↑)

    // Settings panel.
    pub fn settings_nav_w(&self) -> i32 { self.scaled(180.0) } // left nav in settings

    // Dialogs.
    pub fn dialog_md_w(&self) -> i32 { self.scaled(360.0) }   // medium dialog (delete confirm)
    pub fn dialog_lg_w(&self) -> i32 { self.scaled(500.0) }   // large dialog (export/import JSON)

    // Profile page.
    pub fn avatar_profile(&self) -> i32 { self.scaled(80.0) } // big avatar in profile settings
    pub fn banner_h(&self) -> i32 { self.scaled(140.0) }      // profile banner

    // Form controls.
    pub fn combo_box_md_w(&self) -> i32 { self.scaled(180.0) } // preset / language combo
    pub fn combo_box_sm_w(&self) -> i32 { self.scaled(140.0) } // presence combo
    pub fn combo_box_xs_w(&self) -> i32 { self.scaled(100.0) } // (reserved)
    pub fn spin_box_w(&self) -> i32 { self.scaled(100.0) }     // IntRow SpinBox

    // Appearance editor.
    pub fn color_swatch_size(&self) -> i32 { self.scaled(24.0) } // ColorRow swatch
    pub fn preview_box_h(&self) -> i32 { self.scaled(32.0) }     // IntRow preview box

    // Chat composer.
    pub fn reply_banner_h(&self) -> i32 { self.scaled(36.0) }   // reply preview banner

    // List rows.
    pub fn avatar_list_md(&self) -> i32 { self.scaled(32.0) } // 32px list avatar (room list, member list)
    pub fn room_row_h(&self) -> i32 { self.scaled(56.0) }     // room list row
    pub fn space_icon_size(&self) -> i32 { self.scaled(48.0) } // space icon in spaces column
}

impl qmetaobject::QSingletonInit for Theme {
    fn init(&mut self) {
        // Load persisted theme from disk on first creation.
        self.load_from_disk();
        // Store the QPointer for global access.
        THEME_SINGLETON.set(QPointer::from(&*self));
    }
}

/// Built-in color presets. Each returns a fully-populated `ThemeState`.
fn preset(name: &str) -> ThemeState {
    let mut s = base_layout();
    match name {
        "Solarized Dark" => {
            s.preset = "Solarized Dark".into();
            s.window_bg = "#002b36".into();
            s.window_fg = "#93a1a1".into();
            s.sidebar_bg = "#073642".into();
            s.sidebar_fg = "#93a1a1".into();
            s.accent = "#268bd2".into();
            s.accent_fg = "#fdf6e3".into();
            s.bubble_bg_me = "#073642".into();
            s.bubble_bg_them = "#586e75".into();
            s.bubble_fg_me = "#93a1a1".into();
            s.bubble_fg_them = "#fdf6e3".into();
            s.border = "#586e75".into();
            s.muted = "#657b83".into();
        }
        "Tokyo Night" => {
            s.preset = "Tokyo Night".into();
            s.window_bg = "#1a1b26".into();
            s.window_fg = "#c0caf5".into();
            s.sidebar_bg = "#16161e".into();
            s.sidebar_fg = "#c0caf5".into();
            s.accent = "#7aa2f7".into();
            s.accent_fg = "#1a1b26".into();
            s.bubble_bg_me = "#283457".into();
            s.bubble_bg_them = "#24283b".into();
            s.bubble_fg_me = "#c0caf5".into();
            s.bubble_fg_them = "#c0caf5".into();
            s.border = "#414868".into();
            s.muted = "#565f89".into();
        }
        "Nordic" => {
            s.preset = "Nordic".into();
            s.window_bg = "#2e3440".into();
            s.window_fg = "#d8dee9".into();
            s.sidebar_bg = "#3b4252".into();
            s.sidebar_fg = "#e5e9f0".into();
            s.accent = "#88c0d0".into();
            s.accent_fg = "#2e3440".into();
            s.bubble_bg_me = "#434c5e".into();
            s.bubble_bg_them = "#4c566a".into();
            s.bubble_fg_me = "#eceff4".into();
            s.bubble_fg_them = "#eceff4".into();
            s.border = "#4c566a".into();
            s.muted = "#7b8497".into();
        }
        "Dracula" => {
            s.preset = "Dracula".into();
            s.window_bg = "#282a36".into();
            s.window_fg = "#f8f8f2".into();
            s.sidebar_bg = "#21222c".into();
            s.sidebar_fg = "#f8f8f2".into();
            s.accent = "#bd93f9".into();
            s.accent_fg = "#282a36".into();
            s.bubble_bg_me = "#44475a".into();
            s.bubble_bg_them = "#6272a4".into();
            s.bubble_fg_me = "#f8f8f2".into();
            s.bubble_fg_them = "#f8f8f2".into();
            s.border = "#6272a4".into();
            s.muted = "#6272a4".into();
        }
        "Gruvbox" => {
            s.preset = "Gruvbox".into();
            s.window_bg = "#282828".into();
            s.window_fg = "#ebdbb2".into();
            s.sidebar_bg = "#3c3836".into();
            s.sidebar_fg = "#ebdbb2".into();
            s.accent = "#fabd2f".into();
            s.accent_fg = "#282828".into();
            s.bubble_bg_me = "#504945".into();
            s.bubble_bg_them = "#665c54".into();
            s.bubble_fg_me = "#ebdbb2".into();
            s.bubble_fg_them = "#ebdbb2".into();
            s.border = "#7c6f64".into();
            s.muted = "#928374".into();
        }
        "Catppuccin Mocha" => {
            s.preset = "Catppuccin Mocha".into();
            s.window_bg = "#1e1e2e".into();
            s.window_fg = "#cdd6f4".into();
            s.sidebar_bg = "#181825".into();
            s.sidebar_fg = "#cdd6f4".into();
            s.accent = "#cba6f7".into();
            s.accent_fg = "#1e1e2e".into();
            s.bubble_bg_me = "#313244".into();
            s.bubble_bg_them = "#45475a".into();
            s.bubble_fg_me = "#cdd6f4".into();
            s.bubble_fg_them = "#cdd6f4".into();
            s.border = "#45475a".into();
            s.muted = "#6c7086".into();
        }
        "Sunset" => {
            s.preset = "Sunset".into();
            s.window_bg = "#2b1d2a".into();
            s.window_fg = "#f5d9c0".into();
            s.sidebar_bg = "#3a2530".into();
            s.sidebar_fg = "#f5d9c0".into();
            s.accent = "#ff7e6b".into();
            s.accent_fg = "#2b1d2a".into();
            s.bubble_bg_me = "#5a3447".into();
            s.bubble_bg_them = "#7a3a52".into();
            s.bubble_fg_me = "#f5d9c0".into();
            s.bubble_fg_them = "#ffe6cf".into();
            s.border = "#7a3a52".into();
            s.muted = "#a87889".into();
        }
        "Matrix Green" => {
            s.preset = "Matrix Green".into();
            s.window_bg = "#000000".into();
            s.window_fg = "#00ff41".into();
            s.sidebar_bg = "#0a0a0a".into();
            s.sidebar_fg = "#00ff41".into();
            s.accent = "#00ff41".into();
            s.accent_fg = "#000000".into();
            s.bubble_bg_me = "#003b00".into();
            s.bubble_bg_them = "#002200".into();
            s.bubble_fg_me = "#00ff41".into();
            s.bubble_fg_them = "#00ff41".into();
            s.border = "#006400".into();
            s.muted = "#008f11".into();
            s.font_family_mono = "Monospace".into();
        }
        _ => {
            // Material Dark (default)
            s.preset = "Material Dark".into();
            s.window_bg = "#1e1e1e".into();
            s.window_fg = "#e4e4e4".into();
            s.sidebar_bg = "#252525".into();
            s.sidebar_fg = "#e4e4e4".into();
            s.accent = "#7c4dff".into();
            s.accent_fg = "#ffffff".into();
            s.bubble_bg_me = "#7c4dff".into();
            s.bubble_bg_them = "#3a3a3a".into();
            s.bubble_fg_me = "#ffffff".into();
            s.bubble_fg_them = "#e4e4e4".into();
            s.border = "#3a3a3a".into();
            s.muted = "#888888".into();
        }
    }
    s.danger = "#ef4444".into();
    s.success = "#22c55e".into();
    s.warning = "#f59e0b".into();
    s
}

/// The layout / sizing skeleton shared by every preset. Only colors and
/// font family differ between presets; geometry stays consistent so the user
/// can fine-tune without breaking the layout.
fn base_layout() -> ThemeState {
    ThemeState {
        preset: "Material Dark".into(),
        window_bg: "#1e1e1e".into(),
        window_fg: "#e4e4e4".into(),
        sidebar_bg: "#252525".into(),
        sidebar_fg: "#e4e4e4".into(),
        accent: "#7c4dff".into(),
        accent_fg: "#ffffff".into(),
        danger: "#ef4444".into(),
        success: "#22c55e".into(),
        warning: "#f59e0b".into(),
        muted: "#888888".into(),
        border: "#3a3a3a".into(),
        font_family: "Sans Serif".into(),
        font_family_mono: "Monospace".into(),
        font_size_xs: 10,
        font_size_sm: 12,
        font_size_md: 14,
        font_size_lg: 16,
        font_size_xl: 22,
        radius_sm: 4,
        radius_md: 8,
        radius_lg: 16,
        padding_xs: 4,
        padding_sm: 8,
        padding_md: 12,
        padding_lg: 16,
        spacing_xs: 2,
        spacing_sm: 4,
        spacing_md: 8,
        spacing_lg: 16,
        bubble_bg_me: "#7c4dff".into(),
        bubble_bg_them: "#3a3a3a".into(),
        bubble_fg_me: "#ffffff".into(),
        bubble_fg_them: "#e4e4e4".into(),
        bubble_radius: 14,
        bubble_padding_h: 12,
        bubble_padding_v: 8,
        bubble_tail: false,
        bubble_max_width_pct: 75,
        avatar_size_sm: 28,
        avatar_size_md: 36,
        avatar_size_lg: 48,
        avatar_radius: 18,
        avatar_shape: "circle".into(),
        scrollbar_size: 8,
        scrollbar_radius: 4,
        compact_mode: false,
        show_timestamps: true,
        show_avatars: true,
        animate_bubbles: true,
        animation_duration_ms: 180,
        language: "en".into(),
    }
}
