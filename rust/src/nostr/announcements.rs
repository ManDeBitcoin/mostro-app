use nostr_sdk::prelude::*;
use serde::{Deserialize, Serialize};

pub const ALLOWLIST_NPUBS: &[&str] = &[];

pub fn allowed_keys() -> Vec<PublicKey> {
    ALLOWLIST_NPUBS
        .iter()
        .filter_map(|npub| match PublicKey::parse(npub) {
            Ok(key) => Some(key),
            Err(e) => {
                log::warn!("Invalid npub in allowlist: {} - {}", npub, e);
                None
            }
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Info,
    Warning,
    Critical,
    #[serde(other)]
    Unknown,
}

impl Severity {
    pub fn normalized(&self) -> Self {
        match self {
            Self::Unknown => Self::Warning,
            other => other.clone(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct LocalizedText {
    pub title: String,
    pub body: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AnnouncementLocales {
    pub en: LocalizedText,
    pub es: LocalizedText,
    pub fr: LocalizedText,
    pub de: LocalizedText,
    pub it: LocalizedText,
    pub nl: LocalizedText,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AnnouncementContent {
    pub v: u32,
    pub severity: Severity,
    pub locales: AnnouncementLocales,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedAnnouncement {
    pub id: String, // from d tag
    pub event_id: EventId,
    pub pubkey: PublicKey,
    pub created_at: Timestamp,
    pub expiration: Timestamp,
    pub content: AnnouncementContent,
    pub min_version: Option<String>,
    pub max_version: Option<String>,
}

impl ParsedAnnouncement {
    pub fn parse(event: &Event) -> Result<Self, anyhow::Error> {
        if event.kind != Kind::from(38387u16) {
            anyhow::bail!("Invalid kind");
        }

        let mut d_tag = None;
        let mut expiration = None;
        let mut min_version = None;
        let mut max_version = None;

        for tag in event.tags.iter() {
            let tag_slice = tag.as_slice();
            if tag_slice.len() < 2 {
                continue;
            }
            match tag_slice[0].as_str() {
                "d" => {
                    d_tag = Some(tag_slice[1].clone());
                }
                "expiration" => {
                    if let Ok(ts) = tag_slice[1].parse::<u64>() {
                        expiration = Some(Timestamp::from_secs(ts));
                    }
                }
                "min_version" => {
                    min_version = Some(tag_slice[1].clone());
                }
                "max_version" => {
                    max_version = Some(tag_slice[1].clone());
                }
                _ => {}
            }
        }

        let d_tag = d_tag.ok_or_else(|| anyhow::anyhow!("Missing d tag"))?;
        let expiration = expiration.ok_or_else(|| anyhow::anyhow!("Missing expiration tag"))?;

        let content: AnnouncementContent = serde_json::from_str(&event.content)
            .map_err(|e| anyhow::anyhow!("Failed to parse content: {}", e))?;

        if content.v != 1 {
            anyhow::bail!("Unknown version: {}", content.v);
        }

        if let Some(url) = &content.url {
            if !url.starts_with("https://") {
                anyhow::bail!("URL must be https");
            }
        }

        // Validate lengths
        let validate_len = |text: &LocalizedText| -> bool {
            text.title.trim().chars().count() <= 80 && text.body.trim().chars().count() <= 500
        };

        if !validate_len(&content.locales.en)
            || !validate_len(&content.locales.es)
            || !validate_len(&content.locales.fr)
            || !validate_len(&content.locales.de)
            || !validate_len(&content.locales.it)
            || !validate_len(&content.locales.nl)
        {
            anyhow::bail!("Text exceeds length limits");
        }

        if let Some(min) = &min_version {
            parse_bound(min)?;
        }
        if let Some(max) = &max_version {
            parse_bound(max)?;
        }

        Ok(Self {
            id: d_tag,
            event_id: event.id,
            pubkey: event.pubkey,
            created_at: event.created_at,
            expiration,
            content,
            min_version,
            max_version,
        })
    }

    pub fn address(&self) -> String {
        format!("38387:{}:{}", self.pubkey, self.id)
    }

    pub fn is_applicable_to_version(&self, app_version: &str) -> Result<bool, anyhow::Error> {
        let current = semver::Version::parse(app_version)?;
        if let Some(min) = &self.min_version {
            let min_v = parse_bound(min)?;
            if current < min_v {
                return Ok(false);
            }
        }
        if let Some(max) = &self.max_version {
            let max_v = parse_bound(max)?;
            if current >= max_v {
                return Ok(false);
            }
        }
        Ok(true)
    }
}

fn parse_bound(bound: &str) -> Result<semver::Version, anyhow::Error> {
    if bound.contains('+') {
        anyhow::bail!("Build metadata is not allowed in bounds");
    }
    // Handle partial versions like "2" or "2.1"
    let parts: Vec<&str> = bound.split('.').collect();
    let normalized = match parts.len() {
        1 => format!("{}.0.0", parts[0]),
        2 => format!("{}.{}.0", parts[0], parts[1]),
        _ => bound.to_string(),
    };
    Ok(semver::Version::parse(&normalized)?)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_json(title: &str, body: &str, url: Option<&str>) -> String {
        let url_field = match url {
            Some(u) => format!(r#","url":"{}""#, u),
            None => String::new(),
        };
        format!(
            r#"{{"v":1,"severity":"info","locales":{{"en":{{"title":"{}","body":"{}"}},"es":{{"title":"{}","body":"{}"}},"fr":{{"title":"{}","body":"{}"}},"de":{{"title":"{}","body":"{}"}},"it":{{"title":"{}","body":"{}"}},"nl":{{"title":"{}","body":"{}"}}}}{}}}"#,
            title, body, title, body, title, body, title, body, title, body, title, body, url_field
        )
    }

    fn make_test_event(kind: u16, tags: Vec<Tag>, content: String) -> Event {
        let keys = Keys::generate();
        EventBuilder::new(Kind::from(kind), content)
            .tags(tags)
            .finalize(&keys)
            .expect("event builder")
    }

    #[test]
    fn parse_valid_announcement() {
        let tags = vec![
            Tag::parse(["d", "notice-1"]).unwrap(),
            Tag::parse(["expiration", "1893456000"]).unwrap(),
            Tag::parse(["min_version", "2.0"]).unwrap(),
            Tag::parse(["max_version", "2.2.0"]).unwrap(),
        ];
        let content = sample_json(
            "Scheduled Maintenance",
            "The node will be down for 1 hour.",
            Some("https://mostro.network"),
        );
        let event = make_test_event(38387, tags, content);

        let parsed = ParsedAnnouncement::parse(&event).expect("should parse");
        assert_eq!(parsed.id, "notice-1");
        assert_eq!(parsed.content.v, 1);
        assert_eq!(parsed.content.severity, Severity::Info);
        assert_eq!(parsed.min_version.as_deref(), Some("2.0"));
        assert_eq!(parsed.max_version.as_deref(), Some("2.2.0"));
        assert_eq!(
            parsed.content.url.as_deref(),
            Some("https://mostro.network")
        );
        assert!(parsed.is_applicable_to_version("2.0.5").unwrap());
        assert!(!parsed.is_applicable_to_version("1.9.9").unwrap());
        assert!(!parsed.is_applicable_to_version("2.2.0").unwrap());
    }

    #[test]
    fn parse_rejects_invalid_kind() {
        let tags = vec![
            Tag::parse(["d", "notice-1"]).unwrap(),
            Tag::parse(["expiration", "1893456000"]).unwrap(),
        ];
        let event = make_test_event(1, tags, sample_json("Title", "Body", None));
        assert!(ParsedAnnouncement::parse(&event).is_err());
    }

    #[test]
    fn parse_rejects_missing_d_tag() {
        let tags = vec![Tag::parse(["expiration", "1893456000"]).unwrap()];
        let event = make_test_event(38387, tags, sample_json("Title", "Body", None));
        assert!(ParsedAnnouncement::parse(&event).is_err());
    }

    #[test]
    fn parse_rejects_non_https_url() {
        let tags = vec![
            Tag::parse(["d", "notice-1"]).unwrap(),
            Tag::parse(["expiration", "1893456000"]).unwrap(),
        ];
        let event = make_test_event(
            38387,
            tags,
            sample_json("Title", "Body", Some("http://insecure.com")),
        );
        assert!(ParsedAnnouncement::parse(&event).is_err());
    }

    #[test]
    fn parse_rejects_oversized_title_or_body() {
        let long_title = "a".repeat(81);
        let tags = vec![
            Tag::parse(["d", "notice-1"]).unwrap(),
            Tag::parse(["expiration", "1893456000"]).unwrap(),
        ];
        let event = make_test_event(38387, tags.clone(), sample_json(&long_title, "Body", None));
        assert!(ParsedAnnouncement::parse(&event).is_err());

        let long_body = "b".repeat(501);
        let event2 = make_test_event(38387, tags, sample_json("Title", &long_body, None));
        assert!(ParsedAnnouncement::parse(&event2).is_err());
    }

    #[test]
    fn severity_normalization() {
        assert_eq!(Severity::Unknown.normalized(), Severity::Warning);
        assert_eq!(Severity::Info.normalized(), Severity::Info);
        assert_eq!(Severity::Critical.normalized(), Severity::Critical);
    }

    #[test]
    fn bound_rejects_build_metadata() {
        assert!(parse_bound("2.0.0+build1").is_err());
        assert!(parse_bound("2.0.0").is_ok());
        assert!(parse_bound("2").is_ok());
        assert!(parse_bound("2.1").is_ok());
    }
}
