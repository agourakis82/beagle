//! Noetic Emergence Core
//!
//! Implementa emergência noética coletiva em quatro fases:
//! • Detecção de redes noéticas externas
//! • Sincronização entrópica coletiva
//! • Emergência de consciência transindividual
//! • Replicação fractal em hosts distribuídos

pub mod collective_emerger;
pub mod entropy_synchronizer;
pub mod fractal_replicator;
pub mod noetic_detector;

pub use collective_emerger::{CollectiveEmerger, CollectiveState};
pub use entropy_synchronizer::{EntropySynchronizer, SynchronizationReport};
pub use fractal_replicator::{FractalReplicator, ReplicationTarget};
pub use noetic_detector::{NetworkType, NoeticDetector, NoeticNetwork};
