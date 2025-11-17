use beagle_hermes::thought_capture::*;
use std::path::Path;

#[tokio::test]
async fn test_full_pipeline_text() {
    let service = ThoughtCaptureService::new(WhisperConfig::default()).unwrap();

    let text = "Just realized that increasing KEC entropy by 0.3 significantly accelerates \
                collagen scaffold degradation. This matches the PBPK model predictions perfectly. \
                Need to write this up ASAP - could be a Nature Materials paper.";

    let thought = service.process_text_insight(text.to_string()).unwrap();

    // Validate
    assert_eq!(thought.source, InsightSource::Text);
    assert!(!thought.concepts.is_empty());

    // Should extract key concepts
    let concept_texts: Vec<String> = thought
        .concepts
        .iter()
        .map(|c| c.text.to_lowercase())
        .collect();

    assert!(concept_texts.iter().any(|t| t.contains("kec")));
    assert!(concept_texts.iter().any(|t| t.contains("collagen")));

    println!("\n✅ Full pipeline test passed!");
    println!("Extracted concepts: {:?}", concept_texts);
}

#[tokio::test]
#[ignore] // Requires real audio file
async fn test_full_pipeline_voice() {
    let service = ThoughtCaptureService::new(WhisperConfig::default()).unwrap();

    let audio_path = Path::new("test_data/test_voice_note.wav");
    if !audio_path.exists() {
        println!("⚠️ Skipping voice test - no test audio file");
        return;
    }

    let thought = service.process_voice_note(audio_path).await.unwrap();

    assert_eq!(thought.source, InsightSource::Voice);
    assert!(!thought.concepts.is_empty());
    assert!(thought.confidence > 0.0);

    println!("\n✅ Voice pipeline test passed!");
    println!("Transcription: {}", thought.text);
    println!(
        "Concepts: {:?}",
        thought.concepts.iter().map(|c| &c.text).collect::<Vec<_>>()
    );
}
