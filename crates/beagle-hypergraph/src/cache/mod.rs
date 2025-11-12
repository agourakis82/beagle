//! Infraestrutura de cache para nós quentes do hipergrafo.
//!
//! Este módulo expõe adaptadores específicos, como a implementação
//! respaldada por Redis, permitindo estratégias de cache configuráveis.

pub mod redis;

pub use redis::{CacheStats, RedisCache};
