# -*- coding: utf-8 -*-
"""R7 收口脚本：INDEX_REGISTRY.json 88→104 (v1.6.0) + JSONL 88→104（备份、回读校验、sha256 断言、前 88 条逐字节未变）"""
import json, hashlib, io, os, shutil, sys
from datetime import datetime, timezone, timedelta

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

STAGING = r"C:\Library\_Staging_Raw\2026-11-15"
REG = r"C:\Library\INDEX_REGISTRY.json"
REG_BAK = os.path.join(STAGING, "INDEX_REGISTRY.backup_R7.json")
JSONL = r"C:\Library\_AI_Training_Dataset\daoli_st_sft_dataset.jsonl"
JSONL_BAK = JSONL + ".backup_R7"

TZ = timezone(timedelta(hours=8))
NOW = datetime.now(TZ).isoformat(timespec="seconds")

# name -> (category, type, complexity, tags)（tags 含来源组标签，依 ROUND_PLAN_R7 泳道节）
NEW = [
    ("FB_DL_EventCounter",        "DL_Base",    "FB", 6, ["event-counter", "bidirectional-count", "preset-load", "wrap-around", "compare-output", "lgf-counter"]),
    ("FB_DL_ModuloCounter",       "DL_Base",    "FB", 5, ["modulo-counter", "station-index", "conditional-wrap", "jump-validate", "lgf-counter"]),
    ("I_DL_BarcodeScanner",       "DL_Device",  "IF", 3, ["barcode-scanner-interface", "trigger-handshake", "dependency-injection", "device-abstraction", "tcopen-component", "scanner-handshake"]),
    ("FB_DL_SerialScanner",       "DL_Device",  "FB", 8, ["serial-scanner", "trigger-ack-handshake", "noread-retry", "escalation-fault", "trailing-crlf-strip", "tcopen-component", "scanner-handshake"]),
    ("I_DL_SafetyDoor",           "DL_Device",  "IF", 3, ["safety-door-interface", "interlock-sequence", "dependency-injection", "tcopen-component", "safety-interlock"]),
    ("FB_DL_GuardLockDoor",       "DL_Device",  "FB", 9, ["guard-lock-door", "unlock-sequence", "standstill-confirm", "run-down-timer", "tamper-conflict", "restart-inhibit", "open-audit", "tcopen-component", "safety-interlock"]),
    ("I_DL_LightCurtain",         "DL_Device",  "IF", 3, ["light-curtain-interface", "muting-abstraction", "safestop-mirror", "tcopen-component", "light-curtain-muting"]),
    ("FB_DL_SafetyLightCurtain",  "DL_Device",  "FB", 9, ["safety-light-curtain", "ossd-discrepancy", "sequential-muting", "four-sensor", "muting-timeout", "override-lamp-blink", "restart-interlock", "tcopen-component", "light-curtain-muting"]),
    ("I_DL_FlowMeter",            "DL_Device",  "IF", 3, ["flow-meter-interface", "totalizer", "dependency-injection", "tcopen-component", "flow-totalizer"]),
    ("FB_DL_PulseFlowMeter",      "DL_Device",  "FB", 8, ["pulse-flow-meter", "k-factor", "sample-window", "double-buffer", "low-flow-cutoff", "totalizer", "tcopen-component", "flow-totalizer"]),
    ("I_DL_LevelSwitch",          "DL_Device",  "IF", 2, ["level-switch-interface", "failsafe-normalize", "tcopen-component", "level-switch-failsafe"]),
    ("FB_DL_LevelSwitchVib",      "DL_Device",  "FB", 6, ["vibrating-level-switch", "debounce", "cover-bare-delay", "failsafe-high-low", "interlock-mirror", "tcopen-component", "level-switch-failsafe"]),
    ("FB_DL_OeeCalculator",       "DL_Process", "FB", 8, ["oee-calculator", "availability", "performance", "quality", "packml-root-cause", "shift-statistics", "packml-oee"]),
    ("FB_DL_ConveyorZone",        "DL_Process", "FB", 8, ["conveyor-zone", "zero-pressure-accumulation", "run-on", "jam-detection", "vfd-interface-consumer", "surge-stagger", "conveyor-accumulation"]),
    ("FB_DL_BatchDosingControl",  "DL_Process", "FB", 9, ["batch-dosing", "coarse-fine", "inflight-learning", "settle-window", "no-flow-watchdog", "isa-88", "lbp-batch-dosing"]),
    ("FB_DL_SoftLimitGuard",      "DL_Motion",  "FB", 7, ["soft-limit-guard", "braking-distance", "latency-compensation", "directional-intercept", "plcopen-motion"]),
]

# ---------- 备份 ----------
with open(REG, encoding="utf-8") as f:
    reg = json.load(f)
assert reg["total_components"] == 88 and reg["version"] == "1.5.0", "registry 基线与预期不符"
assert reg["counts"] == {"DL_Base": 22, "DL_MathData": 20, "DL_Algo": 18, "DL_Device": 18, "DL_Motion": 6, "DL_Process": 4}, reg["counts"]
shutil.copy2(REG, REG_BAK)
print("registry 备份 ->", REG_BAK)

# ---------- registry 追加 ----------
existing = {c["name"] for c in reg["components"]}
for name, cat, typ, cplx, tags in NEW:
    assert name not in existing, f"重名: {name}"
    p = rf"C:\Library\{cat}\{name}.st"
    assert os.path.isfile(p), f"缺文件: {p}"
    reg["components"].append({
        "name": name, "category": cat, "type": typ, "file_path": p,
        "function_tags": tags, "complexity": cplx, "registered_at": NOW,
    })

reg["total_components"] = 104
reg["version"] = "1.6.0"
reg["last_updated"] = NOW
dir_counts = {}
for c in reg["components"]:
    dir_counts[c["category"]] = dir_counts.get(c["category"], 0) + 1
reg["counts"] = {k: dir_counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["counts"] == {"DL_Base": 24, "DL_MathData": 20, "DL_Algo": 18, "DL_Device": 28, "DL_Motion": 7, "DL_Process": 7}, reg["counts"]

with open(REG, "w", encoding="utf-8") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
with open(REG, encoding="utf-8") as f:
    chk = json.load(f)
assert chk["total_components"] == 104 and chk["version"] == "1.6.0" and len(chk["components"]) == 104
print("registry OK: 88→104, version 1.6.0, counts =", chk["counts"])

# ---------- JSONL 追加 ----------
with open(JSONL, "rb") as f:
    raw_before = f.read()
shutil.copy2(JSONL, JSONL_BAK)
print("jsonl 备份 ->", JSONL_BAK)

lines_before = raw_before.decode("utf-8").splitlines()
assert len(lines_before) == 88, f"现有条数 {len(lines_before)} ≠ 88"
for i, ln in enumerate(lines_before, 1):
    json.loads(ln)
print("现有 88 条逐行 json.loads 校验 PASS（未动内容）")

with open(JSONL, "a", encoding="utf-8", newline="\n") as f:
    for name, cat, typ, cplx, tags in NEW:
        with open(os.path.join(STAGING, "meta", f"{name}.json"), encoding="utf-8") as mf:
            meta = json.load(mf)
        st_bytes = open(rf"C:\Library\{cat}\{name}.st", "rb").read()
        st_text = st_bytes.decode("utf-8")
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
assert len(lines_after) == 104, f"落条后 {len(lines_after)} ≠ 104"
assert lines_after[:88] == lines_before, "前 88 条被改动！"
sample = []
for i, ln in enumerate(lines_after[88:], 89):
    obj = json.loads(ln)
    name, cat = NEW[i - 89][0], NEW[i - 89][1]
    st_bytes = open(rf"C:\Library\{cat}\{name}.st", "rb").read()
    h_out = hashlib.sha256(obj["output"].encode("utf-8")).hexdigest()
    h_st = hashlib.sha256(st_bytes).hexdigest()
    assert h_out == h_st, f"{name} output sha256 不一致"
    sample.append((name, h_st, len(st_bytes)))
print("追加 16 条逐行 json.loads + sha256 一致性断言 ALL PASS")

raw_after_size = len(raw_after)
print(f"\nJSONL 88→104 全部合法，前 88 条逐字节未变（{len(raw_before)} → {raw_after_size} bytes，追加 {raw_after_size - len(raw_before)} bytes）")
print("\nsha256（全部 16 条，output vs .st 一致）：")
for n, h, sz in sample:
    print(f"  {n:26s} {h}  {sz} bytes")
print("\n结论: registry v1.6.0 / 104 组件；JSONL 104 条收口完成。")
