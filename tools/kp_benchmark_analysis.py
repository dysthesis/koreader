#!/usr/bin/env python3
"""Analyse a saved KP dataset without a compiler, font, corpus or native harness."""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import random
import statistics


def distribution(values):
    values = sorted(values)
    if not values:
        return {"n": 0}
    result = {"n": len(values), "mean": statistics.fmean(values), "min": values[0], "max": values[-1]}
    for q in (0.5, 0.9, 0.95, 0.99):
        result[f"p{round(q * 100)}"] = values[math.ceil(q * len(values)) - 1]
    result["worst_5pct_mean"] = statistics.fmean(values[-max(1, math.ceil(0.05 * len(values))):])
    return result


def paragraph_metrics(row):
    scored = [line for line in row["lines"] if line["has_ratio"]]
    ratios = [line["ratio"] for line in scored if line["ratio"] is not None]
    jumps = [abs(b["ratio"] - a["ratio"]) for a, b in zip(row["lines"], row["lines"][1:])
             if a["has_ratio"] and b["has_ratio"] and a["ratio"] is not None and b["ratio"] is not None]
    return {
        "worst_abs_ratio": max(map(abs, ratios), default=0),
        "rms_ratio": math.sqrt(statistics.fmean(x*x for x in ratios)) if ratios else 0,
        "rms_adjacent_jump": math.sqrt(statistics.fmean(x*x for x in jumps)) if jumps else 0,
        "line_count": len(row["lines"]),
        "scored_line_count": len(scored),
    }


def summarise(rows, comparisons=True):
    groups = defaultdict(list)
    pairs = defaultdict(dict)
    for row in rows:
        groups[row["algorithm"]].append(row)
        pairs[row["paragraph"], row["width"]][row["algorithm"]] = row
    report: dict = {"algorithms": {}, "paired_spacing_minus_classical": {}}
    for algorithm, runs in sorted(groups.items()):
        successful = [r for r in runs if r["success"]]
        lines = [line for r in successful for line in r["lines"] if line["has_ratio"]]
        ratios = [line["ratio"] for line in lines if line["ratio"] is not None]
        abs_ratios = list(map(abs, ratios))
        paragraphs = [paragraph_metrics(r) for r in successful if any(l["has_ratio"] for l in r["lines"])
                      and all(l["ratio"] is not None for l in r["lines"])]
        report["algorithms"][algorithm] = {
            "attempts": len(runs), "failed": len(runs) - len(successful),
            "paragraphs_with_infeasible_lines": sum(any(not l["feasible"] for l in r["lines"]) for r in successful),
            "infeasible_scored_lines": sum(not line["feasible"] for line in lines),
            "undefined_ratios": len(lines) - len(ratios),
            "solve_us": distribution([r["solve_us"] for r in runs]),
            "successful_solve_us": distribution([r["solve_us"] for r in successful]),
            "failed_solve_us": distribution([r["solve_us"] for r in runs if not r["success"]]),
            "signed_ratio": distribution(ratios), "abs_ratio": distribution(abs_ratios),
            "badness": distribution([line["badness"] for line in lines]),
            "badness_histogram": dict(sorted(Counter(line["badness"] for line in lines).items())),
            "abs_ratio_exceedance": {str(t): sum(x > t for x in abs_ratios) / len(abs_ratios)
                                     if abs_ratios else None for t in (0.1, 0.2, 0.3, 0.4, 0.5)},
            "paragraphs": {key: distribution([p[key] for p in paragraphs])
                           for key in ("worst_abs_ratio", "rms_ratio", "rms_adjacent_jump", "line_count")},
        }
    if not comparisons:
        return report
    matched = []
    for pair in pairs.values():
        a, b = pair["spacing"], pair["classical"]
        if (a["success"] and b["success"] and any(l["has_ratio"] for l in a["lines"])
                and any(l["has_ratio"] for l in b["lines"])
                and all(l["feasible"] for l in a["lines"] + b["lines"])):
            matched.append((a, b))
    paired = report["paired_spacing_minus_classical"]
    paired["n"] = len(matched)
    paired["feasibility_disagreements"] = sum(p["spacing"]["success"] != p["classical"]["success"] for p in pairs.values())
    for key in ("worst_abs_ratio", "rms_ratio", "rms_adjacent_jump", "line_count"):
        deltas = [paragraph_metrics(a)[key] - paragraph_metrics(b)[key] for a, b in matched]
        paired[key] = distribution(deltas)
        paired[key]["better"] = sum(x < -1e-9 for x in deltas)
        paired[key]["worse"] = sum(x > 1e-9 for x in deltas)
        # Resample paragraphs, keeping all width variants together (not independent lines).
        clusters = defaultdict(list)
        for (a, _), delta in zip(matched, deltas):
            clusters[a["paragraph"]].append(delta)
        if len(clusters) >= 2:
            means = [statistics.fmean(v) for v in clusters.values()]
            rng = random.Random(1729)
            boot = sorted(statistics.fmean(rng.choices(means, k=len(means))) for _ in range(1000))
            paired[key]["equal_paragraph_mean"] = statistics.fmean(means)
            paired[key]["paragraph_bootstrap_95pct"] = [boot[24], boot[974]]
    report["worst_spacing_cases"] = [
        {"paragraph": r["paragraph"], "width": r["width"], **paragraph_metrics(r)}
        for r in sorted(groups["spacing"], key=lambda r: paragraph_metrics(r)["worst_abs_ratio"], reverse=True)
        if r["success"] and any(l["has_ratio"] for l in r["lines"])
    ][:20]
    return report


def prepare_rows(records, manifest):
    version = manifest.get("schema_version", 1)
    if version not in (1, 2):
        raise ValueError("unsupported collection schema")
    low, high, step = map(int, manifest["arguments"]["widths"].split(":"))
    if not 1 <= low <= high <= 10000 or not 1 <= step <= 10000:
        raise ValueError("invalid width range")
    widths = range(low, high + 1, step)
    algorithms = ("spacing", "classical", "greedy_model")
    paragraphs = set(range(manifest["selected"]))
    excluded, seen, rows = set(), set(), []
    for record in records:
        paragraph = record["paragraph"]
        if paragraph not in paragraphs:
            raise ValueError("unknown paragraph")
        if "exclusion" in record:
            if paragraph in excluded:
                raise ValueError("duplicate exclusion")
            excluded.add(paragraph)
            continue
        key = (paragraph, record["width"], record["algorithm"])
        if key in seen or key[1] not in widths or key[2] not in algorithms:
            raise ValueError("duplicate or unexpected measurement")
        seen.add(key)
        row = dict(record)
        if version == 2:
            samples = row["solve_samples_us"]
            if len(samples) != manifest["arguments"]["repeats"] or not samples:
                raise ValueError("unexpected timing sample count")
        else:
            # Previously saved datasets contain only the collector's median.
            samples = [row["solve_us"]]
        if any(type(t) not in (int, float) or not math.isfinite(t) or t < 0 for t in samples):
            raise ValueError("invalid timing sample")
        row["solve_us"] = statistics.median(samples)
        rows.append(row)
    expected = {(p, w, a) for p in paragraphs - excluded for w in widths for a in algorithms}
    if seen != expected or not rows:
        raise ValueError("incomplete or empty measurement grid")
    if manifest.get("measured_paragraphs", len(paragraphs - excluded)) != len(paragraphs - excluded):
        raise ValueError("manifest paragraph count mismatch")
    return rows


def selfcheck():
    assert distribution([]) == {"n": 0}
    assert distribution([3, 0, 2, 1])["p50"] == 1
    assert distribution([3, 0, 2, 1])["worst_5pct_mean"] == 3
    sample = {"paragraph": 0, "width": 10, "success": True, "solve_samples_us": [3, 1, 8, 2],
              "lines": [{"has_ratio": True, "ratio": -1/3, "badness": 100, "feasible": True},
                        {"has_ratio": False, "ratio": 0, "badness": 0, "feasible": True}]}
    records = [{**sample, "algorithm": name} for name in ("spacing", "classical", "greedy_model")]
    manifest = {"schema_version": 2, "selected": 1, "arguments": {"widths": "10:10:1", "repeats": 4}}
    rows = prepare_rows(records, manifest)
    assert rows[0]["solve_us"] == 2.5 and "solve_us" not in records[0]
    check = summarise(rows)
    assert check["algorithms"]["spacing"]["abs_ratio"]["n"] == 1
    assert check["paired_spacing_minus_classical"]["worst_abs_ratio"]["mean"] == 0
    assert paragraph_metrics(sample)["rms_adjacent_jump"] == 0
    for invalid in (records[:-1], records + records[:1],
                    [{**records[0], "solve_samples_us": [1, 2, 3, float("nan")]}, *records[1:]]):
        try:
            prepare_rows(invalid, manifest)
        except ValueError:
            continue
        raise AssertionError("invalid measurements accepted")


def analyse(dataset, output=None):
    selfcheck()
    manifest_data = (dataset / "manifest.json").read_bytes()
    measurements = (dataset / "lines.jsonl").read_bytes()
    manifest = json.loads(manifest_data)
    rows = prepare_rows([json.loads(line) for line in measurements.splitlines()], manifest)
    report = summarise(rows)
    report["by_width"] = {str(w): summarise([r for r in rows if r["width"] == w], comparisons=False)["algorithms"]
                          for w in sorted({r["width"] for r in rows})}
    report["analysis"] = {
        "manifest_sha256": hashlib.sha256(manifest_data).hexdigest(),
        "lines_sha256": hashlib.sha256(measurements).hexdigest(),
        "analyser_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "collection_schema": manifest.get("schema_version", 1),
    }
    output = output or dataset / "summary.json"
    with output.open("x", encoding="utf-8") as out:
        out.write(json.dumps(report, indent=2, allow_nan=False) + "\n")
    for name, data in report["algorithms"].items():
        print(name, json.dumps({key: data[key] for key in ("attempts", "failed", "paragraphs_with_infeasible_lines", "abs_ratio", "successful_solve_us")}))
    print("paired_spacing_minus_classical", json.dumps(report["paired_spacing_minus_classical"]))
    print("Analysis:", output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset", type=Path, nargs="?", help="directory containing manifest.json and lines.jsonl")
    parser.add_argument("--output", type=Path, help="new output file; defaults to DATASET/summary.json")
    parser.add_argument("--selfcheck", action="store_true")
    args = parser.parse_args()
    if args.selfcheck:
        selfcheck()
        print("kp_benchmark_analysis selfcheck passed")
    elif args.dataset is None:
        parser.error("dataset is required")
    else:
        analyse(args.dataset, args.output)
