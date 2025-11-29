// crates/beagle-whisper/examples/advanced_demo.rs
//! Advanced BEAGLE Whisper demonstration

use anyhow::Result;
use beagle_whisper::{
    advanced::{
        AdvancedAudioProcessor, AudioConfig, DiarizationSegment, EmotionResult, Language,
        ProcessingResult,
    },
    streaming::{AudioStreamer, StreamConfig, StreamEvent},
    BeagleVoiceAssistant, BeagleWhisper,
};
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt::init();

    println!("=== BEAGLE Whisper Advanced Demo ===\n");

    // 1. Basic transcription and TTS
    println!("1. Basic Whisper Functionality");
    println!("-------------------------------");
    demo_basic_whisper().await?;

    // 2. Advanced audio processing
    println!("\n2. Advanced Audio Processing");
    println!("-------------------------------");
    demo_advanced_processing().await?;

    // 3. Real-time streaming
    println!("\n3. Real-time Streaming");
    println!("-------------------------------");
    demo_streaming().await?;

    // 4. Voice assistant with emotion
    println!("\n4. Voice Assistant with Emotion Detection");
    println!("-------------------------------");
    demo_voice_assistant().await?;

    println!("\n=== Demo Complete ===");
    Ok(())
}

/// Demonstrate basic Whisper functionality
async fn demo_basic_whisper() -> Result<()> {
    let whisper = BeagleWhisper::new()?;

    // Check TTS backend
    println!("✓ TTS Backend: {}", whisper.tts_backend());

    // Test TTS
    whisper
        .speak("Hello! This is BEAGLE Whisper with advanced audio processing.")
        .await?;
    println!("✓ Text-to-speech working");

    // Simulate transcription
    println!("✓ Whisper transcription ready (requires whisper.cpp)");

    Ok(())
}

/// Demonstrate advanced audio processing
async fn demo_advanced_processing() -> Result<()> {
    let config = AudioConfig {
        sample_rate: 16000,
        enable_diarization: true,
        enable_emotion: true,
        enable_enhancement: true,
        ..Default::default()
    };

    let processor = AdvancedAudioProcessor::new(config);

    // Generate test audio (1 second)
    let test_audio: Vec<f32> = (0..16000)
        .map(|i| {
            let t = i as f32 / 16000.0;
            // Mix of frequencies to simulate speech
            0.3 * (440.0 * 2.0 * std::f32::consts::PI * t).sin() +  // A4 note
            0.2 * (880.0 * 2.0 * std::f32::consts::PI * t).sin() +  // A5 note
            0.1 * (220.0 * 2.0 * std::f32::consts::PI * t).sin() // A3 note
        })
        .collect();

    // Process audio
    let result = processor.process(&test_audio).await?;

    // Display results
    println!("\nProcessing Results:");
    println!("-------------------");

    // Voice activity
    println!("✓ Speech detected: {}", result.has_speech);

    // Speaker diarization
    if let Some(ref diarization) = result.diarization {
        println!("\n✓ Speaker Diarization:");
        for segment in diarization.iter().take(3) {
            println!(
                "  - {} speaking from {:.2}s to {:.2}s (confidence: {:.2})",
                segment.speaker, segment.start_time, segment.end_time, segment.confidence
            );
        }
    }

    // Emotion detection
    if let Some(ref emotion) = result.emotion {
        println!("\n✓ Emotion Detection:");
        println!("  - Primary emotion: {}", emotion.primary_emotion);
        println!("  - Arousal: {:.2}", emotion.arousal);
        println!("  - Valence: {:.2}", emotion.valence);

        println!("  - Emotion scores:");
        for (emo, score) in emotion.scores.iter().take(3) {
            println!("    • {}: {:.2}", emo, score);
        }
    }

    // Language detection
    if let Some(ref lang) = result.language {
        println!("\n✓ Language Detection:");
        println!("  - Language: {} ({})", lang.name, lang.code);
        println!("  - Confidence: {:.2}", lang.confidence);
    }

    Ok(())
}

/// Demonstrate real-time streaming
async fn demo_streaming() -> Result<()> {
    let config = StreamConfig {
        sample_rate: 16000,
        buffer_size: 32000,
        chunk_size: 8000,
        adaptive_bitrate: true,
        ..Default::default()
    };

    let streamer = Arc::new(AudioStreamer::new(config));

    println!("\nStarting audio stream...");

    // Start stream
    let mut rx = streamer.start_stream().await?;

    // Simulate feeding audio
    let test_audio = vec![0.1; 8000]; // 0.5 seconds of audio
    streamer.feed_audio(&test_audio).await?;

    // Process events (with timeout)
    let timeout = tokio::time::timeout(tokio::time::Duration::from_secs(1), async {
        while let Some(event) = rx.recv().await {
            match event {
                StreamEvent::Transcript(segment) => {
                    println!(
                        "✓ Transcript: {} (confidence: {:.2})",
                        segment.text, segment.confidence
                    );
                }
                StreamEvent::AudioData { timestamp, .. } => {
                    println!("✓ Audio chunk at {}ms", timestamp);
                }
                StreamEvent::Stats(stats) => {
                    println!("✓ Stream stats: {} samples processed", stats.total_samples);
                }
                StreamEvent::Error(e) => {
                    println!("✗ Stream error: {}", e);
                }
                _ => {}
            }
            break; // Just process first event for demo
        }
    })
    .await;

    if timeout.is_err() {
        println!("✓ Stream timeout (expected in demo)");
    }

    // Get statistics
    let stats = streamer.get_stats().await;
    println!("\nStream Statistics:");
    println!("  - Total samples: {}", stats.total_samples);
    println!("  - Buffer usage: {:.1}%", stats.buffer_usage * 100.0);
    println!("  - Current bitrate: {} bps", stats.current_bitrate);

    // Stop streams
    streamer.stop_all().await?;

    Ok(())
}

/// Demonstrate voice assistant with emotion-aware responses
async fn demo_voice_assistant() -> Result<()> {
    println!("\nInitializing emotion-aware voice assistant...");

    // Create voice assistant
    let assistant = BeagleVoiceAssistant::new()?;

    // Create advanced processor for emotion detection
    let processor = Arc::new(AdvancedAudioProcessor::new(AudioConfig::default()));

    // Custom callback with emotion awareness
    let emotion_aware_callback = |text: String| {
        let processor = processor.clone();
        async move {
            // Simulate emotion detection on user input
            println!("  [Processing emotion from: {}]", text);

            // Generate emotion-aware response
            let response = match text.to_lowercase().as_str() {
                s if s.contains("happy") || s.contains("joy") => {
                    "I'm glad you're feeling positive! Your happiness is contagious! 😊"
                },
                s if s.contains("sad") || s.contains("down") => {
                    "I understand you're going through a tough time. I'm here to listen and support you."
                },
                s if s.contains("angry") || s.contains("mad") => {
                    "I sense some frustration. Let's take a deep breath together and work through this."
                },
                s if s.contains("worried") || s.contains("anxious") => {
                    "It's okay to feel worried sometimes. Let's focus on what we can control."
                },
                _ => {
                    "I'm here to help. How are you feeling today?"
                }
            };

            response.to_string()
        }
    };

    println!("✓ Emotion-aware assistant ready");
    println!("  (Would start listening for voice input with real microphone)");

    // Simulate conversation
    println!("\nSimulated conversation:");
    println!("----------------------");

    let test_inputs = vec![
        "I'm feeling really happy today!",
        "I'm a bit worried about tomorrow",
        "This makes me so angry",
    ];

    for input in test_inputs {
        println!("\n🎤 User: {}", input);
        let response = emotion_aware_callback(input.to_string()).await;
        println!("🤖 BEAGLE: {}", response);

        // Use TTS to speak response
        if let Err(e) = assistant.whisper().speak(&response).await {
            println!("  (TTS: {})", e);
        }
    }

    Ok(())
}

/// Extended demo showing integration with other BEAGLE components
#[allow(dead_code)]
async fn demo_full_integration() -> Result<()> {
    println!("\n5. Full BEAGLE Integration");
    println!("-------------------------------");

    // This would integrate with:
    // - beagle-llm for intelligent responses
    // - beagle-memory for conversation history
    // - beagle-personality for personality-aware responses
    // - beagle-worldmodel for context understanding

    println!("✓ Ready for integration with:");
    println!("  - LLM processing (beagle-llm)");
    println!("  - Memory system (beagle-memory)");
    println!("  - Personality engine (beagle-personality)");
    println!("  - World model (beagle-worldmodel)");

    Ok(())
}
