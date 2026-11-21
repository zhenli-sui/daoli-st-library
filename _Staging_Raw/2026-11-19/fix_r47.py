# -*- coding: utf-8 -*-
"""R47 收口修复：JSONL 重追加 20 行 + ROADMAP 勾选模式修正"""
import json, os, re, datetime

ROOT = r"C:\Library"
JL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
RM = os.path.join(ROOT, "ROADMAP.md")
ts = datetime.datetime.now().astimezone().replace(microsecond=0).isoformat()

ITEMS = [
 ("FC_DL_IntFloorDiv","DL_Base"),("FC_DL_ByteArrayXor","DL_Base"),("FC_DL_CovarOnline","DL_MathData"),
 ("FB_DL_TrayerNestingCtrl","DL_Process"),("FB_DL_OcvTempNormalize","DL_Process"),
 ("FB_DL_ElectrolyteFifoTrace","DL_Process"),("FB_DL_StringFifoRetry","DL_Process"),
 ("FB_DL_TempCompClassify","DL_Process"),("FB_DL_TankBlanketPrCtrl","DL_Device"),
 ("FB_DL_IvBcdExport","DL_Device"),("FB_DL_RfidTrayRoute","DL_Process"),
 ("FB_DL_FoupRfidCheck","DL_Process"),("FB_DL_ChuckVacuumSeq","DL_Process"),
 ("FB_DL_ChamberPumpDownSeq","DL_Process"),("FB_DL_EfEmoInterlock","DL_Process"),
 ("FB_DL_LaminatorZoneSync","DL_Process"),("FB_DL_R2rRunLogAudit","DL_Process"),
 ("FB_DL_CassetteBcdLabel","DL_Device"),("FB_DL_AxisBacklashIdent","DL_Motion"),
 ("FB_DL_AxisCoggingFf","DL_Motion"),
]

def parse_header(text):
    head = text[: text.find("*)")] if text.find("*)") > 0 else text[:3000]
    secs, cur, buf = {}, "__preamble__", []
    for line in head.splitlines():
        sm = re.match(r"^\s*\*\s*([^\s(\*][^(\*]{0,12}?)\s*(\([^)]*\))?\s*:\s*(.*)$", line)
        if sm:
            if cur in secs:
                secs[cur] = "\n".join(buf).strip()
            cur = sm.group(1).strip()
            first = sm.group(3).strip()
            buf = [first] if first else []
        else:
            lm = re.match(r"^\s*\*\s?(.*)$", line)
            if lm:
                buf.append(lm.group(1).rstrip())
    if cur in secs or buf:
        secs[cur] = "\n".join(buf).strip()
    return secs

def clean(s):
    return re.sub(r"\s+", " ", s or "").strip()

def states_of(text):
    i = text.find("*)")
    b = text[i+2:] if i >= 0 else text
    seen, out = set(), set()
    for m in re.finditer(r"\be[A-Z][A-Za-z0-9]{2,}\b", b):
        t = m.group(0)
        if t in ("eState","eCause","eStatus","eHealth","eGrade","eError") or t in seen:
            continue
        seen.add(t); out.add(t)
        if len(out) >= 8:
            break
    return "/".join(sorted(out)[:8])

lines = open(JL, encoding="utf-8", newline="").read().splitlines()
assert len(lines) == 826, len(lines)
new_outs = {}
with open(JL, "a", encoding="utf-8", newline="") as f:
    for name, cat in ITEMS:
        p = os.path.join(ROOT, cat, name + ".st")
        t = open(p, encoding="utf-8", newline="").read()
        new_outs[name] = t
        secs = parse_header(t)
        ins = "真实工况需求：" + clean(secs.get("功能描述","")) + " 边界条件：" + clean(secs.get("边界",""))
        if len(ins) > 2200:
            ins = ins[:2200] + "……（完整边界见 .st 头注释）"
        parts = ["状态机：" + (states_of(t) if states_of(t) else "纯函数零状态（FC 无状态机）")]
        if clean(secs.get("分工声明","")):
            parts.append("解耦：" + clean(secs.get("分工声明","")))
        parts.append("防错：组态闸前置覆盖每个参与判据引脚、非有限（NaN/Inf）自反判、TON/R_TRIG 段 0 无条件周期刷新、锁存态解除式唯一迁出路径——详见头注释「边界」「解除式」「红线自检」各节（OOP 解耦：全引脚注入，零 GVL/VAR_EXTERNAL/物理地址）。")
        f.write(json.dumps({"instruction": ins, "architecture_thought": " ".join(parts),
                            "output": t}, ensure_ascii=False) + "\n")

lines2 = open(JL, encoding="utf-8", newline="").read().splitlines()
bad = 0
for x in lines2:
    try: json.loads(x)
    except Exception: bad += 1
tail = [json.loads(x) for x in lines2[-20:]]
ok = sum(1 for i,(n,c) in enumerate(ITEMS) if tail[i]["output"] == new_outs[n])
print("JSONL lines=%d badjson=%d MATCH=%d/20" % (len(lines2), bad, ok))

rm = open(RM, encoding="utf-8", newline="").read()
ticked = []
for name, cat in ITEMS:
    pat = re.compile(r"\[ \] `" + name + r"`")
    if pat.search(rm):
        rm = pat.sub(r"[x] `" + name + r"`", rm, count=1)
        ticked.append(name)
with open(RM, "w", encoding="utf-8", newline="") as f:
    f.write(rm)
print("ROADMAP ticked", len(ticked))
for n in ticked: print(" -", n)
