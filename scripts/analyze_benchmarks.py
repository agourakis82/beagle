#!/usr/bin/env python3
import json
import sys
from pathlib import Path

def load_benchmark_data(bench_name: str):
    base_path = Path("target/criterion") / bench_name
    estimates_path = base_path / "base" / "estimates.json"
    if not estimates_path.exists():
        return None
    with open(estimates_path) as f:
        data = json.load(f)
    mean_ns = data["mean"]["point_estimate"]
    mean_ms = mean_ns / 1_000_000.0
    return {
        "name": bench_name,
        "mean_ms": mean_ms,
        "throughput_rps": 1000.0 / mean_ms if mean_ms > 0 else 0.0,
    }

def main():
    grpc_data = load_benchmark_data("grpc_dispatch_task")
    rest_data = load_benchmark_data("rest_dispatch_task")
    if not grpc_data or not rest_data:
        print("Error: Benchmark data not found. Run benchmarks first.")
        sys.exit(1)

    print("\n=== BENCHMARK COMPARISON ===\n")
    print(f"gRPC Latency (mean): {grpc_data['mean_ms']:.2f}ms")
    print(f"REST Latency (mean): {rest_data['mean_ms']:.2f}ms")

    speedup = rest_data["mean_ms"] / grpc_data["mean_ms"]
    print(f"\nSpeedup: {speedup:.2f}x faster\n")

    print(f"gRPC Throughput: {grpc_data['throughput_rps']:.0f} req/s")
    print(f"REST Throughput: {rest_data['throughput_rps']:.0f} req/s")

    print("\n=== TARGET VALIDATION ===\n")
    grpc_target_met = grpc_data["mean_ms"] < 50.0
    rest_target_met = rest_data["mean_ms"] < 200.0
    print(f"gRPC latency < 50ms: {'✅ PASS' if grpc_target_met else '❌ FAIL'}")
    print(f"REST latency < 200ms: {'✅ PASS' if rest_target_met else '❌ FAIL'}")

    if grpc_target_met and speedup > 2.0:
        print("\n✅ gRPC port is JUSTIFIED (>2x speedup + <50ms latency)")
    else:
        print("\n⚠️ gRPC benefits are MARGINAL (consider REST only)")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Generalized analyzer for Criterion benchmarks (gRPC vs REST and others).

Features:
- Parametrizable list of benchmarks
- Statistics: mean, median, p95, 95% CI, std dev
- Throughput estimation (req/s from mean latency)
- Speedup vs reference benchmark
- Targets validation per benchmark
- Outputs: console, Markdown, CSV, JSON
"""

import argparse
import csv
import json
import sys
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any


CRITERION_ROOT = Path("target") / "criterion"


@dataclass
class BenchmarkStats:
    name: str
    status: str  # "ok" | "missing" | "error"
    # nanos (native)
    mean_ns: Optional[float] = None
    median_ns: Optional[float] = None
    stddev_ns: Optional[float] = None
    ci95_low_ns: Optional[float] = None
    ci95_high_ns: Optional[float] = None
    p95_ns: Optional[float] = None
    # derived (ms)
    mean_ms: Optional[float] = None
    median_ms: Optional[float] = None
    stddev_ms: Optional[float] = None
    ci95_low_ms: Optional[float] = None
    ci95_high_ms: Optional[float] = None
    p95_ms: Optional[float] = None
    throughput_rps: Optional[float] = None
    speedup_vs_ref: Optional[float] = None
    # targets
    target_ms: Optional[float] = None
    target_met: Optional[bool] = None
    # diagnostics
    error_message: Optional[str] = None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Analyze Criterion benchmarks and emit console, Markdown, CSV, and JSON outputs."
    )
    parser.add_argument(
        "--benches",
        nargs="*",
        help="List of benchmark names under target/criterion. Defaults to grpc_dispatch_task rest_dispatch_task.",
        default=["grpc_dispatch_task", "rest_dispatch_task"],
    )
    parser.add_argument(
        "--ref",
        help="Reference benchmark name for speedup (default: first in --benches).",
        default=None,
    )
    parser.add_argument(
        "--out-dir",
        help="Output directory for reports.",
        default="bench_reports",
    )
    parser.add_argument(
        "--targets",
        help='Targets as JSON string or comma-separated pairs name:limit_ms. Example: \'{"grpc_dispatch_task":50,"rest_dispatch_task":200}\' or grpc_dispatch_task:50,rest_dispatch_task:200',
        default=None,
    )
    parser.add_argument(
        "--unit",
        choices=["ms", "us", "ns"],
        default="ms",
        help="Human-readable unit for console/markdown/csv output (internal is ns).",
    )
    return parser.parse_args()


def parse_targets_arg(arg: Optional[str]) -> Dict[str, float]:
    if not arg:
        return {"grpc_dispatch_task": 50.0, "rest_dispatch_task": 200.0}
    # Try JSON first
    try:
        parsed = json.loads(arg)
        if isinstance(parsed, dict):
            return {str(k): float(v) for k, v in parsed.items()}
    except json.JSONDecodeError:
        pass
    # Fallback: comma-separated name:limit_ms
    targets: Dict[str, float] = {}
    for pair in arg.split(","):
        pair = pair.strip()
        if not pair:
            continue
        if ":" not in pair:
            continue
        name, limit = pair.split(":", 1)
        try:
            targets[name.strip()] = float(limit.strip())
        except ValueError:
            continue
    return targets


def ns_to_unit(value_ns: Optional[float], unit: str) -> Optional[float]:
    if value_ns is None:
        return None
    if unit == "ns":
        return value_ns
    if unit == "us":
        return value_ns / 1_000.0
    # default ms
    return value_ns / 1_000_000.0


def _read_json(path: Path) -> Optional[Dict[str, Any]]:
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return None


def _read_raw_csv_samples(path: Path) -> Optional[List[float]]:
    """
    Attempt to read Criterion raw samples from CSV.
    Common formats:
      - header with columns, often includes "sample" or time column; we attempt to read last column as nanos.
    Returns list of sample durations in ns if possible.
    """
    try:
        with open(path, "r", newline="") as f:
            reader = csv.reader(f)
            rows = list(reader)
        if not rows:
            return None
        # Detect header
        header = rows[0]
        start_idx = 1 if any(cell.isalpha() for cell in header) else 0
        samples: List[float] = []
        for row in rows[start_idx:]:
            if not row:
                continue
            # take last column as ns if numeric
            try:
                val = float(row[-1])
            except ValueError:
                continue
            samples.append(val)
        return samples if samples else None
    except Exception:
        return None


def _read_sample_json(path: Path) -> Optional[List[float]]:
    """
    Read Criterion sample.json if present.
    Expect a list of numbers (nanoseconds).
    """
    data = _read_json(path)
    if data is None:
        return None
    if isinstance(data, list) and all(isinstance(x, (int, float)) for x in data):
        return [float(x) for x in data]
    # Some Criterion versions store under key "estimate" or "iters"; we will try common keys
    for key in ("samples", "data", "values"):
        if key in data and isinstance(data[key], list):
            try:
                return [float(x) for x in data[key]]
            except Exception:
                continue
    return None


def percentile(values: List[float], p: float) -> float:
    if not values:
        raise ValueError("Empty values for percentile")
    if p <= 0:
        return min(values)
    if p >= 100:
        return max(values)
    sorted_vals = sorted(values)
    k = (len(sorted_vals) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(sorted_vals) - 1)
    if f == c:
        return sorted_vals[f]
    d0 = sorted_vals[f] * (c - k)
    d1 = sorted_vals[c] * (k - f)
    return d0 + d1


def load_benchmark(bench_name: str) -> BenchmarkStats:
    base = CRITERION_ROOT / bench_name / "base"
    estimates_path = base / "estimates.json"
    if not estimates_path.exists():
        return BenchmarkStats(name=bench_name, status="missing")

    try:
        estimates = _read_json(estimates_path)
        if not estimates:
            return BenchmarkStats(name=bench_name, status="error", error_message="Failed to parse estimates.json")

        mean_ns = float(estimates["mean"]["point_estimate"])
        median_ns = float(estimates.get("median", {}).get("point_estimate", mean_ns))
        stddev_ns = float(estimates.get("std_dev", {}).get("point_estimate", 0.0))
        ci = estimates.get("mean", {}).get("confidence_interval", {})
        ci_low_ns = float(ci.get("lower_bound")) if "lower_bound" in ci else None
        ci_high_ns = float(ci.get("upper_bound")) if "upper_bound" in ci else None

        # p95 from raw samples if available; else normal approx
        raw_samples: Optional[List[float]] = None
        raw_csv = base / "raw.csv"
        sample_json = base / "sample.json"
        if raw_csv.exists():
            raw_samples = _read_raw_csv_samples(raw_csv)
        if raw_samples is None and sample_json.exists():
            raw_samples = _read_sample_json(sample_json)
        if raw_samples:
            p95_ns = percentile(raw_samples, 95.0)
        else:
            p95_ns = mean_ns + 1.645 * stddev_ns

        stats = BenchmarkStats(
            name=bench_name,
            status="ok",
            mean_ns=mean_ns,
            median_ns=median_ns,
            stddev_ns=stddev_ns,
            ci95_low_ns=ci_low_ns,
            ci95_high_ns=ci_high_ns,
            p95_ns=p95_ns,
        )

        # Derived (ms)
        stats.mean_ms = ns_to_unit(mean_ns, "ms")
        stats.median_ms = ns_to_unit(median_ns, "ms")
        stats.stddev_ms = ns_to_unit(stddev_ns, "ms")
        stats.ci95_low_ms = ns_to_unit(ci_low_ns, "ms") if ci_low_ns is not None else None
        stats.ci95_high_ms = ns_to_unit(ci_high_ns, "ms") if ci_high_ns is not None else None
        stats.p95_ms = ns_to_unit(p95_ns, "ms")
        if stats.mean_ms and stats.mean_ms > 0:
            stats.throughput_rps = 1000.0 / stats.mean_ms
        else:
            stats.throughput_rps = None
        return stats
    except Exception as e:
        return BenchmarkStats(name=bench_name, status="error", error_message=str(e))


def compute_speedups_and_targets(
    results: List[BenchmarkStats],
    ref_name: str,
    targets_ms: Dict[str, float],
) -> None:
    ref = next((r for r in results if r.name == ref_name and r.status == "ok" and r.mean_ms), None)
    ref_mean_ms = ref.mean_ms if ref else None
    for r in results:
        if r.status == "ok" and r.mean_ms and ref_mean_ms and r.mean_ms > 0:
            r.speedup_vs_ref = ref_mean_ms / r.mean_ms
        else:
            r.speedup_vs_ref = None
        if r.name in targets_ms and r.mean_ms is not None:
            r.target_ms = targets_ms[r.name]
            r.target_met = r.mean_ms < r.target_ms
        elif r.name in targets_ms:
            r.target_ms = targets_ms[r.name]
            r.target_met = None


def ensure_out_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def format_float(value: Optional[float], decimals: int = 2) -> str:
    if value is None:
        return "-"
    return f"{value:.{decimals}f}"


def print_console_table(results: List[BenchmarkStats], unit: str) -> None:
    headers = [
        "name",
        f"mean_{unit}",
        f"median_{unit}",
        f"p95_{unit}",
        f"ci95_low_{unit}",
        f"ci95_high_{unit}",
        "throughput_rps",
        "speedup_vs_ref",
        "target",
    ]
    print("\n=== BENCHMARKS ===\n")
    print(" | ".join(headers))
    print("-" * 100)
    for r in results:
        if r.status != "ok":
            print(f"{r.name} | {r.status} | {r.error_message or ''}")
            continue
        mean_u = ns_to_unit(r.mean_ns, unit)
        median_u = ns_to_unit(r.median_ns, unit)
        p95_u = ns_to_unit(r.p95_ns, unit)
        ci_low_u = ns_to_unit(r.ci95_low_ns, unit) if r.ci95_low_ns is not None else None
        ci_high_u = ns_to_unit(r.ci95_high_ns, unit) if r.ci95_high_ns is not None else None
        target_str = "-"
        if r.target_ms is not None:
            target_unit = r.target_ms if unit == "ms" else (r.target_ms * 1_000.0 if unit == "us" else r.target_ms * 1_000_000.0)
            status = "PASS" if r.target_met else ("PENDING" if r.target_met is None else "FAIL")
            target_str = f"{format_float(target_unit, 2)} {unit} ({status})"
        row = [
            r.name,
            format_float(mean_u, 2),
            format_float(median_u, 2),
            format_float(p95_u, 2),
            format_float(ci_low_u, 2),
            format_float(ci_high_u, 2),
            format_float(r.throughput_rps, 0),
            format_float(r.speedup_vs_ref, 2) if r.speedup_vs_ref is not None else "-",
            target_str,
        ]
        print(" | ".join(row))
    print()


def write_markdown(results: List[BenchmarkStats], out_md: Path, unit: str, ref_name: str) -> None:
    lines: List[str] = []
    lines.append("# Benchmark Report")
    lines.append("")
    lines.append(f"- Reference benchmark: `{ref_name}`")
    lines.append(f"- Unit: `{unit}` (internal ns)")
    lines.append("")
    lines.append("| name | mean | median | p95 | ci95_low | ci95_high | throughput_rps | speedup_vs_ref | target |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for r in results:
        if r.status != "ok":
            lines.append(f"| {r.name} | {r.status} |  |  |  |  |  |  | {r.error_message or ''} |")
            continue
        mean_u = ns_to_unit(r.mean_ns, unit)
        median_u = ns_to_unit(r.median_ns, unit)
        p95_u = ns_to_unit(r.p95_ns, unit)
        ci_low_u = ns_to_unit(r.ci95_low_ns, unit) if r.ci95_low_ns is not None else None
        ci_high_u = ns_to_unit(r.ci95_high_ns, unit) if r.ci95_high_ns is not None else None
        target_txt = "-"
        if r.target_ms is not None:
            target_unit = r.target_ms if unit == "ms" else (r.target_ms * 1_000.0 if unit == "us" else r.target_ms * 1_000_000.0)
            status = "✓ PASS" if r.target_met else ("… PENDING" if r.target_met is None else "✗ FAIL")
            target_txt = f"{target_unit:.2f} {unit} ({status})"
        lines.append(
            "| "
            + " | ".join(
                [
                    r.name,
                    format_float(mean_u, 2),
                    format_float(median_u, 2),
                    format_float(p95_u, 2),
                    format_float(ci_low_u, 2),
                    format_float(ci_high_u, 2),
                    format_float(r.throughput_rps, 0),
                    (f"{r.speedup_vs_ref:.2f}" if r.speedup_vs_ref is not None else "-"),
                    target_txt,
                ]
            )
            + " |"
        )
    # Validation section
    lines.append("")
    lines.append("## Target Validation")
    lines.append("")
    for r in results:
        if r.target_ms is None:
            continue
        if r.target_met is True:
            lines.append(f"- `{r.name}`: ✓ mean < {r.target_ms:.2f} ms")
        elif r.target_met is False:
            lines.append(f"- `{r.name}`: ✗ mean ≥ {r.target_ms:.2f} ms")
        else:
            lines.append(f"- `{r.name}`: … target defined but measurement missing")
    out_md.write_text("\n".join(lines))


def write_csv(results: List[BenchmarkStats], out_csv: Path) -> None:
    fieldnames = [
        "name",
        "status",
        "mean_ns",
        "median_ns",
        "stddev_ns",
        "ci95_low_ns",
        "ci95_high_ns",
        "p95_ns",
        "mean_ms",
        "median_ms",
        "stddev_ms",
        "ci95_low_ms",
        "ci95_high_ms",
        "p95_ms",
        "throughput_rps",
        "speedup_vs_ref",
        "target_ms",
        "target_met",
        "error_message",
    ]
    with open(out_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for r in results:
            row = asdict(r)
            writer.writerow(row)


def write_json(results: List[BenchmarkStats], out_json: Path, meta: Dict[str, Any]) -> None:
    data = {
        "meta": meta,
        "results": [asdict(r) for r in results],
    }
    out_json.write_text(json.dumps(data, indent=2))


def main() -> int:
    args = parse_args()
    out_dir = Path(args.out_dir)
    ensure_out_dir(out_dir)

    targets_ms = parse_targets_arg(args.targets)
    benches: List[str] = list(dict.fromkeys(args.benches))  # dedupe, keep order
    if not benches:
        print("Error: no benches provided.", file=sys.stderr)
        return 1
    ref_name = args.ref or benches[0]
    if ref_name not in benches:
        benches.insert(0, ref_name)

    results: List[BenchmarkStats] = [load_benchmark(b) for b in benches]
    # Compute speedups and targets
    compute_speedups_and_targets(results, ref_name=ref_name, targets_ms=targets_ms)

    # Console output
    print_console_table(results, unit=args.unit)

    # Files
    out_md = out_dir / "benchmark_report.md"
    out_csv = out_dir / "benchmark_report.csv"
    out_json = out_dir / "benchmark_report.json"
    write_markdown(results, out_md, unit=args.unit, ref_name=ref_name)
    write_csv(results, out_csv)
    meta = {
        "unit": args.unit,
        "ref": ref_name,
        "benches": benches,
        "targets_ms": targets_ms,
        "criterion_root": str(CRITERION_ROOT),
    }
    write_json(results, out_json, meta=meta)

    any_ok = any(r.status == "ok" for r in results)
    return 0 if any_ok else 1


if __name__ == "__main__":
    sys.exit(main())


