//! Groq, OpenAI and Hlas Cloud transcription. All speak the OpenAI
//! /audio/transcriptions multipart API; only endpoint, model and key differ.

use crate::core::errors::NetError;
use crate::core::wav;
use anyhow::Result;
use std::time::Duration;

#[derive(Clone, Copy)]
pub enum Provider {
    Groq,
    OpenAI,
    HlasCloud,
}

impl Provider {
    fn name(self) -> &'static str {
        match self {
            Provider::Groq => "Groq",
            Provider::OpenAI => "OpenAI",
            Provider::HlasCloud => "Hlas Cloud",
        }
    }
    fn endpoint(self) -> String {
        match self {
            Provider::Groq => "https://api.groq.com/openai/v1/audio/transcriptions".into(),
            Provider::OpenAI => "https://api.openai.com/v1/audio/transcriptions".into(),
            Provider::HlasCloud => crate::core::cloud::transcription_endpoint(),
        }
    }
    fn model(self) -> &'static str {
        match self {
            Provider::Groq => "whisper-large-v3-turbo",
            Provider::OpenAI => "gpt-transcribe",
            // The server always uses its own model.
            Provider::HlasCloud => "hlas-cloud",
        }
    }
}

/// Maps a transport error to the user-facing kind, like macOS does.
pub fn classify(err: &reqwest::Error, provider: &'static str) -> NetError {
    if err.is_timeout() {
        NetError::TimedOut { provider }
    } else if err.is_connect() {
        NetError::Offline
    } else {
        NetError::Unavailable { provider }
    }
}

pub fn transcribe(
    provider: Provider,
    api_key: &str,
    samples: &[f32],
    language: Option<&str>,
    prompt: Option<&str>,
) -> Result<String> {
    let name = provider.name();
    let audio_secs = samples.len() as f64 / 16_000.0;
    let part = reqwest::blocking::multipart::Part::bytes(wav::encode(samples, 16_000))
        .file_name("audio.wav")
        .mime_str("audio/wav")?;
    let mut form = reqwest::blocking::multipart::Form::new()
        .text("model", provider.model())
        .text("response_format", "json")
        .text("temperature", "0")
        .part("file", part);
    if let Some(lang) = language {
        form = form.text("language", lang.to_string());
    }
    if let Some(prompt) = prompt {
        form = form.text("prompt", prompt.to_string());
    }

    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(15))
        .timeout(Duration::from_secs_f64(
            (audio_secs * 0.3).clamp(30.0, 120.0),
        ))
        .build()?;
    let mut req = client.post(provider.endpoint()).bearer_auth(api_key);
    if matches!(provider, Provider::HlasCloud) {
        req = req.header(crate::core::cloud::DEVICE_HEADER, install_id());
    }
    let resp = req.multipart(form).send().map_err(|e| classify(&e, name))?;
    let status = resp.status();
    if !status.is_success() {
        log::warn!("{name} transcription HTTP {}", status.as_u16());
        return Err(NetError::Http {
            status: status.as_u16(),
            provider: name,
        }
        .into());
    }
    let value: serde_json::Value = resp
        .json()
        .map_err(|_| NetError::InvalidResponse { provider: name })?;
    let text = value
        .get("text")
        .and_then(|t| t.as_str())
        .ok_or(NetError::InvalidResponse { provider: name })?;
    Ok(text.trim().to_string())
}

/// Asks the server about a licence key. Blocking; call it off the UI thread.
pub fn account(key: &str) -> Result<crate::core::cloud::Status> {
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(12))
        .build()?;
    let resp = client
        .get(crate::core::cloud::account_endpoint())
        .bearer_auth(key)
        .header(crate::core::cloud::DEVICE_HEADER, install_id())
        .send()
        .map_err(|e| classify(&e, "Hlas Cloud"))?;
    let status = resp.status().as_u16();
    let body = resp.text().unwrap_or_default();
    crate::core::cloud::parse_account(status, &body).ok_or_else(|| {
        NetError::Http {
            status,
            provider: "Hlas Cloud",
        }
        .into()
    })
}

/// A one-time Stripe customer portal link for this licence, if the server
/// knows the key. Blocking; call it off the UI thread.
pub fn portal_url(key: &str) -> Option<String> {
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(12))
        .build()
        .ok()?;
    let resp = client
        .post(crate::core::cloud::portal_endpoint())
        .bearer_auth(key)
        .send()
        .ok()?;
    if !resp.status().is_success() {
        return None;
    }
    let v: serde_json::Value = resp.json().ok()?;
    v.get("url").and_then(|u| u.as_str()).map(str::to_string)
}

/// Random id of this install, kept in %LOCALAPPDATA%\Hlas\install-id. One free
/// trial per install, and the server's limit of 5 computers per licence.
pub fn install_id() -> String {
    use sha2::{Digest, Sha256};
    let path = crate::core::config::Config::dir().map(|d| d.join("install-id"));
    if let Ok(p) = &path {
        if let Ok(id) = std::fs::read_to_string(p) {
            let id = id.trim().to_string();
            if id.len() >= 16 {
                return id;
            }
        }
    }
    let seed = format!(
        "{:?}{}{:p}",
        std::time::SystemTime::now(),
        std::process::id(),
        &path
    );
    let digest = Sha256::digest(seed.as_bytes());
    let id = format!("win-{}", hex(&digest[..16]));
    if let Ok(p) = &path {
        if let Some(dir) = p.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(p, &id);
    }
    id
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// Starts (or returns the existing) free trial for this install. Ok((key,
/// still running)) or a message for Settings. Blocking; call it off the UI thread.
pub fn start_trial() -> std::result::Result<(String, bool), String> {
    let client = reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(15))
        .build()
        .map_err(|e| e.to_string())?;
    let resp = client
        .post(crate::core::cloud::trial_endpoint())
        .json(&serde_json::json!({ "device": install_id() }))
        .send()
        .map_err(|_| "Could not reach Hlas Cloud. Check your connection.".to_string())?;
    if resp.status().as_u16() == 429 {
        return Err("Too many trials from this network today. Try again tomorrow.".into());
    }
    if !resp.status().is_success() {
        return Err("Hlas Cloud could not start a trial. Try again later.".into());
    }
    let v: serde_json::Value = resp
        .json()
        .map_err(|_| "Hlas Cloud could not start a trial. Try again later.".to_string())?;
    let key = v
        .get("key")
        .and_then(|k| k.as_str())
        .and_then(crate::core::cloud::normalize_key)
        .ok_or_else(|| "Hlas Cloud could not start a trial. Try again later.".to_string())?;
    Ok((
        key,
        v.get("active").and_then(|a| a.as_bool()).unwrap_or(false),
    ))
}
