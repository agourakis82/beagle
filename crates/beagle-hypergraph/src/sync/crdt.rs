//! Estruturas livres de conflitos para sincronização eventual do hipergrafo.
//!
//! Implementa um conjunto *Last-Writer-Wins* (LWW) e um relógio vetorial
//! minimalista, permitindo reconstrução determinística de estados replicados
//! após edições concorrentes entre dispositivos.

#![allow(dead_code)]

use chrono::{DateTime, Utc};
use std::cmp::Ordering;
use std::collections::{HashMap, HashSet};
use std::hash::Hash;

/// Timestamp lógico adotado pelas réplicas.
pub type Timestamp = DateTime<Utc>;

/// Enumeração que descreve a relação causal entre dois relógios vetoriais.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ClockComparison {
    /// Ambos os estados são idênticos.
    Equal,
    /// O primeiro relógio ocorreu antes do segundo (é dominado).
    HappensBefore,
    /// O primeiro relógio ocorreu depois do segundo (domina).
    HappensAfter,
    /// As operações são concorrentes, não havendo relação causal direta.
    Concurrent,
}

/// Relógio vetorial genérico utilizado para rastrear causalidade entre
/// dispositivos ou réplicas lógicas.
#[derive(Debug, Clone)]
pub struct VectorClock<ID>
where
    ID: Eq + Hash,
{
    entries: HashMap<ID, u64>,
}

impl<ID> PartialEq for VectorClock<ID>
where
    ID: Eq + Hash,
{
    fn eq(&self, other: &Self) -> bool {
        self.entries == other.entries
    }
}

impl<ID> Eq for VectorClock<ID> where ID: Eq + Hash {}

impl<ID> Default for VectorClock<ID>
where
    ID: Eq + Hash,
{
    fn default() -> Self {
        Self {
            entries: HashMap::new(),
        }
    }
}

impl<ID> VectorClock<ID>
where
    ID: Eq + Hash + Clone,
{
    /// Cria um relógio vetorial vazio.
    pub fn new() -> Self {
        Self::default()
    }

    /// Retorna o contador associado a um identificador de réplica, se existir.
    pub fn get(&self, replica_id: &ID) -> Option<u64> {
        self.entries.get(replica_id).copied()
    }

    /// Iterador imutável sobre os pares `(<replica>, <contador>)`.
    pub fn iter(&self) -> impl Iterator<Item = (&ID, &u64)> {
        self.entries.iter()
    }

    /// Incrementa o contador da réplica informada, retornando o novo valor.
    pub fn increment(&mut self, replica_id: ID) -> u64 {
        let counter = self.entries.entry(replica_id).or_insert(0);
        *counter += 1;
        *counter
    }

    /// Integra outro relógio vetorial tomando o máximo componente a componente.
    pub fn merge(&mut self, other: &Self) {
        for (replica, counter) in &other.entries {
            self.entries
                .entry(replica.clone())
                .and_modify(|current| {
                    if *current < *counter {
                        *current = *counter;
                    }
                })
                .or_insert(*counter);
        }
    }

    /// Compara dois relógios vetoriais para determinar a relação causal.
    pub fn compare(&self, other: &Self) -> ClockComparison {
        let mut self_greater = false;
        let mut other_greater = false;

        for replica in self
            .entries
            .keys()
            .chain(other.entries.keys())
            .collect::<HashSet<_>>()
        {
            let a = self.entries.get(replica).copied().unwrap_or(0);
            let b = other.entries.get(replica).copied().unwrap_or(0);

            match a.cmp(&b) {
                Ordering::Greater => self_greater = true,
                Ordering::Less => other_greater = true,
                Ordering::Equal => {}
            }

            if self_greater && other_greater {
                return ClockComparison::Concurrent;
            }
        }

        match (self_greater, other_greater) {
            (false, false) => ClockComparison::Equal,
            (true, false) => ClockComparison::HappensAfter,
            (false, true) => ClockComparison::HappensBefore,
            (true, true) => ClockComparison::Concurrent,
        }
    }
}

/// Conjunto *Last-Writer-Wins* que mantém a operação determinística frente a
/// edições concorrentes.
#[derive(Debug, Clone)]
pub struct LWWElementSet<T>
where
    T: Eq + Hash,
{
    adds: HashMap<T, Timestamp>,
    removes: HashMap<T, Timestamp>,
}

impl<T> PartialEq for LWWElementSet<T>
where
    T: Eq + Hash,
{
    fn eq(&self, other: &Self) -> bool {
        self.adds == other.adds && self.removes == other.removes
    }
}

impl<T> Eq for LWWElementSet<T> where T: Eq + Hash {}

impl<T> Default for LWWElementSet<T>
where
    T: Eq + Hash,
{
    fn default() -> Self {
        Self {
            adds: HashMap::new(),
            removes: HashMap::new(),
        }
    }
}

impl<T> LWWElementSet<T>
where
    T: Eq + Hash + Clone,
{
    /// Cria um LWW-Set vazio.
    pub fn new() -> Self {
        Self::default()
    }

    /// Constrói um LWW-Set com capacidade inicial informada.
    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            adds: HashMap::with_capacity(capacity),
            removes: HashMap::with_capacity(capacity),
        }
    }

    /// Registra uma operação de inserção com o timestamp associado.
    ///
    /// Apenas timestamps mais recentes que o previamente registrado são
    /// considerados válidos.
    pub fn add(&mut self, element: T, timestamp: Timestamp) {
        use std::collections::hash_map::Entry;

        match self.adds.entry(element) {
            Entry::Occupied(mut entry) => {
                if timestamp > *entry.get() {
                    entry.insert(timestamp);
                }
            }
            Entry::Vacant(entry) => {
                entry.insert(timestamp);
            }
        }
    }

    /// Registra uma operação de remoção com o timestamp associado.
    ///
    /// Remoções apenas prevalecem se forem mais recentes que o valor conhecido.
    pub fn remove(&mut self, element: T, timestamp: Timestamp) {
        use std::collections::hash_map::Entry;

        match self.removes.entry(element) {
            Entry::Occupied(mut entry) => {
                if timestamp > *entry.get() {
                    entry.insert(timestamp);
                }
            }
            Entry::Vacant(entry) => {
                entry.insert(timestamp);
            }
        }
    }

    /// Verifica se o elemento pertence ao conjunto considerando o último evento.
    pub fn contains(&self, element: &T) -> bool {
        let add_time = self.adds.get(element);
        let remove_time = self.removes.get(element);

        match (add_time, remove_time) {
            (Some(a), Some(r)) => a > r,
            (Some(_), None) => true,
            _ => false,
        }
    }

    /// Número de elementos efetivamente presentes (opera em tempo linear).
    pub fn len(&self) -> usize {
        self.elements().count()
    }

    /// Retorna `true` quando não há elementos presentes.
    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Iterador sobre os elementos atualmente presentes no conjunto.
    pub fn elements(&self) -> impl Iterator<Item = &T> {
        self.adds.iter().filter_map(|(element, add_ts)| {
            let remove_ts = self.removes.get(element);
            if remove_ts.map_or(true, |ts| add_ts > ts) {
                Some(element)
            } else {
                None
            }
        })
    }

    /// Integra outra réplica tomando o máximo de cada timestamp.
    pub fn merge(&mut self, other: &Self) {
        for (elem, ts) in &other.adds {
            self.adds
                .entry(elem.clone())
                .and_modify(|current| {
                    if *current < *ts {
                        *current = *ts;
                    }
                })
                .or_insert(*ts);
        }

        for (elem, ts) in &other.removes {
            self.removes
                .entry(elem.clone())
                .and_modify(|current| {
                    if *current < *ts {
                        *current = *ts;
                    }
                })
                .or_insert(*ts);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ClockComparison, LWWElementSet, Timestamp, VectorClock};
    use chrono::{TimeZone, Utc};

    fn ts(seconds: i64) -> Timestamp {
        Utc.timestamp_opt(seconds, 0).unwrap()
    }

    #[test]
    fn lww_add_and_remove_bias_to_latest() {
        let mut set = LWWElementSet::new();
        let element = "node-1".to_string();
        set.add(element.clone(), ts(10));
        assert!(set.contains(&element));

        set.remove(element.clone(), ts(12));
        assert!(!set.contains(&element));

        // Reinserção com timestamp mais novo deve prevalecer.
        set.add(element.clone(), ts(15));
        assert!(set.contains(&element));

        // Remoção com timestamp antigo não deve vencer.
        set.remove(element.clone(), ts(14));
        assert!(set.contains(&element));
    }

    #[test]
    fn lww_merge_is_commutative_and_idempotent() {
        let mut replica_a = LWWElementSet::new();
        let mut replica_b = LWWElementSet::new();

        let alpha = "alpha".to_string();
        let beta = "beta".to_string();

        replica_a.add(alpha.clone(), ts(5));
        replica_b.add(beta.clone(), ts(6));
        replica_b.remove(alpha.clone(), ts(7));

        let mut merged_ab = replica_a.clone();
        merged_ab.merge(&replica_b);

        let mut merged_ba = replica_b.clone();
        merged_ba.merge(&replica_a);

        assert_eq!(merged_ab, merged_ba);
        assert!(merged_ab.contains(&beta));
        assert!(!merged_ab.contains(&alpha));

        // Idempotência.
        let mut merged_twice = merged_ab.clone();
        merged_twice.merge(&merged_ab);
        assert_eq!(merged_twice, merged_ab);
    }

    #[test]
    fn vector_clock_detects_causality_and_concurrency() {
        let mut vc1 = VectorClock::new();
        let mut vc2 = VectorClock::new();

        vc1.increment("device-a");
        vc1.increment("device-a");
        vc2.merge(&vc1);

        vc2.increment("device-b");

        assert_eq!(vc1.compare(&vc2), ClockComparison::HappensBefore);
        assert_eq!(vc2.compare(&vc1), ClockComparison::HappensAfter);

        vc1.increment("device-a");
        vc1.increment("device-b");

        assert_eq!(vc1.compare(&vc2), ClockComparison::Concurrent);
    }

    #[test]
    fn eventual_consistency_after_concurrent_edits() {
        let mut replica_a = LWWElementSet::new();
        let mut replica_b = LWWElementSet::new();

        let shared = "shared".to_string();
        let unique_b = "unique-b".to_string();

        replica_a.add(shared.clone(), ts(20));
        replica_b.remove(shared.clone(), ts(21));
        replica_b.add(unique_b.clone(), ts(22));

        let mut merged_a = replica_a.clone();
        merged_a.merge(&replica_b);

        let mut merged_b = replica_b.clone();
        merged_b.merge(&replica_a);

        assert_eq!(merged_a, merged_b);
        assert!(!merged_a.contains(&shared));
        assert!(merged_a.contains(&unique_b));
    }
}
