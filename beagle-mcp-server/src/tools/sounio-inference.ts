/**
 * Sounio Inference Service — MCP tools
 *
 * Exposes the 5 verified-inference verbs from the Sounio Inference Service as
 * structured MCP tools. Each tool POSTs typed numeric/logical data (never prose)
 * to the in-cluster FastAPI service and returns the solver verdict.
 *
 * Base URL is configurable via SOUNIO_INFERENCE_URL; default: in-cluster svc.
 */

import { z } from "zod";
import { McpTool } from "./index.js";
import { sanitizeOutput } from "../security.js";
import { logger } from "../logger.js";

function inferenceBaseUrl(): string {
    return (
        process.env.SOUNIO_INFERENCE_URL ||
        "http://sounio-inference.beagle.svc.cluster.local:80"
    );
}

async function inferencePost(path: string, body: unknown): Promise<unknown> {
    const url = `${inferenceBaseUrl()}${path}`;
    const res = await fetch(url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
    });
    if (!res.ok) {
        const text = await res.text().catch(() => "(no body)");
        throw new Error(`Sounio Inference ${path} → HTTP ${res.status}: ${text.slice(0, 400)}`);
    }
    return res.json();
}

// ──────────────────────── smt.check ────────────────────────

const LiaConstraintSchema = z.object({
    coeffs: z
        .array(z.number().int())
        .min(1)
        .max(16)
        .describe("Coefficients [c0, c1, …] such that Σ coeffs[i]·x_i ≤ bound"),
    bound: z.number().int().describe("RHS integer bound"),
    label: z.string().optional().describe("Human-readable name for this constraint"),
});

const SmtCheckSchema = z.object({
    constraints: z
        .array(LiaConstraintSchema)
        .min(1)
        .max(64)
        .describe("Set of QF_LIA linear-arithmetic constraints to check for consistency"),
});

// ──────────────────────── gum.propagate ────────────────────────

const GumInputSchema = z.object({
    value: z.number().describe("Measured value"),
    u: z.number().describe("Standard uncertainty (1σ)"),
    label: z.string().optional().describe("Optional label for this input"),
});

const GumPropagateSchema = z.object({
    op: z
        .enum(["add", "sub", "mul", "div"])
        .describe("Binary arithmetic operation to apply: add | sub | mul | div"),
    inputs: z
        .tuple([GumInputSchema, GumInputSchema])
        .describe("Exactly two GUM measurement inputs [a, b] — the operation is applied as a op b"),
});

// ──────────────────────── causal.dsep ────────────────────────

const DsepSchema = z.object({
    n: z.number().int().min(1).max(32).describe("Number of nodes in the DAG (0-indexed)"),
    edges: z
        .array(z.tuple([z.number().int(), z.number().int()]))
        .describe("Directed edges [[from, to], …]"),
    x: z.number().int().describe("Source node index"),
    y: z.number().int().describe("Target node index"),
    z: z
        .array(z.number().int())
        .max(32)
        .default([])
        .describe("Conditioning set (node indices); empty = marginal independence"),
});

// ──────────────────────── pcs.reason ────────────────────────

const PcsReasonSchema = z.object({
    symptoms: z
        .object({
            depression: z.number().min(0).max(1).default(0.5),
            anxiety: z.number().min(0).max(1).default(0.5),
            stress: z.number().min(0).max(1).default(0.5),
            sleep: z.number().min(0).max(1).default(0.7),
        })
        .describe(
            "Initial symptom levels (0.0–1.0). The service integrates a 4-state ODE (RK4, t=0..10) and returns final state + severity.",
        ),
});

// ──────────────────────── theorem.prove ────────────────────────

// Recursive expression type is defined at the tool level only (JSON Schema),
// because Zod cannot express recursive schemas simply without z.lazy.
// We do a lightweight structural check in the handler instead.
const TheoremProveSchema = z.object({
    atoms: z
        .array(z.string())
        .min(1)
        .max(32)
        .describe("Propositional variable names, e.g. [\"P\", \"Q\", \"R\"]"),
    hypotheses: z
        .array(z.record(z.unknown()))
        .default([])
        .describe(
            'List of proposition expressions assumed as hypotheses. Each expression is a single-key object: {"atom":"P"}, {"not": <expr>}, {"and":[<e1>,<e2>]}, {"or":[<e1>,<e2>]}, {"implies":[<e1>,<e2>]}.',
        ),
    goal: z
        .record(z.unknown())
        .describe("The proposition expression to prove from the hypotheses."),
    depth: z
        .number()
        .int()
        .min(1)
        .max(64)
        .default(6)
        .describe("Proof search depth (1–64; default 6; increase for complex goals)"),
});

// ──────────────────────── tool definitions ────────────────────────

export function sounioInferenceTools(): McpTool[] {
    return [
        {
            name: "sounio_smt_check",
            description: `Check consistency of a set of linear arithmetic constraints (QF_LIA) using Sounio's DPLL(T) SMT solver.

Returns SAT (constraints are mutually consistent), UNSAT (provably contradictory), or UNKNOWN.

Each constraint encodes: Σ coeffs[i]·x_i ≤ bound (up to 16 variables per constraint, up to 64 constraints total).

Use this to detect logical contradictions in numeric claims — e.g. when a research draft states two bounds that cannot both hold.`,
            inputSchema: {
                type: "object",
                properties: {
                    constraints: {
                        type: "array",
                        minItems: 1,
                        maxItems: 64,
                        items: {
                            type: "object",
                            properties: {
                                coeffs: {
                                    type: "array",
                                    minItems: 1,
                                    maxItems: 16,
                                    items: { type: "integer" },
                                    description: "Coefficients [c0,c1,…] so that Σ coeffs[i]·x_i ≤ bound",
                                },
                                bound: { type: "integer", description: "RHS integer bound" },
                                label: {
                                    type: "string",
                                    description: "Optional human-readable constraint name",
                                },
                            },
                            required: ["coeffs", "bound"],
                        },
                        description: "QF_LIA constraints to check for consistency",
                    },
                },
                required: ["constraints"],
            },
            handler: async (args: unknown) => {
                const parsed = SmtCheckSchema.parse(args);
                logger.info("sounio_smt_check called", {
                    n_constraints: parsed.constraints.length,
                });
                const result = await inferencePost("/v1/smt/check", parsed);
                return sanitizeOutput(result);
            },
        },

        {
            name: "sounio_gum_propagate",
            description: `Propagate measurement uncertainty through a binary arithmetic operation using the GUM (JCGM 100) framework via Sounio's epistemic::gum stdlib.

Returns: combined value, combined standard uncertainty, degrees of freedom, coverage factor k95, expanded uncertainty U95, relative uncertainty %, and 95% confidence interval [lo, hi].

op must be one of: add | sub | mul | div
inputs must be exactly two GUM measurements {value, u} where u is the standard (1σ) uncertainty.`,
            inputSchema: {
                type: "object",
                properties: {
                    op: {
                        type: "string",
                        enum: ["add", "sub", "mul", "div"],
                        description: "Binary arithmetic operation: add | sub | mul | div",
                    },
                    inputs: {
                        type: "array",
                        minItems: 2,
                        maxItems: 2,
                        items: {
                            type: "object",
                            properties: {
                                value: { type: "number", description: "Measured value" },
                                u: {
                                    type: "number",
                                    description: "Standard uncertainty (1σ)",
                                },
                                label: { type: "string", description: "Optional label" },
                            },
                            required: ["value", "u"],
                        },
                        description: "Two measurement inputs [a, b]; operation applied as a op b",
                    },
                },
                required: ["op", "inputs"],
            },
            handler: async (args: unknown) => {
                const parsed = GumPropagateSchema.parse(args);
                logger.info("sounio_gum_propagate called", { op: parsed.op });
                const result = await inferencePost("/v1/gum/propagate", {
                    op: parsed.op,
                    inputs: parsed.inputs,
                });
                return sanitizeOutput(result);
            },
        },

        {
            name: "sounio_causal_dsep",
            description: `Test d-separation (conditional independence) between two nodes in a DAG using Sounio's causal::base Pearl Bayes-ball algorithm.

Returns d_separated: true means x ⊥ y | z (independent given the conditioning set z), false means d-connected (a dependence path is open).

Graph: specify the number of nodes n (0-indexed), directed edges as [[from, to], …], and the conditioning set z (may be empty for marginal independence).

Constraints: n ≤ 32 nodes, |z| ≤ 32.`,
            inputSchema: {
                type: "object",
                properties: {
                    n: {
                        type: "integer",
                        minimum: 1,
                        maximum: 32,
                        description: "Number of nodes (0-indexed)",
                    },
                    edges: {
                        type: "array",
                        items: {
                            type: "array",
                            items: { type: "integer" },
                            minItems: 2,
                            maxItems: 2,
                        },
                        description: "Directed edges [[from, to], …]",
                    },
                    x: { type: "integer", description: "Source node index" },
                    y: { type: "integer", description: "Target node index" },
                    z: {
                        type: "array",
                        items: { type: "integer" },
                        maxItems: 32,
                        default: [],
                        description:
                            "Conditioning set (node indices); [] = marginal independence test",
                    },
                },
                required: ["n", "edges", "x", "y"],
            },
            handler: async (args: unknown) => {
                const parsed = DsepSchema.parse(args);
                logger.info("sounio_causal_dsep called", {
                    n: parsed.n,
                    n_edges: parsed.edges.length,
                    x: parsed.x,
                    y: parsed.y,
                    z_size: parsed.z.length,
                });
                const result = await inferencePost("/v1/causal/dsep", parsed);
                return sanitizeOutput(result);
            },
        },

        {
            name: "sounio_pcs_reason",
            description: `Run the PCS (Precision Computational Psychiatry Sounio) ODE solver on a 4-dimensional symptom state.

Integrates the psychiatry ODE system (depression, anxiety, stress, sleep) from t=0 to t=10 using Sounio's RK4 solver and returns the final state + severity score.

Each symptom is a float in [0, 1]. Defaults: depression=0.5, anxiety=0.5, stress=0.5, sleep=0.7.

Returns: final_state {depression, anxiety, stress, sleep}, severity_score (mean of dep+anx+stress at t=10).`,
            inputSchema: {
                type: "object",
                properties: {
                    symptoms: {
                        type: "object",
                        properties: {
                            depression: {
                                type: "number",
                                minimum: 0,
                                maximum: 1,
                                default: 0.5,
                            },
                            anxiety: { type: "number", minimum: 0, maximum: 1, default: 0.5 },
                            stress: { type: "number", minimum: 0, maximum: 1, default: 0.5 },
                            sleep: { type: "number", minimum: 0, maximum: 1, default: 0.7 },
                        },
                        description: "Initial symptom levels (0.0–1.0)",
                    },
                },
                required: ["symptoms"],
            },
            handler: async (args: unknown) => {
                const parsed = PcsReasonSchema.parse(args);
                logger.info("sounio_pcs_reason called", { symptoms: parsed.symptoms });
                const result = await inferencePost("/v1/pcs/reason", parsed);
                return sanitizeOutput(result);
            },
        },

        {
            name: "sounio_theorem_prove",
            description: `Attempt to prove a propositional logic goal from hypotheses using Sounio's natural-deduction theorem prover (theorem::search, auto_prove + verify).

SOUND: only a genuine proof derivation returns PROVED — the truth-table/trusted fallback is rejected to UNKNOWN. Arithmetic is not supported.

Atoms: list of propositional variable names (up to 32).
Expressions: single-key objects — {"atom":"P"}, {"not":<expr>}, {"and":[<e1>,<e2>]}, {"or":[<e1>,<e2>]}, {"implies":[<e1>,<e2>]}.

Returns: result (PROVED | UNKNOWN | INVALID), confidence, and plain-language meaning.`,
            inputSchema: {
                type: "object",
                properties: {
                    atoms: {
                        type: "array",
                        minItems: 1,
                        maxItems: 32,
                        items: { type: "string" },
                        description: 'Propositional variable names, e.g. ["P", "Q", "R"]',
                    },
                    hypotheses: {
                        type: "array",
                        items: { type: "object" },
                        default: [],
                        description:
                            'Propositions assumed as hypotheses. Each is a single-key expression object: {"atom":"P"}, {"not":<expr>}, {"and":[<e1>,<e2>]}, {"or":[<e1>,<e2>]}, {"implies":[<e1>,<e2>]}.',
                    },
                    goal: {
                        type: "object",
                        description: "The proposition to prove from the hypotheses.",
                    },
                    depth: {
                        type: "integer",
                        minimum: 1,
                        maximum: 64,
                        default: 6,
                        description: "Proof search depth (default 6; increase for complex goals)",
                    },
                },
                required: ["atoms", "goal"],
            },
            handler: async (args: unknown) => {
                const parsed = TheoremProveSchema.parse(args);
                logger.info("sounio_theorem_prove called", {
                    n_atoms: parsed.atoms.length,
                    n_hypotheses: parsed.hypotheses.length,
                    depth: parsed.depth,
                });
                const result = await inferencePost("/v1/theorem/prove", parsed);
                return sanitizeOutput(result);
            },
        },
    ];
}
