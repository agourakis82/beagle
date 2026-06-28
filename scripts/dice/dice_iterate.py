#!/usr/bin/env python3
"""
DICE Task 4 — Implicit reward scoring + synthetic preference pair generation.

Implements the DICE iterative loop (ICLR 2025):
  β * log[π_θ(y|x) / π_ref(y|x)]

Where:
  π_θ = current round's DPO-trained model (LoRA adapter merged over base)
  π_ref = base model (Qwen2.5-7B-Instruct)
  β = DPO beta (0.1, matching axolotl config)

For each prompt in the candidate pool, generates N completions from π_θ,
scores each with the implicit reward, and writes chosen/rejected pairs
for the next DPO round.

Usage:
  python3 dice_iterate.py --round 1 [--candidates 200] [--n-completions 4] [--dry-run]

Requires:
  - BEAGLE_DATA_DIR set
  - vLLM serving the current-round adapter at DICE_MODEL_URL (default: Qwen2.5-7B base)
  - DICE_REF_URL for the reference model (default: same as base, no adapter)
"""

import argparse
import json
import math
import os
import sys
from pathlib import Path

import requests


BETA = 0.1  # Must match dpo_beta in axolotl config


def log_prob(model_url: str, prompt: str, completion: str) -> float:
    """Approximate log P(completion | prompt) via OpenAI-compat echo endpoint."""
    payload = {
        "model": "qwen25-7b",
        "prompt": f"{prompt}\n{completion}",
        "max_tokens": 0,
        "echo": True,
        "logprobs": 1,
    }
    try:
        r = requests.post(f"{model_url}/v1/completions", json=payload, timeout=30)
        r.raise_for_status()
        data = r.json()
        logprobs = data["choices"][0]["logprobs"]["token_logprobs"]
        # Sum logprobs for the completion tokens only (skip prompt prefix)
        prompt_tokens = len(data["choices"][0]["logprobs"]["tokens"]) - len(completion.split())
        return float(sum(logprobs[max(0, prompt_tokens):]))
    except Exception as e:
        print(f"[dice] log_prob failed: {e}", file=sys.stderr)
        return float("-inf")


def implicit_reward(
    policy_url: str,
    ref_url: str,
    prompt: str,
    completion: str,
) -> float:
    lp_policy = log_prob(policy_url, prompt, completion)
    lp_ref = log_prob(ref_url, prompt, completion)
    if math.isinf(lp_policy) or math.isinf(lp_ref):
        return float("-inf")
    return BETA * (lp_policy - lp_ref)


def generate(model_url: str, prompt: str, n: int = 4, max_tokens: int = 512) -> list[str]:
    """Generate n completions from the policy model."""
    payload = {
        "model": "qwen25-7b",
        "messages": [{"role": "user", "content": prompt}],
        "n": n,
        "max_tokens": max_tokens,
        "temperature": 0.8,
    }
    try:
        r = requests.post(f"{model_url}/v1/chat/completions", json=payload, timeout=60)
        r.raise_for_status()
        return [c["message"]["content"] for c in r.json()["choices"]]
    except Exception as e:
        print(f"[dice] generate failed: {e}", file=sys.stderr)
        return []


def load_candidate_prompts(data_dir: Path, round_n: int) -> list[str]:
    """Load prompts from previous round pairs + exocortex feedback."""
    prompts = set()
    # From previous round pairs
    prev_pairs = data_dir / "dice" / f"preference_pairs_round{round_n - 1}.jsonl"
    if prev_pairs.exists():
        with open(prev_pairs) as f:
            for line in f:
                d = json.loads(line)
                for turn in d.get("conversations", []):
                    if turn.get("from") == "human":
                        prompts.add(turn["value"])
    # From beagle feedback prompts
    feedback_dir = data_dir / "feedback"
    if feedback_dir.exists():
        for p in feedback_dir.glob("*.jsonl"):
            with open(p) as f:
                for line in f:
                    d = json.loads(line.strip() or "{}")
                    prompt = d.get("prompt") or d.get("user_text", "")
                    if prompt:
                        prompts.add(prompt)
    return list(prompts)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--round", type=int, required=True, help="Current iteration round (1-based)")
    parser.add_argument("--candidates", type=int, default=200, help="Max prompts to score")
    parser.add_argument("--n-completions", type=int, default=4, help="Completions per prompt")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    data_dir = Path(os.environ.get("BEAGLE_DATA_DIR", os.path.expanduser("~/beagle-data")))
    policy_url = os.environ.get("DICE_MODEL_URL", "http://vllm.vllm-test.svc:8000")
    ref_url = os.environ.get("DICE_REF_URL", policy_url)

    prompts = load_candidate_prompts(data_dir, args.round)
    prompts = prompts[: args.candidates]
    print(f"[dice] round {args.round} — scoring {len(prompts)} prompts ({args.n_completions} completions each)")

    pairs = []
    for i, prompt in enumerate(prompts):
        completions = generate(policy_url, prompt, n=args.n_completions)
        if len(completions) < 2:
            continue
        scored = []
        for c in completions:
            r = implicit_reward(policy_url, ref_url, prompt, c)
            scored.append((r, c))
        scored.sort(key=lambda x: x[0], reverse=True)
        chosen_reward, chosen = scored[0]
        rejected_reward, rejected = scored[-1]
        if chosen_reward <= rejected_reward:
            continue
        pairs.append({
            "conversations": [{"from": "human", "value": prompt}],
            "chosen": [{"from": "gpt", "value": chosen}],
            "rejected": [{"from": "gpt", "value": rejected}],
            "source": f"dice-implicit-round{args.round}",
            "chosen_reward": chosen_reward,
            "rejected_reward": rejected_reward,
        })
        if (i + 1) % 20 == 0:
            print(f"[dice]   {i + 1}/{len(prompts)} prompts done, {len(pairs)} pairs so far")

    print(f"[dice] Generated {len(pairs)} synthetic pairs for round {args.round}")

    if args.dry_run:
        print("[dice] Dry run — not writing")
        return

    out_dir = data_dir / "dice"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"preference_pairs_round{args.round}.jsonl"
    with open(out_path, "w") as f:
        for p in pairs:
            f.write(json.dumps(p, ensure_ascii=False) + "\n")
    print(f"[dice] Wrote {len(pairs)} pairs → {out_path}")


if __name__ == "__main__":
    main()
