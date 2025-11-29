// WebSocket compression strategies
//
// References:
// - RFC 7692: Compression Extensions for WebSocket
// - Deutsch, P. (1996). DEFLATE Compressed Data Format. RFC 1951.

use crate::{Result, WebSocketError};
use bytes::{Bytes, BytesMut};
use flate2::read::{GzDecoder, GzEncoder};
use flate2::Compression;
use std::io::Read;

#[derive(Debug, Clone)]
pub enum CompressionStrategy {
    None,
    Gzip,
    Deflate,
    Lz4,
    Adaptive, // Choose based on message size and type
}

#[derive(Debug, Clone, Copy)]
pub enum CompressionLevel {
    None = 0,
    Fast = 1,
    Default = 6,
    Best = 9,
}

impl From<u32> for CompressionLevel {
    fn from(level: u32) -> Self {
        match level {
            0 => Self::None,
            1..=3 => Self::Fast,
            4..=6 => Self::Default,
            7..=9 => Self::Best,
            _ => Self::Default,
        }
    }
}

pub struct CompressionManager {
    strategy: CompressionStrategy,
    level: CompressionLevel,
    threshold: usize, // Don't compress below this size
}

impl CompressionManager {
    pub fn new(strategy: CompressionStrategy, level: CompressionLevel, threshold: usize) -> Self {
        Self {
            strategy,
            level,
            threshold,
        }
    }

    pub fn compress(&self, data: &[u8]) -> Result<Bytes> {
        if data.len() < self.threshold {
            return Ok(Bytes::copy_from_slice(data));
        }

        match self.strategy {
            CompressionStrategy::None => Ok(Bytes::copy_from_slice(data)),
            CompressionStrategy::Gzip => self.compress_gzip(data),
            CompressionStrategy::Deflate => self.compress_deflate(data),
            CompressionStrategy::Lz4 => self.compress_lz4(data),
            CompressionStrategy::Adaptive => self.compress_adaptive(data),
        }
    }

    pub fn decompress(&self, data: &[u8]) -> Result<Bytes> {
        match self.strategy {
            CompressionStrategy::None => Ok(Bytes::copy_from_slice(data)),
            CompressionStrategy::Gzip => self.decompress_gzip(data),
            CompressionStrategy::Deflate => self.decompress_deflate(data),
            CompressionStrategy::Lz4 => self.decompress_lz4(data),
            CompressionStrategy::Adaptive => self.decompress_adaptive(data),
        }
    }

    fn compress_gzip(&self, data: &[u8]) -> Result<Bytes> {
        let compression = match self.level {
            CompressionLevel::None => return Ok(Bytes::copy_from_slice(data)),
            CompressionLevel::Fast => Compression::fast(),
            CompressionLevel::Default => Compression::default(),
            CompressionLevel::Best => Compression::best(),
        };

        let mut encoder = GzEncoder::new(data, compression);
        let mut compressed = Vec::new();
        encoder
            .read_to_end(&mut compressed)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(compressed))
    }

    fn decompress_gzip(&self, data: &[u8]) -> Result<Bytes> {
        let mut decoder = GzDecoder::new(data);
        let mut decompressed = Vec::new();
        decoder
            .read_to_end(&mut decompressed)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(decompressed))
    }

    fn compress_deflate(&self, data: &[u8]) -> Result<Bytes> {
        use flate2::read::DeflateEncoder;

        let compression = match self.level {
            CompressionLevel::None => return Ok(Bytes::copy_from_slice(data)),
            CompressionLevel::Fast => Compression::fast(),
            CompressionLevel::Default => Compression::default(),
            CompressionLevel::Best => Compression::best(),
        };

        let mut encoder = DeflateEncoder::new(data, compression);
        let mut compressed = Vec::new();
        encoder
            .read_to_end(&mut compressed)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(compressed))
    }

    fn decompress_deflate(&self, data: &[u8]) -> Result<Bytes> {
        use flate2::read::DeflateDecoder;

        let mut decoder = DeflateDecoder::new(data);
        let mut decompressed = Vec::new();
        decoder
            .read_to_end(&mut decompressed)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(decompressed))
    }

    fn compress_lz4(&self, data: &[u8]) -> Result<Bytes> {
        let compressed = lz4::block::compress(data, None, false)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(compressed))
    }

    fn decompress_lz4(&self, data: &[u8]) -> Result<Bytes> {
        let decompressed = lz4::block::decompress(data, None)
            .map_err(|e| WebSocketError::CodecError(e.to_string()))?;

        Ok(Bytes::from(decompressed))
    }

    fn compress_adaptive(&self, data: &[u8]) -> Result<Bytes> {
        // Choose compression based on data characteristics
        let size = data.len();

        if size < 100 {
            // Too small, don't compress
            Ok(Bytes::copy_from_slice(data))
        } else if size < 1024 {
            // Small, use LZ4 for speed
            self.compress_lz4(data)
        } else if self.is_likely_compressible(data) {
            // Large and compressible, use gzip
            self.compress_gzip(data)
        } else {
            // Large but not compressible (e.g., already compressed)
            Ok(Bytes::copy_from_slice(data))
        }
    }

    fn decompress_adaptive(&self, data: &[u8]) -> Result<Bytes> {
        // Try to detect compression format
        if data.len() >= 2 {
            // Check for gzip magic bytes
            if data[0] == 0x1f && data[1] == 0x8b {
                return self.decompress_gzip(data);
            }

            // Check for deflate (less reliable)
            if data[0] == 0x78 {
                return self.decompress_deflate(data);
            }
        }

        // Try LZ4
        if let Ok(decompressed) = self.decompress_lz4(data) {
            return Ok(decompressed);
        }

        // Assume uncompressed
        Ok(Bytes::copy_from_slice(data))
    }

    fn is_likely_compressible(&self, data: &[u8]) -> bool {
        // Simple heuristic: check entropy
        if data.is_empty() {
            return false;
        }

        let mut byte_counts = [0u32; 256];
        for &byte in data {
            byte_counts[byte as usize] += 1;
        }

        // Calculate Shannon entropy
        let len = data.len() as f64;
        let entropy: f64 = byte_counts
            .iter()
            .filter(|&&count| count > 0)
            .map(|&count| {
                let p = count as f64 / len;
                -p * p.log2()
            })
            .sum();

        // High entropy (> 7 bits) suggests already compressed or random data
        entropy < 7.0
    }
}
