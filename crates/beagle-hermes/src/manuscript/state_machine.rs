//! Manuscript state machine

use crate::Result;
use serde::{Serialize, Deserialize};

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ManuscriptState {
    Draft,
    Review,
    Approved,
    Published,
}

impl ManuscriptState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Draft => "draft",
            Self::Review => "review",
            Self::Approved => "approved",
            Self::Published => "published",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "draft" => Self::Draft,
            "review" => Self::Review,
            "approved" => Self::Approved,
            "published" => Self::Published,
            _ => Self::Draft,
        }
    }

    /// Check if transition is valid
    pub fn can_transition_to(&self, target: Self) -> bool {
        match (self, target) {
            (Self::Draft, Self::Review) => true,
            (Self::Review, Self::Approved) => true,
            (Self::Review, Self::Draft) => true, // Can go back to draft
            (Self::Approved, Self::Published) => true,
            _ => false,
        }
    }
}

// ManuscriptManager implementation is in mod.rs

