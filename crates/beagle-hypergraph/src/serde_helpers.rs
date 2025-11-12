//! Utilitários especializados de serialização/ desserialização usados para
//! compactar representações JSON garantindo compatibilidade semântica.
use crate::types::Embedding;
use chrono::{DateTime, Utc};
use serde::de::{Deserializer, Error as DeError};
use serde::ser::{SerializeSeq, Serializer};
use serde::Deserialize;
use uuid::Uuid;

/// Serializa um [`DateTime<Utc>`] como string ISO 8601 compacta.
pub fn serialize_datetime<S>(date: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    serializer.serialize_str(&date.to_rfc3339())
}

/// Desserializa um [`DateTime<Utc>`] a partir de string ISO 8601.
pub fn deserialize_datetime<'de, D>(deserializer: D) -> Result<DateTime<Utc>, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    DateTime::parse_from_rfc3339(&s)
        .map(|dt| dt.with_timezone(&Utc))
        .map_err(D::Error::custom)
}

/// Serializa [`Option<DateTime<Utc>>`], omitindo o campo quando `None`.
pub fn serialize_optional_datetime<S>(
    date: &Option<DateTime<Utc>>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match date {
        Some(dt) => serializer.serialize_some(&dt.to_rfc3339()),
        None => serializer.serialize_none(),
    }
}

/// Desserializa [`Option<DateTime<Utc>>`] a partir de string ISO 8601.
pub fn deserialize_optional_datetime<'de, D>(
    deserializer: D,
) -> Result<Option<DateTime<Utc>>, D::Error>
where
    D: Deserializer<'de>,
{
    Option::<String>::deserialize(deserializer)?.map_or(Ok(None), |value| {
        DateTime::parse_from_rfc3339(&value)
            .map(|dt| dt.with_timezone(&Utc))
            .map(Some)
            .map_err(D::Error::custom)
    })
}

/// Serializa [`Vec<Uuid>`] como strings hex compactas (sem hífens).
pub fn serialize_uuid_vec<S>(uuids: &[Uuid], serializer: S) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    let mut seq = serializer.serialize_seq(Some(uuids.len()))?;
    for uuid in uuids {
        seq.serialize_element(&uuid.as_simple().to_string())?;
    }
    seq.end()
}

/// Desserializa [`Vec<Uuid>`] a partir de strings hex compactas.
pub fn deserialize_uuid_vec<'de, D>(deserializer: D) -> Result<Vec<Uuid>, D::Error>
where
    D: Deserializer<'de>,
{
    let strings: Vec<String> = Vec::deserialize(deserializer)?;
    strings
        .into_iter()
        .map(|s| Uuid::parse_str(&s).map_err(D::Error::custom))
        .collect()
}

/// Serializa [`Option<Embedding>`] mantendo representação compacta.
pub fn serialize_optional_embedding<S>(
    embedding: &Option<Embedding>,
    serializer: S,
) -> Result<S::Ok, S::Error>
where
    S: Serializer,
{
    match embedding {
        Some(vec) => serializer.serialize_some(vec),
        None => serializer.serialize_none(),
    }
}
