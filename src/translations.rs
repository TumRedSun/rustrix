//! `Translations` — Rust-side translation singleton.
//!
//! Exposes a single method `tr(language, source)` that looks up a
//! translation in a hardcoded dictionary. QML calls it as
//! `Tr.tr(Theme.language, "Reply")`. Passing `Theme.language` as an
//! argument makes the binding depend on `Theme.language` (which has a
//! NOTIFY signal), so when the user changes the language in settings,
//! every `text: Tr.tr(Theme.language, "X")` binding re-evaluates and
//! the UI updates dynamically — no restart required.
//!
//! Languages currently with non-empty dictionaries: ru. Other supported
//! languages (de, fr, es, pt, ja, zh, ko, it, pl, uk) have empty
//! dictionaries and fall back to the source English string. Add new
//! translations by appending to the `LANG_SOURCES` array for the
//! relevant language below — the `source` strings MUST match the
//! `qsTr("...")` strings used in QML exactly (otherwise the lookup
//! misses and English shows through).

use qmetaobject::*;
use std::collections::HashMap;
use std::sync::OnceLock;

/// Static translation dictionary: lang_code -> (source_string -> translated_string).
static DICT: OnceLock<HashMap<&'static str, HashMap<&'static str, &'static str>>> = OnceLock::new();

fn build_dict() -> HashMap<&'static str, HashMap<&'static str, &'static str>> {
    let mut m: HashMap<&'static str, HashMap<&'static str, &'static str>> = HashMap::new();

    // Russian
    let mut ru_map: HashMap<&'static str, &'static str> = HashMap::new();
    for &(s, t) in RU_SOURCES {
        ru_map.insert(s, t);
    }
    m.insert("ru", ru_map);

    // To add another language, e.g. German:
    //   let mut de_map: HashMap<&'static str, &'static str> = HashMap::new();
    //   for &(s, t) in DE_SOURCES { de_map.insert(s, t); }
    //   m.insert("de", de_map);

    m
}

/// Russian translation table.
///
/// Source strings must match `qsTr("...")` / `Tr.tr(Theme.language, "...")`
/// calls in QML exactly. Missing strings fall back to the source English text.
#[allow(dead_code)]
const RU_SOURCES: &[(&str, &str)] = &[
    // ── Common actions / states ──
    ("Reply", "Ответить"),
    ("React…", "Реакция…"),
    ("Save", "Сохранить"),
    ("Copy", "Копировать"),
    ("Delete", "Удалить"),
    ("Hide for me", "Скрыть для меня"),
    ("Send", "Отправить"),
    ("Back", "Назад"),
    ("Forward", "Вперёд"),
    ("Close", "Закрыть"),
    ("Cancel", "Отмена"),
    ("Rename attachment", "Переименовать вложение"),
    ("New name (the original file is not modified):", "Новое имя (оригинальный файл не изменяется):"),
    ("Rename this file (does not modify the original)", "Переименовать этот файл (оригинал не изменяется)"),
    ("Remove this attachment", "Удалить это вложение"),
    ("Attach files (multiple selection supported)", "Прикрепить файлы (можно выбрать несколько)"),
    ("Add a caption (optional) and press Enter to send…", "Добавьте подпись (необязательно) и нажмите Enter для отправки…"),
    ("Type a message…", "Введите сообщение…"),
    ("Offline — messages cannot be sent", "Не в сети — сообщения не могут быть отправлены"),
    ("Offline", "Не в сети"),
    ("Ready", "Готово"),
    ("Syncing…", "Синхронизация…"),
    ("Select a conversation", "Выберите беседу"),
    ("No room selected", "Беседа не выбрана"),
    ("Replying to:", "Ответ для:"),
    ("(original message)", "(исходное сообщение)"),
    ("Downloaded to %1", "Сохранено в %1"),
    ("Refresh", "Обновить"),
    ("Refresh rooms & spaces", "Обновить комнаты и пространства"),
    ("Search…", "Поиск…"),

    // ── Emoji picker ──
    ("React with emoji", "Реакция эмодзи"),
    ("Insert emoji", "Вставить эмодзи"),
    ("Type to search  ·  ↑↓ to move  ·  Enter to react  ·  Esc to close",
     "Печатайте для поиска  ·  ↑↓ для перемещения  ·  Enter для реакции  ·  Esc для закрытия"),
    ("Type to search  ·  ↑↓ to move  ·  Enter to insert  ·  Esc to close",
     "Печатайте для поиска  ·  ↑↓ для перемещения  ·  Enter для вставки  ·  Esc для закрытия"),
    ("Search emoji (e.g. heart, fire, thumbs up)…",
     "Поиск эмодзи (напр. сердце, огонь, палец вверх)…"),
    ("No emoji match your search.", "Эмодзи не найдены."),
    ("%1 emoji", "%1 эмодзи"),
    ("Insert emoji into message", "Вставить эмодзи в сообщение"),

    // ── Reaction senders popup ──
    ("Reactions", "Реакции"),
    ("Left-click this reaction in the chat to toggle your own.",
     "ЛКМ по реакции в чате переключает вашу собственную."),

    // ── Message bubble ──
    ("(empty)", "(пусто)"),
    ("Encrypted message — decryption pending", "Зашифрованное сообщение — ожидание расшифровки"),
    ("(event)", "(событие)"),
    ("Loading image…", "Загрузка изображения…"),
    ("Loading video…", "Загрузка видео…"),
    ("Audio", "Аудио"),
    ("File", "Файл"),
    ("🎬 Video", "🎬 Видео"),

    // ── Main window / sidebar ──
    ("Rustrix", "Rustrix"),
    ("Rustrix — %1", "Rustrix — %1"),
    ("Direct Messages", "Личные сообщения"),
    ("Rooms", "Комнаты"),
    ("Find user", "Найти пользователя"),
    ("Type a username (e.g. @alice:matrix.org)…",
     "Введите имя пользователя (напр. @alice:matrix.org)…"),
    ("(no display name)", "(нет отображаемого имени)"),
    ("No users found. Try the full Matrix ID (e.g. @alice:matrix.org).",
     "Пользователи не найдены. Попробуйте полный Matrix ID (напр. @alice:matrix.org)."),
    ("Close conversation?", "Закрыть беседу?"),
    ("Conversation closed", "Беседа закрыта"),
    ("This will leave the room. Your and the other participant's messages will no longer be visible to you in this client.",
     "Это покинет комнату. Ваши сообщения и сообщения собеседника больше не будут видны вам в этом клиенте."),

    // ── Settings ──
    ("Settings", "Настройки"),
    ("My Profile", "Мой профиль"),
    ("Your Profile", "Ваш профиль"),
    ("Appearance", "Внешний вид"),
    ("Language", "Язык"),
    ("Interface Language", "Язык интерфейса"),
    ("Available Languages", "Доступные языки"),
    ("Connection & Behavior", "Подключение и поведение"),
    ("Connection", "Подключение"),
    ("Network", "Сеть"),
    ("Account", "Аккаунт"),
    ("Diagnostics", "Диагностика"),
    ("Presence", "Присутствие"),
    ("Logout", "Выйти"),
    ("Delete Account", "Удалить аккаунт"),
    ("Set", "Установить"),
    ("Status (optional)", "Статус (необязательно)"),
    ("Status: %1", "Статус: %1"),
    ("User ID: %1", "ID пользователя: %1"),
    ("Last error: %1", "Последняя ошибка: %1"),
    ("Name", "Имя"),
    ("Click to set profile banner", "Нажмите, чтобы установить баннер профиля"),
    ("Choose a banner image", "Выберите изображение баннера"),
    ("Choose a new avatar", "Выберите новый аватар"),
    ("Not connected", "Не подключено"),
    ("Force IPv6-only transport", "Только IPv6-транспорт"),
    ("(only AAAA records are resolved; IPv4 endpoints are refused)",
     "(разрешаются только AAAA-записи; IPv4-конечные точки отклоняются)"),
    ("Homeserver accepts domain, IPv4, or [IPv6] (port optional). Both A and AAAA records are tried.",
     "Хоумсервер принимает домен, IPv4 или [IPv6] (порт необязателен). Записи A и AAAA обе используются."),
    ("Warning: Deleting your account is irreversible. All data will be permanently removed from the server.",
     "Внимание: Удаление аккаунта необратимо. Все данные будут навсегда удалены с сервера."),
    ("Account Actions", "Действия с аккаунтом"),

    // ── Appearance settings (redesigned) ──
    ("Theme presets", "Готовые темы"),
    ("Pick a ready-made theme, then fine-tune anything below.",
     "Выберите готовую тему — затем тонко настройте что угодно ниже."),
    ("Hello! This is how your theme looks.", "Привет! Так выглядит твоя тема."),
    ("Looks good! Keep tweaking.", "Класс! Настраиваю."),
    ("Message…", "Сообщение…"),
    ("Interface colors", "Цвета интерфейса"),
    ("Messages", "Сообщения"),
    ("Bubble corner radius", "Скругление пузырей"),
    ("Padding horizontal", "Отступ по горизонтали"),
    ("Padding vertical", "Отступ по вертикали"),
    ("Max width", "Макс. ширина"),
    ("Text", "Текст"),
    ("Monospace font", "Моноширинный шрифт"),
    ("Small text (timestamps, statuses)", "Мелкий текст (время, статусы)"),
    ("Body text", "Обычный текст"),
    ("Controls (buttons, fields)", "Кнопки и поля"),
    ("Headings", "Заголовки"),
    ("Large headings", "Крупные заголовки"),
    ("Small size", "Малый размер"),
    ("Medium size", "Средний размер"),
    ("Large size", "Крупный размер"),
    ("Avatar corner radius", "Скругление аватарок"),
    ("Interface", "Интерфейс"),
    ("Animation duration", "Длительность анимации"),
    ("Advanced", "Дополнительные настройки"),
    ("Fine-grained geometry knobs. Most people never need these — radius, padding and spacing below affect every corner of the app.",
     "Тонкая настройка геометрии. Большинству это не нужно: скругления, отступы и промежутки ниже влияют на весь интерфейс."),
    ("Corner radius · small", "Скругление · мелкие элементы"),
    ("Corner radius · cards", "Скругление · карточки"),
    ("Corner radius · panels", "Скругление · панели и окна"),
    ("Inner padding · XS", "Внутренние отступы · XS"),
    ("Inner padding · SM", "Внутренние отступы · SM"),
    ("Inner padding · MD", "Внутренние отступы · MD"),
    ("Inner padding · LG", "Внутренние отступы · LG"),
    ("Gaps · XS", "Промежутки · XS"),
    ("Gaps · SM", "Промежутки · SM"),
    ("Gaps · MD", "Промежутки · MD"),
    ("Gaps · LG", "Промежутки · LG"),
    ("Scrollbar width", "Ширина полос прокрутки"),
    ("Scrollbar radius", "Скругление полос прокрутки"),

    // ── Language switch notice ──
    // Old text was: "Changing the language will take effect after restarting the application."
    // New text (since switching is now dynamic): no restart needed.
    ("Language changes apply immediately — no restart needed.",
     "Смена языка применяется сразу — перезапуск не нужен."),

    // ── Appearance page ──
    ("Preset", "Пресет"),
    ("Colors", "Цвета"),
    ("Window bg", "Фон окна"),
    ("Window fg", "Текст окна"),
    ("Sidebar bg", "Фон боковой панели"),
    ("Sidebar fg", "Текст боковой панели"),
    ("Accent", "Акцент"),
    ("Accent fg", "Текст акцента"),
    ("Danger", "Опасность"),
    ("Success", "Успех"),
    ("Warning", "Предупреждение"),
    ("Muted", "Приглушённый"),
    ("Border", "Граница"),
    ("Typography", "Типографика"),
    ("Font family", "Семейство шрифта"),
    ("Mono family", "Моноширинный шрифт"),
    ("Geometry", "Геометрия"),
    ("Radius", "Радиус"),
    ("Radius SM", "Радиус SM"),
    ("Radius MD", "Радиус MD"),
    ("Radius LG", "Радиус LG"),
    ("Corner r", "Радиус угла"),
    ("Padding H", "Отступ H"),
    ("Padding V", "Отступ V"),
    ("Pad XS", "Отступ XS"),
    ("Pad SM", "Отступ SM"),
    ("Pad MD", "Отступ MD"),
    ("Pad LG", "Отступ LG"),
    ("Space XS", "Пробел XS"),
    ("Space SM", "Пробел SM"),
    ("Space MD", "Пробел MD"),
    ("Space LG", "Пробел LG"),
    ("Size XS", "Размер XS"),
    ("Size SM", "Размер SM"),
    ("Size MD", "Размер MD"),
    ("Size LG", "Размер LG"),
    ("Size XL", "Размер XL"),
    ("Width", "Ширина"),
    ("Scrollbars", "Полосы прокрутки"),
    ("Behavior", "Поведение"),
    ("Compact mode", "Компактный режим"),
    ("Show timestamps", "Показывать время"),
    ("Show avatars", "Показывать аватары"),
    ("Animate bubbles", "Анимировать пузыри"),
    ("Anim ms", "Анимация мс"),
    ("Avatars", "Аватары"),
    ("Shape", "Форма"),
    ("Message bubbles", "Пузыри сообщений"),
    ("Bubble own bg", "Свой пузырь фон"),
    ("Bubble own fg", "Свой пузырь текст"),
    ("Bubble other bg", "Чужой пузырь фон"),
    ("Bubble other fg", "Чужой пузырь текст"),
    ("Bubble radius", "Радиус пузыря"),
    ("Bubble tail", "Хвостик пузыря"),
    ("Max width %", "Макс. ширина %"),
    ("Theme JSON", "JSON темы"),
    ("Paste theme JSON", "Вставить JSON темы"),
    ("Invalid JSON", "Неверный JSON"),
    ("Import", "Импорт"),
    ("Export", "Экспорт"),
    ("Reset", "Сбросить"),
    ("Preview", "Предпросмотр"),

    // ── SpacesPage ──
    ("Spaces & Rooms", "Пространства и комнаты"),
    ("Pick a room from the left to start chatting",
     "Выберите комнату слева, чтобы начать общение"),
    ("%1 unread", "%1 непрочитанных"),
    ("room", "комната"),
    ("direct", "личная"),
    ("space", "пространство"),

    // ── Login page ──
    ("Login", "Вход"),
    ("Homeserver", "Хоумсервер"),
    ("Homeserver — domain, IPv4, or [IPv6] (port optional)",
     "Хоумсервер — домен, IPv4 или [IPv6] (порт необязателен)"),
    ("Username", "Имя пользователя"),
    ("Password", "Пароль"),
    ("Logging in…", "Вход…"),
    ("Auto-login on next launch", "Автоматический вход при следующем запуске"),
    ("Login with SSO", "Войти через SSO"),
    ("Invalid credentials", "Неверные учётные данные"),
    ("Connection failed", "Не удалось подключиться"),

    // ── Loading screen ──
    ("Loading…", "Загрузка…"),
    ("Synchronizing…", "Синхронизация…"),
    ("Almost there…", "Почти готово…"),
];

#[derive(QObject, Default)]
pub struct Translations {
    base: qt_base_class!(trait QObject),
    /// `tr(language, source) -> translated_string`.
    /// QML calls this as `Tr.tr(Theme.language, "Reply")`.
    /// Passing `Theme.language` explicitly makes the QML binding depend
    /// on the `Theme.language` property (which has a NOTIFY signal),
    /// so when the user changes the language, every binding re-evaluates
    /// and the UI updates dynamically.
    tr: qt_method!(fn(&self, language: QString, source: QString) -> QString),
}

impl Translations {
    /// Look up a translation. Falls back to the source string when:
    ///   - language is "en" or empty
    ///   - language has no dictionary entry
    ///   - the source string isn't in the dictionary for that language
    ///
    /// This is a pure function — no side effects, no property reads —
    /// so it's safe to call from any thread (though QML always calls
    /// it on the Qt main thread).
    pub fn tr(&self, language: QString, source: QString) -> QString {
        let lang = language.to_string();
        if lang.is_empty() || lang == "en" {
            return source;
        }
        let dict = DICT.get_or_init(build_dict);
        if let Some(lang_dict) = dict.get(lang.as_str()) {
            let src = source.to_string();
            if let Some(translated) = lang_dict.get(src.as_str()) {
                return QString::from(*translated);
            }
        }
        // Fallback: return the source string unchanged.
        source
    }
}

impl qmetaobject::QSingletonInit for Translations {
    fn init(&mut self) {
        // Pre-build the dictionary on first singleton init so the first
        // `tr()` call is fast. Subsequent calls just look up.
        DICT.get_or_init(build_dict);
    }
}
