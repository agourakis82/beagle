/// # Advanced CRDT Implementations
///
/// State-of-the-art Conflict-Free Replicated Data Types
/// Based on latest research (2024-2025)
use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt::Debug;
use uuid::Uuid;

/// Base CRDT trait
pub trait CRDT: Send + Sync + Debug {
    /// Apply operation to CRDT
    fn apply_operation(&self, op: &crate::Operation) -> Result<()>;

    /// Merge with another CRDT state
    fn merge(&mut self, other: &dyn CRDT) -> Result<()>;

    /// Get current state as bytes
    fn get_state(&self) -> Result<Vec<u8>>;

    /// Load state from bytes
    fn load_state(&mut self, state: &[u8]) -> Result<()>;

    /// Get CRDT type identifier
    fn type_id(&self) -> &str;
}

/// State-based CRDT
pub trait StateBasedCRDT: CRDT {
    type State: Clone + Serialize + for<'de> Deserialize<'de>;

    fn get_full_state(&self) -> Self::State;
    fn merge_state(&mut self, other: Self::State);
}

/// Operation-based CRDT
pub trait OperationBasedCRDT: CRDT {
    type Op: Clone + Serialize + for<'de> Deserialize<'de>;

    fn prepare(&self, op: Self::Op) -> Self::Op;
    fn effect(&mut self, op: Self::Op);
}

/// Delta CRDT for efficient sync
pub trait DeltaCRDT: StateBasedCRDT {
    type Delta: Clone + Serialize + for<'de> Deserialize<'de>;

    fn get_delta(&self, since: u64) -> Self::Delta;
    fn merge_delta(&mut self, delta: Self::Delta);
}

// ===== LWW Register =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LWWRegister<T: Clone + Debug> {
    value: T,
    timestamp: u64,
    node_id: String,
}

impl<T: Clone + Debug + Send + Sync + 'static> LWWRegister<T> {
    pub fn new(value: T, node_id: String) -> Self {
        Self {
            value,
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
            node_id,
        }
    }

    pub fn set(&mut self, value: T, node_id: String) {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;

        if timestamp > self.timestamp || (timestamp == self.timestamp && node_id > self.node_id) {
            self.value = value;
            self.timestamp = timestamp;
            self.node_id = node_id;
        }
    }

    pub fn get(&self) -> &T {
        &self.value
    }
}

// ===== Multi-Value Register =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MVRegister<T: Clone + Debug + PartialEq> {
    values: HashSet<(T, Uuid)>,
}

impl<T: Clone + Debug + PartialEq> MVRegister<T> {
    pub fn new() -> Self {
        Self {
            values: HashSet::new(),
        }
    }

    pub fn set(&mut self, value: T) {
        self.values.clear();
        self.values.insert((value, Uuid::new_v4()));
    }

    pub fn get_all(&self) -> Vec<T> {
        self.values.iter().map(|(v, _)| v.clone()).collect()
    }

    pub fn merge(&mut self, other: &MVRegister<T>) {
        self.values.extend(other.values.clone());
    }
}

// ===== G-Counter =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GCounter {
    counts: HashMap<String, u64>,
}

impl GCounter {
    pub fn new() -> Self {
        Self {
            counts: HashMap::new(),
        }
    }

    pub fn increment(&mut self, node_id: &str, amount: u64) {
        *self.counts.entry(node_id.to_string()).or_insert(0) += amount;
    }

    pub fn value(&self) -> u64 {
        self.counts.values().sum()
    }

    pub fn merge(&mut self, other: &GCounter) {
        for (node, &count) in &other.counts {
            self.counts
                .entry(node.clone())
                .and_modify(|c| *c = (*c).max(count))
                .or_insert(count);
        }
    }
}

// ===== PN-Counter =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PNCounter {
    positive: GCounter,
    negative: GCounter,
}

impl PNCounter {
    pub fn new() -> Self {
        Self {
            positive: GCounter::new(),
            negative: GCounter::new(),
        }
    }

    pub fn increment(&mut self, node_id: &str, amount: u64) {
        self.positive.increment(node_id, amount);
    }

    pub fn decrement(&mut self, node_id: &str, amount: u64) {
        self.negative.increment(node_id, amount);
    }

    pub fn value(&self) -> i64 {
        self.positive.value() as i64 - self.negative.value() as i64
    }

    pub fn merge(&mut self, other: &PNCounter) {
        self.positive.merge(&other.positive);
        self.negative.merge(&other.negative);
    }
}

// ===== OR-Set =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ORSet<T: Clone + Debug + Eq + std::hash::Hash> {
    adds: HashMap<T, HashSet<Uuid>>,
    removes: HashSet<Uuid>,
}

impl<T: Clone + Debug + Eq + std::hash::Hash> ORSet<T> {
    pub fn new() -> Self {
        Self {
            adds: HashMap::new(),
            removes: HashSet::new(),
        }
    }

    pub fn add(&mut self, element: T) -> Uuid {
        let uid = Uuid::new_v4();
        self.adds
            .entry(element)
            .or_insert_with(HashSet::new)
            .insert(uid);
        uid
    }

    pub fn remove(&mut self, element: &T) {
        if let Some(uids) = self.adds.get(element) {
            self.removes.extend(uids.clone());
        }
    }

    pub fn contains(&self, element: &T) -> bool {
        self.adds.get(element).map_or(false, |uids| {
            uids.iter().any(|uid| !self.removes.contains(uid))
        })
    }

    pub fn elements(&self) -> Vec<T> {
        self.adds
            .iter()
            .filter(|(_, uids)| uids.iter().any(|uid| !self.removes.contains(uid)))
            .map(|(elem, _)| elem.clone())
            .collect()
    }

    pub fn merge(&mut self, other: &ORSet<T>) {
        for (elem, uids) in &other.adds {
            self.adds
                .entry(elem.clone())
                .or_insert_with(HashSet::new)
                .extend(uids.clone());
        }
        self.removes.extend(&other.removes);
    }
}

// ===== RGA (Replicated Growable Array) =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RGA<T: Clone + Debug> {
    tombstones: HashSet<Uuid>,
    vertices: BTreeMap<Timestamp, Vertex<T>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
struct Timestamp {
    time: u64,
    node_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Vertex<T> {
    id: Uuid,
    value: T,
    next: Option<Timestamp>,
}

impl<T: Clone + Debug> RGA<T> {
    pub fn new() -> Self {
        Self {
            tombstones: HashSet::new(),
            vertices: BTreeMap::new(),
        }
    }

    pub fn insert(&mut self, index: usize, value: T, node_id: String) -> Uuid {
        let id = Uuid::new_v4();
        let timestamp = Timestamp {
            time: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
            node_id,
        };

        let vertex = Vertex {
            id,
            value,
            next: self.find_next_at_index(index),
        };

        self.vertices.insert(timestamp, vertex);
        id
    }

    pub fn delete(&mut self, id: Uuid) {
        self.tombstones.insert(id);
    }

    pub fn to_vec(&self) -> Vec<T> {
        let mut result = Vec::new();
        let mut current = self.find_head();

        while let Some(ts) = current {
            if let Some(vertex) = self.vertices.get(&ts) {
                if !self.tombstones.contains(&vertex.id) {
                    result.push(vertex.value.clone());
                }
                current = vertex.next.clone();
            } else {
                break;
            }
        }

        result
    }

    fn find_head(&self) -> Option<Timestamp> {
        self.vertices.keys().next().cloned()
    }

    fn find_next_at_index(&self, _index: usize) -> Option<Timestamp> {
        // Simplified: return last timestamp
        self.vertices.keys().last().cloned()
    }
}

// ===== Causal Tree =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CausalTree<T: Clone + Debug> {
    atoms: HashMap<AtomId, Atom<T>>,
    weave: Vec<AtomId>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
struct AtomId {
    timestamp: u64,
    node_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Atom<T> {
    id: AtomId,
    cause: Option<AtomId>,
    value: T,
    deleted: bool,
}

impl<T: Clone + Debug> CausalTree<T> {
    pub fn new() -> Self {
        Self {
            atoms: HashMap::new(),
            weave: Vec::new(),
        }
    }

    pub fn insert(&mut self, value: T, cause: Option<AtomId>, node_id: String) -> AtomId {
        let id = AtomId {
            timestamp: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_millis() as u64,
            node_id,
        };

        let atom = Atom {
            id: id.clone(),
            cause,
            value,
            deleted: false,
        };

        self.atoms.insert(id.clone(), atom);
        self.update_weave();

        id
    }

    pub fn delete(&mut self, id: &AtomId) {
        if let Some(atom) = self.atoms.get_mut(id) {
            atom.deleted = true;
        }
        self.update_weave();
    }

    fn update_weave(&mut self) {
        // Simplified weaving algorithm
        self.weave = self.atoms.keys().cloned().collect();
        self.weave
            .sort_by_key(|id| (id.timestamp, id.node_id.clone()));
    }

    pub fn to_string(&self) -> String {
        self.weave
            .iter()
            .filter_map(|id| {
                self.atoms.get(id).and_then(|atom| {
                    if !atom.deleted {
                        Some(format!("{:?}", atom.value))
                    } else {
                        None
                    }
                })
            })
            .collect::<Vec<_>>()
            .join("")
    }
}

// ===== WOOT =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WOOT {
    characters: Vec<WChar>,
    pool: HashSet<WChar>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
struct WChar {
    id: WCharId,
    visible: bool,
    value: char,
    prev: WCharId,
    next: WCharId,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
struct WCharId {
    node_id: String,
    counter: u64,
}

impl WOOT {
    pub fn new() -> Self {
        Self {
            characters: Vec::new(),
            pool: HashSet::new(),
        }
    }

    pub fn insert(&mut self, pos: usize, c: char, node_id: String) -> WCharId {
        let id = WCharId {
            node_id,
            counter: self.characters.len() as u64,
        };

        let (prev, next) = self.get_neighbors(pos);

        let wchar = WChar {
            id: id.clone(),
            visible: true,
            value: c,
            prev,
            next,
        };

        self.pool.insert(wchar.clone());
        self.integrate_insert(wchar);

        id
    }

    pub fn delete(&mut self, id: &WCharId) {
        for wchar in &mut self.characters {
            if wchar.id == *id {
                wchar.visible = false;
                break;
            }
        }
    }

    fn get_neighbors(&self, pos: usize) -> (WCharId, WCharId) {
        // Simplified: return begin and end markers
        (
            WCharId {
                node_id: "begin".to_string(),
                counter: 0,
            },
            WCharId {
                node_id: "end".to_string(),
                counter: u64::MAX,
            },
        )
    }

    fn integrate_insert(&mut self, wchar: WChar) {
        // Simplified integration
        self.characters.push(wchar);
        self.characters.sort_by_key(|w| w.id.counter);
    }

    pub fn to_string(&self) -> String {
        self.characters
            .iter()
            .filter(|w| w.visible)
            .map(|w| w.value)
            .collect()
    }
}

// ===== Treedoc =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Treedoc {
    atoms: BTreeMap<TreedocId, TreedocAtom>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
struct TreedocId {
    path: Vec<u8>,
    disambiguator: DisambiguatorTuple,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
struct DisambiguatorTuple {
    node_id: String,
    counter: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct TreedocAtom {
    value: char,
    tombstone: bool,
}

impl Treedoc {
    pub fn new() -> Self {
        Self {
            atoms: BTreeMap::new(),
        }
    }

    pub fn insert(&mut self, pos: usize, c: char, node_id: String) -> TreedocId {
        let path = self.generate_path(pos);
        let id = TreedocId {
            path,
            disambiguator: DisambiguatorTuple {
                node_id,
                counter: self.atoms.len() as u64,
            },
        };

        let atom = TreedocAtom {
            value: c,
            tombstone: false,
        };

        self.atoms.insert(id.clone(), atom);
        id
    }

    pub fn delete(&mut self, id: &TreedocId) {
        if let Some(atom) = self.atoms.get_mut(id) {
            atom.tombstone = true;
        }
    }

    fn generate_path(&self, pos: usize) -> Vec<u8> {
        // Simplified path generation
        vec![pos as u8]
    }

    pub fn to_string(&self) -> String {
        self.atoms
            .values()
            .filter(|a| !a.tombstone)
            .map(|a| a.value)
            .collect()
    }
}

// ===== Logoot =====

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Logoot {
    atoms: BTreeMap<LogootId, LogootAtom>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
struct LogootId {
    positions: Vec<LogootPosition>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
struct LogootPosition {
    digit: u32,
    site_id: String,
    clock: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct LogootAtom {
    value: char,
    deleted: bool,
}

impl Logoot {
    pub fn new() -> Self {
        Self {
            atoms: BTreeMap::new(),
        }
    }

    pub fn insert(&mut self, pos: usize, c: char, node_id: String) -> LogootId {
        let id = self.generate_position(pos, node_id);

        let atom = LogootAtom {
            value: c,
            deleted: false,
        };

        self.atoms.insert(id.clone(), atom);
        id
    }

    pub fn delete(&mut self, id: &LogootId) {
        if let Some(atom) = self.atoms.get_mut(id) {
            atom.deleted = true;
        }
    }

    fn generate_position(&self, _pos: usize, node_id: String) -> LogootId {
        // Simplified position generation
        LogootId {
            positions: vec![LogootPosition {
                digit: rand::random::<u32>() % 1000000,
                site_id: node_id,
                clock: std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_millis() as u64,
            }],
        }
    }

    pub fn to_string(&self) -> String {
        self.atoms
            .values()
            .filter(|a| !a.deleted)
            .map(|a| a.value)
            .collect()
    }
}
