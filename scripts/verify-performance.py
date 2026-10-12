#!/usr/bin/env python3
"""Measure a running MacPower process; fail when its CPU budget is exceeded.

Set up the desired UI state before running. CPU is cumulative process time divided
by elapsed wall time (one core = 100%). No hardware identifiers are collected.
"""
import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--duration", type=float, default=60)
parser.add_argument("--max-cpu-percent", type=float, default=0.5)
parser.add_argument("--scenario", default="background")
parser.add_argument("--output", type=Path, default=Path("build/evidence/performance.json"))
args = parser.parse_args()
if args.duration < 5 or args.max_cpu_percent <= 0:
    parser.error("duration must be at least 5 seconds and CPU budget must be positive")


def observe():
    line = subprocess.check_output(
        ["ps", "-p", str(args.pid), "-o", "time=,rss=,comm="], text=True
    ).strip()
    cpu, rss, command = line.split(maxsplit=2)
    if not command.endswith("/MacPower.app/Contents/MacOS/MacPower"):
        raise RuntimeError("PID is not MacPower")
    parts = cpu.split(":")
    seconds = float(parts[-1]) + 60 * int(parts[-2])
    if len(parts) == 3:
        seconds += 3600 * int(parts[-3])
    return {"cpu_seconds": seconds, "rss_mib": int(rss) / 1024}


start = time.monotonic()
observations = []
while True:
    observations.append({"elapsed_seconds": time.monotonic() - start, **observe()})
    remaining = args.duration - (time.monotonic() - start)
    if remaining <= 0:
        break
    time.sleep(min(5, remaining))
elapsed = observations[-1]["elapsed_seconds"] - observations[0]["elapsed_seconds"]
cpu = (observations[-1]["cpu_seconds"] - observations[0]["cpu_seconds"]) / elapsed * 100
result = {
    "observed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "scenario": args.scenario,
    "elapsed_seconds": round(elapsed, 3),
    "mean_cpu_percent_one_core": round(cpu, 4),
    "max_cpu_percent": args.max_cpu_percent,
    "passed": cpu < args.max_cpu_percent,
    "rss_first_mib": observations[0]["rss_mib"],
    "rss_last_mib": observations[-1]["rss_mib"],
    "rss_peak_mib": max(p["rss_mib"] for p in observations),
    "scope": "this process and UI state only; not battery drain or long-term endurance",
    "observations": observations,
}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: v for k, v in result.items() if k != "observations"}, indent=2))
raise SystemExit(0 if result["passed"] else 1)
