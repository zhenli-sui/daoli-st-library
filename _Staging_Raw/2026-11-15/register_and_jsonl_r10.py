# -*- coding: utf-8 -*-
"""R10 注册收口：INDEX_REGISTRY 登记（136→152）+ SFT JSONL 追加 16 条"""
import json, os, sys, io, shutil, hashlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
REG_BAK = os.path.join(LIB, "INDEX_REGISTRY.json.backup_R10")
META = os.path.join(LIB, r"_Staging_Raw\2026-11-15\meta\R10")
DS = os.path.join(LIB, r"_AI_Training_Dataset\daoli_st_sft_dataset.jsonl")
DS_BAK = DS + ".backup_R10"
TS = "2026-11-15T17:05:00+08:00"

# name, category, type, tags, complexity, code_segment, source
NEW = [
    ("FC_DL_BitFieldExtract", "DL_Base", "FC",
     ["lgf-bitlogic", "bit-field-extract", "offset-width", "right-align", "mask-construction"],
     3, "16#0001_0113~0115(信息级)", "lgf-bitlogic"),
    ("FC_DL_WeekOfYearCalc", "DL_Base", "FC",
     ["lgf-datetime", "iso-8601", "week-number", "thursday-attribution", "zeller-congruence"],
     5, "16#0001_0116~0117(信息级)", "lgf-datetime"),
    ("FB_DL_BidirectionalCounter", "DL_Base", "FB",
     ["lgf-counter", "ctud-superset", "dual-preset", "saturation", "up-priority-arbitration"],
     5, "16#0001_0118(信息级) / 16#0001_0215、0216(故障级)", "lgf-counter"),
    ("FC_DL_SearchMinMax", "DL_MathData", "FC",
     ["lgf-math", "extremum-scan", "index-report", "nan-guard", "single-pass"],
     4, "16#0001_0119、011A(信息级) / 16#0001_0217(故障级)", "lgf-math"),
    ("FC_DL_NthRoot", "DL_MathData", "FC",
     ["lgf-math", "nth-root", "odd-even-branch", "negative-domain-guard", "pure-function"],
     3, "16#0001_011B、011C(信息级)", "lgf-math"),
    ("FC_DL_FactorialSat", "DL_MathData", "FC",
     ["lgf-math", "factorial", "saturation", "domain-0-12", "pure-function"],
     2, "16#0001_011D(信息级)", "lgf-math"),
    ("FB_DL_SineGenerator", "DL_Algo", "FB",
     ["lgf-signalgen", "sine-wave", "phase-accumulation", "amplitude-offset", "clamp-output"],
     6, "16#0002_1B01~1B04(信息级) / 16#0002_1B10、1B11(故障级)", "lgf-signalgen"),
    ("FB_DL_SawtoothGenerator", "DL_Algo", "FB",
     ["lgf-signalgen", "sawtooth-triangle", "symmetry-ratio", "phase-normalised", "clamp-output"],
     6, "16#0002_1C01~1C03(信息级) / 16#0002_1C10(故障级)", "lgf-signalgen"),
    ("FC_DL_CoilDiameterCalc", "DL_Algo", "FC",
     ["lgf-technology", "coil-diameter", "line-speed-ratio", "low-speed-hold", "layer-count"],
     5, "16#0002_1D01~1D04(信息级) / 16#0002_1D10(故障级)", "lgf-technology"),
    ("FC_DL_AirDensity", "DL_Algo", "FC",
     ["oscat-building", "moist-air-density", "magnus-tetens", "partial-pressure", "domain-clamp"],
     4, "16#0002_1E01~1E04(信息级) / 16#0002_1E10(故障级)", "oscat-building"),
    ("I_DL_RfidReader", "DL_Device", "INTERFACE",
     ["tcopen-component", "rockwell-aoi", "interface-contract", "rfid-reader", "tag-snapshot"],
     3, "无（接口契约不发布故障码，码位由实现块承担）", "tcopen-component"),
    ("FB_DL_RfidTagHandler", "DL_Device", "FB",
     ["tcopen-component", "rockwell-aoi", "rfid-fsm", "duplicate-suppression", "retry-chain"],
     7, "16#0003_0138~013A(信息级) / 16#0003_02F0~02F3(故障级)", "tcopen-component"),
    ("FB_DL_AxiolineDiagLatch", "DL_Device", "FB",
     ["plcnext-community", "axioline-diagnosis", "bit-field-parse", "first-out-latch", "slot-locating"],
     6, "16#0003_013B、013C(信息级) / 16#0003_02F4~02F6(故障级)", "plcnext-community"),
    ("FB_DL_PdiReadScheduler", "DL_Device", "FB",
     ["plcnext-community", "pdi-read", "async-scheduler", "dual-code-packing", "length-verify"],
     7, "16#0003_013D~013F(信息级) / 16#0003_02F7~02F9(故障级)", "plcnext-community"),
    ("FB_DL_WindingTraverse", "DL_Motion", "FB",
     ["lgf-technology", "s7-motion", "diameter-recursion", "traverse-winding", "endpoint-dwell"],
     8, "16#0004_01B0~01B3(信息级) / 16#0004_02C0~02C3(故障级)", "lgf-technology"),
    ("FB_DL_PickAndPlaceStation", "DL_Process", "FB",
     ["packml-omac", "tcopen-component", "pick-and-place", "state-machine", "dependency-injection"],
     9, "16#0005_01B0~01B4(信息级) / 16#0005_02B0~02B7(故障级)", "packml-omac"),
]


def sha(b):
    return hashlib.sha256(b).hexdigest()


print("[1] 备份 INDEX_REGISTRY.json")
shutil.copyfile(REG, REG_BAK)
reg = json.load(open(REG, encoding="utf-8"))
print(f"    前: total={reg['total_components']} version={reg['version']} counts={reg['counts']}")
assert reg["total_components"] == 136 and len(reg["components"]) == 136

names = {c["name"] for c in reg["components"]}
for name, cat, typ, tags, cplx, seg, src in NEW:
    assert name not in names, f"重复登记 {name}"
    fp = os.path.join(LIB, cat, name + ".st")
    assert os.path.exists(fp), f"文件不存在 {fp}"
    md = json.load(open(os.path.join(META, name + ".json"), encoding="utf-8"))
    assert md["function_tags"] == tags, f"{name} 标签与 meta 不一致"
    assert md["complexity"] == cplx, f"{name} 复杂度与 meta 不一致"
    reg["components"].append({
        "name": name, "category": cat, "type": typ, "file_path": fp,
        "function_tags": tags, "complexity": cplx, "registered_at": TS,
        "code_segment": seg, "source": src,
    })

reg["version"] = "1.9.0"
reg["total_components"] = len(reg["components"])
reg["last_updated"] = TS
counts = {}
for c in reg["components"]:
    counts[c["category"]] = counts.get(c["category"], 0) + 1
reg["counts"] = {k: counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo",
                                        "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["total_components"] == 152
assert reg["counts"] == {"DL_Base": 32, "DL_MathData": 29, "DL_Algo": 24, "DL_Device": 36,
                         "DL_Motion": 15, "DL_Process": 16}, reg["counts"]

with open(REG, "w", encoding="utf-8", newline="\n") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
chk = json.load(open(REG, encoding="utf-8"))
assert chk["total_components"] == 152 and len(chk["components"]) == 152
assert all(os.path.exists(c["file_path"]) for c in chk["components"])
dup = len(chk["components"]) - len({c["name"] for c in chk["components"]})
print(f"    后: total={chk['total_components']} version={chk['version']} "
      f"counts={chk['counts']} 重名={dup}")
assert dup == 0

print("[2] 备份 SFT 数据集")
shutil.copyfile(DS, DS_BAK)
bak = open(DS_BAK, "rb").read()
old_lines = [l for l in bak.split(b"\n") if l.strip()]
assert len(old_lines) == 136, len(old_lines)
for i, lb in enumerate(old_lines, 1):
    json.loads(lb.decode("utf-8"))
print(f"    备份 {len(old_lines)} 行，逐行 JSON 合法")

print("[3] 追加 16 条新条目（output 从 .st 读取注入）")
new_lines, report = [], []
for name, cat, typ, tags, cplx, seg, src in NEW:
    md = json.load(open(os.path.join(META, name + ".json"), encoding="utf-8"))
    ins, arch = md["instruction"].strip(), md["architecture_thought"].strip()
    assert len(ins) >= 150 and len(arch) >= 150, f"{name} 文本过短"
    bad = [t for t in ("ROUND_PLAN", "泳道", "落盘", "C:\\Library", "clean-room",
                       "§", "meta/", "JSONL") if t in ins or t in arch]
    assert not bad, f"{name} 内部流程信息残留 {bad}"
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    out = raw.decode("utf-8")
    assert out.encode("utf-8") == raw
    line = json.dumps({"instruction": ins, "architecture_thought": arch, "output": out},
                      ensure_ascii=False)
    assert "\n" not in line
    new_lines.append(line.encode("utf-8"))
    report.append((name, len(ins), len(arch), len(raw), sha(raw)[:12]))

with open(DS, "wb") as f:
    for lb in old_lines:
        f.write(lb + b"\n")
    for lb in new_lines:
        f.write(lb + b"\n")

print("[4] 校验")
allb = open(DS, "rb").read()
lines = allb.split(b"\n")
assert lines[-1] == b""
body = lines[:-1]
print(f"    总行数={len(body)}（136 存量 + 16 新增）")
assert len(body) == 152
short_legacy = 0
for i, lb in enumerate(body, 1):
    d = json.loads(lb.decode("utf-8"))
    assert set(d.keys()) == {"instruction", "architecture_thought", "output"}, f"L{i} 字段异常"
    assert d["output"].strip()
    if i > 136:
        assert len(d["instruction"]) >= 150, f"L{i} 新增条目 instruction 过短"
    elif len(d["instruction"]) < 150:
        short_legacy += 1
print(f"    152/152 行合法 JSON，三字段齐备；新增 16 条 instruction 均不少于 150 字"
      f"（存量中 {short_legacy} 条不足 150 字，属历史条目，本轮不动）")

ok = 0
for idx, (name, cat, typ, tags, cplx, seg, src) in enumerate(NEW):
    d = json.loads(body[136 + idx].decode("utf-8"))
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    if d["output"].encode("utf-8") == raw:
        ok += 1
    else:
        print(f"    [FAIL] {name} output 与源文件字节不一致")
print(f"    新增 16 条 output 字节一致 {ok}/16")
assert ok == 16

same = 0
old_bak = [l for l in open(DS_BAK, "rb").read().split(b"\n") if l.strip()]
for i in range(136):
    if body[i] == old_bak[i]:
        same += 1
print(f"    存量 136 行未改动 {same}/136")
assert same == 136

print("[5] 逐条明细")
for name, ins, arch, blen, h in report:
    print(f"    {name:28s} ins={ins:3d} arch={arch:3d} {blen:6d}B sha={h}")
print(f"    数据集 sha256 前={sha(bak)[:16]} 后={sha(allb)[:16]}")
print("\n完成。")
