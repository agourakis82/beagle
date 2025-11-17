//! Whisper transcription integration via PyO3

use crate::{Result, HermesError};
use pyo3::prelude::*;
use pyo3::types::PyModule;
use tracing::{debug, warn};

pub struct WhisperTranscriber {
    py_module: Py<PyModule>,
}

impl WhisperTranscriber {
    pub fn new(model_path: &str) -> Result<Self> {
        Python::with_gil(|py| {
            // Import whisper module
            let sys = py.import("sys")?;
            let path = sys.getattr("path")?;
            path.call_method1("append", ("./python/hermes",))?;

            let module = py.import("whisper_transcriber")?;

            // Initialize model
            module.getattr("load_model")?
                .call1((model_path,))?;

            Ok(Self {
                py_module: module.into(),
            })
        })
    }

    pub fn transcribe(&self, audio_data: &[u8], sample_rate: u32) -> Result<String> {
        Python::with_gil(|py| {
            let module = self.py_module.as_ref(py);

            // Call Python function: transcribe(audio_bytes, sample_rate)
            let result = module
                .getattr("transcribe")?
                .call1((audio_data.to_vec(), sample_rate))?;

            let transcription: String = result.extract()?;

            debug!("Whisper transcription completed: {} chars", transcription.len());
            Ok(transcription)
        })
    }
}

