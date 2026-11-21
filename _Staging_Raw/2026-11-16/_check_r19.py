# -*- coding: utf-8 -*-
"""R19 红线机检：7 项红线 + 码位账实一致 + 禁记号扫描（逐件 PASS/FAIL）"""
import io, os, re, sys, json

SPEC = {
 # name : (reserved_codes, required_codes)
 "FC_DL_DintMsToTod":      ["16#0001_0401","16#0001_0320"],
 "FC_DL_TimeRatioCalc":    ["16#0001_0323"],
 "FC_DL_RatioToPwrDb":     ["16#0001_0326"],
 "FC_DL_LintToUdintSat":   ["16#0001_0328","16#0001_0329"],
 "FB_DL_BitShiftRegister": ["16#0001_0409","16#0001_032C"],
 "FC_DL_ModbusRtuFrameCheck": [],
 "FB_DL_FlowSqrtExtract":  ["16#0002_2702","16#0002_2712"],
 "FB_DL_RatioController":  ["16#0002_2802"],
 "FB_DL_LeadLagCompensator":["16#0002_2902","16#0002_2912"],
 "FB_DL_AutoTuneRelay":    ["16#0002_2A02"],
 "FB_DL_DeviceHealthArbiter":["16#0003_016B","16#0003_0332"],
 "FB_DL_ProfinetAlarmDiag":["16#0003_016D","16#0003_0335"],
 "FB_DL_EscChuckCurrentMonitor":["16#0003_016F"],
 "FB_DL_DeviceParamWrite": ["16#0003_0171"],
 "FB_DL_ExternalEncoderScaler":["16#0004_01CE"],
 "FB_DL_CamPhaseTrim":     ["16#0004_01D0"],
 "FB_DL_FilmWebCenter":    ["16#0004_01D2"],
 "FB_DL_WindingLayerCounter":["16#0004_01D4","16#0004_02E9"],
 "FB_DL_DrumLevelThreeElem":["16#0005_01D7"],
 "FB_DL_VacCupRingCtrl":   ["16#0005_01D9"],
}
CAT = {"FC_DL_DintMsToTod":"DL_MathData","FC_DL_TimeRatioCalc":"DL_MathData",
 "FC_DL_RatioToPwrDb":"DL_MathData","FC_DL_LintToUdintSat":"DL_MathData",
 "FB_DL_BitShiftRegister":"DL_Base","FC_DL_ModbusRtuFrameCheck":"DL_MathData",
 "FB_DL_FlowSqrtExtract":"DL_Algo","FB_DL_RatioController":"DL_Algo",
 "FB_DL_LeadLagCompensator":"DL_Algo","FB_DL_AutoTuneRelay":"DL_Algo",
 "FB_DL_DeviceHealthArbiter":"DL_Device","FB_DL_ProfinetAlarmDiag":"DL_Device",
 "FB_DL_EscChuckCurrentMonitor":"DL_Device","FB_DL_DeviceParamWrite":"DL_Device",
 "FB_DL_ExternalEncoderScaler":"DL_Motion","FB_DL_CamPhaseTrim":"DL_Motion",
 "FB_DL_FilmWebCenter":"DL_Motion","FB_DL_WindingLayerCounter":"DL_Motion",
 "FB_DL_DrumLevelThreeElem":"DL_Process","FB_DL_VacCupRingCtrl":"DL_Process"}

CODE_RE = re.compile(r"16#000[1-5]_[0-9A-F]{4}")

def check(name, root="C:/Library"):
    path = os.path.join(root, CAT[name], name + ".st")
    if not os.path.exists(path):
        return name, ["MISSING FILE"], 0
    s = io.open(path, encoding="utf-8").read()
    lines = s.splitlines()
    fails = []

    # 红线 1：零全局 / 零物理地址（含注释）
    for tok in ["GVL", "VAR_EXTERNAL", "g_"]:
        for i, l in enumerate(lines, 1):
            if tok in l and not l.strip().startswith("*"):
                if tok == "g_":
                    if re.search(r"\bg_[A-Za-z]", l):
                        fails.append("L%d 出现全局记号 %s" % (i, tok))
                else:
                    fails.append("L%d 出现禁记号 %s" % (i, tok))
    if re.search(r"%[IQM][XBWDL]?\d", s):
        fails.append("出现物理地址 %I/%Q/%M")
    # 红线 7：零厂商库 / 零指针
    if re.search(r"\b(Sys[A-Z]\w+|Tc[A-Z]\w+|SM3_\w+)", s):
        fails.append("出现厂商库记号")
    if "POINTER TO" in s or "REFERENCE TO" in s:
        fails.append("出现指针/引用类型")
    # 禁 WHILE
    if re.search(r"\bWHILE\b", s):
        fails.append("出现 WHILE")

    # 终结符
    if name.startswith("FC_"):
        if "END_FUNCTION" not in s or "FUNCTION " not in s:
            fails.append("缺 END_FUNCTION/FUNCTION 头")
    else:
        if "END_FUNCTION_BLOCK" not in s:
            fails.append("缺 END_FUNCTION_BLOCK")

    # 红线 3：声明区逐行双语注释
    in_var = False
    for i, l in enumerate(lines, 1):
        st = l.strip()
        if re.match(r"^VAR(_INPUT|_OUTPUT|_IN_OUT|_TEMP)?(\s+CONSTANT)?$", st):
            in_var = True; continue
        if st == "END_VAR":
            in_var = False; continue
        if in_var and st and not st.startswith("//") and not st.startswith("(*"):
            if "//" not in l:
                fails.append("L%d 声明行缺同行注释: %s" % (i, st[:52]))
            elif not re.search(r"[\u4e00-\u9fff]", l):
                fails.append("L%d 声明行缺中文注释" % i)

    # 红线 5：定时器/沿实例无条件刷新（调用行不得缩进进 IF/CASE）
    for m in re.finditer(r"^\s+fb(Trig\w+|Timeout|Build|LossConfirm|Write|Verify|Confirm)\(\s*(CLK|IN)", s, re.M):
        fails.append("L? 实例调用被缩进（疑似在条件分支内）: " + m.group(0).strip())

    # 红线 4：状态机 CASE 必须带 ELSE；纯函数无状态机必须有 R6 句式
    has_case = re.search(r"\bCASE[ \t]+[A-Za-z_]\w*[ \t]+OF\b", s)
    has_state_case = re.search(r"\bCASE[ \t]+[A-Za-z_]*[Ss]tate[A-Za-z_]*[ \t]+OF\b", s)
    if has_case:
        if not re.search(r"\bELSE\b", s):
            fails.append("有 CASE 但无 ELSE 兜底")
        if "R6 标注 N/A" in s and has_state_case:
            fails.append("有状态机 CASE 却标注 N/A")
    else:
        if "R6 标注 N/A" not in s and not re.search(r"无 CASE", s):
            fails.append("无 CASE 且未写 R6 N/A 句式")

    # 码位：头注释 5 槽 + 实现体一致
    codes = CODE_RE.findall(s)
    uniq = sorted(set(codes))
    if len(uniq) != 5:
        fails.append("码位槽数 != 5 实际 %d: %s" % (len(uniq), uniq))
    if "码位总账" not in s:
        fails.append("缺码位总账行")
    body = s.split("*)", 1)[-1] if "(*" in s else s
    for rc in SPEC[name]:
        if len(re.findall(r"\b" + re.escape(rc) + r"\b", body)) > 0:
            fails.append("预留码 %s 在实现体内被赋值" % rc)
        if s.count(rc) < 2:
            fails.append("预留码 %s 未在头注释列全" % rc)

    # 浮点判等（宽松：形如 fX = fY / fX <> fY 的可疑行，排除 <> fX 用于 NaN 复检）
    for i, l in enumerate(lines, 1):
        if re.search(r"\bf[A-Z]\w*\s*(=|<>)\s*[-\w.]+\s*(THEN|;)", l):
            seg = l.split("//")[0]
            if re.search(r"\bf[A-Z]\w*\s*=\s*[-\d]", seg) or re.search(r"<>\s*[-\d]", seg):
                fails.append("L%d 浮点疑似判等: %s" % (i, seg.strip()[:60]))
    return name, fails, len(lines)

def main():
    todo = sys.argv[1:] or list(SPEC.keys())
    bad = 0
    for n in todo:
        nm, fails, ln = check(n)
        tag = "PASS" if not fails else "FAIL"
        if fails: bad += 1
        print("%-32s %-4s %4d lines" % (nm, tag, ln))
        for f in fails: print("      - " + f)
    print("---- 合计 %d 件，FAIL %d 件" % (len(todo), bad))

main()
