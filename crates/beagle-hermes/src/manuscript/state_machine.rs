//! Manuscript state machine

use crate::SectionType;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// End-to-end states described in the BPSE specification.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum ManuscriptState {
    Ideation,
    Drafting,
    Review,
    Refining,
    Ready,
    Published,
}

impl ManuscriptState {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Ideation => "ideation",
            Self::Drafting => "drafting",
            Self::Review => "review",
            Self::Refining => "refining",
            Self::Ready => "ready",
            Self::Published => "published",
        }
    }

    pub fn from_str(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "ideation" => Self::Ideation,
            "drafting" => Self::Drafting,
            "review" => Self::Review,
            "refining" => Self::Refining,
            "ready" => Self::Ready,
            "published" => Self::Published,
            _ => Self::Ideation,
        }
    }
}

/// Events that drive the FSM.
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum ManuscriptEvent {
    ThresholdReached,
    SectionCompleted { section: SectionType },
    DraftingComplete,
    ReviewApproved,
    FeedbackRequested,
    RefinementComplete,
    PublishRequested,
}

impl ManuscriptEvent {
    pub fn as_str(&self) -> &'static str {
        match self {
            ManuscriptEvent::ThresholdReached => "threshold_reached",
            ManuscriptEvent::SectionCompleted { .. } => "section_completed",
            ManuscriptEvent::DraftingComplete => "drafting_complete",
            ManuscriptEvent::ReviewApproved => "review_approved",
            ManuscriptEvent::FeedbackRequested => "feedback_requested",
            ManuscriptEvent::RefinementComplete => "refinement_complete",
            ManuscriptEvent::PublishRequested => "publish_requested",
        }
    }
}

/// Manuscript state manager with section progress tracking.
#[derive(Debug, Clone)]
pub struct ManuscriptStateMachine {
    state: ManuscriptState,
    completed_sections: HashSet<SectionType>,
    last_transition: DateTime<Utc>,
}

impl Default for ManuscriptStateMachine {
    fn default() -> Self {
        Self::new()
    }
}

impl ManuscriptStateMachine {
    pub fn new() -> Self {
        Self {
            state: ManuscriptState::Ideation,
            completed_sections: HashSet::new(),
            last_transition: Utc::now(),
        }
    }

    pub fn from_parts(
        state: ManuscriptState,
        completed_sections: HashSet<SectionType>,
        last_transition: DateTime<Utc>,
    ) -> Self {
        Self {
            state,
            completed_sections,
            last_transition,
        }
    }

    pub fn state(&self) -> ManuscriptState {
        self.state
    }

    pub fn last_transition(&self) -> DateTime<Utc> {
        self.last_transition
    }

    pub fn completed_sections(&self) -> usize {
        self.completed_sections.len()
    }

    pub fn completed_section_list(&self) -> Vec<SectionType> {
        self.completed_sections.iter().copied().collect()
    }

    pub fn progress(&self) -> f64 {
        self.completed_sections.len() as f64 / SectionType::all().len() as f64
    }

    pub fn apply(&mut self, event: ManuscriptEvent) -> ManuscriptState {
        match event {
            ManuscriptEvent::ThresholdReached
                if matches!(self.state, ManuscriptState::Ideation) =>
            {
                self.set_state(ManuscriptState::Drafting);
            }
            ManuscriptEvent::SectionCompleted { section } => {
                self.completed_sections.insert(section);
                if self.state == ManuscriptState::Drafting
                    && self.completed_sections.len() == SectionType::all().len()
                {
                    self.set_state(ManuscriptState::Review);
                } else if self.state == ManuscriptState::Refining
                    && self.completed_sections.len() == SectionType::all().len()
                {
                    self.set_state(ManuscriptState::Ready);
                }
            }
            ManuscriptEvent::DraftingComplete if self.state == ManuscriptState::Drafting => {
                self.set_state(ManuscriptState::Review);
            }
            ManuscriptEvent::ReviewApproved if self.state == ManuscriptState::Review => {
                self.set_state(ManuscriptState::Ready);
            }
            ManuscriptEvent::FeedbackRequested
                if matches!(self.state, ManuscriptState::Review | ManuscriptState::Ready) =>
            {
                self.set_state(ManuscriptState::Refining);
            }
            ManuscriptEvent::RefinementComplete if self.state == ManuscriptState::Refining => {
                self.set_state(ManuscriptState::Ready);
            }
            ManuscriptEvent::PublishRequested if self.state == ManuscriptState::Ready => {
                self.set_state(ManuscriptState::Published);
            }
            _ => {}
        }

        self.state
    }

    fn set_state(&mut self, state: ManuscriptState) {
        if self.state != state {
            self.state = state;
            self.last_transition = Utc::now();
        }
    }
}
