//! Settings, in the macOS look: a sidebar (Dictation, Engine, Vocabulary,
//! History, About) and one page of cards at a time. 780x540, so it fits a
//! 1366x768 laptop at 125 % scaling.

use super::controls::{self as c, Theme};
use super::skin::{self, ds, Dropdown, Kind, Meter, Segmented, Skin, Text};
use crate::core::config::{Engine, OutputMode};
use crate::core::text::{format_replacements, parse_replacements};
use crate::core::{hotkeys, languages};
use crate::win::engine::model;
use crate::win::{autostart, keystore, mic, shell, state};
use native_windows_gui as nwg;
use nwg::NwgError;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use std::sync::{Arc, Mutex};
use crate::core::cloud;

const MEMORY: [(u64, &str); 3] = [
    (0, "Save memory - unload at once"),
    (180, "Balanced - keep 3 minutes"),
    (600, "Fast start - keep 10 minutes"),
];
const RETENTION: [(u32, &str); 4] = [
    (0, "Until cleared"),
    (1, "1 day"),
    (7, "7 days"),
    (30, "30 days"),
];
const ENGINES: [Engine; 4] = [Engine::Local, Engine::HlasCloud, Engine::Groq, Engine::OpenAI];

// Layout, in logical pixels.
const WIDTH: i32 = 780;
const HEIGHT: i32 = 540;
const SIDEBAR: i32 = 200;
const X0: i32 = 228;
const CW: i32 = 524;
const PAD: i32 = 18;
const ROW: i32 = 52;
const CTRL_W: i32 = 250;
const CTRL_X: i32 = X0 + CW - PAD - CTRL_W;

const PAGES: [(char, &str, &str); 6] = [
    ('\u{E720}', "Dictation", "How you talk to Hlas."),
    (
        '\u{E945}',
        "Engine",
        "Where speech turns into text. API keys stay in Windows Credential Manager.",
    ),
    (
        '\u{E753}',
        "Hlas Cloud",
        "Unlimited dictation without keys or a model download.",
    ),
    (
        '\u{E8D2}',
        "Vocabulary",
        "Help Hlas spell names, brands and jargon.",
    ),
    (
        '\u{E81C}',
        "History",
        "Stored only on this PC, never synced.",
    ),
    ('\u{E946}', "About", "Dictation. Not typing."),
];

fn engine_note(engine: Engine) -> &'static str {
    match engine {
        Engine::Local => {
            "Runs on this PC. Private, free and offline after a one-time 547 MB download."
        }
        Engine::HlasCloud => {
            "Hlas Cloud. Unlimited dictation for EUR 35 a year, no keys. Add your licence on the Hlas Cloud page."
        }
        Engine::Groq => "Groq cloud. The fastest, about $3 a month with your own key.",
        Engine::OpenAI => {
            "OpenAI cloud. Best accuracy and vocabulary, about $8 a month with your own key."
        }
    }
}

pub struct SettingsWindow {
    window: nwg::Window,
    skin: Rc<Skin>,
    nav: Segmented,
    hotkey: Dropdown,
    language: Dropdown,
    favorites: nwg::TextInput,
    microphone: Dropdown,
    output: Segmented,
    launch: nwg::Button,
    engine: Segmented,
    engine_note: Text,
    model_status: Text,
    model_button: nwg::Button,
    model_meter: Meter,
    memory: Dropdown,
    groq_key: nwg::TextInput,
    openai_key: nwg::TextInput,
    cloud_key: nwg::TextInput,
    cloud_status: Text,
    cloud_check: nwg::Button,
    cloud_trial: nwg::Button,
    cloud_buy: nwg::Button,
    cloud_manage: nwg::Button,
    /// Result of the last background licence check, picked up by the timer.
    cloud_result: Arc<Mutex<Option<String>>>,
    /// Result of "Try free for 7 days": the trial key, or a message.
    trial_result: Arc<Mutex<Option<Result<String, String>>>>,
    vocabulary: nwg::TextBox,
    replacements: nwg::TextBox,
    history_on: nwg::Button,
    retention: Dropdown,
    open_history: nwg::Button,
    clear_history: nwg::Button,
    open_log: nwg::Button,
    privacy: nwg::Button,
    updates: nwg::Button,
    save: nwg::Button,
    status: Text,
    timer: nwg::AnimationTimer,
    mic_names: RefCell<Vec<String>>,
    clear_armed: Cell<bool>,
    handler: RefCell<Option<nwg::EventHandler>>,
}

fn language_items() -> Vec<String> {
    std::iter::once(languages::AUTO)
        .chain(languages::ALL.iter().copied())
        .map(|(code, name)| format!("{name} ({code})"))
        .collect()
}

fn language_code(index: usize) -> String {
    if index == 0 {
        "auto".into()
    } else {
        languages::ALL
            .get(index - 1)
            .map(|(c, _)| c.to_string())
            .unwrap_or_else(|| "auto".into())
    }
}

fn language_index(code: &str) -> usize {
    languages::ALL
        .iter()
        .position(|(c, _)| *c == code)
        .map(|i| i + 1)
        .unwrap_or(0)
}

/// A row label inside a card, vertically centred in the row.
fn row_label(skin: &Skin, group: u8, text: &str, top: i32) {
    let t = skin.theme.clone();
    skin.label(
        group,
        text,
        (X0 + PAD, top, CTRL_X - X0 - PAD - 12, ROW),
        &t.body,
        ds::FG,
        skin::LINE,
    );
}

/// Title and switch row (60 high) with a muted second line.
#[allow(clippy::too_many_arguments)]
fn switch_row(
    skin: &Skin,
    group: u8,
    title: &str,
    detail: &str,
    top: i32,
) -> Result<nwg::Button, NwgError> {
    let t = skin.theme.clone();
    skin.label(
        group,
        title,
        (X0 + PAD, top + 10, CW - 2 * PAD - 60, 22),
        &t.medium,
        ds::FG,
        skin::LINE,
    );
    skin.label(
        group,
        detail,
        (X0 + PAD, top + 32, CW - 2 * PAD - 60, 18),
        &t.small,
        ds::FG3,
        skin::LINE,
    );
    skin.toggle(group, X0 + CW - PAD - 40, top + 19, ds::SURFACE, false)
}

impl SettingsWindow {
    pub fn build(theme: Rc<Theme>) -> Result<Rc<SettingsWindow>, NwgError> {
        let t = theme.clone();
        let w = c::window(&t, "Hlas Settings", (WIDTH, HEIGHT), false)?;
        let skin = Skin::new(theme, &w, ds::BG);
        let s = &*skin;

        // Sidebar.
        s.fill(0, (0, 0, SIDEBAR, HEIGHT), ds::SIDEBAR);
        s.fill(0, (SIDEBAR, 0, 1, HEIGHT), ds::BORDER);
        s.logo(0, 20, 24, 26);
        s.tracked(0, "HLAS", (56, 22, 130, 30), &t.wordmark, ds::FG, 4);
        s.tracked(
            0,
            "DICTATION. NOT TYPING.",
            (20, 60, 175, 16),
            &t.section,
            ds::BRAND,
            2,
        );
        let nav_items: Vec<(char, &str)> = PAGES.iter().map(|(i, n, _)| (*i, *n)).collect();
        let nav = s.nav(&nav_items, 12, 98, SIDEBAR - 24, ds::SIDEBAR)?;
        s.label(
            0,
            &format!("Version {}", env!("CARGO_PKG_VERSION")),
            (20, HEIGHT - 34, 170, 18),
            &t.small,
            ds::FG3,
            skin::LINE,
        );

        // Page titles.
        for (i, (_, name, detail)) in PAGES.iter().enumerate() {
            let g = i as u8 + 1;
            s.label(g, name, (X0, 20, CW, 30), &t.heading, ds::FG, skin::LINE);
            s.label(g, detail, (X0, 52, CW, 20), &t.small, ds::FG3, skin::LINE);
        }

        // 1. Dictation.
        let g = 1;
        s.card(g, (X0, 84, CW, 4 * ROW));
        for (i, name) in [
            "Push-to-talk key",
            "Language",
            "Tray languages",
            "Microphone",
        ]
        .iter()
        .enumerate()
        {
            let top = 84 + i as i32 * ROW;
            row_label(s, g, name, top);
            if i > 0 {
                s.rule(g, X0 + PAD, top, CW - 2 * PAD);
            }
        }
        let hotkey = s.combo(
            g,
            hotkeys::KEYS.iter().map(|(_, n)| n.to_string()).collect(),
            (CTRL_X, 84 + 9, CTRL_W),
        )?;
        let language = s.combo(g, language_items(), (CTRL_X, 84 + ROW + 9, CTRL_W))?;
        let favorites = s.input(g, (CTRL_X, 84 + 2 * ROW + 9, CTRL_W, 34), false)?;
        let microphone = s.combo(g, vec![], (CTRL_X, 84 + 3 * ROW + 9, CTRL_W))?;

        s.card(g, (X0, 306, CW, 96));
        row_label(s, g, "Output", 306);
        let output = s.segmented(
            g,
            &["Transcript", "Smart text"],
            (CTRL_X, 306 + 9, CTRL_W, 34),
            0,
        )?;
        s.label(
            g,
            "Smart text cleans up punctuation and turns spoken lists into bullets. Hold Shift when you start for a plain transcript once.",
            (X0 + PAD, 306 + ROW, CW - 2 * PAD, 36),
            &t.small,
            ds::FG3,
            skin::WRAP,
        );

        s.card(g, (X0, 416, CW, 60));
        let launch = switch_row(
            s,
            g,
            "Start Hlas when I sign in",
            "Keep dictation ready in the tray.",
            416,
        )?;

        // 2. Engine.
        let g = 2;
        s.card(g, (X0, 84, CW, 100));
        let engine = s.segmented(
            g,
            &["On this PC", "Hlas Cloud", "Groq", "OpenAI"],
            (X0 + PAD, 84 + PAD, CW - 2 * PAD, 36),
            0,
        )?;
        let engine_note = s.label(
            g,
            "",
            (X0 + PAD, 84 + 62, CW - 2 * PAD, 34),
            &t.small,
            ds::FG2,
            skin::WRAP,
        );

        s.card(g, (X0, 198, CW, 144));
        s.label(
            g,
            "Local model",
            (X0 + PAD, 198 + 14, 260, 22),
            &t.medium,
            ds::FG,
            skin::LINE,
        );
        let model_status = s.label(
            g,
            "",
            (X0 + PAD, 198 + 38, CW - 2 * PAD - 140, 34),
            &t.small,
            ds::FG2,
            skin::WRAP,
        );
        let model_button = s.button(
            g,
            "Download",
            (X0 + CW - PAD - 120, 198 + 18, 120, 34),
            Kind::Secondary,
            ds::SURFACE,
        )?;
        let model_meter = s.meter(g, (X0 + PAD, 198 + 78, CW - 2 * PAD, 4));
        s.rule(g, X0 + PAD, 198 + 92, CW - 2 * PAD);
        row_label(s, g, "Model memory", 198 + 92);
        let memory = s.combo(
            g,
            MEMORY.iter().map(|(_, n)| n.to_string()).collect(),
            (CTRL_X, 198 + 92 + 9, CTRL_W),
        )?;

        s.card(g, (X0, 356, CW, 2 * ROW));
        row_label(s, g, "Groq API key", 356);
        let groq_key = s.input(g, (CTRL_X, 356 + 9, CTRL_W, 34), true)?;
        s.rule(g, X0 + PAD, 356 + ROW, CW - 2 * PAD);
        row_label(s, g, "OpenAI API key", 356 + ROW);
        let openai_key = s.input(g, (CTRL_X, 356 + ROW + 9, CTRL_W, 34), true)?;

        // 3. Hlas Cloud.
        let g = 3;
        s.card(g, (X0, 84, CW, 2 * ROW));
        row_label(s, g, "Licence key", 84);
        let cloud_key = s.input(g, (CTRL_X, 84 + 9, CTRL_W, 34), true)?;
        s.rule(g, X0 + PAD, 84 + ROW, CW - 2 * PAD);
        let cloud_status = s.label(
            g,
            "",
            (X0 + PAD, 84 + ROW, CW - 2 * PAD - 130, ROW),
            &t.small,
            ds::FG2,
            skin::LINE,
        );
        let cloud_check = s.button(
            g,
            "Check",
            (X0 + CW - PAD - 110, 84 + ROW + 9, 110, 34),
            Kind::Secondary,
            ds::SURFACE,
        )?;
        s.label(
            g,
            "EUR 35 a year + VAT, unlimited dictation with fair use up to 3 hours a day. After payment the welcome page opens Hlas and fills in your key. Audio goes through our server to Groq and is not stored.",
            (X0, 84 + 2 * ROW + 14, CW, 54),
            &t.small,
            ds::FG3,
            skin::WRAP,
        );
        let cloud_trial = s.button(
            g,
            "Try free for 7 days",
            (X0, 84 + 2 * ROW + 80, 170, 36),
            Kind::Primary,
            ds::BG,
        )?;
        let cloud_buy = s.button(
            g,
            "Get Hlas Cloud",
            (X0 + 180, 84 + 2 * ROW + 80, 150, 36),
            Kind::Secondary,
            ds::BG,
        )?;
        let cloud_manage = s.button(
            g,
            "Manage subscription",
            (X0 + 340, 84 + 2 * ROW + 80, 184, 36),
            Kind::Secondary,
            ds::BG,
        )?;

        // 4. Vocabulary.
        let g = 4;
        let mut boxes = Vec::new();
        for (i, (name, help)) in [
            ("Words to recognize", "One per line: names, brands, jargon."),
            ("Replacements", "One per line:   eden makers => Edenmakers"),
        ]
        .iter()
        .enumerate()
        {
            let top = 84 + i as i32 * 206;
            s.card(g, (X0, top, CW, 192));
            s.label(
                g,
                name,
                (X0 + PAD, top + 14, CW - 2 * PAD, 22),
                &t.medium,
                ds::FG,
                skin::LINE,
            );
            s.label(
                g,
                help,
                (X0 + PAD, top + 36, CW - 2 * PAD, 18),
                &t.small,
                ds::FG3,
                skin::LINE,
            );
            boxes.push(s.text_box(g, (X0 + PAD, top + 62, CW - 2 * PAD, 114), false)?);
        }
        let replacements = boxes.pop().expect("two boxes");
        let vocabulary = boxes.pop().expect("two boxes");

        // 5. History.
        let g = 5;
        s.card(g, (X0, 84, CW, 60 + ROW));
        let history_on = switch_row(
            s,
            g,
            "Save dictation history",
            "Search, copy and reformat past dictations.",
            84,
        )?;
        s.rule(g, X0 + PAD, 84 + 60, CW - 2 * PAD);
        row_label(s, g, "Keep history", 84 + 60);
        let retention = s.combo(
            g,
            RETENTION.iter().map(|(_, n)| n.to_string()).collect(),
            (CTRL_X, 84 + 60 + 9, CTRL_W),
        )?;
        let open_history = s.button(
            g,
            "Open history",
            (X0, 214, 160, 36),
            Kind::Secondary,
            ds::BG,
        )?;
        let clear_history = s.button(
            g,
            "Clear history",
            (X0 + 172, 214, 190, 36),
            Kind::Danger,
            ds::BG,
        )?;

        // 6. About.
        let g = 6;
        s.card(g, (X0, 84, CW, 128));
        s.logo(g, X0 + PAD, 84 + 18, 40);
        s.label(
            g,
            &format!("Hlas for Windows {}", env!("CARGO_PKG_VERSION")),
            (X0 + 72, 84 + 18, CW - 90, 22),
            &t.bold,
            ds::FG,
            skin::LINE,
        );
        s.label(
            g,
            "Free, local, no account. Hold a key, speak, release.",
            (X0 + 72, 84 + 40, CW - 90, 20),
            &t.small,
            ds::FG2,
            skin::LINE,
        );
        let open_log = s.button(
            g,
            "Log folder",
            (X0 + PAD, 84 + 76, 130, 34),
            Kind::Secondary,
            ds::SURFACE,
        )?;
        let privacy = s.button(
            g,
            "Privacy",
            (X0 + PAD + 140, 84 + 76, 110, 34),
            Kind::Secondary,
            ds::SURFACE,
        )?;
        let updates = s.button(
            g,
            "Check for updates",
            (X0 + PAD + 260, 84 + 76, 170, 34),
            Kind::Secondary,
            ds::SURFACE,
        )?;

        // Footer.
        let status = s.label(
            0,
            "",
            (X0, HEIGHT - 50, CW - 140, 36),
            &t.small,
            ds::FG2,
            skin::LINE,
        );
        let save = s.button(
            0,
            "Save",
            (X0 + CW - 120, HEIGHT - 50, 120, 36),
            Kind::Primary,
            ds::BG,
        )?;
        let timer = c::timer(&w, 400)?;

        let ui = Rc::new(SettingsWindow {
            window: w,
            skin,
            nav,
            hotkey,
            language,
            favorites,
            microphone,
            output,
            launch,
            engine,
            engine_note,
            model_status,
            model_button,
            model_meter,
            memory,
            groq_key,
            openai_key,
            cloud_key,
            cloud_status,
            cloud_check,
            cloud_trial,
            cloud_buy,
            cloud_manage,
            cloud_result: Arc::new(Mutex::new(None)),
            trial_result: Arc::new(Mutex::new(None)),
            vocabulary,
            replacements,
            history_on,
            retention,
            open_history,
            clear_history,
            open_log,
            privacy,
            updates,
            save,
            status,
            timer,
            mic_names: RefCell::new(Vec::new()),
            clear_armed: Cell::new(false),
            handler: RefCell::new(None),
        });
        ui.show_page(0);

        let weak = Rc::downgrade(&ui);
        let handler = nwg::full_bind_event_handler(&ui.window.handle, move |evt, data, handle| {
            let Some(ui) = weak.upgrade() else { return };
            use nwg::Event as E;
            if evt == E::OnButtonClick {
                ui.skin.click(&handle);
            }
            match evt {
                E::OnWindowClose if handle == ui.window.handle => {
                    if let nwg::EventData::OnWindowClose(d) = data {
                        d.close(false);
                    }
                    ui.window.set_visible(false);
                }
                E::OnButtonClick if ui.nav.index_of(&handle).is_some() => {
                    ui.show_page(ui.nav.index_of(&handle).unwrap_or(0))
                }
                E::OnButtonClick if ui.engine.index_of(&handle).is_some() => ui.refresh_engine(),
                E::OnButtonClick if handle == ui.save.handle => ui.save(),
                E::OnButtonClick if handle == ui.cloud_check.handle => ui.check_cloud(),
                E::OnButtonClick if handle == ui.cloud_buy.handle => shell::open(cloud::BUY_URL),
                E::OnButtonClick if handle == ui.cloud_trial.handle => ui.start_trial(),
                E::OnButtonClick if handle == ui.cloud_manage.handle => ui.manage_cloud(),
                E::OnButtonClick if handle == ui.model_button.handle => {
                    if model::status().active {
                        model::cancel();
                    } else {
                        model::start();
                    }
                    ui.refresh_model();
                }
                E::OnButtonClick if handle == ui.open_history.handle => {
                    super::send(super::Command::OpenHistory)
                }
                E::OnButtonClick if handle == ui.clear_history.handle => {
                    if ui.clear_armed.get() {
                        state::clear_history();
                        ui.clear_armed.set(false);
                        ui.clear_history.set_text("Clear history");
                        ui.status.set_text("History cleared.");
                    } else {
                        ui.clear_armed.set(true);
                        ui.clear_history.set_text("Click again to clear");
                    }
                }
                E::OnButtonClick if handle == ui.open_log.handle => {
                    if let Ok(dir) = crate::core::config::Config::dir() {
                        shell::open(&dir.to_string_lossy());
                    }
                }
                E::OnButtonClick if handle == ui.privacy.handle => shell::open(shell::PRIVACY),
                E::OnButtonClick if handle == ui.updates.handle => {
                    crate::win::update::check_in_background(true)
                }
                E::OnTimerTick if handle == ui.timer.handle && ui.window.visible() => {
                    ui.refresh_model();
                    ui.refresh_cloud();
                }
                _ => {}
            }
        });
        *ui.handler.borrow_mut() = Some(handler);
        ui.timer.start();
        Ok(ui)
    }

    pub fn show(&self) {
        self.load();
        c::present(&self.window);
    }

    fn show_page(&self, index: usize) {
        self.skin.select(&self.nav, index);
        self.skin.set_visible(1u64 << (index + 1));
    }

    /// Fills every control from the current config.
    fn load(&self) {
        let cfg = state::config();
        self.hotkey.set_selection(
            hotkeys::KEYS
                .iter()
                .position(|(vk, _)| *vk == cfg.hotkey_vk)
                .or(Some(0)),
        );
        self.language
            .set_selection(Some(language_index(&cfg.language)));
        self.favorites.set_text(&cfg.favorite_languages.join(", "));
        self.skin.select(
            &self.output,
            if cfg.output_mode == OutputMode::Smart {
                1
            } else {
                0
            },
        );

        let mut names = vec![String::new()];
        names.extend(mic::device_names());
        if !cfg.input_device.is_empty() && !names.contains(&cfg.input_device) {
            names.push(cfg.input_device.clone());
        }
        let labels: Vec<String> = names
            .iter()
            .map(|n| {
                if n.is_empty() {
                    "Windows default".to_string()
                } else {
                    n.clone()
                }
            })
            .collect();
        self.microphone.set_collection(labels);
        self.microphone.set_selection(
            names
                .iter()
                .position(|n| *n == cfg.input_device)
                .or(Some(0)),
        );
        *self.mic_names.borrow_mut() = names;

        self.skin
            .set_on(&self.launch.handle, autostart::is_enabled());
        self.skin.select(
            &self.engine,
            ENGINES.iter().position(|e| *e == cfg.engine).unwrap_or(0),
        );
        self.memory.set_selection(Some(
            MEMORY
                .iter()
                .position(|(s, _)| *s == cfg.model_keep_alive_secs)
                .unwrap_or(1),
        ));
        self.groq_key
            .set_text(&keystore::get_key(keystore::GROQ).unwrap_or_default());
        self.openai_key
            .set_text(&keystore::get_key(keystore::OPENAI).unwrap_or_default());
        let cloud_key = keystore::get_key(keystore::HLAS_CLOUD);
        self.cloud_key.set_text(cloud_key.as_deref().unwrap_or_default());
        self.cloud_trial.set_visible(cloud_key.is_none());
        self.cloud_status.set_color(ds::FG2);
        if cloud_key.is_some() {
            self.check_cloud();
        } else {
            self.cloud_status.set_text("No licence yet.");
        }
        c::set_box_text(&self.vocabulary, &cfg.vocabulary.join("\n"));
        c::set_box_text(&self.replacements, &format_replacements(&cfg.replacements));
        self.skin
            .set_on(&self.history_on.handle, cfg.history_enabled);
        self.retention.set_selection(Some(
            RETENTION
                .iter()
                .position(|(d, _)| *d == cfg.history_retention_days)
                .unwrap_or(0),
        ));
        self.clear_armed.set(false);
        self.clear_history.set_text("Clear history");
        self.status.set_text("");
        self.refresh_engine();
        self.refresh_model();
    }

    fn engine(&self) -> Engine {
        ENGINES[self.skin.selected(&self.engine).min(ENGINES.len() - 1)]
    }

    fn refresh_engine(&self) {
        self.engine_note.set_text(engine_note(self.engine()));
    }

    /// Checks the licence in the background; the timer shows the answer.
    fn check_cloud(&self) {
        let Some(key) = cloud::normalize_key(&self.cloud_key.text()) else {
            self.cloud_status.set_color(ds::DANGER);
            self.cloud_status.set_text(if self.cloud_key.text().trim().is_empty() {
                "No licence yet."
            } else {
                "That does not look like a licence key (hlas_XXXXX-...)."
            });
            return;
        };
        self.cloud_status.set_color(ds::FG2);
        self.cloud_status.set_text("Checking...");
        let slot = self.cloud_result.clone();
        std::thread::spawn(move || {
            let text = match crate::win::engine::cloud::account(&key) {
                Ok(status) => cloud::describe(&status),
                Err(e) => crate::core::errors::user_message(&e),
            };
            *slot.lock().unwrap() = Some(text);
        });
    }

    /// Starts the free trial in the background; the timer stores the key.
    fn start_trial(&self) {
        self.cloud_status.set_color(ds::FG2);
        self.cloud_status.set_text("Starting your free trial...");
        let slot = self.trial_result.clone();
        std::thread::spawn(move || {
            let result = crate::win::engine::cloud::start_trial().map(|(key, _)| key);
            *slot.lock().unwrap() = Some(result);
        });
    }

    fn refresh_cloud(&self) {
        if let Some(result) = self.trial_result.lock().unwrap().take() {
            match result {
                Ok(key) => {
                    self.cloud_key.set_text(&key);
                    self.skin.select(
                        &self.engine,
                        ENGINES.iter().position(|e| *e == Engine::HlasCloud).unwrap_or(1),
                    );
                    self.save();
                    self.check_cloud();
                }
                Err(message) => {
                    self.cloud_status.set_color(ds::DANGER);
                    self.cloud_status.set_text(&message);
                }
            }
        }
        if let Some(text) = self.cloud_result.lock().unwrap().take() {
            let ok = text.starts_with("Active");
            self.cloud_trial.set_visible(self.cloud_key.text().trim().is_empty());
            self.cloud_status.set_color(if ok { ds::BRAND } else { ds::DANGER });
            self.cloud_status.set_text(&text);
        }
    }

    /// Opens the Stripe portal for this licence, or the portal sign-in page.
    fn manage_cloud(&self) {
        let key = cloud::normalize_key(&self.cloud_key.text());
        std::thread::spawn(move || {
            let url = key
                .and_then(|k| crate::win::engine::cloud::portal_url(&k))
                .unwrap_or_else(|| cloud::PORTAL_LOGIN_URL.to_string());
            shell::open(&url);
        });
    }

    fn refresh_model(&self) {
        let s = model::status();
        if !crate::win::engine::local::cpu_supported() {
            self.model_status.set_text(
                "This processor cannot run the local engine. Use Hlas Cloud, Groq or OpenAI.",
            );
            self.model_button.set_text("Unavailable");
            self.model_button.set_enabled(false);
            self.model_meter.set(0.0);
        } else if model::present() {
            self.model_status
                .set_text("Ready. large-v3-turbo, 547 MB, works offline.");
            self.model_button.set_text("Ready");
            self.model_button.set_enabled(false);
            self.model_meter.set(1.0);
        } else if s.active {
            let text = if s.verifying {
                "Verifying download...".to_string()
            } else {
                format!("Downloading model... {}%", s.percent)
            };
            self.model_status.set_text(&text);
            self.model_button.set_text("Cancel");
            self.model_button.set_enabled(true);
            self.model_meter.set(s.percent as f32 / 100.0);
        } else {
            let text = s
                .error
                .unwrap_or_else(|| "The local engine needs a one-time 547 MB download.".into());
            self.model_status.set_text(&text);
            self.model_button.set_text("Download");
            self.model_button.set_enabled(true);
            self.model_meter.set(0.0);
        }
    }

    fn save(&self) {
        let engine = self.engine();
        let hotkey = self
            .hotkey
            .selection()
            .and_then(|i| hotkeys::KEYS.get(i))
            .map(|(vk, _)| *vk)
            .unwrap_or(hotkeys::DEFAULT_VK);
        let language = language_code(self.language.selection().unwrap_or(0));
        let favorites = languages::parse_list(&self.favorites.text());
        let output = if self.skin.selected(&self.output) == 1 {
            OutputMode::Smart
        } else {
            OutputMode::Transcript
        };
        let device = self
            .microphone
            .selection()
            .and_then(|i| self.mic_names.borrow().get(i).cloned())
            .unwrap_or_default();
        let memory = self
            .memory
            .selection()
            .and_then(|i| MEMORY.get(i))
            .map(|(s, _)| *s)
            .unwrap_or(180);
        let vocabulary: Vec<String> = c::box_text(&self.vocabulary)
            .lines()
            .map(|l| l.trim().to_string())
            .filter(|l| !l.is_empty())
            .collect();
        let replacements = parse_replacements(&c::box_text(&self.replacements));
        let retention = self
            .retention
            .selection()
            .and_then(|i| RETENTION.get(i))
            .map(|(d, _)| *d)
            .unwrap_or(0);
        let history_on = self.skin.is_on(&self.history_on.handle);
        let launch = self.skin.is_on(&self.launch.handle);

        keystore::persist(keystore::GROQ, &self.groq_key.text());
        keystore::persist(keystore::OPENAI, &self.openai_key.text());
        let cloud_text = self.cloud_key.text();
        let cloud_key = cloud::normalize_key(&cloud_text);
        let cloud_typo = cloud_key.is_none() && !cloud_text.trim().is_empty();
        if !cloud_typo {
            keystore::persist(keystore::HLAS_CLOUD, cloud_key.as_deref().unwrap_or(""));
            if let Some(k) = &cloud_key {
                self.cloud_key.set_text(k);
            }
        }
        if let Err(e) = autostart::set(launch) {
            log::error!("autostart change failed: {e}");
        }
        state::update_config(|cfg| {
            cfg.engine = engine;
            cfg.hotkey_vk = hotkey;
            cfg.language = language;
            if !favorites.is_empty() {
                cfg.favorite_languages = favorites;
            }
            cfg.output_mode = output;
            cfg.input_device = device;
            cfg.model_keep_alive_secs = memory;
            cfg.vocabulary = vocabulary;
            cfg.replacements = replacements;
            cfg.history_retention_days = retention;
            cfg.history_enabled = history_on;
            cfg.launch_at_login = launch;
        });
        let (warning, color) = match engine {
            _ if cloud_typo => (
                "Saved, but the Hlas Cloud licence key looks wrong. Paste it again.",
                ds::DANGER,
            ),
            Engine::HlasCloud if !keystore::has_key(keystore::HLAS_CLOUD) => (
                "Saved. Add your licence on the Hlas Cloud page.",
                ds::DANGER,
            ),
            Engine::Groq if !keystore::has_key(keystore::GROQ) => {
                ("Saved. Add a Groq key to use Groq.", ds::DANGER)
            }
            Engine::OpenAI if !keystore::has_key(keystore::OPENAI) => {
                ("Saved. Add an OpenAI key to use OpenAI.", ds::DANGER)
            }
            Engine::Local if !model::present() && !model::status().active => (
                "Saved. Download the model to use the local engine.",
                ds::DANGER,
            ),
            _ => ("Saved.", ds::BRAND),
        };
        self.status.set_color(color);
        self.status.set_text(warning);
        self.load_favorites_only();
    }

    fn load_favorites_only(&self) {
        let cfg = state::config();
        self.favorites.set_text(&cfg.favorite_languages.join(", "));
    }
}
