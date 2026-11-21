# -*- coding: utf-8 -*-
"""R6 收口脚本：INDEX_REGISTRY.json 72→88 (v1.5.0) + JSONL 72→88（备份、回读校验、sha256 断言）"""
import json, hashlib, io, os, shutil, sys
from datetime import datetime, timezone, timedelta

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

STAGING = r"C:\Library\_Staging_Raw\2026-11-15"
REG = r"C:\Library\INDEX_REGISTRY.json"
REG_BAK = os.path.join(STAGING, "INDEX_REGISTRY.backup_R6.json")
JSONL = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl"
JSONL_BAK = JSONL + ".backup_R6"

TZ = timezone(timedelta(hours=8))
NOW = datetime.now(TZ).isoformat(timespec="seconds")

# name -> (category, type, complexity, tags)（tags 含来源组标签，依 ROUND_PLAN_R6 第 5 节）
NEW = [
    ("FB_DL_SingleSolenoidCyl",  "DL_Device",  "FB", 6, ["single-solenoid-cylinder", "spring-return", "time-mode", "reed-check", "stroke-count", "lbp-basic-process", "lbp-device"]),
    ("I_DL_VacuumGenerator",     "DL_Device",  "IF", 3, ["vacuum-generator-interface", "dependency-injection", "device-abstraction", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_VacuumEjector",      "DL_Device",  "FB", 8, ["vacuum-ejector", "hysteresis", "blow-off-pulse", "dual-confirm", "hold-last-good", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_StarDeltaMotor",     "DL_Device",  "FB", 9, ["star-delta-motor", "contactor-sequence", "dead-time-interlock", "mutual-exclusion-assert", "restart-inhibit", "lbp-basic-process", "lbp-device"]),
    ("I_DL_VfdDrive",            "DL_Device",  "IF", 4, ["vfd-interface", "preset-speed", "dependency-injection", "device-abstraction", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_VfdGeneric",         "DL_Device",  "FB", 9, ["vfd-generic", "terminal-control", "jog-priority", "preset-speed-table", "analog-frequency-mapping", "fault-reset-pulse", "lbp-basic-process", "lbp-device"]),
    ("I_DL_ProportionalValve",   "DL_Device",  "IF", 3, ["proportional-valve-interface", "dependency-injection", "device-abstraction", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_AnalogValve",        "DL_Device",  "FB", 6, ["analog-valve", "deadband-compensation", "deviation-alarm", "span-mapping", "lbp-basic-process", "lbp-device"]),
    ("I_DL_MotorizedValve",      "DL_Device",  "IF", 4, ["motorized-valve-interface", "pulse-drive", "dependency-injection", "device-abstraction", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_ThreePointValve",    "DL_Device",  "FB", 9, ["three-point-valve", "position-integration", "limit-anchoring", "endpoint-guard", "travel-count", "lbp-basic-process", "lbp-device"]),
    ("FB_DL_AxisHomingSeq",      "DL_Motion",  "FB", 9, ["axis-homing", "homing-sequence", "limit-switch-homing", "zero-pulse-homing", "torque-block-homing", "travel-guard", "plcopen-motion", "s7-motion"]),
    ("FB_DL_AxisRelativeMove",   "DL_Motion",  "FB", 6, ["axis-relative-move", "chain-stepping", "polling-state", "command-arbitration", "plcopen-motion", "s7-motion"]),
    ("FB_DL_AxisVelocityMove",   "DL_Motion",  "FB", 6, ["axis-velocity-move", "dynamic-retarget", "velocity-clamp", "polling-state", "plcopen-motion", "s7-motion"]),
    ("FB_DL_EnthalpyCompareCtrl","DL_Process", "FB", 7, ["enthalpy-compare", "economizer", "schmitt-hysteresis", "high-limit-trip", "minimum-oa-position", "oscat-building", "lgf-datetime", "hvac"]),
    ("FB_DL_OccScheduleWindow",  "DL_Process", "FB", 7, ["occupancy-schedule", "multi-window", "holiday-override", "pre-start-lead", "weekday-matrix", "oscat-building", "lgf-datetime", "hvac"]),
    ("FB_DL_RampSoakProfile",    "DL_Algo",    "FB", 8, ["ramp-soak-profile", "multi-segment", "hold-freeze", "skip-segment", "track-resync", "loop-profile", "lgf-technology"]),
]

# ---------- 任务 3：registry ----------
with open(REG, encoding="utf-8") as f:
    reg = json.load(f)
assert reg["total_components"] == 72 and reg["version"] == "1.4.0", "registry 基线与预期不符"
assert reg["counts"] == {"DL_Base": 22, "DL_MathData": 20, "DL_Algo": 17, "DL_Device": 8, "DL_Motion": 3, "DL_Process": 2}, reg["counts"]
shutil.copy2(REG, REG_BAK)
print("registry 备份 ->", REG_BAK)

existing = {c["name"] for c in reg["components"]}
for name, cat, typ, cplx, tags in NEW:
    assert name not in existing, f"重名: {name}"
    p = rf"C:\Library\{cat}\{name}.st"
    assert os.path.isfile(p), f"缺文件: {p}"
    reg["components"].append({
        "name": name, "category": cat, "type": typ, "file_path": p,
        "function_tags": tags, "complexity": cplx, "registered_at": NOW,
    })

reg["total_components"] = 88
reg["version"] = "1.5.0"
reg["last_updated"] = NOW
dir_counts = {}
for c in reg["components"]:
    dir_counts[c["category"]] = dir_counts.get(c["category"], 0) + 1
reg["counts"] = {k: dir_counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["counts"] == {"DL_Base": 22, "DL_MathData": 20, "DL_Algo": 18, "DL_Device": 18, "DL_Motion": 6, "DL_Process": 4}, reg["counts"]

with open(REG, "w", encoding="utf-8") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
with open(REG, encoding="utf-8") as f:
    chk = json.load(f)
assert chk["total_components"] == 88 and chk["version"] == "1.5.0" and len(chk["components"]) == 88
print("registry OK: 72→88, version 1.5.0, counts =", chk["counts"])

# ---------- 任务 4：JSONL ----------
with open(JSONL, "rb") as f:
    raw_before = f.read()
shutil.copy2(JSONL, JSONL_BAK)
print("jsonl 备份 ->", JSONL_BAK)

lines_before = raw_before.decode("utf-8").splitlines()
assert len(lines_before) == 72, f"现有条数 {len(lines_before)} ≠ 72"
for i, ln in enumerate(lines_before, 1):
    json.loads(ln)
print("现有 72 条逐行 json.loads 校验 PASS（未动内容）")

with open(JSONL, "a", encoding="utf-8", newline="\n") as f:
    for name, cat, typ, cplx, tags in NEW:
        with open(os.path.join(STAGING, "meta", f"{name}.json"), encoding="utf-8") as mf:
            meta = json.load(mf)
        st_text = open(rf"C:\Library\{cat}\{name}.st", "rb").read().decode("utf-8")
        rec = {
            "instruction": meta["instruction"],
            "architecture_thought": meta["architecture_thought"],
            "output": st_text,
        }
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

# ---------- 回读校验 ----------
with open(JSONL, "rb") as f:
    raw_after = f.read()
lines_after = raw_after.decode("utf-8").splitlines()
assert len(lines_after) == 88, f"落条后 {len(lines_after)} ≠ 88"
assert lines_after[:72] == lines_before, "前 72 条被改动！"
sample = []
for i, ln in enumerate(lines_after[72:], 73):
    obj = json.loads(ln)
    name, cat = NEW[i - 73][0], NEW[i - 73][1]
    st_bytes = open(rf"C:\Library\{cat}\{name}.st", "rb").read()
    h_out = hashlib.sha256(obj["output"].encode("utf-8")).hexdigest()
    h_st = hashlib.sha256(st_bytes).hexdigest()
    assert h_out == h_st, f"{name} output sha256 不一致"
    sample.append((name, h_st, len(st_bytes)))
print("追加 16 条逐行 json.loads + sha256 一致性断言 ALL PASS")

raw_after_size = len(raw_after)
print(f"\nJSONL 72→88 全部合法，前 72 条逐字节未变（{len(raw_before)} → {raw_after_size} bytes，追加 {raw_after_size - len(raw_before)} bytes）")
print("\nsha256（全部 16 条，output vs .st 一致）：")
for n, h, sz in sample:
    print(f"  {n:26s} {h}  {sz} bytes")
print("\n结论: registry v1.5.0 / 88 组件；JSONL 88 条收口完成。")
