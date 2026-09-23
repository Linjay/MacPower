#!/usr/bin/env python3
"""Observe our running app without opening its UI or changing hardware state."""
import argparse
import datetime
import json
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("pid", type=int)
parser.add_argument("--duration", type=int, default=600)
parser.add_argument("--output", type=Path, default=Path("build/evidence/background-verification.json"))
args = parser.parse_args()
history = Path.home() / "Library/Application Support/MacPower/history-v1.json"

def read_process():
    line = subprocess.check_output(["ps", "-p", str(args.pid), "-o", "time=,rss=,comm="], text=True).strip()
    cpu, rss, command = line.split(maxsplit=2)
    if not command.endswith("/MacPower.app/Contents/MacOS/MacPower"):
        raise RuntimeError("PID is not the built MacPower application")
    parts = cpu.split(":")
    seconds = float(parts[-1]) + 60 * int(parts[-2]) + (3600 * int(parts[-3]) if len(parts) == 3 else 0)
    return {"cpu_seconds": seconds, "rss_mib": int(rss) / 1024}

def read_history():
    data = json.loads(history.read_text())
    return {"points": len(data["points"]), "samples": sum(p["samples"] for p in data["points"]),
            "last_sample": max((p["lastSampleAt"] for p in data["points"]), default=None),
            "health_days": len(data["health"]), "bytes": history.stat().st_size,
            "segments": len({p["segment"] for p in data["points"]})}

start = time.monotonic()
initial_history = read_history()
observations = []
deadline = start + args.duration
while True:
    now = time.monotonic()
    observations.append({"elapsed_seconds": round(now - start, 3), **read_process()})
    if now >= deadline:
        break
    time.sleep(min(5, deadline - now))
final_history = read_history()
elapsed = observations[-1]["elapsed_seconds"]
cpu = (observations[-1]["cpu_seconds"] - observations[0]["cpu_seconds"]) / elapsed * 100
peak = max(x["rss_mib"] for x in observations)
result = {"observed_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "elapsed_seconds": elapsed, "mean_cpu_percent_one_core": round(cpu, 4),
          "rss_first_mib": observations[0]["rss_mib"], "rss_last_mib": observations[-1]["rss_mib"],
          "rss_peak_mib": peak, "cpu_under_half_percent": cpu < 0.5,
          "rss_under_80_mb": peak * 1024 * 1024 < 80_000_000, "history_before": initial_history, "history_after": final_history,
          "new_persisted_samples": final_history["samples"] - initial_history["samples"],
          "recording_continued": final_history["last_sample"] > initial_history["last_sample"],
          "scope": "local process CPU/RSS and history continuity for elapsed_seconds, not battery drain or full-day endurance",
          "observations": observations}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: v for k, v in result.items() if k != "observations"}, indent=2), flush=True)
raise SystemExit(0 if result["recording_continued"] else 1)
