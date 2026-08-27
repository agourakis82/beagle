# services/epistemic-search/app.py
import os
import subprocess
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

BINARY = os.environ.get("CONCLAVE_SEARCH_BIN", "/opt/conclave-search/bin/conclave-search")
SEARXNG_HOST = os.environ.get("SEARXNG_HOST", "10.96.250.10")
BEAGLE_CORE_HOST = os.environ.get("BEAGLE_CORE_HOST", "10.96.250.20")
SEARCH_TIMEOUT = int(os.environ.get("SEARCH_TIMEOUT_SECONDS", "60"))

app = FastAPI(title="Epistemic Search Service", version="0.1.0")

class SearchRequest(BaseModel):
    query: str

def _extract_json_line(stdout: str) -> str:
    """conclave-search has no stderr primitive: every status line
    ("conclave-search: ...") is printed to stdout, before AND sometimes
    after the final JSON answer, even on a successful (exit 0) run. Its
    own convention is that the JSON answer is the last non-empty line
    printed before a successful exit, so pull just that line out rather
    than handing the whole interleaved blob to a JSON parser downstream.
    """
    lines = [l for l in stdout.splitlines() if l.strip()]
    return lines[-1] if lines else ""

@app.get("/health")
def health():
    return {"status": "ok", "binary_exists": os.path.exists(BINARY)}

@app.post("/v1/search")
def search(req: SearchRequest):
    if not req.query.strip():
        raise HTTPException(422, "query must not be empty")
    try:
        result = subprocess.run(
            [BINARY, req.query, SEARXNG_HOST, BEAGLE_CORE_HOST],
            capture_output=True, text=True, timeout=SEARCH_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(504, f"search timed out after {SEARCH_TIMEOUT}s")
    if result.returncode != 0:
        raise HTTPException(
            502,
            f"search failed (exit {result.returncode}): "
            f"stdout: {result.stdout[-500:]} | stderr: {result.stderr[-500:]}",
        )
    return {"raw_stdout": _extract_json_line(result.stdout)}
