# -*- coding: utf-8 -*-
"""R47 增量机检（20 新件 + 4 返修件）：R44/R46 固化口径
词表：禁词 TODO/FIXME/XXX/待补[充善]；剥 // 与 (* *) 注释；
CASE 切分排 ':='；T0 溯源短语仅对 iec-std-wrapper/T0 类；R228B 排 ':='。
"""
import os, re, io, json

LIB = "C:/Library"
OUT = os.path.join(LIB, "_Staging_Raw", "2026-11-19", "_check_r47_result.json")

TARGETS = [
    # (name, cat, is_repair)
    ("FC_DL_IntFloorDiv", "DL_Base", False),
    ("FC_DL_ByteArrayXor", "DL_Base", False),
    ("FC_DL_CovarOnline", "DL_MathData", False),
    ("FB_DL_TrayerNestingCtrl", "DL_Process", False),
    ("FB_DL_OcvTempNormalize", "DL_Process", False),
    ("FB_DL_ElectrolyteFifoTrace", "DL_Process", False),
    ("FB_DL_StringFifoRetry", "DL_Process", False),
    ("FB_DL_TempCompClassify", "DL_Process", False),
    ("FB_DL_TankBlanketPrCtrl", "DL_Device", False),
    ("FB_DL_IvBcdExport", "DL_Device", False),
    ("FB_DL_RfidTrayRoute", "DL_Process", False),
    ("FB_DL_FoupRfidCheck", "DL_Process", False),
    ("FB_DL_ChuckVacuumSeq", "DL_Process", False),
    ("FB_DL_ChamberPumpDownSeq", "DL_Process", False),
    ("FB_DL_EfEmoInterlock", "DL_Process", False),
    ("FB_DL_LaminatorZoneSync", "DL_Process", False),
    ("FB_DL_R2rRunLogAudit", "DL_Process", False),
    ("FB_DL_CassetteBcdLabel", "DL_Device", False),
    ("FB_DL_AxisBacklashIdent", "DL_Motion", False),
    ("FB_DL_AxisCoggingFf", "DL_Motion", False),
    ("FB_DL_RlsEstimator", "DL_Algo", True),
    ("FB_DL_LuenbergerObserver", "DL_Algo", True),
    ("FB_DL_TabWeldingMonitor", "DL_Process", True),
    ("FB_DL_AxisFeedbackFailoverSeq", "DL_Motion", True),
]

BANNED_WORDS = [r"\bTODO\b", r"\bFIXME\b", r"待补[充善]", r"\bXXX\b"]

def strip_comments(t):
    t = re.sub(r"\(\*(?:(?!\(\*).)*?\*\)", " ", t, flags=re.S)
    t = re.sub(r"//[^\n]*", " ", t)
    return t

def check(name, cat, repair):
    p = os.path.join(LIB, cat, name + ".st")
    if not os.path.exists(p):
        return ["MISSING FILE"]
    raw = io.open(p, "rb").read()
    txt = raw.decode("utf-8", "replace")
    body = strip_comments(txt)
    errs = []
    # 禁词（原文含注释，禁词连注释也不许）
    for w in BANNED_WORDS:
        for m in re.finditer(w, txt):
            errs.append("BANNED WORD %s @L%d" % (w, txt[:m.start()].count("\n") + 1))
    # 禁硬接口
    for b in [r"\bVAR_EXTERNAL\b", r"\bGVL\b", r"%[IQM][XBWDL]?\d"]:
        for m in re.finditer(b, body):
            errs.append("BANNED %s @L%d" % (b, body[:m.start()].count("\n") + 1))
    # 枚举成员冒号（切分排 ':='）
    for m in re.finditer(r"TYPE\s+\w+\s*:\s*\(([^)]*)\)", body, flags=re.S):
        for mem in m.group(1).split(","):
            if re.search(r":(?!s*=)", mem):
                errs.append("ENUM COLON %s" % mem.strip()[:24])
    # CASE-ELSE 配对
    ncase = len(re.findall(r"^\s*CASE\b", body, re.M))
    nelse = len(re.findall(r"^\s*ELSE\s*$", body, re.M))
    if ncase and nelse < ncase:
        errs.append("CASE WITHOUT ELSE ncase=%d nelse=%d" % (ncase, nelse))
    # 嵌套注释
    if re.search(r"\(\*(?:(?!\*\)).)*\(\*", txt, flags=re.S):
        errs.append("NESTED COMMENT")
    # 新件必须有 VAR_OUTPUT；返修件豁免
    if not repair and not re.search(r"VAR_OUTPUT", body):
        errs.append("NO VAR_OUTPUT SECTION")
    # R228B：FB 实例调用在 IF 内（排 ':=' 赋值行）
    for m in re.finditer(r"^\s*(\w+)\s*\(\s*IN\s*:?=", body, re.M):
        inst = m.group(1)
        if re.search(r"\b%s\s*:\s*(TON|TOF|R_TRIG|F_TRIG|CTU|CTD)\b" % inst, body, re.I):
            depth = 0
            for line in body[:m.start()].splitlines():
                ls = line.strip()
                if re.match(r"IF\b", ls): depth += 1
                elif re.match(r"END_IF", ls): depth -= 1
            if depth > 0:
                errs.append("FB-INSTANCE IN IF %s @L%d" % (inst, body[:m.start()].count("\n") + 1))
    # POU 终止符
    if not re.search(r"^\s*END_FUNCTION(_BLOCK)?\b", body, re.M):
        errs.append("NO POU TERMINATOR")
    # CRLF
    if b"\r\n" not in raw:
        errs.append("NOT CRLF")
    # T0 溯源短语：仅 iec-std-wrapper/T0 类
    sm = re.search(r"来源标签[^:]*:\s*(.*)", txt)
    tag = sm.group(1) if sm else ""
    if ("T0" in tag or "iec-std-wrapper" in tag) and ("IEC 61131-3 标准语义" not in txt):
        errs.append("T0 溯源短语缺失（T0 件须注明 IEC 61131-3 标准语义来源）")
    # 返修件须有 v1.0.1 返修节
    if repair and not re.search(r"返修记录|v1\.0\.1", txt):
        errs.append("REPAIR HEADER MISSING v1.0.1")
    return errs

rows, fail = [], 0
for name, cat, repair in TARGETS:
    errs = check(name, cat, repair)
    if errs:
        fail += 1
    rows.append({"name": name, "category": cat, "repair": repair,
                 "result": "PASS" if not errs else "FAIL", "errors": errs})
    print(("PASS" if not errs else "FAIL"), name, cat, "(repair)" if repair else "")
    for e in errs:
        print("   -", e)

res = {"round": "R47", "date": "2026-11-19", "targets": len(TARGETS),
       "pass": len(TARGETS) - fail, "fail": fail, "rows": rows}
json.dump(res, io.open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
print("\nTOTAL %d PASS %d FAIL %d" % (len(TARGETS), len(TARGETS) - fail, fail))
