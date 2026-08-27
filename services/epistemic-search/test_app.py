# services/epistemic-search/test_app.py
#
# Lightweight self-check for _extract_json_line, run with plain `assert`
# statements (no pytest dependency -- this service has no existing Python
# test setup to match). Run directly:
#
#   python3 services/epistemic-search/test_app.py
#
from app import _extract_json_line


def test_pure_json_no_preamble():
    stdout = '{"summary": "ok", "summary_kind": "placeholder-concat"}'
    assert _extract_json_line(stdout) == stdout


def test_status_lines_before_json():
    # This is the realistic mixed-stdout shape from a successful
    # conclave-search run that hit a fail-soft branch (F1's finding):
    # status lines on stdout, then the JSON answer as the last line.
    stdout = (
        "conclave-search: fetch_memory_context failed (unreachable beagle-core, or no atoms)\n"
        "conclave-search: continuing with empty enrichment\n"
        '{"summary": "the sky is blue", "summary_kind": "placeholder-concat", '
        '"confidence_low": 0.1, "confidence_high": 0.9, '
        '"confidence_semantics": "independent-corroboration-width"}'
    )
    extracted = _extract_json_line(stdout)
    assert extracted == (
        '{"summary": "the sky is blue", "summary_kind": "placeholder-concat", '
        '"confidence_low": 0.1, "confidence_high": 0.9, '
        '"confidence_semantics": "independent-corroboration-width"}'
    )
    import json
    parsed = json.loads(extracted)
    assert parsed["summary"] == "the sky is blue"


def test_trailing_blank_lines_after_json():
    # Trailing blank lines (e.g. a final newline) must not shadow the
    # real last non-empty line.
    stdout = (
        "conclave-search: some status\n"
        '{"summary": "x", "summary_kind": "placeholder-concat"}\n'
        "\n"
    )
    extracted = _extract_json_line(stdout)
    assert extracted == '{"summary": "x", "summary_kind": "placeholder-concat"}'


def test_write_back_warning_after_json_is_not_the_current_fix_target():
    # Per the review, write-back warnings can be printed AFTER the JSON
    # too (src/main.sio:758-759). _extract_json_line only guarantees the
    # LAST non-empty line is returned -- if a warning line follows the
    # JSON, that warning line (not the JSON) would be "last". This test
    # documents the known boundary of the fix rather than asserting a
    # false guarantee.
    stdout = (
        '{"summary": "x", "summary_kind": "placeholder-concat"}\n'
        "conclave-search: warning: failed to write back memory atom\n"
    )
    extracted = _extract_json_line(stdout)
    assert extracted == "conclave-search: warning: failed to write back memory atom"


def test_empty_stdout():
    assert _extract_json_line("") == ""


def test_whitespace_only_stdout():
    assert _extract_json_line("   \n  \n") == ""


if __name__ == "__main__":
    test_pure_json_no_preamble()
    test_status_lines_before_json()
    test_trailing_blank_lines_after_json()
    test_write_back_warning_after_json_is_not_the_current_fix_target()
    test_empty_stdout()
    test_whitespace_only_stdout()
    print("all _extract_json_line self-checks passed")
