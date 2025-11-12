#![allow(unused_imports)]

//! Módulos de travessia e algoritmos de navegação no hipergrafo.
//!
//! Este namespace concentra implementações clássicas (BFS, DFS) adaptadas
//! a hipergrafos e utilitários para descoberta de componentes conectados.

pub mod traversal;

pub use traversal::{
    BfsTraversal, ConnectedComponents, DfsTraversal, ShortestPath, TraversalResult,
    TraversalStrategy,
};
