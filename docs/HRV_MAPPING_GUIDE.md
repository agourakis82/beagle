# HRV Mapping Guide — Observer 2.0

**Heart Rate Variability (HRV) Integration in BEAGLE**

---

## Overview

BEAGLE's Observer 2.0 module captures Heart Rate Variability (HRV) and other physiological signals to provide **adaptive context** for the scientific writing pipeline. HRV reflects the user's autonomic nervous system state and cognitive readiness, allowing BEAGLE to adjust tone, complexity, and pacing dynamically.

**Key Principle:** BEAGLE is **not a medical device** and does not diagnose conditions. HRV is used heuristically to optimize cognitive load and writing style.

---

## HRV Basics

### What is HRV?

Heart Rate Variability measures the variation in time intervals between consecutive heartbeats. Higher HRV typically indicates:
- Better stress resilience
- Improved cognitive flexibility
- Enhanced parasympathetic (rest-and-digest) activity

Lower HRV may indicate:
- Acute stress or fatigue
- Reduced cognitive capacity
- Sympathetic (fight-or-flight) dominance

### Measurement

HRV is typically measured as:
- **RMSSD** (Root Mean Square of Successive Differences) — Standard deviation of beat-to-beat intervals
- **Time domain** — Expressed in milliseconds (ms)

BEAGLE uses **RMSSD in milliseconds** as the primary HRV metric.

---

## HRV Classification Thresholds

### Default Thresholds

```rust
pub struct PhysioThresholds {
    pub hrv_low_ms: f32,      // Default: 30.0 ms
    // ... (other thresholds)
}
```

| Level | Range (ms) | State | Cognitive Impact |
|-------|-----------|-------|------------------|
| **Low** | < 30 ms | Stress/Fatigue | Reduced working memory, impaired reasoning |
| **Normal** | 30-80 ms | Balanced | Typical cognitive function |
| **High** | > 80 ms | Flow/Relaxed | Enhanced creativity, deep focus |

### Customization

Override via environment variables:

```bash
export BEAGLE_HRV_LOW_MS="25.0"   # Lower threshold
export BEAGLE_HRV_HIGH_MS="85.0"  # Upper threshold
```

---

## HRV Mapping Logic

### Classification Function

**Location:** `crates/beagle-config/src/lib.rs`

```rust
pub fn classify_hrv(hrv_ms: f32, config: &PhysioThresholds) -> String {
    if hrv_ms < config.hrv_low_ms {
        "low".to_string()
    } else if hrv_ms > 80.0 {  // Can make this configurable
        "high".to_string()
    } else {
        "normal".to_string()
    }
}
```

### Gain Computation

**Location:** `crates/beagle-config/src/lib.rs`

```rust
pub fn compute_gain_from_hrv(hrv_ms: f32, config: &HrvControlConfig) -> f32 {
    let normalized = (hrv_ms - config.min_hrv_ms) / 
                     (config.max_hrv_ms - config.min_hrv_ms);
    
    let clamped = normalized.clamp(0.0, 1.0);
    
    config.min_gain + clamped * (config.max_gain - config.min_gain)
}
```

**Purpose:** Converts raw HRV into a "gain" factor (0.0-1.0) for adaptive prompt adjustment.

---

## Pipeline Integration

### Observer Phase

**Location:** `apps/beagle-monorepo/src/pipeline.rs`

During pipeline execution (Phase 2), Observer captures:

```rust
let user_ctx = observer.current_user_context().await?;

let hrv_level = user_ctx.physio.hrv_level;  // "low" | "normal" | "high"
let hrv_raw = user_ctx.physio.hrv_rmssd_ms; // Raw value (e.g., 45.2 ms)
```

### Prompt Adaptation

**HERMES synthesis** adjusts tone based on HRV:

```rust
if let Some(level) = hrv_level {
    match level {
        "low" => {
            prompt.push_str("⚠️ NOTA: O estado fisiológico atual indica HRV baixo. \
                            Ajuste o tom para ser mais calmo e contemplativo, \
                            evitando sobrecarga cognitiva.\n\n");
        }
        "high" => {
            prompt.push_str("✨ NOTA: O estado fisiológico atual indica HRV alto (flow). \
                            Você pode ser mais criativo e explorar conexões mais profundas.\n\n");
        }
        _ => {}  // Normal: no special instructions
    }
}
```

### Behavioral Changes by HRV Level

| HRV Level | Tone Adjustment | Complexity | Pacing | Example Modifications |
|-----------|----------------|------------|--------|----------------------|
| **Low** | Calmer, supportive | Reduced | Slower | Shorter sentences, simpler structure, more white space |
| **Normal** | Balanced | Standard | Normal | Default scientific style |
| **High** | Creative, exploratory | Higher | Faster | Deeper connections, more interdisciplinary links, denser concepts |

---

## Data Flow

```
HealthKit (iOS) or Manual Input
         ↓
UniversalObserver (Rust)
         ↓
UserContext.physio.hrv_level
         ↓
Pipeline (HERMES synthesis)
         ↓
Adaptive Prompt
         ↓
LLM Generation
         ↓
Draft Paper (optimized for user's cognitive state)
```

---

## Experimental Control: HRV-Aware vs HRV-Blind

For A/B testing, BEAGLE supports disabling HRV adaptation:

### Via API

```json
POST /api/pipeline/start
{
  "question": "...",
  "hrv_aware": false,
  "experiment_id": "hrv_ablation_001"
}
```

### Via Pipeline Function

```rust
let experiment_flags = ExperimentFlags {
    hrv_aware: false,  // Disable HRV adaptation
    triad_enabled: true,
};

run_beagle_pipeline(&mut ctx, question, run_id, None, None, Some(experiment_flags)).await?;
```

**Use Case:** Compare paper quality with/without HRV adaptation to validate the feature.

---

## Physiological Context (Beyond HRV)

Observer 2.0 captures additional signals:

### Physiological

- **Heart Rate (HR):** Tachycardia detection (> 110 bpm default)
- **SpO₂:** Oxygen saturation (< 94% warning)
- **Respiration Rate:** Breathing rate (12-25 bpm normal)
- **Skin Temperature:** Body temperature (33-37.5°C normal)

### Environmental

- **Altitude:** High altitude stress (> 2000m)
- **Barometric Pressure:** Weather changes
- **Temperature:** Ambient heat/cold stress
- **UV Index:** Sun exposure
- **Humidity:** Air quality

### Space Weather (Heliobiology)

- **Kp Index:** Geomagnetic storm intensity (> 5.0 = moderate storm)
- **Solar Wind Speed:** > 600 km/s = high
- **X-ray Flux:** Solar flare activity
- **Proton Flux:** Radiation levels

### Severity Aggregation

Observer computes **composite severity** for each domain:

```rust
pub enum Severity {
    None,     // All normal
    Low,      // Minor deviations
    Moderate, // Noticeable impact expected
    High,     // Significant impact expected
    Critical, // Immediate concern
}
```

**Example:**
- HRV = 25 ms (low) + HR = 115 bpm (tachy) + SpO₂ = 96% (normal) → **Physio Severity: Moderate**

This severity is included in the prompt context.

---

## Configuration Reference

### HRV Thresholds

```bash
# HRV classification
export BEAGLE_HRV_LOW_MS="30.0"      # Below this = "low"
export BEAGLE_HRV_HIGH_MS="80.0"     # Above this = "high"

# Gain computation (advanced)
export BEAGLE_HRV_MIN_GAIN="0.3"     # Minimum gain factor
export BEAGLE_HRV_MAX_GAIN="1.0"     # Maximum gain factor
export BEAGLE_HRV_MIN_MS="20.0"      # Min HRV for normalization
export BEAGLE_HRV_MAX_MS="100.0"     # Max HRV for normalization
```

### Other Physiological Thresholds

```bash
# Heart Rate
export BEAGLE_HR_TACHY_BPM="110.0"   # Tachycardia threshold
export BEAGLE_HR_BRADY_BPM="45.0"    # Bradycardia threshold

# Oxygen Saturation
export BEAGLE_SPO2_WARNING="94.0"    # Warning level
export BEAGLE_SPO2_CRITICAL="90.0"   # Critical level

# Skin Temperature
export BEAGLE_SKIN_TEMP_LOW_C="33.0"
export BEAGLE_SKIN_TEMP_HIGH_C="37.5"

# Respiration Rate
export BEAGLE_RESP_RATE_LOW_BPM="12.0"
export BEAGLE_RESP_RATE_HIGH_BPM="25.0"
```

---

## Use Cases

### 1. Late-Night Writing (Low HRV)

**Scenario:** User is fatigued after a long day, HRV drops to 22 ms.

**BEAGLE Response:**
- Simpler sentence structure
- Shorter paragraphs
- Avoids deeply nested logical arguments
- More supportive, less demanding tone

**Example Prompt Modification:**
> "⚠️ Given low HRV, structure the text clearly with short paragraphs. Avoid complex nested arguments. Use calming, supportive language."

### 2. Morning Flow State (High HRV)

**Scenario:** User is well-rested, in flow state, HRV at 92 ms.

**BEAGLE Response:**
- Richer interdisciplinary connections
- Denser conceptual arguments
- More creative leaps
- Exploratory tone

**Example Prompt Modification:**
> "✨ High HRV detected (flow state). Feel free to explore deep interdisciplinary connections, use richer conceptual density, and pursue creative insights."

### 3. Normal Baseline (Normal HRV)

**Scenario:** User is in typical working state, HRV at 55 ms.

**BEAGLE Response:**
- Standard scientific writing style
- Balanced complexity
- No special tone adjustments

---

## Data Collection for Feedback Loop

### Logged in feedback_events.jsonl

```json
{
  "event_type": "pipeline_run",
  "run_id": "550e8400...",
  "hrv_level": "low",
  "llm_provider_main": "grok3",
  "grok3_calls": 4,
  "accepted": true,
  "rating_0_10": 8,
  "notes": "Good quality despite low HRV"
}
```

### Analysis Questions

1. **Does HRV-aware adaptation improve quality?**
   - Compare `accepted` rate for low HRV runs with/without adaptation

2. **Does HRV correlate with rating?**
   - Correlation between `hrv_level` and `rating_0_10`

3. **Optimal thresholds?**
   - Cluster analysis on HRV values vs quality metrics

---

## Future Enhancements

### 1. Dynamic Threshold Learning

Use feedback data to optimize thresholds per user:

```python
# Pseudocode
for user in users:
    optimal_low_threshold = find_threshold_maximizing_quality(user.feedback_data)
    user.config.hrv_low_ms = optimal_low_threshold
```

### 2. Multi-Modal Fusion

Combine HRV with other signals:

```
Composite Cognitive Readiness Score = 
    α * HRV_normalized + 
    β * (1 - stress_index) + 
    γ * sleep_quality + 
    δ * (1 - kp_index_normalized)
```

### 3. Real-Time Adaptation

Adjust prompts mid-generation based on streaming HRV:

```
If HRV drops during generation → Simplify remaining sections
If HRV increases → Expand depth in remaining sections
```

### 4. Personalized Models

Train LoRA adapters per user with their typical HRV patterns:

```
User A (athlete, high baseline HRV) → Adapter optimized for high HRV
User B (chronic stress, low baseline) → Adapter optimized for low HRV
```

---

## Best Practices

### For Users

1. **Consistency:** Measure HRV at the same time of day for reliable baselines
2. **Calibration:** Run 10-20 pipelines to establish your personal HRV profile
3. **Validation:** Compare papers written at different HRV levels to see the effect
4. **Context:** Note external factors (caffeine, exercise, sleep) in feedback notes

### For Developers

1. **Validation:** Always validate HRV data (0 < HRV < 200 ms is reasonable range)
2. **Fallback:** If HRV unavailable, use neutral context (no adaptation)
3. **Logging:** Always log raw HRV values alongside classifications
4. **Ethics:** Never present HRV data as medical diagnosis

---

## Medical Disclaimer

⚠️ **IMPORTANT:** BEAGLE is **not a medical device**. HRV measurements and interpretations provided by BEAGLE are for **cognitive optimization only** and should not be used for:

- Medical diagnosis
- Treatment decisions
- Health monitoring
- Clinical assessment

Always consult qualified healthcare professionals for medical concerns.

---

## References

### Scientific Background

1. **Shaffer, F., & Ginsberg, J. P. (2017).** An overview of heart rate variability metrics and norms. *Frontiers in Public Health*, 5, 258.

2. **Thayer, J. F., et al. (2012).** A model of neurovisceral integration in emotion regulation and dysregulation. *Journal of Affective Disorders*, 61(3), 201-216.

3. **Kim, H. G., et al. (2018).** Stress and heart rate variability: A meta-analysis and review of the literature. *Psychiatry Investigation*, 15(3), 235.

### BEAGLE Implementation

- `crates/beagle-observer/src/lib.rs` — Observer 2.0 implementation
- `crates/beagle-config/src/lib.rs` — HRV threshold configuration
- `apps/beagle-monorepo/src/pipeline.rs` — Pipeline integration

---

## Quick Reference

### Check HRV Status in Output

```bash
# View run report
cat ~/beagle-data/logs/beagle-pipeline/*_<run_id>.json | jq '.observer'

# Output:
{
  "physio_severity": "moderate",
  "hrv_level": "low",
  "heart_rate_bpm": 78,
  "spo2_percent": 97,
  "stress_index": 0.65
}
```

### Test HRV Adaptation

```bash
# Run with normal HRV (simulated)
cargo run --bin pipeline --package beagle-monorepo -- "Test question"

# Compare output quality at different HRV levels
# (Requires Observer connected to HealthKit or manual input)
```

---

**Last Updated:** January 2025  
**Version:** BEAGLE v0.1  
**Module:** Observer 2.0  
**Status:** Production Ready