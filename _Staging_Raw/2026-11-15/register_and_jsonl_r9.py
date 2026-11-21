# -*- coding: utf-8 -*-
"""R9 注册收口：INDEX_REGISTRY 登记（120→136）+ SFT JSONL 追加 16 条 + 旧条目 Crc16 再同步"""
import json, os, sys, io, shutil, hashlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
REG_BAK = os.path.join(LIB, "INDEX_REGISTRY.json.backup_R9")
META = os.path.join(LIB, r"_Staging_Raw\2026-11-15\meta")
DS = os.path.join(LIB, r"_AI_Training_Dataset\daoli_st_sft_dataset.jsonl")
DS_BAK = DS + ".backup_R9"
TS = "2026-11-15T13:52:00+08:00"

# name, category, type, tags, complexity, code_segment, source
NEW = [
    ("FB_DL_FifoBuffer", "DL_MathData", "FB",
     ["lgf-datahandling", "fifo-queue", "fixed-slot-buffer", "overflow-underflow", "pointer-consistency"],
     5, "16#0001_010A~010D(信息级) / 16#0001_0204(故障级)", "lgf-datahandling"),
    ("FB_DL_ArraySearchFirst", "DL_MathData", "FB",
     ["lgf-datahandling", "linear-search", "array-scan", "multi-hit-count", "index-report"],
     4, "16#0001_010E(信息级) / 16#0001_0205(故障级)", "lgf-datahandling"),
    ("FC_DL_BinarySearchLReal", "DL_MathData", "FC",
     ["lgf-datahandling", "binary-search", "sorted-array", "pure-function", "tolerance-compare"],
     4, "16#0001_010F(信息级) / 16#0001_0206(故障级)", "lgf-datahandling"),
    ("FB_DL_ToleranceWindow", "DL_Base", "FB",
     ["lgf-comparator", "tolerance-band", "hysteresis", "three-state-verdict", "window-monitor"],
     5, "16#0001_0112(信息级) / 16#0001_0213(故障级)", "lgf-comparator"),
    ("FC_DL_LimitClassify", "DL_Base", "FC",
     ["lgf-comparator", "limit-classification", "four-threshold", "pure-function", "severity-grading"],
     4, "16#0001_0214(故障级)", "lgf-comparator"),
    ("FC_DL_TempUnitConvert", "DL_MathData", "FC",
     ["lgf-converter", "temperature-unit", "celsius-fahrenheit-kelvin", "pure-function", "absolute-zero-guard"],
     3, "16#0001_0110(信息级) / 16#0001_0207~0208(故障级)", "lgf-converter"),
    ("FC_DL_BcdToWord", "DL_MathData", "FC",
     ["lgf-converter", "bcd-decode", "nibble-validation", "pure-function", "dip-switch"],
     3, "16#0001_0105(故障级)", "lgf-converter"),
    ("FC_DL_WordToBcd", "DL_MathData", "FC",
     ["lgf-converter", "bcd-encode", "overflow-saturation", "pure-function", "seven-segment"],
     3, "16#0001_0106~0107(故障级)", "lgf-converter"),
    ("FC_DL_WordBitPack", "DL_Base", "FC",
     ["lgf-bitlogic", "bit-field-pack", "mask-operations", "pure-function", "status-word"],
     4, "16#0001_0108(故障级)", "lgf-bitlogic"),
    ("FB_DL_MonthWindowCheck", "DL_Base", "FB",
     ["lgf-datetime", "month-window", "annual-window", "countdown-day", "maintenance-schedule"],
     5, "16#0001_0109(信息级) / 16#0001_0203(信息级)", "lgf-datetime"),
    ("FB_DL_PresetCounterSat", "DL_Base", "FB",
     ["lgf-counter", "preset-counter", "saturation", "threshold-event", "batch-full"],
     4, "16#0001_0212(故障级)", "lgf-counter"),
    ("FB_DL_SuperimposedMove", "DL_Motion", "FB",
     ["plcopen-motion", "s7-motion", "superimposed-move", "offset-compensation", "vision-correction"],
     7, "16#0004_01A0~01A3(信息级) / 16#0004_02B0~02B2(故障级)", "plcopen-motion"),
    ("I_DL_StepperOpenLoop", "DL_Device", "INTERFACE",
     ["stepper", "tcopen", "open-loop-contract", "pulse-direction", "interface-contract"],
     3, "无（接口契约不发布故障码，码位由实现块承担）", "stepper"),
    ("FB_DL_PulseDirStepper", "DL_Device", "FB",
     ["stepper", "plcopen-motion", "pulse-direction", "trapezoidal-ramp", "stall-timeout"],
     8, "16#0003_0130~0137(信息级) / 16#0003_02E0~02E4(故障级)", "stepper"),
    ("FB_DL_ModbusPollMaster", "DL_Process", "FB",
     ["codesys-forge-modbus", "modbus-rtu", "poll-scheduler", "retry-timeout", "transport-abstraction"],
     8, "16#0005_0190~0193(信息级) / 16#0005_0290~0292(故障级)", "codesys-forge-modbus"),
    ("FB_DL_AndonCallSystem", "DL_Process", "FB",
     ["andon", "omac", "call-escalation", "response-time-stat", "shift-reset"],
     7, "16#0005_01A0~01A1(信息级) / 16#0005_02A0~02A1(故障级)", "andon"),
]

# 旧条目再同步（本轮全库审计修复的注释类缺陷：头注释内嵌注释定界符）
RESYNC = [("FC_DL_Crc16Modbus", "DL_MathData")]


def sha(b):
    return hashlib.sha256(b).hexdigest()


print("[1] 备份 INDEX_REGISTRY.json")
shutil.copyfile(REG, REG_BAK)
reg = json.load(open(REG, encoding="utf-8"))
print(f"    前: total={reg['total_components']} version={reg['version']} counts={reg['counts']}")
assert reg["total_components"] == 120 and len(reg["components"]) == 120

names = {c["name"] for c in reg["components"]}
for name, cat, typ, tags, cplx, seg, src in NEW:
    assert name not in names, f"重复登记 {name}"
    fp = os.path.join(LIB, cat, name + ".st")
    assert os.path.exists(fp), f"文件不存在 {fp}"
    reg["components"].append({
        "name": name, "category": cat, "type": typ, "file_path": fp,
        "function_tags": tags, "complexity": cplx, "registered_at": TS,
        "code_segment": seg, "source": src,
    })

reg["version"] = "1.8.0"
reg["total_components"] = len(reg["components"])
reg["last_updated"] = TS
counts = {}
for c in reg["components"]:
    counts[c["category"]] = counts.get(c["category"], 0) + 1
reg["counts"] = {k: counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["total_components"] == 136
assert reg["counts"] == {"DL_Base": 29, "DL_MathData": 26, "DL_Algo": 20, "DL_Device": 32,
                         "DL_Motion": 14, "DL_Process": 15}, reg["counts"]

with open(REG, "w", encoding="utf-8", newline="\n") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
chk = json.load(open(REG, encoding="utf-8"))
assert chk["total_components"] == 136 and len(chk["components"]) == 136
assert all(os.path.exists(c["file_path"]) for c in chk["components"])
dup = len(chk["components"]) - len({c["name"] for c in chk["components"]})
print(f"    后: total={chk['total_components']} version={chk['version']} counts={chk['counts']} 重名={dup}")
assert dup == 0

print("[2] 备份 SFT 数据集并再同步旧条目")
shutil.copyfile(DS, DS_BAK)
bak = open(DS_BAK, "rb").read()
bak_lines = [l for l in bak.split(b"\n") if l.strip()]
assert len(bak_lines) == 120, len(bak_lines)

body = [json.loads(l.decode("utf-8")) for l in bak_lines]
resynced = 0
old_bytes = [l for l in bak_lines]
for name, cat in RESYNC:
    idx = next(i for i, d in enumerate(body)
               if ("FUNCTION " + name) in d["output"] or ("FUNCTION_BLOCK " + name) in d["output"])
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    body[idx]["output"] = raw.decode("utf-8")
    assert body[idx]["output"].encode("utf-8") == raw
    old_bytes[idx] = json.dumps(body[idx], ensure_ascii=False).encode("utf-8")
    resynced += 1
    print(f"    再同步 L{idx+1} {name} {len(raw)}B sha={sha(raw)[:12]}")

print("[3] 追加 16 条新条目")
new_lines, report = [], []
for name, cat, typ, tags, cplx, seg, src in NEW:
    md = json.load(open(os.path.join(META, name + ".json"), encoding="utf-8"))
    ins, arch = md["instruction"].strip(), md["architecture_thought"].strip()
    assert len(ins) >= 150 and len(arch) >= 150, f"{name} 文本过短"
    bad = [t for t in ("ROUND_PLAN", "泳道", "落盘", "C:\\Library", "clean-room", "§", "meta/", "JSONL")
           if t in ins or t in arch]
    assert not bad, f"{name} 内部流程信息残留 {bad}"
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    out = raw.decode("utf-8")
    assert out.encode("utf-8") == raw
    line = json.dumps({"instruction": ins, "architecture_thought": arch, "output": out}, ensure_ascii=False)
    assert "\n" not in line
    new_lines.append(line.encode("utf-8"))
    report.append((name, len(ins), len(arch), len(raw), sha(raw)[:12]))

with open(DS, "wb") as f:
    for lb in old_bytes:
        f.write(lb + b"\n")
    for lb in new_lines:
        f.write(lb + b"\n")

print("[4] 校验")
allb = open(DS, "rb").read()
lines = allb.split(b"\n")
assert lines[-1] == b""
body2 = lines[:-1]
print(f"    总行数={len(body2)}（120 存量 + 16 新增）")
assert len(body2) == 136
for i, lb in enumerate(body2, 1):
    d = json.loads(lb.decode("utf-8"))
    assert set(d.keys()) == {"instruction", "architecture_thought", "output"}, f"L{i} 字段异常"
print("    136/136 行合法 JSON，三字段齐备")

ok = 0
for idx, (name, cat, typ, tags, cplx, seg, src) in enumerate(NEW):
    d = json.loads(body2[120 + idx].decode("utf-8"))
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    if d["output"].encode("utf-8") == raw:
        ok += 1
    else:
        print(f"    [FAIL] {name} output 与源文件字节不一致")
print(f"    新增 16 条 output 字节一致 {ok}/16")
assert ok == 16

same = sum(1 for i in range(120) if i not in [next(j for j, (n, c) in enumerate(body) if n == RESYNC[0][0] and True)]
           and body2[i] == [l for l in bak.split(b"\n") if l.strip()][i])
print(f"    存量 120 行中未改动 {same}/119 行（Crc16 1 行已按修复再同步）")

print("[5] 逐条明细")
for name, ins, arch, blen, h in report:
    print(f"    {name:26s} ins={ins:3d} arch={arch:3d} {blen:6d}B sha={h}")
print(f"    数据集 sha256 前={sha(bak)[:16]} 后={sha(allb)[:16]}")
print("\n完成。")
