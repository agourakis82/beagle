// SPDX-License-Identifier: AGPL-3.0-only
//
// Derived VT/ANSI fidelity audit for the Warp bridge spike.
// This is not a renderer-success claim. It only checks whether the block model
// preserves terminal-control evidence before any renderer promotion decision.

const CSI_RE = /\x1b\[[0-?]*[ -/]*[@-~]/g;
const OSC_RE = /\x1b\][^\x07]*(?:\x07|\x1b\\)/g;
const ESC_RE = /\x1b/g;

function countMatches(value, regex) {
  return Array.from(String(value || "").matchAll(regex)).length;
}

function byteLength(value) {
  return Buffer.byteLength(String(value || ""));
}

function charCount(value, char) {
  return String(value || "").split(char).length - 1;
}

function ratio(actual, expected) {
  if (!expected) return 1;
  return Math.round((actual / expected) * 1000) / 1000;
}

export function summarizeTerminalControls(value) {
  const text = String(value || "");
  return {
    bytes: byteLength(text),
    esc: countMatches(text, ESC_RE),
    csi: countMatches(text, CSI_RE),
    osc: countMatches(text, OSC_RE),
    carriage_returns: charCount(text, "\r"),
    line_feeds: charCount(text, "\n"),
    replacement_chars: charCount(text, "\ufffd"),
  };
}

export function analyzeVtFidelity({ terminalBlock = {}, warpBlock = {} } = {}) {
  const privacyClass = String(terminalBlock.privacyClass || terminalBlock.privacy_class || "sensitive");
  const restricted = privacyClass === "restricted" || privacyClass === "restricted_local_only";
  const original = String(terminalBlock.outputPreview || terminalBlock.output_preview || "");
  const preview = String(warpBlock.outputPreview || "");
  const expected = summarizeTerminalControls(original);
  const observed = summarizeTerminalControls(preview);

  if (restricted) {
    const redacted = preview === "[restricted output redacted]";
    return {
      status: redacted ? "pass" : "fail",
      mode: "restricted_redaction",
      expected,
      observed,
      ratios: {
        bytes: 0,
        esc: 0,
        csi: 0,
        osc: 0,
        carriage_returns: 0,
        line_feeds: 0,
      },
      notes: redacted
        ? ["Restricted fixture redacted before WarpBlock preview; raw VT stream intentionally not exposed."]
        : ["Restricted fixture was not redacted before WarpBlock preview."],
    };
  }

  const ratios = {
    bytes: ratio(observed.bytes, expected.bytes),
    esc: ratio(observed.esc, expected.esc),
    csi: ratio(observed.csi, expected.csi),
    osc: ratio(observed.osc, expected.osc),
    carriage_returns: ratio(observed.carriage_returns, expected.carriage_returns),
    line_feeds: ratio(observed.line_feeds, expected.line_feeds),
  };

  const hasTerminalControls = expected.esc > 0 || expected.carriage_returns > 0 || expected.line_feeds > 0;
  const controlPreserved = ratios.esc >= 1 && ratios.csi >= 1 && ratios.osc >= 1;
  const lineDisciplinePreserved = ratios.carriage_returns >= 0.95 && ratios.line_feeds >= 0.95;
  const noReplacementChars = observed.replacement_chars === 0;
  const notOverExpanded = expected.bytes === 0 || observed.bytes <= expected.bytes * 1.05;
  const enoughBytes = expected.bytes === 0 || observed.bytes >= expected.bytes * 0.9;
  const status = hasTerminalControls && controlPreserved && lineDisciplinePreserved && noReplacementChars && notOverExpanded && enoughBytes
    ? "pass"
    : "partial";

  const notes = [];
  if (!hasTerminalControls) notes.push("Fixture has no VT/ANSI control evidence; use ANSI/OSC fixtures for renderer promotion.");
  if (controlPreserved) notes.push("CSI/OSC escape taxonomy preserved through TerminalBlock to WarpBlock conversion.");
  if (!lineDisciplinePreserved) notes.push("Line discipline changed enough to require renderer inspection.");
  if (!noReplacementChars) notes.push("Replacement characters observed in preview.");
  if (!notOverExpanded || !enoughBytes) notes.push("Output byte envelope changed outside audit tolerance.");

  return {
    status,
    mode: "terminalblock_to_warpblock_preview",
    expected,
    observed,
    ratios,
    notes,
  };
}
