
//! Priority Queue for Synthesis Tasks

use anyhow::Result;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::cmp::Ordering;
use std::collections::{BinaryHeap, HashSet};

/// Maximum queue size
const MAX_QUEUE_SIZE: usize = 100;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SynthesisTask {
    pub cluster_id: String,
    pub topic: String,
    pub insight_count: usize,
    pub priority: f64,
    pub retries: usize,
    pub created_at: DateTime<Utc>,
}

impl PartialEq for SynthesisTask {
    fn eq(&self, other: &Self) -> bool {
        self.cluster_id == other.cluster_id
    }
}

impl Eq for SynthesisTask {}

impl PartialOrd for SynthesisTask {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

impl Ord for SynthesisTask {
    fn cmp(&self, other: &Self) -> Ordering {
        // Higher priority first (reverse ordering for max-heap)
        other
            .priority
            .partial_cmp(&self.priority)
            .unwrap_or(Ordering::Equal)
    }
}

pub struct PriorityQueue {
    heap: BinaryHeap<SynthesisTask>,
    seen_clusters: HashSet<String>,
    max_size: usize,
}

impl PriorityQueue {
    pub fn new(max_size: usize) -> Self {
        Self {
            heap: BinaryHeap::new(),
            seen_clusters: HashSet::new(),
            max_size,
        }
    }

    /// Push task to queue with deduplication
    pub fn push(&mut self, task: SynthesisTask) -> Result<()> {
        // Deduplication check
        if self.seen_clusters.contains(&task.cluster_id) {
            return Ok(()); // Already in queue, skip
        }

        // Check queue size limit
        if self.heap.len() >= self.max_size {
            // If new task has higher priority than lowest, replace
            if let Some(lowest) = self.heap.peek() {
                if task.priority > lowest.priority {
                    // Remove lowest priority task
                    if let Some(removed) = self.heap.pop() {
                        self.seen_clusters.remove(&removed.cluster_id);
                    }
                } else {
                    // New task has lower priority, reject
                    return Ok(());
                }
            }
        }

        // Add task
        self.seen_clusters.insert(task.cluster_id.clone());
        self.heap.push(task);

        Ok(())
    }

    /// Pop highest priority task
    pub fn pop(&mut self) -> Option<SynthesisTask> {
        if let Some(task) = self.heap.pop() {
            self.seen_clusters.remove(&task.cluster_id);
            Some(task)
        } else {
            None
        }
    }

    /// Peek at highest priority task without removing
    pub fn peek(&self) -> Option<&SynthesisTask> {
        self.heap.peek()
    }

    /// Get queue length
    pub fn len(&self) -> usize {
        self.heap.len()
    }

    /// Check if queue is empty
    pub fn is_empty(&self) -> bool {
        self.heap.is_empty()
    }

    /// Check if cluster is in queue
    pub fn contains(&self, cluster_id: &str) -> bool {
        self.seen_clusters.contains(cluster_id)
    }

    /// Clear queue
    pub fn clear(&mut self) {
        self.heap.clear();
        self.seen_clusters.clear();
    }

    /// Get all tasks (for debugging/status)
    pub fn get_all(&self) -> Vec<SynthesisTask> {
        self.heap.iter().cloned().collect()
    }
}

impl Default for PriorityQueue {
    fn default() -> Self {
        Self::new(MAX_QUEUE_SIZE)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_task(id: &str, priority: f64) -> SynthesisTask {
        SynthesisTask {
            cluster_id: id.to_string(),
            topic: "test".to_string(),
            insight_count: 20,
            priority,
            retries: 0,
            created_at: Utc::now(),
        }
    }

    #[test]
    fn test_priority_queue_ordering() {
        let mut queue = PriorityQueue::new(10);

        queue.push(create_task("low", 10.0)).unwrap();
        queue.push(create_task("high", 100.0)).unwrap();
        queue.push(create_task("medium", 50.0)).unwrap();

        // Should pop in priority order (high first)
        assert_eq!(queue.pop().unwrap().cluster_id, "high");
        assert_eq!(queue.pop().unwrap().cluster_id, "medium");
        assert_eq!(queue.pop().unwrap().cluster_id, "low");
    }

    #[test]
    fn test_deduplication() {
        let mut queue = PriorityQueue::new(10);

        queue.push(create_task("cluster1", 50.0)).unwrap();
        queue.push(create_task("cluster1", 60.0)).unwrap(); // Duplicate, should be ignored

        assert_eq!(queue.len(), 1);
    }

    #[test]
    fn test_max_size_limit() {
        let mut queue = PriorityQueue::new(3);

        queue.push(create_task("task1", 10.0)).unwrap();
        queue.push(create_task("task2", 20.0)).unwrap();
        queue.push(create_task("task3", 30.0)).unwrap();

        assert_eq!(queue.len(), 3);

        // Try to add lower priority task (should be rejected)
        queue.push(create_task("task4", 5.0)).unwrap();
        assert_eq!(queue.len(), 3);
        assert!(!queue.contains("task4"));

        // Add higher priority task (should replace lowest)
        queue.push(create_task("task5", 40.0)).unwrap();
        assert_eq!(queue.len(), 3);
        assert!(queue.contains("task5"));
        assert!(!queue.contains("task1")); // Lowest priority, should be removed
    }

    #[test]
    fn test_peek() {
        let mut queue = PriorityQueue::new(10);

        queue.push(create_task("high", 100.0)).unwrap();
        queue.push(create_task("low", 10.0)).unwrap();

        let peeked = queue.peek().unwrap();
        assert_eq!(peeked.cluster_id, "high");
        assert_eq!(queue.len(), 2); // Peek should not remove
    }

    #[test]
    fn test_contains() {
        let mut queue = PriorityQueue::new(10);

        queue.push(create_task("cluster1", 50.0)).unwrap();

        assert!(queue.contains("cluster1"));
        assert!(!queue.contains("cluster2"));
    }

    #[test]
    fn test_clear() {
        let mut queue = PriorityQueue::new(10);

        queue.push(create_task("task1", 10.0)).unwrap();
        queue.push(create_task("task2", 20.0)).unwrap();

        assert_eq!(queue.len(), 2);

        queue.clear();

        assert_eq!(queue.len(), 0);
        assert!(!queue.contains("task1"));
        assert!(!queue.contains("task2"));
    }
}
