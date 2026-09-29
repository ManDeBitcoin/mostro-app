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
            if tag_slice.is_empty() {
                continue;
            }
            match tag_slice[0].as_str() {
                "d" => {
                    if tag_slice.len() > 1 {
                        d_tag = Some(tag_slice[1].clone());
                    }
                }
                "expiration" => {
                    if tag_slice.len() > 1 {
                        if let Ok(ts) = tag_slice[1].parse::<u64>() {
                            expiration = Some(Timestamp::from_secs(ts));
                        }
                    }
                }
                "min_version" => {
                    if tag_slice.len() > 1 {
                        min_version = Some(tag_slice[1].clone());
                    }
                }
                "max_version" => {
                    if tag_slice.len() > 1 {
                        max_version = Some(tag_slice[1].clone());
                    }
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
