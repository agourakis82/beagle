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


# ───────────────────────── pcs.reason ─────────────────────────
# PCS symptom dynamics, ported from Julia reason_symbolically into REAL Sounio:
# a 4-state ODE (depression/anxiety/stress/sleep) integrated t=0..10 with an
# RK4 loop in pure Sounio (no Julia, no external solver). The initial state is
# supplied by the request; the trajectory + severity are solver-computed.
PCS_SIO_TEMPLATE = r'''//@ run-pass
fn og_min(a: f64, b: f64) -> f64 { if a < b { a } else { b } }
struct EState { values: [f64; 64], variances: [f64; 64], n: i64 }
fn estate_new(n: i64) -> EState { EState { values: [0.0; 64], variances: [0.0; 64], n: n } }
fn estate_set(s: &!EState, idx: i64, val: f64, var_: f64) with Mut {
    if idx >= 0 && idx < 64 { s.values[idx] = val; s.variances[idx] = var_ }
}
struct ODEParams { params: [f64; 64], param_variances: [f64; 64], n_params: i64 }
fn ode_params_new() -> ODEParams { ODEParams { params: [0.0; 64], param_variances: [0.0; 64], n_params: 0 } }
fn estate_axpy(dst: &!EState, a: &EState, scale: f64, b: &EState) with Mut {
    var i = 0
    while i < a.n { if i < 64 { dst.values[i] = a.values[i] + scale * b.values[i] }; i = i + 1 }
    dst.n = a.n
}
fn rhs_psychiatry(t: f64, y: &EState, p: &ODEParams, out: &!EState) with Mut, Div, Panic {
    let dep  = y.values[0]
    let anx  = y.values[1]
    let str_ = y.values[2]
    let slp  = y.values[3]
    out.values[0] = (0.0 - 0.1) * dep  + 0.05 * str_ + 0.02 * anx
    out.values[1] = (0.0 - 0.15) * anx + 0.08 * str_ + 0.03 * dep
    out.values[2] = (0.0 - 0.2) * str_ + 0.1 * (1.0 - slp)
    out.values[3] = 0.3 * (1.0 - slp)  - 0.1 * str_
    out.n = 4
}
fn rk4_step_generic(rhs: fn(f64, &EState, &ODEParams, &!EState) -> (), t: f64, state: &!EState, p: &ODEParams, dt: f64) with Mut, Div, Panic {
    let n = state.n
    var k1 = estate_new(n); var k2 = estate_new(n)
    var k3 = estate_new(n); var k4 = estate_new(n)
    var tmp = estate_new(n)
    rhs(t, state, p, &!k1)
    estate_axpy(&!tmp, state, 0.5 * dt, &k1)
    rhs(t + 0.5 * dt, &tmp, p, &!k2)
    estate_axpy(&!tmp, state, 0.5 * dt, &k2)
    rhs(t + 0.5 * dt, &tmp, p, &!k3)
    estate_axpy(&!tmp, state, dt, &k3)
    rhs(t + dt, &tmp, p, &!k4)
    var i = 0
    while i < n {
        if i < 64 {
            let dy = (k1.values[i] + 2.0 * k2.values[i] + 2.0 * k3.values[i] + k4.values[i]) / 6.0
            state.values[i] = state.values[i] + dt * dy
        }
        i = i + 1
    }
}
fn solve_generic(rhs: fn(f64, &EState, &ODEParams, &!EState) -> (), n_dims: i64, y0: EState, p: ODEParams, t_start: f64, t_end: f64, dt: f64, max_steps: i64) -> EState with Mut, Div, Panic {
    var state = y0
    state.n = n_dims
    var t = t_start
    var step = 0
    while t < t_end && step < max_steps {
        let h = og_min(dt, t_end - t)
        if h <= 1.0e-15 { t = t_end }
        else { rk4_step_generic(rhs, t, &!state, &p, h); t = t + h; step = step + 1 }
    }
    state
}
fn main() -> i64 with IO, Mut, Div, Panic {
    var y0 = estate_new(4)
    estate_set(&!y0, 0, __DEP0__, 0.0)
    estate_set(&!y0, 1, __ANX0__, 0.0)
    estate_set(&!y0, 2, __STR0__, 0.0)
    estate_set(&!y0, 3, __SLP0__, 0.0)
    var p = ode_params_new()
    let final_state = solve_generic(rhs_psychiatry, 4, y0, p, 0.0, 10.0, 0.01, 2000)
    let dep_f = final_state.values[0]
    let anx_f = final_state.values[1]
    let str_f = final_state.values[2]
    let slp_f = final_state.values[3]
    let sev   = (dep_f + anx_f + str_f) / 3.0
    println(dep_f); println(",")
    println(anx_f); println(",")
    println(str_f); println(",")
    println(slp_f); println(",")
    println(sev);   println(",")
    0
}
'''


class Symptoms(BaseModel):
    depression: float = 0.5
    anxiety: float = 0.5
    stress: float = 0.5
    sleep: float = 0.7


class PcsReasonReq(BaseModel):
    symptoms: Symptoms = Symptoms()


@app.post("/v1/pcs/reason")
def pcs_reason(req: PcsReasonReq):
    s = req.symptoms
    src = (
        PCS_SIO_TEMPLATE
        .replace("__DEP0__", repr(_num(s.depression)))
        .replace("__ANX0__", repr(_num(s.anxiety)))
        .replace("__STR0__", repr(_num(s.stress)))
        .replace("__SLP0__", repr(_num(s.sleep)))
    )
    toks = [t for t in _compile_and_run(src).replace("\n", "").split(",") if t.strip()]
    try:
        dep, anx, stress, sleep, severity = (float(t) for t in toks[:5])
    except ValueError:
        raise HTTPException(502, f"could not parse PCS output: {toks[:5]}")
    return {
        "verb": "pcs.reason",
        "inputs": {"depression": s.depression, "anxiety": s.anxiety, "stress": s.stress, "sleep": s.sleep},
        "final_state": {"depression": dep, "anxiety": anx, "stress": stress, "sleep": sleep},
        "severity_score": severity,
        "engine": "sounio (RK4 ODE; ported from Julia reason_symbolically)",
    }


@app.get("/v1/catalog")
def catalog():
    return {"verbs": [
        {"verb": "smt.check", "path": "/v1/smt/check", "nature": "logical decision (SAT/UNSAT)"},
        {"verb": "gum.propagate", "path": "/v1/gum/propagate", "nature": "numeric uncertainty propagation"},
        {"verb": "causal.dsep", "path": "/v1/causal/dsep", "nature": "structural graph reasoning"},
        {"verb": "pcs.reason", "path": "/v1/pcs/reason", "nature": "symptom ODE dynamics (Sounio RK4)"},
    ]}


@app.get("/health")
def health():
    ok = os.path.exists(SOUC_BIN) and os.path.isdir(STDLIB)
    return {"status": "ok" if ok else "degraded", "souc": SOUC_BIN, "stdlib": STDLIB,
            "cache_dir": CACHE_DIR}
