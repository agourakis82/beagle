"""Sounio Inference Service — exposes Sounio's verified-inference stdlib as HTTP verbs.

Each verb renders a small Sounio (.sio) program from the (untrusted) request, compiles
it to a standalone native ELF with `souc` (cached by source hash so repeats are ~1ms),
runs it, and returns a structured verdict. The Sounio side does pure computation; this
service layer is the security boundary — untrusted JSON is parsed and validated to
typed numerics/ints here, and only those are interpolated into generated source.

Verbs (v1, CPU):
  POST /v1/smt/check      — QF_LIA consistency (theorem::smt DPLL(T)) -> SAT/UNSAT/UNKNOWN
  POST /v1/gum/propagate  — GUM uncertainty propagation (epistemic::gum)
  POST /v1/causal/dsep    — d-separation / conditional independence (causal::base, Bayes-ball)
  GET  /health            — liveness + toolchain probe
  GET  /v1/catalog        — verb catalog
"""
from __future__ import annotations

import hashlib
import os
import subprocess
import tempfile
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

SOUNIO_DIR = os.environ.get("SOUNIO_DIR", "/home/devsounio/sounio")
SOUC_BIN = os.environ.get("SOUC_BIN", f"{SOUNIO_DIR}/bin/souc")
STDLIB = os.environ.get("SOUNIO_STDLIB_PATH", f"{SOUNIO_DIR}/stdlib")
CACHE_DIR = os.environ.get("SOUNIO_VERB_CACHE", "/tmp/sounio-verb-cache")
COMPILE_TIMEOUT = int(os.environ.get("SOUNIO_COMPILE_TIMEOUT", "120"))
RUN_TIMEOUT = int(os.environ.get("SOUNIO_RUN_TIMEOUT", "30"))

os.makedirs(CACHE_DIR, exist_ok=True)
app = FastAPI(title="Sounio Inference Service", version="0.1.0")


def _compile_and_run(source: str) -> str:
    """Compile `source` to a cached native ELF (keyed by source sha256) and run it.

    Repeated identical sources skip compilation (run only, ~1ms). Returns stdout.
    """
    digest = hashlib.sha256(source.encode()).hexdigest()[:32]
    binpath = os.path.join(CACHE_DIR, f"{digest}.out")
    env = dict(os.environ, SOUC_BIN=SOUC_BIN, SOUNIO_STDLIB_PATH=STDLIB)
    if not os.path.exists(binpath):
        with tempfile.NamedTemporaryFile("w", suffix=".sio", dir=CACHE_DIR, delete=False) as f:
            f.write(source)
            srcpath = f.name
        try:
            cc = subprocess.run(
                [SOUC_BIN, "compile", srcpath, "-o", binpath],
                cwd=SOUNIO_DIR, env=env, capture_output=True, text=True, timeout=COMPILE_TIMEOUT,
            )
            if cc.returncode != 0 or not os.path.exists(binpath):
                raise HTTPException(502, f"souc compile failed: {cc.stderr[-400:] or cc.stdout[-400:]}")
        finally:
            try:
                os.unlink(srcpath)
            except OSError:
                pass
    run = subprocess.run([binpath], cwd=CACHE_DIR, capture_output=True, text=True, timeout=RUN_TIMEOUT)
    if run.returncode != 0:
        raise HTTPException(502, f"verb run failed (exit {run.returncode}): {run.stderr[-400:]}")
    return run.stdout


def _int(x: Any) -> int:
    if isinstance(x, bool) or not isinstance(x, int):
        raise HTTPException(422, "integer required")
    return x


def _num(x: Any) -> float:
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        raise HTTPException(422, "number required")
    return float(x)


# ───────────────────────── smt.check ─────────────────────────
class LiaConstraint(BaseModel):
    coeffs: list[int] = Field(..., description="Σ coeffs[i]·x_i <= bound")
    bound: int
    label: str | None = None


class SmtCheckReq(BaseModel):
    constraints: list[LiaConstraint]


@app.post("/v1/smt/check")
def smt_check(req: SmtCheckReq):
    cons = req.constraints
    if not (1 <= len(cons) <= 64):
        raise HTTPException(422, "1..64 constraints")
    body = []
    for i, c in enumerate(cons):
        if len(c.coeffs) > 16:
            raise HTTPException(422, "<=16 vars")
        body.append(f"    var c{i}: [i64; 16] = [0; 16]")
        for j, v in enumerate(c.coeffs):
            if _int(v) != 0:
                body.append(f"    c{i}[{j}] = {v}")
        body.append(f"    smt_add_lia(&! ctx, &c{i}, {_int(c.bound)})")
    src = (
        "use theorem::smt::*\n"
        "fn main() -> i32 with IO, Mut, Div {\n"
        "    var ctx = smt_new()\n"
        + "\n".join(body) + "\n"
        "    let r = smt_solve(&! ctx)\n"
        '    if r == 0 { println("UNSAT") } else if r == 1 { println("SAT") } else { println("UNKNOWN") }\n'
        "    return 0\n}\n"
    )
    out = _compile_and_run(src).split()
    verdict = next((t for t in reversed(out) if t in ("SAT", "UNSAT", "UNKNOWN")), "UNKNOWN")
    return {
        "verb": "smt.check", "theory": "QF_LIA", "result": verdict,
        "claims": [c.label or f"c{i}" for i, c in enumerate(cons)],
        "meaning": {"UNSAT": "claims provably contradictory",
                    "SAT": "claims mutually consistent",
                    "UNKNOWN": "undecided (bounds/capacity)"}[verdict],
        "engine": "sounio::theorem::smt (DPLL(T))",
    }


# ──────────────────────── gum.propagate ───────────────────────
class GumInput(BaseModel):
    value: float
    u: float
    label: str | None = None


class GumReq(BaseModel):
    inputs: list[GumInput]
    op: str = Field(..., pattern="^(add|sub|mul|div)$")


@app.post("/v1/gum/propagate")
def gum_propagate(req: GumReq):
    if len(req.inputs) != 2:
        raise HTTPException(422, "exactly 2 inputs (v1 binary form)")
    a, b = req.inputs
    src = (
        "use epistemic::gum::*\n"
        "fn main() -> i32 with IO, Mut, Div {\n"
        f"    let a = gum_simple({_num(a.value)!r}, {_num(a.u)!r})\n"
        f"    let b = gum_simple({_num(b.value)!r}, {_num(b.u)!r})\n"
        f"    let y = gum_{req.op}(a, b)\n"
        "    let iv = gum_interval_95(y)\n"
        '    println(y.value); println(",")\n'
        '    println(y.std_uncertainty); println(",")\n'
        '    println(y.degrees_of_freedom); println(",")\n'
        '    println(y.coverage_factor_95); println(",")\n'
        '    println(y.expanded_uncertainty_95); println(",")\n'
        '    println(relative_uncertainty_percent(y)); println(",")\n'
        '    println(iv.lo); println(",")\n'
        '    println(iv.hi); println(",")\n'
        "    return 0\n}\n"
    )
    toks = [t for t in _compile_and_run(src).replace("\n", "").split(",") if t.strip()]
    try:
        v, uc, dof, k, U95, rel, lo, hi = (float(t) for t in toks[:8])
    except ValueError:
        raise HTTPException(502, f"could not parse GUM output: {toks[:8]}")
    return {
        "verb": "gum.propagate", "op": req.op, "value": v,
        "combined_std_uncertainty": uc, "coverage_factor_k95": k,
        "expanded_uncertainty_95": U95, "rel_uncertainty_pct": rel,
        "interval_95": [lo, hi], "eff_dof": dof,
        "engine": "sounio::epistemic::gum (GUM JCGM 100)",
    }


# ───────────────────────── causal.dsep ────────────────────────
class DsepReq(BaseModel):
    n: int
    edges: list[list[int]]
    x: int
    y: int
    z: list[int] = []


@app.post("/v1/causal/dsep")
def causal_dsep(req: DsepReq):
    n = _int(req.n)
    if not (1 <= n <= 32) or len(req.z) > 32:
        raise HTTPException(422, "1..32 nodes, |z|<=32")
    edges = "\n".join(f"    cg_add_edge(&!g, {_int(a)}, {_int(b)})" for a, b in req.edges)
    zl = "\n".join(f"    z[{i}] = {_int(v)}" for i, v in enumerate(req.z))
    src = (
        "use causal::base::*\n"
        "fn main() -> i32 with IO, Mut, Panic, Div {\n"
        f"    var g = cg_new({n})\n"
        f"{edges}\n"
        "    var z: [i32; 32] = [0; 32]\n"
        f"{zl}\n"
        f"    let sep = cat_d_separated(&g, {_int(req.x)}, {_int(req.y)}, &z, {len(req.z)})\n"
        '    if sep { println("1") } else { println("0") }\n'
        "    return 0\n}\n"
    )
    toks = [t for t in _compile_and_run(src).split() if t in ("0", "1")]
    if not toks:
        raise HTTPException(502, "no verdict from causal.dsep")
    sep = toks[-1] == "1"
    return {
        "verb": "causal.dsep", "x": req.x, "y": req.y, "given": req.z,
        "d_separated": sep,
        "meaning": "conditionally independent" if sep else "d-connected (dependence path open)",
        "engine": "sounio::causal::base (Pearl Bayes-ball)",
    }


@app.get("/v1/catalog")
def catalog():
    return {"verbs": [
        {"verb": "smt.check", "path": "/v1/smt/check", "nature": "logical decision (SAT/UNSAT)"},
        {"verb": "gum.propagate", "path": "/v1/gum/propagate", "nature": "numeric uncertainty propagation"},
        {"verb": "causal.dsep", "path": "/v1/causal/dsep", "nature": "structural graph reasoning"},
    ]}


@app.get("/health")
def health():
    ok = os.path.exists(SOUC_BIN) and os.path.isdir(STDLIB)
    return {"status": "ok" if ok else "degraded", "souc": SOUC_BIN, "stdlib": STDLIB,
            "cache_dir": CACHE_DIR}
