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
  POST /v1/fractal/recurse— deterministic fractal-tree growth (pure Sounio; replaces Julia)
  POST /v1/phi/compute    — IIT-4 integrated information Φ + MIP (pure Sounio)
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


# ───────────────────────── theorem.prove ─────────────────────────
# Propositional natural-deduction proving via Sounio's theorem::search (auto_prove + verify).
# SOUND by construction: only a real derivation (proof tree) counts as PROVED — auto_prove's
# truth-table/`trusted` fallback (root proof tag 22) is rejected to UNKNOWN, since it was
# observed to over-accept (e.g. claiming A ⊢ B). Arithmetic is NOT offered (it is trusted()-
# backed in the stdlib, not a real derivation).
_CONN = {"and": "prop_and", "or": "prop_or", "implies": "prop_implies"}


def _compile_prop(e, atoms, lines, ctr):
    if not isinstance(e, dict) or len(e) != 1:
        raise HTTPException(422, "each expr must be a single-key object")
    (k, val), = e.items()
    if k == "atom":
        if val not in atoms:
            raise HTTPException(422, f"unknown atom: {val}")
        v = f"e{ctr[0]}"; ctr[0] += 1
        lines.append(f"    let {v} = ctx_prop(&! ctx, prop_custom({atoms[val]}))")
        return v
    if k == "not":
        inner = _compile_prop(val, atoms, lines, ctr)
        v = f"e{ctr[0]}"; ctr[0] += 1
        lines.append(f"    let {v} = ctx_prop(&! ctx, prop_not({inner}))")
        return v
    if k in _CONN:
        if not isinstance(val, list) or len(val) != 2:
            raise HTTPException(422, f"{k} needs exactly 2 operands")
        lft = _compile_prop(val[0], atoms, lines, ctr)
        rgt = _compile_prop(val[1], atoms, lines, ctr)
        v = f"e{ctr[0]}"; ctr[0] += 1
        lines.append(f"    let {v} = ctx_prop(&! ctx, {_CONN[k]}({lft}, {rgt}))")
        return v
    raise HTTPException(422, f"bad connective: {k}")


class TheoremReq(BaseModel):
    atoms: list[str]
    hypotheses: list[dict] = []
    goal: dict
    depth: int = 6


@app.post("/v1/theorem/prove")
def theorem_prove(req: TheoremReq):
    if not (1 <= len(req.atoms) <= 32):
        raise HTTPException(422, "1..32 atoms")
    atoms = {n: i + 1 for i, n in enumerate(req.atoms)}
    lines, ctr = [], [0]
    hyp_vars = [_compile_prop(h, atoms, lines, ctr) for h in req.hypotheses]
    asserts = "\n".join(f"    assume(&! ctx, {i + 1}, {v})" for i, v in enumerate(hyp_vars))
    goal_var = _compile_prop(req.goal, atoms, lines, ctr)
    depth = max(1, min(int(req.depth), 64))
    src = (
        "use theorem::search::{proof_context_new, ctx_prop, ctx_get_proof, prop_custom, "
        "prop_and, prop_or, prop_not, prop_implies, assume, auto_prove, verify}\n"
        "fn main() -> i64 with IO, Mut, Div, Panic {\n"
        "    var ctx = proof_context_new()\n"
        + "\n".join(lines) + "\n" + asserts + "\n"
        f"    let prf = auto_prove(&! ctx, {goal_var}, {depth})\n"
        '    if prf < 0 { println("UNKNOWN"); println("0.0"); return 0 }\n'
        "    let pr = ctx_get_proof(&ctx, prf)\n"
        '    if pr.tag == 22 { println("UNKNOWN"); println("0.0"); return 0 }\n'
        "    let v = verify(&ctx, prf)\n"
        '    if v.is_valid { println("PROVED") } else { println("INVALID") }\n'
        "    println(pr.confidence)\n"
        "    return 0\n}\n"
    )
    toks = _compile_and_run(src).split()
    verdict = next((t for t in toks if t in ("PROVED", "UNKNOWN", "INVALID")), None)
    conf = next((t for t in toks if t.replace(".", "", 1).replace("-", "", 1).isdigit()), None)
    if not verdict:
        raise HTTPException(502, "no verdict from theorem.prove")
    return {
        "verb": "theorem.prove", "result": verdict,
        "confidence": float(conf) if conf is not None else None,
        "logic": "propositional natural deduction (sound: real derivation only)",
        "meaning": {
            "PROVED": "goal DERIVED from hypotheses (real proof tree)",
            "UNKNOWN": "no derivation found (NOT a refutation)",
            "INVALID": "proof failed verification",
        }[verdict],
        "engine": "sounio::theorem::search (auto_prove + verify)",
    }


# ───────────────────────── fractal.recurse ─────────────────────────
# Deterministic fractal-tree growth in pure Sounio (replaces the dead Julia
# Fractal.jl grow_fractal! shell-out — Julia is not in the deployed image).
# Budget-bounded breadth-first growth: node_count = Σ branching^i for i in 0..depth,
# capped at `budget`; max_depth is the deepest level actually grown within budget.
FRACTAL_SIO_TEMPLATE = r'''fn main() -> i64 with IO, Mut, Div {
    let max_depth: i64 = __DEPTH__
    let branching: i64 = __BRANCH__
    let budget: i64 = __BUDGET__
    var node_count: i64 = 0
    var level_size: i64 = 1
    var depth_reached: i64 = 0
    var level: i64 = 0
    var stop: i64 = 0
    while level <= max_depth && stop == 0 {
        if node_count + level_size > budget {
            node_count = budget
            depth_reached = level
            stop = 1
        } else {
            node_count = node_count + level_size
            depth_reached = level
            level_size = level_size * branching
            level = level + 1
        }
    }
    println(node_count); println(",")
    println(depth_reached); println(",")
    0
}
'''


class FractalRecurseReq(BaseModel):
    depth: int = Field(5, ge=1, le=16)
    branching: int = Field(2, ge=2, le=8)
    budget: int = Field(10000, ge=1, le=1_000_000)
    seed: float = 1.0


@app.post("/v1/fractal/recurse")
def fractal_recurse(req: FractalRecurseReq):
    src = (
        FRACTAL_SIO_TEMPLATE
        .replace("__DEPTH__", str(_int(req.depth)))
        .replace("__BRANCH__", str(_int(req.branching)))
        .replace("__BUDGET__", str(_int(req.budget)))
    )
    toks = [t for t in _compile_and_run(src).replace("\n", "").split(",") if t.strip()]
    try:
        node_count, max_depth_reached = (int(t) for t in toks[:2])
    except ValueError:
        raise HTTPException(502, f"could not parse fractal output: {toks[:2]}")
    return {
        "verb": "fractal.recurse",
        "depth_requested": req.depth, "branching": req.branching, "budget": req.budget,
        "seed": req.seed,
        "node_count": node_count, "max_depth": max_depth_reached,
        "truncated": node_count >= req.budget,
        "engine": "sounio (deterministic budget-bounded fractal-tree growth)",
    }


# ───────────────────────── phi.compute ─────────────────────────
# IIT-4 integrated information Φ + minimum-information-partition (MIP) in pure
# Sounio. Ports the beagle-transcend IIT4Calculator bipartition-MIP method: over
# all non-trivial bipartitions of an n-node substrate (connectivity matrix W,
# row-major, weights >= 0), Φ is the minimum normalized cross-partition weight
# (information lost by the best cut); the MIP is the cut achieving it. Φ≈0 ⇒
# substrate decomposable (not integrated); Φ>0 ⇒ irreducible integration.
# Exhaustive over all 2^n bipartitions (n<=8 request cap → <=256 partitions).
PHI_SIO_TEMPLATE = r'''fn main() -> i64 with IO, Mut, Div {
    let n: i64 = __N__
    var w: [f64; 64] = [0.0; 64]
__WEIGHTS__
    var pow2n: i64 = 1
    var t: i64 = 0
    while t < n { pow2n = pow2n * 2; t = t + 1 }
    var best_phi: f64 = 1.0e18
    var best_mask: i64 = 0
    var mask: i64 = 1
    while mask < pow2n - 1 {
        var cross: f64 = 0.0
        var size1: i64 = 0
        var i: i64 = 0
        while i < n {
            var pi: i64 = mask
            var ki: i64 = 0
            while ki < i { pi = pi / 2; ki = ki + 1 }
            let mi: i64 = pi % 2
            if mi == 1 { size1 = size1 + 1 }
            var j: i64 = 0
            while j < n {
                var pj: i64 = mask
                var kj: i64 = 0
                while kj < j { pj = pj / 2; kj = kj + 1 }
                let mj: i64 = pj % 2
                if mi == 1 && mj == 0 {
                    cross = cross + w[i*n+j] + w[j*n+i]
                }
                j = j + 1
            }
            i = i + 1
        }
        let size2: i64 = n - size1
        var minsz: i64 = size1
        if size2 < size1 { minsz = size2 }
        if minsz > 0 {
            let norm: f64 = cross / (minsz as f64)
            if norm < best_phi { best_phi = norm; best_mask = mask }
        }
        mask = mask + 1
    }
    println(best_phi); println(",")
    println(best_mask); println(",")
    0
}
'''


class PhiComputeReq(BaseModel):
    n: int = Field(..., ge=2, le=8)
    matrix: list[float] = Field(..., description="row-major n*n connectivity, weights >= 0")


@app.post("/v1/phi/compute")
def phi_compute(req: PhiComputeReq):
    n = _int(req.n)
    if len(req.matrix) != n * n:
        raise HTTPException(422, f"matrix must have exactly n*n={n * n} entries")
    weights = []
    for idx, v in enumerate(req.matrix):
        fv = _num(v)
        if fv != 0.0:
            weights.append(f"    w[{idx}] = {fv!r}")
    src = (
        PHI_SIO_TEMPLATE
        .replace("__N__", str(n))
        .replace("__WEIGHTS__", "\n".join(weights))
    )
    toks = [t for t in _compile_and_run(src).replace("\n", "").split(",") if t.strip()]
    try:
        phi = float(toks[0])
        mask = int(toks[1])
    except (ValueError, IndexError):
        raise HTTPException(502, f"could not parse phi output: {toks[:2]}")
    part1 = [i for i in range(n) if (mask >> i) & 1]
    part2 = [i for i in range(n) if not ((mask >> i) & 1)]
    return {
        "verb": "phi.compute",
        "n": n, "phi": phi,
        "mip_partition": [part1, part2],
        "integrated": phi > 0.0,
        "meaning": "irreducible integration (Φ>0)" if phi > 0.0
        else "substrate decomposable — not integrated (Φ=0)",
        "engine": "sounio (IIT-4 bipartition-MIP; ported from beagle-transcend IIT4Calculator)",
    }


@app.get("/v1/catalog")
def catalog():
    return {"verbs": [
        {"verb": "smt.check", "path": "/v1/smt/check", "nature": "logical decision (SAT/UNSAT)"},
        {"verb": "gum.propagate", "path": "/v1/gum/propagate", "nature": "numeric uncertainty propagation"},
        {"verb": "causal.dsep", "path": "/v1/causal/dsep", "nature": "structural graph reasoning"},
        {"verb": "pcs.reason", "path": "/v1/pcs/reason", "nature": "symptom ODE dynamics (Sounio RK4)"},
        {"verb": "theorem.prove", "path": "/v1/theorem/prove", "nature": "propositional proof (natural deduction)"},
        {"verb": "fractal.recurse", "path": "/v1/fractal/recurse", "nature": "deterministic fractal-tree growth (Sounio)"},
        {"verb": "phi.compute", "path": "/v1/phi/compute", "nature": "IIT-4 integrated information Φ + MIP (Sounio)"},
    ]}


@app.get("/health")
def health():
    ok = os.path.exists(SOUC_BIN) and os.path.isdir(STDLIB)
    return {"status": "ok" if ok else "degraded", "souc": SOUC_BIN, "stdlib": STDLIB,
            "cache_dir": CACHE_DIR}
