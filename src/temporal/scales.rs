use serde::{Deserialize, Serialize};

use std::time::Duration;



#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]

pub enum TemporalScale {

    Micro,   // ms to seconds

    Meso,    // minutes to hours

    Macro,   // days to months

    Meta,    // years to decades

}



impl TemporalScale {

    pub fn typical_duration(&self) -> Duration {

        match self {

            Self::Micro => Duration::from_millis(100),

            Self::Meso => Duration::from_secs(3600),

            Self::Macro => Duration::from_secs(86400 * 30),

            Self::Meta => Duration::from_secs(86400 * 365),

        }

    }

    

    pub fn name(&self) -> &str {

        match self {

            Self::Micro => "Molecular/Quantum",

            Self::Meso => "Cellular/Pharmacokinetic",

            Self::Macro => "Organismal/Clinical",

            Self::Meta => "Population/Evolutionary",

        }

    }

}



#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct TimePoint {

    pub scale: TemporalScale,

    pub value: f64,

    pub unit: String,

}



#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct TimeRange {

    pub scale: TemporalScale,

    pub start: f64,

    pub end: f64,

    pub unit: String,

}
