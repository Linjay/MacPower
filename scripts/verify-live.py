#!/usr/bin/env python3
"""Compare the public diagnostic executable with stable, independent IORegistry reads.
Only whitelisted numeric fields are written; hardware identifiers never leave memory.
"""
import argparse
import json
import plistlib
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("probe", type=Path)
parser.add_argument("--output", type=Path, default=Path("build/evidence/live-verification.json"))
args = parser.parse_args()

def registry():
    rows = plistlib.loads(subprocess.check_output(["ioreg", "-r", "-c", "AppleSmartBattery", "-a"]))
    if not rows:
        raise RuntimeError("No internal battery to verify on this device")
    row = rows[0]
    telemetry = row.get("PowerTelemetryData", {})
    return {"SystemPowerIn": telemetry.get("SystemPowerIn"),
            "BatteryPower": telemetry.get("BatteryPower"),
            "SystemLoad": telemetry.get("SystemLoad"),
            "CycleCount": row.get("CycleCount"),
            "ExternalConnected": row.get("ExternalConnected"),
            "Voltage": row.get("Voltage"),
            "Amperage": row.get("InstantAmperage", row.get("Amperage")),
            "AdapterWatts": row.get("AdapterDetails", {}).get("Watts")}

checks = []
for attempt in range(5):
    before = registry()
    report = json.loads(subprocess.check_output([str(args.probe.resolve())]))
    after = registry()
    snapshot = report["snapshot"]
    if before["ExternalConnected"] is False and after["ExternalConnected"] is False:
        checks.append({"attempt": attempt+1, "metric":"disconnected-input", "result":"passed" if snapshot["input"].get("value") == 0 and snapshot.get("adapterWatts") is None and snapshot["externalConnected"] is False else "failed"})
        for metric in ("battery", "system"):
            record = {"attempt":attempt+1, "metric":metric, "sampledAt":snapshot["timestamp"]}
            if any(before[k] is None or before[k] != after[k] for k in ("Voltage", "Amperage")):
                record["result"] = "inconclusive-source-changed"
            else:
                current = before["Amperage"] - 2**64 if before["Amperage"] > 2**63-1 else before["Amperage"]
                if current <= 0:
                    expected = before["Voltage"] * current / 1_000_000 * (1 if metric == "battery" else -1)
                    record.update(expected_w=expected, actual_w=snapshot[metric].get("value"))
                    record["result"] = "passed" if snapshot[metric]["quality"] == "estimated" and abs(snapshot[metric].get("value",float("inf"))-expected) < 0.0001 else "failed"
                else:
                    record["result"] = "passed" if snapshot[metric].get("value") is None else "failed"
            checks.append(record)
        if attempt != 4:
            time.sleep(1)
        continue
    for raw, metric in [("SystemPowerIn", "input"), ("BatteryPower", "battery"), ("SystemLoad", "system")]:
        record = {"attempt": attempt + 1, "metric": metric, "sampledAt": snapshot["timestamp"]}
        if before[raw] is None or before[raw] != after[raw] or before["ExternalConnected"] != after["ExternalConnected"]:
            record["result"] = "inconclusive-source-changed"
        elif snapshot[metric]["quality"] != "telemetry":
            record["result"] = "inconclusive-non-telemetry-path"
        else:
            signed = before[raw] - 2**64 if before[raw] > 2**63-1 else before[raw]
            expected = signed / 1000
            record.update(expected_w=expected, actual_w=snapshot[metric].get("value"))
            record["result"] = "passed" if abs(snapshot[metric].get("value", float("inf")) - expected) < 0.0001 else "failed"
        checks.append(record)
    if before["ExternalConnected"] == after["ExternalConnected"] is True and before["AdapterWatts"] == after["AdapterWatts"]:
        checks.append({"attempt": attempt+1, "metric": "adapter-capability", "expected_w":before["AdapterWatts"], "actual_w":snapshot.get("adapterWatts"), "result":"passed" if snapshot.get("adapterWatts") == before["AdapterWatts"] else "failed"})
    if attempt != 4:
        time.sleep(1)

result = {"checks": checks, "passed": sum(x["result"] == "passed" for x in checks),
          "failed": sum(x["result"] == "failed" for x in checks),
          "inconclusive": sum(x["result"].startswith("inconclusive") for x in checks),
          "scope": "same-device system-field and unit/sign consistency; not independent wattmeter calibration"}
args.output.parent.mkdir(parents=True,exist_ok=True)
args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n")
print(json.dumps({k:v for k,v in result.items() if k != "checks"},ensure_ascii=False))
raise SystemExit(1 if result["failed"] or not result["passed"] else 0)
