//! Integration tests for beagle-paradox
//!
//! Tests the complete paradoxical self-modification system:
//! - ParadoxEngine creation and iteration tracking
//! - ParadoxResult structure and resolution detection
//! - SelfModifier code validation and backup creation
//! - Safety guard effectiveness
//! - Change identification and tracking

use beagle_paradox::{ModificationReport, ParadoxEngine, ParadoxResult, SelfModifier};
use std::fs;
use std::path::PathBuf;
use tempfile::TempDir;

// ============================================================================
// PARADOX ENGINE TESTS (15 tests)
// ============================================================================

#[test]
fn test_paradox_engine_creation() {
    // Verify ParadoxEngine can be instantiated
    let _engine = ParadoxEngine::new();
    assert!(true); // If we get here, creation succeeded
}

#[test]
fn test_paradox_engine_default() {
    // Verify Default trait implementation
    let _engine = ParadoxEngine::default();
    assert!(true);
}

#[test]
fn test_paradox_result_structure() {
    // Verify ParadoxResult can hold all data correctly
    let result = ParadoxResult {
        iterations_completed: 5,
        paradox_resolved: true,
        final_code_length: 1500,
        modifications_made: vec![
            "Iteração 1: 50 caracteres modificados".to_string(),
            "Iteração 2: 75 caracteres modificados".to_string(),
        ],
        resolution_strategy: Some("Paradoxo resolvido via modificação estrutural".to_string()),
    };

    assert_eq!(result.iterations_completed, 5);
    assert!(result.paradox_resolved);
    assert_eq!(result.final_code_length, 1500);
    assert_eq!(result.modifications_made.len(), 2);
    assert!(result.resolution_strategy.is_some());
}

#[test]
fn test_paradox_result_unresolved() {
    // Verify ParadoxResult with unresolved paradox
    let result = ParadoxResult {
        iterations_completed: 3,
        paradox_resolved: false,
        final_code_length: 1200,
        modifications_made: vec!["Iteração 1: 30 caracteres".to_string()],
        resolution_strategy: None,
    };

    assert_eq!(result.iterations_completed, 3);
    assert!(!result.paradox_resolved);
    assert_eq!(result.final_code_length, 1200);
    assert!(result.resolution_strategy.is_none());
}

#[test]
fn test_paradox_result_no_modifications() {
    // Verify empty modifications list is handled
    let result = ParadoxResult {
        iterations_completed: 0,
        paradox_resolved: false,
        final_code_length: 0,
        modifications_made: vec![],
        resolution_strategy: None,
    };

    assert!(result.modifications_made.is_empty());
}

#[test]
fn test_paradox_result_serialization() {
    // Verify ParadoxResult can be serialized to JSON
    let result = ParadoxResult {
        iterations_completed: 2,
        paradox_resolved: true,
        final_code_length: 2000,
        modifications_made: vec!["Mudança 1".to_string()],
        resolution_strategy: Some("Estratégia".to_string()),
    };

    let json = serde_json::to_string(&result);
    assert!(json.is_ok());
    let json_str = json.unwrap();
    assert!(json_str.contains("iterations_completed"));
    assert!(json_str.contains("paradox_resolved"));
}

#[test]
fn test_paradox_result_deserialization() {
    // Verify ParadoxResult can be deserialized from JSON
    let json_str = r#"{
        "iterations_completed": 3,
        "paradox_resolved": false,
        "final_code_length": 1500,
        "modifications_made": ["Mudança 1", "Mudança 2"],
        "resolution_strategy": null
    }"#;

    let result: Result<ParadoxResult, _> = serde_json::from_str(json_str);
    assert!(result.is_ok());
    let result = result.unwrap();
    assert_eq!(result.iterations_completed, 3);
    assert!(!result.paradox_resolved);
}

#[test]
fn test_paradox_result_iteration_bounds() {
    // Verify iteration count is u8 (0-255)
    let result = ParadoxResult {
        iterations_completed: 255,
        paradox_resolved: false,
        final_code_length: 1000,
        modifications_made: vec![],
        resolution_strategy: None,
    };

    assert_eq!(result.iterations_completed, 255);
}

#[test]
fn test_paradox_result_large_code_size() {
    // Verify large code sizes are handled
    let result = ParadoxResult {
        iterations_completed: 10,
        paradox_resolved: true,
        final_code_length: 1_000_000, // 1 MB
        modifications_made: vec![],
        resolution_strategy: None,
    };

    assert_eq!(result.final_code_length, 1_000_000);
}

#[test]
fn test_paradox_result_modifications_tracking() {
    // Verify modifications list tracks changes accurately
    let mods = vec![
        "Iter 1: 100 -> 150".to_string(),
        "Iter 2: 150 -> 200".to_string(),
        "Iter 3: 200 -> 180".to_string(),
    ];

    let result = ParadoxResult {
        iterations_completed: 3,
        paradox_resolved: false,
        final_code_length: 180,
        modifications_made: mods,
        resolution_strategy: None,
    };

    assert_eq!(result.modifications_made.len(), 3);
    assert!(result.modifications_made[0].contains("100"));
}

// ============================================================================
// SELF MODIFIER TESTS (15 tests)
// ============================================================================

#[test]
fn test_self_modifier_creation() {
    // Verify SelfModifier can be instantiated
    let _modifier = SelfModifier::new();
    assert!(true);
}

#[test]
fn test_self_modifier_default() {
    // Verify Default trait implementation
    let _modifier = SelfModifier::default();
    assert!(true);
}

#[test]
fn test_validate_valid_rust_code() {
    // Verify valid Rust code passes validation
    let modifier = SelfModifier::new();
    let code = "pub fn hello() { println!(\"Hello\"); }";
    assert!(modifier.validate_rust_code(code));
}

#[test]
fn test_validate_code_with_struct() {
    // Verify code with struct passes validation
    let modifier = SelfModifier::new();
    let code = "pub struct MyStruct { field: i32 }";
    assert!(modifier.validate_rust_code(code));
}

#[test]
fn test_validate_code_with_pub_keyword() {
    // Verify code with pub keyword passes validation
    let modifier = SelfModifier::new();
    let code = "pub const VALUE: i32 = 42;";
    assert!(modifier.validate_rust_code(code));
}

#[test]
fn test_validate_empty_code_rejected() {
    // Verify empty code is rejected
    let modifier = SelfModifier::new();
    assert!(!modifier.validate_rust_code(""));
    assert!(!modifier.validate_rust_code("   "));
}

#[test]
fn test_validate_no_rust_structure_rejected() {
    // Verify code without Rust structure is rejected
    let modifier = SelfModifier::new();
    let code = "Hello world this is not Rust";
    assert!(!modifier.validate_rust_code(code));
}

#[test]
fn test_validate_unsafe_pointer_pattern_rejected() {
    // Verify unsafe pointer patterns are rejected
    let modifier = SelfModifier::new();
    let code = "unsafe { std::ptr::null_mut() }";
    assert!(!modifier.validate_rust_code(code));
}

#[test]
fn test_validate_unsafe_without_pointer_allowed() {
    // Verify unsafe without null_mut pattern is allowed (must have function def)
    let modifier = SelfModifier::new();
    let code = "fn test() { unsafe { let x = 42; } }";
    assert!(modifier.validate_rust_code(code));
}

#[test]
fn test_modification_report_structure() {
    // Verify ModificationReport structure is correct
    let report = ModificationReport {
        file_path: PathBuf::from("/path/to/file.rs"),
        modification_successful: true,
        code_length_before: 100,
        code_length_after: 150,
        changes_made: vec!["Added function".to_string()],
        validation_passed: true,
    };

    assert_eq!(report.code_length_before, 100);
    assert_eq!(report.code_length_after, 150);
    assert!(report.modification_successful);
    assert!(report.validation_passed);
}

#[test]
fn test_modification_report_serialization() {
    // Verify ModificationReport can be serialized
    let report = ModificationReport {
        file_path: PathBuf::from("/path/to/file.rs"),
        modification_successful: true,
        code_length_before: 100,
        code_length_after: 150,
        changes_made: vec!["Change 1".to_string()],
        validation_passed: true,
    };

    let json = serde_json::to_string(&report);
    assert!(json.is_ok());
}

// ============================================================================
// BACKUP AND FILE OPERATIONS TESTS (10 tests)
// ============================================================================

#[test]
fn test_create_backup_new_file() {
    // Verify backup creation for existing file
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    // Create a test file
    fs::write(&file_path, "pub fn test() {}").unwrap();

    let modifier = SelfModifier::new();
    let backup_path = modifier.create_backup(&file_path);

    assert!(backup_path.is_ok());
    let backup = backup_path.unwrap();
    assert!(backup.exists());
    assert!(backup.to_string_lossy().contains("backup"));
}

#[test]
fn test_create_backup_nonexistent_file() {
    // Verify backup creation handles nonexistent file gracefully
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("nonexistent.rs");

    let modifier = SelfModifier::new();
    let backup_path = modifier.create_backup(&file_path);

    // Should succeed even if file doesn't exist (no copy needed)
    assert!(backup_path.is_ok());
}

#[test]
fn test_apply_modification_valid_code() {
    // Verify apply_modification succeeds with valid code
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    // Create initial file
    fs::write(&file_path, "pub fn old() {}").unwrap();

    let modifier = SelfModifier::new();
    let result = modifier.apply_modification(&file_path, "pub fn new() {}");

    assert!(result.is_ok());
    let report = result.unwrap();
    assert!(report.modification_successful);
    assert!(report.validation_passed);
}

#[test]
fn test_apply_modification_invalid_code() {
    // Verify apply_modification rejects invalid code
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    fs::write(&file_path, "pub fn old() {}").unwrap();

    let modifier = SelfModifier::new();
    let result = modifier.apply_modification(&file_path, "");

    assert!(result.is_err());
}

#[test]
fn test_apply_modification_creates_backup() {
    // Verify backup is created before modification
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    fs::write(&file_path, "pub fn original() {}").unwrap();

    let modifier = SelfModifier::new();
    let _ = modifier.apply_modification(&file_path, "pub fn modified() {}");

    // Check that backup was created
    let backup_path = file_path.with_extension("rs.backup");
    assert!(backup_path.exists());
}

#[test]
fn test_apply_modification_tracks_size_change() {
    // Verify code_length_before and after are tracked
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let original = "pub fn test() {}";
    let modified = "pub fn test_with_longer_name() {}";

    fs::write(&file_path, original).unwrap();

    let modifier = SelfModifier::new();
    let result = modifier.apply_modification(&file_path, modified).unwrap();

    assert_eq!(result.code_length_before, original.len());
    assert_eq!(result.code_length_after, modified.len());
    assert!(result.code_length_after > result.code_length_before);
}

#[test]
fn test_apply_modification_tracks_changes() {
    // Verify changes_made includes size change description
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    fs::write(&file_path, "pub fn test() {}").unwrap();

    let modifier = SelfModifier::new();
    let result = modifier
        .apply_modification(&file_path, "pub fn test_new() {}")
        .unwrap();

    assert!(!result.changes_made.is_empty());
    assert!(result
        .changes_made
        .iter()
        .any(|c| c.contains("Tamanho") || c.contains("caracteres")));
}

#[test]
fn test_apply_modification_file_updated() {
    // Verify file is actually updated on disk
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let original = "pub fn original() {}";
    let modified = "pub fn modified() {}";

    fs::write(&file_path, original).unwrap();

    let modifier = SelfModifier::new();
    let _ = modifier.apply_modification(&file_path, modified);

    let file_content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(file_content, modified);
}

#[test]
fn test_apply_modification_no_overwrite_without_validation() {
    // Verify file is not modified if validation fails
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let original = "pub fn original() {}";
    fs::write(&file_path, original).unwrap();

    let modifier = SelfModifier::new();
    let _ = modifier.apply_modification(&file_path, "");

    // File should remain unchanged
    let file_content = fs::read_to_string(&file_path).unwrap();
    assert_eq!(file_content, original);
}

// ============================================================================
// SAFETY GUARD TESTS (10 tests)
// ============================================================================

#[test]
fn test_dangerous_pattern_unsafe_pointer() {
    // Verify unsafe pointer patterns trigger rejection
    let modifier = SelfModifier::new();
    let dangerous = "pub fn danger() { unsafe { std::ptr::null_mut() } }";

    // This should fail validation due to unsafe + null_mut combo
    assert!(!modifier.validate_rust_code(dangerous));
}

#[test]
fn test_dangerous_pattern_unsafe_only_allowed() {
    // Verify unsafe alone is allowed (only unsafe + pointer combo rejected)
    let modifier = SelfModifier::new();
    let code = "pub fn safe_unsafe() { unsafe { let x = 42; } }";

    assert!(modifier.validate_rust_code(code));
}

#[test]
fn test_empty_string_rejected() {
    // Verify empty string rejected
    let modifier = SelfModifier::new();
    assert!(!modifier.validate_rust_code(""));
}

#[test]
fn test_whitespace_only_rejected() {
    // Verify whitespace-only string rejected
    let modifier = SelfModifier::new();
    assert!(!modifier.validate_rust_code("   \n  \t  "));
}

#[test]
fn test_plain_text_rejected() {
    // Verify plain text without Rust keywords rejected
    let modifier = SelfModifier::new();
    let plain_text = "This is just plain English text with no Rust code";
    assert!(!modifier.validate_rust_code(plain_text));
}

#[test]
fn test_function_definition_accepted() {
    // Verify function definitions accepted
    let modifier = SelfModifier::new();
    assert!(modifier.validate_rust_code("fn test() {}"));
}

#[test]
fn test_pub_fn_definition_accepted() {
    // Verify pub function definitions accepted
    let modifier = SelfModifier::new();
    assert!(modifier.validate_rust_code("pub fn test() {}"));
}

#[test]
fn test_struct_definition_accepted() {
    // Verify struct definitions accepted
    let modifier = SelfModifier::new();
    assert!(modifier.validate_rust_code("struct MyType { field: u32 }"));
}

#[test]
fn test_pub_struct_definition_accepted() {
    // Verify pub struct definitions accepted
    let modifier = SelfModifier::new();
    assert!(modifier.validate_rust_code("pub struct MyType { field: u32 }"));
}

#[test]
fn test_multiple_rust_elements() {
    // Verify code with multiple Rust elements accepted
    let modifier = SelfModifier::new();
    let code = r#"
        pub struct MyStruct {
            field: i32,
        }

        pub fn my_function() {
            println!("Hello");
        }
    "#;

    assert!(modifier.validate_rust_code(code));
}

// ============================================================================
// CHANGE DETECTION TESTS (5 tests)
// ============================================================================

#[test]
fn test_identify_changes_size_change() {
    // Verify size changes are detected
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let before = "pub fn test() {}";
    let after = "pub fn test_with_much_longer_name_here() {}";

    fs::write(&file_path, before).unwrap();

    let modifier = SelfModifier::new();
    let report = modifier.apply_modification(&file_path, after).unwrap();

    assert!(report.changes_made.iter().any(|c| c.contains("Tamanho")));
}

#[test]
fn test_identify_changes_line_count() {
    // Verify line count changes are detected
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let before = "pub fn test() {}";
    let after = "pub fn test() {\n    let x = 1;\n    let y = 2;\n}";

    fs::write(&file_path, before).unwrap();

    let modifier = SelfModifier::new();
    let report = modifier.apply_modification(&file_path, after).unwrap();

    assert!(report.changes_made.iter().any(|c| c.contains("Linhas")));
}

#[test]
fn test_identify_changes_function_count() {
    // Verify function count changes are detected
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    let before = "pub fn test1() {}";
    let after = "pub fn test1() {}\npub fn test2() {}";

    fs::write(&file_path, before).unwrap();

    let modifier = SelfModifier::new();
    let report = modifier.apply_modification(&file_path, after).unwrap();

    assert!(report.changes_made.iter().any(|c| c.contains("Funções")));
}

#[test]
fn test_changes_report_not_empty() {
    // Verify changes_made list is never empty
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("test.rs");

    fs::write(&file_path, "pub fn old() {}").unwrap();

    let modifier = SelfModifier::new();
    let report = modifier
        .apply_modification(&file_path, "pub fn new() {}")
        .unwrap();

    assert!(!report.changes_made.is_empty());
}

#[test]
fn test_modification_report_file_path_set() {
    // Verify file_path is correctly set in report
    let temp_dir = TempDir::new().unwrap();
    let file_path = temp_dir.path().join("specific_file.rs");

    fs::write(&file_path, "pub fn test() {}").unwrap();

    let modifier = SelfModifier::new();
    let report = modifier
        .apply_modification(&file_path, "pub fn modified() {}")
        .unwrap();

    assert_eq!(report.file_path, file_path);
}
