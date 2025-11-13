//! Temporal Multi-Scale Reasoning

//! 

//! Simultaneous reasoning across 4 temporal scales:

//! - Micro (ms-s): Molecular/quantum

//! - Meso (min-h): Cellular/pharmacokinetic

//! - Macro (days-months): Organismal/clinical

//! - Meta (years): Population/evolutionary



pub mod scales;

pub mod reasoning;

pub mod causality;



pub use scales::{TemporalScale, TimePoint, TimeRange};

pub use reasoning::TemporalReasoner;

pub use causality::CrossScaleCausality;
