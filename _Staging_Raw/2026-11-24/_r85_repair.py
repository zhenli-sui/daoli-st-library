# -*- coding: utf-8 -*-
"""R85 定点修复 4 件（3 件审校 BLOCK + 1 件加固）。仅最小修，不改语义结构。"""
import io, sys, os, shutil
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
LIB = r'C:\Library'
def patch(path, pairs, must=True):
    p = os.path.join(LIB, path)
    s = open(p, encoding='utf-8').read()
    orig = s
    for a, b in pairs:
        if a not in s:
            print('  MISS:', path, '|', a[:60].replace('\n', ' '))
            if must: return False
            continue
        s = s.replace(a, b, 1)
    if s == orig:
        print('  NOCHANGE', path); return False
    shutil.copy2(p, p + '.bak_r85fix')
    open(p, 'w', encoding='utf-8').write(s)
    print('  FIXED', path)
    return True

# ---- 1. QuenchOil：换热能力量纲 kW -> kW/K（QA BLOCK #3，属实）----
print('[1] FC_DL_QuenchOilTempRiseCalc 量纲修复')
patch(r'DL_Process\FC_DL_QuenchOilTempRiseCalc.st', [
 ('    fExchCapKW  : REAL;   (* 换热器换热能力 [kW] Heat exchanger capacity *)',
  '    fExchCapKWperK : REAL; (* 换热器换热能力（k·A 传导率）[kW/K] Heat exchanger conductance k*A *)'),
 ('fExchCapKW <> fExchCapKW', 'fExchCapKWperK <> fExchCapKWperK'),
 ('((fExchCapKW - fExchCapKW) <> 0.0)', '((fExchCapKWperK - fExchCapKWperK) <> 0.0)'),
 ('OR (fExchCapKW <= DL_EPS) THEN', 'OR (fExchCapKWperK <= DL_EPS) THEN'),
 ('(* 热平衡稳态：热源平均功率 Q/t [kJ/s = kW] 由换热能力带走，温升增量 = 功率 / 换热能力 *)\nfSteadyTempC := fOilTemp0C + (fPartHeatKJ / fCycleTimeS) / fExchCapKW;',
  '(* 热平衡稳态：热源平均功率 P = Q/t [kJ/s = kW]；稳态温升 dT = P / (k*A) [kW / (kW/K) = K]，量纲自洽 *)\nfSteadyTempC := fOilTemp0C + (fPartHeatKJ / fCycleTimeS) / fExchCapKWperK;'),
])

# ---- 2. SugarPanBatchSeq：批次活跃相排除抽真空/进糖浆（QA BLOCK #1，属实）----
print('[2] FB_DL_SugarPanBatchSeq 空罐误锁修复')
patch(r'DL_Process\FB_DL_SugarPanBatchSeq.st', [
 ('_bBatchActive := (_ePhase <> E_DL_SpbPhase.eIdle) AND (_ePhase <> E_DL_SpbPhase.eDone)',
  '_bBatchActive := (_ePhase <> E_DL_SpbPhase.eIdle) AND (_ePhase <> E_DL_SpbPhase.eDone)\n                   AND (_ePhase <> E_DL_SpbPhase.eVacuum) AND (_ePhase <> E_DL_SpbPhase.eFillSyrup)   (* 空罐与进料相锤度天然为 0，不计入信号域判 / Exclude vacuum & fill phases: brix is naturally 0 *)'),
])

# ---- 3. LadlePourWeightCtrl：除零早退 + ELSE 清阀（QA BLOCK #4，属实）----
print('[3] FB_DL_LadlePourWeightCtrl 除零与兜底修复')
patch(r'DL_Device\FB_DL_LadlePourWeightCtrl.st', [
 ('fDevPct := (fWeightKg - fTargetKg) / fTargetKg * DL_PCT_BASE;',
  'IF ABS(fTargetKg) > DL_EPS THEN\n    fDevPct := (fWeightKg - fTargetKg) / fTargetKg * DL_PCT_BASE;   (* 分母已过域闸 [%] / Guarded division *)\nELSE\n    fDevPct := 0.0;                                (* 目标为 0：偏差无定义，置 0 不留 Inf/NaN / Undefined -> 0 *)\nEND_IF'),
 ('ELSE\n    _bFault := TRUE;                                 (* 兜底：非法相位锁存 *)\n    _uFault := 16#0026_0009;\n    _ePhase := E_DL_PourPhase.eFault;\nEND_CASE',
  'ELSE\n    bPourFast := FALSE; bPourSlow := FALSE;          (* 兜底相：先关双阀再锁故障，安全侧不留上拍开阀值 *)\n    _bFault := TRUE;                                 (* 兜底：非法相位锁存 *)\n    _uFault := 16#0026_0009;\n    _ePhase := E_DL_PourPhase.eFault;\nEND_CASE'),
])

# ---- 4. CarburizeCaseDepthCalc：加固输出自检（审校 BLOCK #2 经核为误判，仅按建议加固）----
print('[4] FC_DL_CarburizeCaseDepthCalc 输出自检加固')
patch(r'DL_Process\FC_DL_CarburizeCaseDepthCalc.st', [
 ('xValid := TRUE;                             (* 链路有效 / Chain valid *)\nFC_DL_CarburizeCaseDepthCalc := fCaseMm;',
  '(* 输出自检：K 极小或 t 极大时 (x/K)^2 可上溢 Inf，出口一律复检非有限 *)\nIF (fCaseMm <> fCaseMm) OR ((fCaseMm - fCaseMm) <> 0.0)\n   OR (fKCoef <= DL_EPS)\n   OR (fTimeTargetH <> fTimeTargetH) OR ((fTimeTargetH - fTimeTargetH) <> 0.0) THEN\n    fCaseMm := 0.0; fKCoef := 0.0; fTimeTargetH := 0.0;\n    xValid := FALSE;                         (* 输出不可信 / Output not trustworthy *)\n    FC_DL_CarburizeCaseDepthCalc := -1.0;    (* 哨兵 -1：输出溢出 / Sentinel -1 overflow *)\n    RETURN;\nEND_IF\nxValid := TRUE;                             (* 链路有效 / Chain valid *)\nFC_DL_CarburizeCaseDepthCalc := fCaseMm;'),
])
print('DONE')
