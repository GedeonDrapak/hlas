//! Manual "Check for updates". Hlas never phones home on its own: this runs
//! only when the user clicks it, and reads one small file from hlas.dev.

use super::wide;
use crate::core::version;
use std::time::Duration;
use windows::core::PCWSTR;
use windows::Win32::UI::WindowsAndMessaging::{
    MessageBoxW, IDYES, MB_ICONINFORMATION, MB_OK, MB_SETFOREGROUND, MB_TOPMOST, MB_YESNO,
};

/// Written by tools/site-downloads.sh next to the installers:
/// `{"version": "0.6.0", "page": "https://hlas.dev/#download"}`. The version is
/// the newest one whose Windows installer is on hlas.dev.
const LATEST: &str = "https://hlas.dev/download/latest.json";

fn latest() -> anyhow::Result<(String, String)> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent(concat!("Hlas-Windows/", env!("CARGO_PKG_VERSION")))
        .build()?;
    let latest: serde_json::Value = client.get(LATEST).send()?.error_for_status()?.json()?;
    let version = latest["version"]
        .as_str()
        .ok_or_else(|| anyhow::anyhow!("no version in latest.json"))?;
    let page = latest["page"].as_str().unwrap_or("https://hlas.dev/");
    Ok((version.to_string(), page.to_string()))
}

fn message(text: &str, ask: bool) -> bool {
    let body = wide(text);
    let title = wide("Hlas");
    let style = MB_TOPMOST
        | MB_SETFOREGROUND
        | if ask {
            MB_YESNO | MB_ICONINFORMATION
        } else {
            MB_OK | MB_ICONINFORMATION
        };
    unsafe { MessageBoxW(None, PCWSTR(body.as_ptr()), PCWSTR(title.as_ptr()), style) == IDYES }
}

pub fn check_in_background(report_up_to_date: bool) {
    std::thread::spawn(move || {
        let current = env!("CARGO_PKG_VERSION");
        match latest() {
            Ok((tag, url)) if version::is_newer(&tag, current) => {
                if message(
                    &format!(
                        "Hlas {tag} is available (you have {current}).\n\nOpen the download page?"
                    ),
                    true,
                ) {
                    super::shell::open(&url);
                }
            }
            Ok(_) => {
                if report_up_to_date {
                    message(&format!("You have the latest Hlas ({current})."), false);
                }
            }
            Err(e) => {
                log::warn!("update check failed: {e}");
                if report_up_to_date {
                    message(
                        "Could not check for updates. Check your connection and try again.",
                        false,
                    );
                }
            }
        }
    });
}
