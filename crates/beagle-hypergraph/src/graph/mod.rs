#![allow(unused_imports)]

//! Módulos de travessia e algoritmos de navegação no hipergrafo.
//!
//! Este namespace concentra implementações clássicas (BFS, DFS) adaptadas
//! a hipergrafos e utilitários para descoberta de componentes conectados.

#[cfg(feature = "database")]
pub mod traversal;

#[cfg(feature = "database")]
pub use traversal::{
    BfsTraversal, ConnectedComponents, DfsTraversal, ShortestPath, TraversalResult,
    TraversalStrategy,
};
