//! Hlas Cloud: the paid engine. The app sends audio with a licence key as
//! bearer token to our server, which checks the Stripe subscription and
//! forwards to Groq. Same protocol and key format as Hlas for macOS.

/// Base URL of the Hlas Cloud server.
pub const BASE_URL: &str = "https://api.hlas.dev";
/// Stripe checkout for the yearly subscription.
pub const BUY_URL: &str = "https://buy.stripe.com/5kQ8wIdAe58W1YB1zI3Je00";
/// Stripe customer portal sign-in, used when the key is missing or unknown.
pub const PORTAL_LOGIN_URL: &str = "https://billing.stripe.com/p/login/5kQ8wIdAe58W1YB1zI3Je00";

pub fn transcription_endpoint() -> String {
    format!("{BASE_URL}/v1/audio/transcriptions")
}
pub fn chat_endpoint() -> String {
    format!("{BASE_URL}/v1/chat/completions")
}
pub fn account_endpoint() -> String {
    format!("{BASE_URL}/v1/account")
}
pub fn portal_endpoint() -> String {
    format!("{BASE_URL}/v1/portal")
}
pub fn trial_endpoint() -> String {
    format!("{BASE_URL}/v1/trial")
}

/// Header with the install id on every Hlas Cloud request (trial, 5-computer limit).
pub const DEVICE_HEADER: &str = "X-Hlas-Device";

/// Canonical key form `hlas_XXXXX-XXXXX-XXXXX-XXXXX-XXXXX` (Crockford base32).
/// Accepts pasted keys with spaces, lower case or a missing prefix, exactly like
/// the server's normalizeLicenseKey. None when it cannot be a key.
pub fn normalize_key(input: &str) -> Option<String> {
    let raw = input.trim();
    let body = raw
        .strip_prefix("hlas_")
        .or_else(|| raw.strip_prefix("HLAS_"))
        .unwrap_or(raw);
    let chars: String = body
        .chars()
        .filter(|c| c.is_ascii_alphanumeric())
        .map(|c| c.to_ascii_uppercase())
        .collect();
    if chars.len() != 25 {
        return None;
    }
    let groups: Vec<&str> = (0..5).map(|i| &chars[i * 5..i * 5 + 5]).collect();
    Some(format!("hlas_{}", groups.join("-")))
}

/// The key inside an activation link `hlas://activate?key=...`, as opened by
/// the welcome page after payment.
pub fn key_from_activation_url(url: &str) -> Option<String> {
    let rest = url.trim().strip_prefix("hlas://")?;
    let (path, query) = rest.split_once('?')?;
    if path.trim_end_matches('/') != "activate" {
        return None;
    }
    query
        .split('&')
        .filter_map(|pair| pair.split_once('='))
        .find(|(k, _)| *k == "key")
        .and_then(|(_, v)| normalize_key(&percent_decode(v)))
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(if bytes[i] == b'+' { b' ' } else { bytes[i] });
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// What the server says about a licence key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Status {
    /// Subscription active until `period_end` (Unix seconds), if known.
    Active {
        email: Option<String>,
        period_end: Option<i64>,
    },
    /// Known key, but the subscription is not active (cancelled, unpaid).
    Inactive { email: Option<String> },
    /// Free trial running until `ends` (Unix seconds).
    Trial { ends: Option<i64> },
    /// Free trial is over.
    TrialEnded,
    /// The server does not know this key.
    Unknown,
}

/// Parses `GET /v1/account`: 200 with `{email, active, period_end}`, 401 for an unknown key.
pub fn parse_account(http_status: u16, body: &str) -> Option<Status> {
    if http_status == 401 {
        return Some(Status::Unknown);
    }
    if http_status != 200 {
        return None;
    }
    let v: serde_json::Value = serde_json::from_str(body).ok()?;
    let email = v.get("email").and_then(|e| e.as_str()).map(str::to_string);
    let active = v.get("active").and_then(|a| a.as_bool()).unwrap_or(false);
    if v.get("trial").and_then(|t| t.as_bool()).unwrap_or(false) {
        return Some(if active {
            Status::Trial {
                ends: v.get("period_end").and_then(|p| p.as_i64()),
            }
        } else {
            Status::TrialEnded
        });
    }
    if v.get("active").and_then(|a| a.as_bool()).unwrap_or(false) {
        Some(Status::Active {
            email,
            period_end: v.get("period_end").and_then(|p| p.as_i64()),
        })
    } else {
        Some(Status::Inactive { email })
    }
}

/// One line for Settings.
pub fn describe(status: &Status) -> String {
    match status {
        Status::Active { email, period_end } => {
            let until = period_end
                .and_then(|p| chrono::DateTime::from_timestamp(p, 0))
                .map(|d| format!(" until {}", d.format("%-d %b %Y")))
                .unwrap_or_default();
            match email {
                Some(e) => format!("Active{until}. {e}"),
                None => format!("Active{until}."),
            }
        }
        Status::Inactive { .. } => "Subscription not active. Renew it to keep dictating.".into(),
        Status::Trial { ends } => {
            let until = ends
                .and_then(|p| chrono::DateTime::from_timestamp(p, 0))
                .map(|d| format!(" until {}", d.format("%-d %b %Y")))
                .unwrap_or_default();
            format!("Active: free trial{until}, 30 minutes a day.")
        }
        Status::TrialEnded => "Your free trial has ended. Get Hlas Cloud to keep dictating.".into(),
        Status::Unknown => "This licence key was not recognised.".into(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_pasted_keys() {
        let want = "hlas_ABCDE-FGH12-34567-89ABC-DEFGH";
        assert_eq!(
            normalize_key("hlas_ABCDE-FGH12-34567-89ABC-DEFGH").as_deref(),
            Some(want)
        );
        assert_eq!(
            normalize_key("  abcde fgh12 34567 89abc defgh ").as_deref(),
            Some(want)
        );
        assert_eq!(normalize_key("hlas_short"), None);
        assert_eq!(normalize_key(""), None);
    }

    #[test]
    fn reads_activation_links() {
        let want = Some("hlas_ABCDE-FGH12-34567-89ABC-DEFGH".to_string());
        assert_eq!(
            key_from_activation_url("hlas://activate?key=hlas_ABCDE-FGH12-34567-89ABC-DEFGH"),
            want
        );
        assert_eq!(
            key_from_activation_url(
                "hlas://activate/?src=web&key=hlas%5FABCDE-FGH12-34567-89ABC-DEFGH"
            ),
            want
        );
        assert_eq!(
            key_from_activation_url("hlas://other?key=hlas_ABCDE-FGH12-34567-89ABC-DEFGH"),
            None
        );
        assert_eq!(key_from_activation_url("https://example.com"), None);
    }

    #[test]
    fn parses_account_status() {
        assert_eq!(parse_account(401, ""), Some(Status::Unknown));
        assert_eq!(parse_account(500, ""), None);
        assert_eq!(
            parse_account(
                200,
                r#"{"email":"a@b.cz","active":true,"period_end":1800000000}"#
            ),
            Some(Status::Active {
                email: Some("a@b.cz".into()),
                period_end: Some(1800000000)
            })
        );
        assert_eq!(
            parse_account(200, r#"{"email":null,"active":false,"period_end":null}"#),
            Some(Status::Inactive { email: None })
        );
        assert!(describe(&Status::Active {
            email: None,
            period_end: Some(1800000000)
        })
        .starts_with("Active until 15 Jan 2027"));
        assert_eq!(
            parse_account(
                200,
                r#"{"email":null,"active":true,"period_end":1800000000,"trial":true}"#
            ),
            Some(Status::Trial {
                ends: Some(1800000000)
            })
        );
        assert_eq!(
            parse_account(
                200,
                r#"{"email":null,"active":false,"period_end":1,"trial":true}"#
            ),
            Some(Status::TrialEnded)
        );
    }
}
