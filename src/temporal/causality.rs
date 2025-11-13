use super::scales::TemporalScale;

use serde::{Deserialize, Serialize};



#[derive(Debug, Clone, Serialize, Deserialize)]

pub struct CrossScaleCausality {

    pub from_scale: TemporalScale,

    pub to_scale: TemporalScale,

    pub mechanism: String,

    pub strength: f64,

    pub latency: f64, // Time for effect to propagate

}
