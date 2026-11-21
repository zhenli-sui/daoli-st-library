# -*- coding: utf-8 -*-
"""R5 注册脚本：INDEX_REGISTRY.json 56→72 + JSONL 56→72（含备份、回读校验、sha256 断言）"""
import json, hashlib, io, os, shutil, sys
from datetime import datetime, timezone, timedelta

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

STAGING = r"C:\Library\_Staging_Raw\2026-11-15"
REG = r"C:\Library\INDEX_REGISTRY.json"
REG_BAK = os.path.join(STAGING, "INDEX_REGISTRY.backup_R5.json")
JSONL = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl"
JSONL_BAK = JSONL + ".backup_R5"

TZ = timezone(timedelta(hours=8))
NOW = datetime.now(TZ).isoformat(timespec="seconds")

# name -> (category, type, complexity, tags)
NEW = [
    ("I_DL_Cylinder",             "DL_Device",  "IF", 3, ["cylinder-interface", "state-machine", "dependency-injection", "device-abstraction", "lbp-device"]),
    ("FB_DL_PneumaticCylinder",   "DL_Device",  "FB", 8, ["pneumatic-cylinder", "reed-debounce", "double-solenoid", "fault-latch", "timeout-protection", "lbp-device"]),
    ("I_DL_MotorDriver",          "DL_Device",  "IF", 3, ["motor-interface", "dol-motor", "dependency-injection", "device-abstraction", "lbp-device"]),
    ("FB_DL_DolMotor",            "DL_Device",  "FB", 9, ["dol-motor", "contactor-feedback", "thermal-overload", "restart-inhibit", "starts-per-hour", "lbp-device"]),
    ("I_DL_AnalogSensor",         "DL_Device",  "IF", 3, ["analog-sensor-interface", "signal-quality", "alarm-limits", "device-abstraction", "namur-ne43"]),
    ("FB_DL_AnalogTransmitter",   "DL_Device",  "FB", 8, ["analog-transmitter", "span-scaling", "moving-average", "wire-break", "alarm-limits", "hold-last-good", "namur-ne43"]),
    ("I_DL_TemperatureZone",      "DL_Device",  "IF", 4, ["temperature-zone-interface", "pid", "dependency-injection", "device-abstraction", "lbp-device"]),
    ("FB_DL_HeatCoolZone",        "DL_Device",  "FB", 9, ["heat-cool-zone", "split-range", "pid-consumer", "pwm-ssr", "sensor-break", "lbp-device", "namur-ne43"]),
    ("I_DL_MotionAxis",           "DL_Motion",  "IF", 5, ["motion-axis-interface", "plcopen-states", "dependency-injection", "s7-motion", "plcopen"]),
    ("FB_DL_SingleAxis",          "DL_Motion",  "FB", 9, ["single-axis", "virtual-kinematics", "soft-limit", "command-arbitration", "fault-latch", "s7-motion", "plcopen"]),
    ("FB_DL_AxisJogController",   "DL_Motion",  "FB", 6, ["jog-controller", "two-speed", "braking-distance", "soft-limit", "s7-motion"]),
    ("FB_DL_PackMlStateMachine",  "DL_Process", "FB", 8, ["packml", "state-machine", "isa-tr88", "unit-mode", "abort-recovery", "packml-omac"]),
    ("FB_DL_PackMlCmdDecoder",    "DL_Process", "FB", 5, ["packml", "command-decoder", "one-shot", "conflict-detection", "packml-omac"]),
    ("FC_DL_DayOfWeekCalc",       "DL_Base",    "FC", 3, ["day-of-week", "iso-8601", "leap-year", "pure-function", "lgf-datetime"]),
    ("FB_DL_TimeWindowCheck",     "DL_Base",    "FB", 4, ["time-window", "cross-midnight", "weekday-enable", "edge-pulse", "lgf-datetime"]),
    ("FC_DL_HumidAirEnthalpy",    "DL_Algo",    "FC", 5, ["enthalpy", "psychrometrics", "magnus-tetens", "hvac", "oscat-building"]),
]

# ---------- 任务 3：registry ----------
with open(REG, encoding="utf-8") as f:
    reg = json.load(f)
assert reg["total_components"] == 56 and reg["version"] == "1.3.0", "registry 基线与预期不符"
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

reg["total_components"] = 72
reg["version"] = "1.4.0"
reg["last_updated"] = NOW
# 每目录 counts（以实际入库文件为准）
dir_counts = {}
for c in reg["components"]:
    dir_counts[c["category"]] = dir_counts.get(c["category"], 0) + 1
reg["counts"] = {k: dir_counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["counts"] == {"DL_Base": 22, "DL_MathData": 20, "DL_Algo": 17, "DL_Device": 8, "DL_Motion": 3, "DL_Process": 2}, reg["counts"]

with open(REG, "w", encoding="utf-8") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
# 回读校验
with open(REG, encoding="utf-8") as f:
    chk = json.load(f)
assert chk["total_components"] == 72 and chk["version"] == "1.4.0" and len(chk["components"]) == 72
print("registry OK: 56→72, version 1.4.0, counts =", chk["counts"])

# ---------- 任务 4：JSONL ----------
with open(JSONL, "rb") as f:
    raw_before = f.read()
shutil.copy2(JSONL, JSONL_BAK)
print("jsonl 备份 ->", JSONL_BAK)

lines_before = raw_before.decode("utf-8").splitlines()
assert len(lines_before) == 56, f"现有条数 {len(lines_before)} ≠ 56"
for i, ln in enumerate(lines_before, 1):
    json.loads(ln)  # 逐行合法性
print("现有 56 条逐行 json.loads 校验 PASS（未动内容）")

with open(JSONL, "a", encoding="utf-8", newline="\n") as f:
    for name, cat, typ, cplx, tags in NEW:
        with open(os.path.join(STAGING, "meta", f"{name}.json"), encoding="utf-8") as mf:
            meta = json.load(mf)
        st_bytes = open(rf"C:\Library\{cat}\{name}.st", "rb").read()
        st_text = st_bytes.decode("utf-8")
        rec = {
            "instruction": meta["instruction"],
            "architecture_thought": meta["architecture_thought"],
            "output": st_text,  # 字节级原文（UTF-8 解码后写回，json 转义仅为序列化，不改内容语义）
        }
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

# ---------- 回读校验 ----------
with open(JSONL, "rb") as f:
    raw_after = f.read()
lines_after = raw_after.decode("utf-8").splitlines()
assert len(lines_after) == 72, f"落条后 {len(lines_after)} ≠ 72"
# 前 56 条逐字节未变
assert lines_after[:56] == lines_before, "前 56 条被改动！"
sample = []
for i, ln in enumerate(lines_after[56:], 57):
    obj = json.loads(ln)  # 逐行合法性
    name = NEW[i - 57][0]
    cat = NEW[i - 57][1]
    st_bytes = open(rf"C:\Library\{cat}\{name}.st", "rb").read()
    # output 与 .st 一致性断言（sha256）
    h_out = hashlib.sha256(obj["output"].encode("utf-8")).hexdigest()
    h_st = hashlib.sha256(st_bytes).hexdigest()
    assert h_out == h_st, f"{name} output sha256 不一致"
    sample.append((name, h_st[:16], len(st_bytes)))
print("追加 16 条逐行 json.loads + sha256 一致性断言 ALL PASS")
print("\nsha256 抽样（全部 16 条）：")
for n, h, sz in sample:
    print(f"  {n:32s} {h}…  {sz} bytes")
print("\n结论: JSONL 56→72 全部合法，前 56 条逐字节未变。")
