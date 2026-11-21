# -*- coding: utf-8 -*-
"""R8 注册收口：INDEX_REGISTRY 登记 + SFT JSONL 追加（字节级注入）"""
import json, os, sys, io, shutil, hashlib

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
REG_BAK = os.path.join(LIB, "INDEX_REGISTRY.json.backup_R8")
META = os.path.join(LIB, r"_Staging_Raw\2026-11-15\meta\R8")
DS = os.path.join(LIB, r"_AI_Training_Dataset\daoli_st_sft_dataset.jsonl")
DS_BAK = DS + ".backup_R8"
TS = "2026-11-15T11:30:23+08:00"

# name, category, type, tags, complexity, code_segment, source
NEW = [
    ("FB_DL_ElectronicGear", "DL_Motion", "FB",
     ["electronic-gear", "gear-ratio-coupling", "plcopen-motion", "phase-compensation", "speed-synchronization"],
     7, "16#0004_0130~0132(信息级) / 16#0004_0250~0252(故障级) / 16#0004_0299(兜底)",
     "plcopen-motion"),
    ("FB_DL_ElectronicCam", "DL_Motion", "FB",
     ["electronic-cam", "cam-profile", "plcopen-motion", "flying-shear", "phase-correction"],
     8, "16#0004_0140~0142(信息级) / 16#0004_0260~0265(故障级) / 16#0004_0298(兜底)",
     "plcopen-motion"),
    ("FB_DL_GantrySyncAxis", "DL_Motion", "FB",
     ["gantry-sync", "dual-drive", "skew-protection", "plcopen-motion", "following-error"],
     7, "16#0004_0150~0152(信息级) / 16#0004_0270~0274(故障级) / 16#0004_0297(兜底)",
     "plcopen-motion"),
    ("FB_DL_TorqueLimitControl", "DL_Motion", "FB",
     ["torque-limit", "press-fit", "plcopen-motion", "stop-point-detection", "in-position-window"],
     8, "16#0004_0160~0164(信息级) / 16#0004_0280~0284(故障级) / 16#0004_0296(兜底)",
     "plcopen-motion"),
    ("FB_DL_MarkPositionLatch", "DL_Motion", "FB",
     ["mark-latch", "registration-mark", "plcopen-motion", "position-capture", "pitch-measurement"],
     6, "16#0004_0170~0171(信息级) / 16#0004_0290(故障级) / 16#0004_0295(兜底)",
     "plcopen-motion"),
    ("FC_DL_CalcMoveTime", "DL_Motion", "FC",
     ["cycle-time-estimation", "trapezoidal-profile", "plcopen-motion", "motion-planning", "pure-function"],
     5, "16#0004_0180~0184(入参非法/不可达，无故障锁存)",
     "plcopen-motion"),
    ("FB_DL_ConveyorLineLink", "DL_Process", "FB",
     ["smema", "handshake", "conveyor-cascade", "line-link", "watchdog"],
     6, "16#0005_0130~0133(信息级) / 16#0005_0230~0231(故障级)",
     "smema"),
    ("FB_DL_RecipeManager", "DL_Process", "FB",
     ["recipe-management", "codesys-forge", "parameter-validation", "recipe-switch", "checksum"],
     6, "16#0005_0140~0143(信息级) / 16#0005_0240~0246(故障级)",
     "codesys-forge"),
    ("FB_DL_LeakTestStation", "DL_Process", "FB",
     ["leak-test", "pressure-decay", "leak-rate", "test-station", "ok-ng-verdict"],
     8, "16#0005_0150~0153(信息级) / 16#0005_0250~0257(故障级)",
     "leak-test"),
    ("FB_DL_MixRecipeControl", "DL_Process", "FB",
     ["mixing", "isa-88-phase", "agitation", "torque-limit", "recipe-control"],
     8, "16#0005_0160~0164(信息级) / 16#0005_0260~0265(故障级)",
     "isa-88-phase"),
    ("FB_DL_CipCleaningSeq", "DL_Process", "FB",
     ["cip-cleaning", "isa-88-phase", "phase-sequencing", "conductivity-endpoint", "tact-interlock"],
     8, "16#0005_0170~0173(信息级) / 16#0005_0270~0274(故障级)",
     "cip-cleaning"),
    ("FB_DL_BufferMagazine", "DL_Process", "FB",
     ["buffer-magazine", "slot-management", "storage-scheduling", "lift-control", "material-handling"],
     7, "16#0005_0180~0186(信息级) / 16#0005_0280~0283(故障级)",
     "material-handling"),
    ("I_DL_TowerLight", "DL_Device", "IF",
     ["tcopen-component", "stack-light", "andon", "tower-light", "interface-contract"],
     3, "无（接口契约不发布故障码，码位由实现块承担）",
     "tcopen-component"),
    ("FB_DL_SignalTower", "DL_Device", "FB",
     ["tcopen-component", "stack-light", "andon", "priority-arbitration", "buzzer-silence"],
     7, "16#0003_0123~0126(信息级) / 16#0003_02D0~02D1(故障级)",
     "tcopen-component"),
    ("FB_DL_PeakDetector", "DL_Algo", "FB",
     ["lgf-math", "peak-hold", "extremum-tracking", "signal-conditioning", "envelope-detection"],
     5, "16#0002_1901~1904(信息级/入参降级)",
     "lgf-math"),
    ("FB_DL_StepController", "DL_Algo", "FB",
     ["lbp-step-controller", "lgf-technology", "stage-control", "hysteresis", "load-rotation"],
     8, "16#0002_1A01~1A06(信息级/参数钳位)",
     "lbp-step-controller"),
]

# 泳道 B 六条 instruction 质量补写（原文本含轮次编号/泳道/落盘路径等内部流程信息）
REWRITE = {
 "FB_DL_ConveyorLineLink":
  "板线拼线时上游机给出有料信号、下游机给出可收信号，两边还各有一路强制抑制。接线习惯各家不一样：有人叫有料，有人叫请求，接反了不会报错，只是一直不传板。要写一个与供应商无关的握手协调器：三路输入各带独立消抖，握手判据要能一眼看懂；传递卡住要能锁住并只由复位清除；消抖窗配得比看门狗还长时不许出现幽灵超时，这条要自己兜住。维护直通只强制抑制输出为 FALSE，但不能绕过卡料锁存。两组互斥信号如果同一拍都为真，按保守侧不放行，只出信息码提示接线错误，不要替现场仲裁。",
 "FB_DL_RecipeManager":
  "一台设备要做十几个规格，配方参数放在数组里由上位机下发，加载、写回、校验三个动作按上升沿受理。校验要一层层过：配方号在不在域内、这条配方启没启用、参数个数对不对、有没有非有限值、每项在不在上下限里、校验和对不对。应用必须一拍全量写进去，不能出现写了一半的中间态，写完再回读比对一次。机台运行中拒载配方算正常联锁不算故障，只给提示。写回时把校验和清零，不要替上位机伪造。越界标志要直接指向第一个越界项，另外留审计计数。",
 "FB_DL_LeakTestStation":
  "压降法气密检漏：夹具确认、充气、稳压、隔离测量、换算泄漏率、排气、判 OK/NG 这一串相序。现场最容易出两个错——稳压时间太短既藏漏又造漏，还有把设备自己的毛病判成工件不合格。要求：稳压阶段压力超出容差一律算设备异常，只有泄漏率超限才算工件 NG，两类码不能混着写。充气要保证最小保持时间并且压力达标；测量窗内压力陡降按大漏提前判 NG；压差回负按零处理。泄漏率换算带温度补偿，量纲要写清楚。中止指令最高优先，直接安全排气且不记 NG。容积、时长这类参数非法要锁故障，不要硬算。",
 "FB_DL_MixRecipeControl":
  "搅拌罐按相控制：投料就绪后定速搅拌，也可以正反交替搅，时间到或扭矩上升到位就判终点，然后慢速出料助排、停转。最大的坑是正反转直接反接，减速机很快就打坏；另外变频器接口每拍只许一次方法调用，代码里散着调用必然打架。要求：交替换向必须先停、等转速落零再反向启动，设定值补发不能和启动同拍；搅拌计时只在转速确认建立后累计，中途降速暂停不虚增时长。扭矩超限立即停机并锁存，频率设定越界钳位给提示、不报警停线。驱动报故障时不许下发启动指令。",
 "FB_DL_CipCleaningSeq":
  "CIP 原位清洗六相：预冲、碱洗、中冲、酸洗、终冲、消毒。现场最关心的是「洗了多久」和「洗干净没有」是两回事：温度、电导率、流量任一不达标，这一相的时间就不该继续算，要冻结并提示，恢复后接着累计；但停太久就该判这一相失败。终冲洗不要用固定时间判终点，按回液电导率判，时间只做最长兜底。换相先停泵留个间隔，防止酸碱混液。清洗完成给一个许可信号放行生产，中止就立即失效。运行中改相序要拒绝并提示，不许中途跳相；加药按周期发脉冲，脉冲要能自清。",
 "FB_DL_BufferMagazine":
  "多层料仓升降存取：取料去最低的满层，存良品去最低空层，存不良品优先占隔离位；层位置和到位信号都从引脚来，块里不许出现硬件依赖。方向指令要用层位置和目标层同源比较算出来，天然互斥；层位置未知时不许发方向指令，等超时锁存。到位判据是层号相等且到位信号消抖后为真。手动指定层优先，指定的层对不上就拒绝；运行中改目标层下一周期生效。空层、满层、占用计数每拍重算，越界钳位不要停机。",
}


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


# ---------- 1. registry ----------
print("[1] 备份 INDEX_REGISTRY.json")
shutil.copyfile(REG, REG_BAK)
print(f"    -> {REG_BAK}  sha256={sha(REG_BAK)[:16]}  bytes={os.path.getsize(REG_BAK)}")
reg = json.load(open(REG, encoding="utf-8"))
print(f"    备份前合法 JSON：total={reg['total_components']} version={reg['version']} "
      f"counts={reg['counts']} 实际条目={len(reg['components'])}")
assert reg["total_components"] == 104 and len(reg["components"]) == 104, "备份前状态不符"

names = {c["name"] for c in reg["components"]}
for name, cat, typ, tags, cplx, seg, src in NEW:
    assert name not in names, f"重复登记 {name}"
    fp = os.path.join(LIB, cat, name + ".st")
    assert os.path.exists(fp), f"文件不存在 {fp}"
    reg["components"].append({
        "name": name,
        "category": cat,
        "type": typ,
        "file_path": fp,
        "function_tags": tags,
        "complexity": cplx,
        "registered_at": TS,
        "code_segment": seg,
        "source": src,
    })

reg["version"] = "1.7.0"
reg["total_components"] = len(reg["components"])
reg["last_updated"] = TS
counts = {}
for c in reg["components"]:
    counts[c["category"]] = counts.get(c["category"], 0) + 1
reg["counts"] = {k: counts[k] for k in ["DL_Base", "DL_MathData", "DL_Algo", "DL_Device", "DL_Motion", "DL_Process"]}
assert reg["total_components"] == 120, reg["total_components"]
assert reg["counts"] == {"DL_Base": 24, "DL_MathData": 20, "DL_Algo": 20, "DL_Device": 30,
                         "DL_Motion": 13, "DL_Process": 13}, reg["counts"]

with open(REG, "w", encoding="utf-8", newline="\n") as f:
    json.dump(reg, f, ensure_ascii=False, indent=2)
    f.write("\n")
chk = json.load(open(REG, encoding="utf-8"))
print(f"    写入后合法 JSON：total={chk['total_components']} version={chk['version']} ",
      f"counts={chk['counts']} 条目={len(chk['components'])}")
assert chk["total_components"] == 120 and len(chk["components"]) == 120
assert all(os.path.exists(c["file_path"]) for c in chk["components"]), "存在失效 file_path"

# ---------- 2. 元数据质量补写 ----------
print("[2] 元数据质量补写（内部流程信息清理）")
for nm, txt in REWRITE.items():
    mp = os.path.join(META, nm + ".json")
    md = json.load(open(mp, encoding="utf-8"))
    old = md["instruction"]
    md["instruction"] = txt
    with open(mp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(md, f, ensure_ascii=False, indent=2)
        f.write("\n")
    bad = [t for t in ("ROUND_PLAN", "泳道", "落盘", "C:\\Library", "clean-room", "§") if t in txt]
    print(f"    {nm:28s} {len(old)} -> {len(txt)} 字符 残留内部标记={bad or '无'}")

# ---------- 3. JSONL ----------
print("[3] 备份 SFT 数据集")
shutil.copyfile(DS, DS_BAK)
bak_bytes = open(DS_BAK, "rb").read()
print(f"    -> {DS_BAK}  sha256={sha(DS_BAK)[:16]}  bytes={len(bak_bytes)}")
bak_lines = [l for l in bak_bytes.split(b"\n") if l.strip()]
print(f"    备份行数={len(bak_lines)}")
assert len(bak_lines) == 104

orig = open(DS, "rb").read()
assert orig == bak_bytes, "备份与正文不一致"
if not orig.endswith(b"\n"):
    orig += b"\n"

new_lines, report = [], []
for name, cat, typ, tags, cplx, seg, src in NEW:
    md = json.load(open(os.path.join(META, name + ".json"), encoding="utf-8"))
    ins, arch = md["instruction"].strip(), md["architecture_thought"].strip()
    assert len(ins) >= 150 and len(arch) >= 150, f"{name} 文本过短"
    fp = os.path.join(LIB, cat, name + ".st")
    raw = open(fp, "rb").read()
    out = raw.decode("utf-8")
    assert out.encode("utf-8") == raw, f"{name} 字节级往返不一致"
    rec = {"instruction": ins, "architecture_thought": arch, "output": out}
    line = json.dumps(rec, ensure_ascii=False)
    assert "\n" not in line, f"{name} 出现裸换行"
    new_lines.append(line.encode("utf-8"))
    report.append((name, len(ins), len(arch), len(raw), hashlib.sha256(raw).hexdigest()))

with open(DS, "ab") as f:
    for lb in new_lines:
        f.write(lb + b"\n")

# ---------- 4. 校验 ----------
print("[4] 逐行 JSON 校验 + 一致性验证")
allb = open(DS, "rb").read()
lines = allb.split(b"\n")
assert lines[-1] == b"", "文件末尾缺换行"
body = lines[:-1]
print(f"    总行数={len(body)}（备份 104 + 新增 {len(new_lines)}）")
assert len(body) == 120
bad = []
for i, lb in enumerate(body, 1):
    try:
        d = json.loads(lb.decode("utf-8"))
    except Exception as ex:
        bad.append(f"L{i} JSON 非法: {ex}")
        continue
    if set(d.keys()) != {"instruction", "architecture_thought", "output"}:
        bad.append(f"L{i} 字段不符: {list(d.keys())}")
assert not bad, bad
print("    120/120 行合法 JSON，三字段齐备")

# 新增 16 条与 .st 字节比对
ok_bytes = 0
for idx, (name, cat, *_rest) in enumerate(NEW):
    d = json.loads(body[104 + idx].decode("utf-8"))
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    if d["output"].encode("utf-8") == raw:
        ok_bytes += 1
    else:
        print(f"    [FAIL] {name} output 与源文件字节不一致")
print(f"    output 字节一致 {ok_bytes}/16")

# 前 104 条字节不变
prefix_same = body[:104] == [l for l in bak_bytes.split(b"\n") if l.strip()]
if not prefix_same:
    diff = next(i for i in range(104) if body[i] != [l for l in bak_bytes.split(b"\n") if l.strip()][i])
    print(f"    [FAIL] 前 104 条在第 {diff+1} 行发生字节变化")
print(f"    前 104 条逐字节未变：{'是' if prefix_same else '否'}")
print(f"    文件 sha256 前={hashlib.sha256(bak_bytes).hexdigest()[:16]} 后={hashlib.sha256(allb).hexdigest()[:16]}")

print("[5] 新增条目 sha256 对照（JSONL 内 output vs 源文件）")
for idx, (name, cat, typ, tags, cplx, seg, src) in enumerate(NEW):
    d = json.loads(body[104 + idx].decode("utf-8"))
    raw = open(os.path.join(LIB, cat, name + ".st"), "rb").read()
    h_src = hashlib.sha256(raw).hexdigest()
    h_json = hashlib.sha256(d["output"].encode("utf-8")).hexdigest()
    print(f"    {name:30s} ins={len(d['instruction']):3d} arch={len(d['architecture_thought']):3d} "
          f"{len(raw):6d}B sha={h_src[:12]} 一致={'是' if h_src == h_json else '否'}")
    assert h_src == h_json, name

print("\n完成。")
