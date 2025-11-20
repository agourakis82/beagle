//! Sistema de broadcast para observações
//!
//! Permite múltiplos subscribers receberem as mesmas observações

use super::Observation;
use tokio::sync::mpsc;
use std::sync::Arc;
use tokio::sync::Mutex;

pub struct ObservationBroadcast {
    subscribers: Arc<Mutex<Vec<mpsc::UnboundedSender<Observation>>>>,
}

impl ObservationBroadcast {
    pub fn new() -> Self {
        Self {
            subscribers: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub async fn subscribe(&self) -> mpsc::UnboundedReceiver<Observation> {
        let (tx, rx) = mpsc::unbounded_channel();
        let mut subs = self.subscribers.lock().await;
        subs.push(tx);
        rx
    }

    pub async fn broadcast(&self, obs: Observation) {
        let mut subs = self.subscribers.lock().await;
        subs.retain(|sub| {
            sub.send(obs.clone()).is_ok()
        });
    }
}

impl Clone for ObservationBroadcast {
    fn clone(&self) -> Self {
        Self {
            subscribers: self.subscribers.clone(),
        }
    }
}

