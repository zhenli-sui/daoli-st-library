# -*- coding: utf-8 -*-
"""R65 收口脚本：registry 注册 + JSONL 追加 + 断言（pipeline v2 首轮）"""
import io, json, os, shutil, datetime

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
BAK = os.path.join(LIB, "_archive", "registry_backups", "INDEX_REGISTRY.json.bak_r65")

def st_read(cat, name):
    p = os.path.join(LIB, cat, name + ".st")
    src = io.open(p, encoding="utf-8").read()
    return p, src

NEW = [
 ("FC_DL_StringEditDistance","DL_Base","FC",6,"道莅原创","internal","t1-original",["string","edit-distance","levenshtein","fuzzy-match","recipe-lookup","iec-std-free","t1-original","r65-new"]),
 ("FC_DL_StringWildMatch","DL_Base","FC",5,"道莅原创","internal","t1-original",["string","wildcard","pattern-match","alarm-filter","t1-original","r65-new"]),
 ("FC_DL_ArrFillEx","DL_Base","FC",4,"西门子 LGF DataHandling 分类语义借鉴，clean-room 重写","classification","lgf-datahandling",["array","fill","segment","bounds-guard","lgf-datahandling","cleanroom","r65-new"]),
 ("FC_DL_ArrCopySeg","DL_Base","FC",4,"西门子 LGF DataHandling 分类语义借鉴，clean-room 重写","classification","lgf-datahandling",["array","copy","segment","truncate","lgf-datahandling","cleanroom","r65-new"]),
 ("FC_DL_SortIndexInt","DL_Base","FC",5,"西门子 LGF DataHandling 分类语义借鉴，clean-room 重写","classification","lgf-datahandling",["array","sort","stable","index-map","lgf-datahandling","cleanroom","r65-new"]),
 ("FB_DL_HysteresisBandMon","DL_Base","FB",6,"西门子 LGF Comparator 分类语义借鉴，clean-room 重写","classification","lgf-comparator",["hysteresis","band-monitor","zone-state","edge-pulse","lgf-comparator","cleanroom","r65-new"]),
 ("FC_DL_AngleUnitConvert","DL_MathData","FC",3,"道莅原创","internal","t1-original",["angle","unit-convert","deg","rad","grad","t1-original","r65-new"]),
 ("FC_DL_TankVolumeHoriCyl","DL_Process","FC",5,"道莅原创","internal","t1-original",["tank","volume","horizontal-cylinder","segment-area","level","t1-original","r65-new"]),
 ("FB_DL_AnalogSignalHealth","DL_Device","FB",7,"西门子 LGF Measurement 分类语义借鉴，clean-room 重写","classification","lgf-measurement",["analog","4-20ma","signal-health","wire-break","stuck","lgf-measurement","cleanroom","r65-new"]),
 ("FB_DL_PneuCylinderDiag","DL_Device","FB",7,"道莅原创","internal","t1-original",["pneumatic","cylinder","diag","timeout","stall","sensor-conflict","t1-original","r65-new"]),
]
FIX = [("FB_DL_DualValveBlockSet","DL_Device","FB_DL_DualValveBlockSet v1.0.1 点修（R64 终审中项）：tonMismatch 计时补 eRun 相位闸，非运行相 IN=FALSE 不累计；窗残留由相位闸+锁存门控双路自清。","返修不改架构（双阀封锁判定状态机）。改动仅两点：① TON 实例 IN 条件串入相判据，防非运行相静默累计；② 超时触发路径复用既有锁存清账出口，无新增状态。防错要点：推进判据与超时计时同源必须在相闸下解耦（R300）。"),
 ("FB_DL_ReworkLotGate","DL_Process","FB_DL_ReworkLotGate v1.0.1 点修（R64 终审轻项）：eReleased 放行相单拍驻留后无条件回迁 eIdle，rtRelease 自清沿 + nReleased 审计台账保持，下批次可正常进入。","返修不改架构（返工批次闸状态机）。改动：放行相出口由驻留改为单拍回迁，回迁天然清放行态；未新增变量。防错要点：终态相不可自锁死，必须有可达回迁路径。"),
 ("FB_DL_UnscramblerSeq","DL_Process","FB_DL_UnscramblerSeq v1.0.1 点修（R64 终审轻项）：_bHold 跨相粘滞统一清零——段 0a 置于 tonPhase 刷新之前对非保持相统一 _bHold := FALSE，防下一拍 tonPhase（串 NOT _bHold 门控）读到旧值。","返修不改架构（理瓶序列状态机）。改动：新增段 0a 统一清零（择统一式而非逐出口补清，迁移出口分散两相共 5 处易漏）；段 0 定时器与段 4 状态机语义零变更。防错要点：相标志的清零点必须与消费点同拍序约束明确。"),
]
JSL_NEW = {
 "FC_DL_StringEditDistance":("配方名/批次号模糊匹配：两条 STRING(64) 计算最小编辑距离（插入/删除/替换代价均 1），可选大小写敏感；用于 MES 批次核对、HMI 搜索联想。边界：任一串空返回另一串长度；超长（>64）截断并报 bTooLong。","滚动单行 DP：保存上一行 65 长度整型数组，空间 O(min(m,n))。防错：数组下标 0..64 与 LEN 结果钳位联动，字符串全用 IEC 标准 LEN/MID，无平台专有函数；bValid 语义=两输入均可解析。"),
 "FC_DL_StringWildMatch":("报警过滤/点名匹配：模式串支持 * 与 ?，对文本做全串匹配；典型用于报警屏蔽表与对象路径过滤。边界：连续 * 折叠；截断报 bValid=FALSE。","迭代双指针 + 回溯锚点（记录最后 * 的匹配位置），无递归防栈深；大小写可选。防错：指针越界显式判等，回溯只回退到锚点后一位，复杂度最坏 O(m*n)。"),
 "FC_DL_ArrFillEx":("数组段初始化：把 ARRAY[0..255] OF LREAL 的 [iFrom, iTo] 区间统一填充某值（缓冲区复位、配方默认值下发）。边界：iFrom/iTo 非法自动钳位、零长早退、fVal 非有限且 bFillNaN=FALSE 时拒绝。","纯函数无状态。下标钳位先行（负下标归 0、上界钳 255），填充计数 nFilled 反映实际写入数；非有限值守卫用 fVal = fVal 的 NaN 判定与 ABS 上界双检。"),
 "FC_DL_ArrCopySeg":("数组段拷贝：源数组段复制到目标数组段（配方搬运、环形缓冲快照）。边界：nCnt<=0 合法零拷贝；源/目标越界自动截断并 bTrunc 报告；nCopied 反映实际数量。","纯函数。截断量 = min(nCnt, 源余量, 目标余量)，逐元素循环拷贝（不用平台 MEMCopy）；越界属信息级而非故障级，保证部分拷贝仍可用。"),
 "FC_DL_SortIndexInt":("报警优先级/批次序号排序：对 INT 数组做稳定排序，输出原下标索引表（不改原数组，调用方可按索引回查）。边界：nUsed 钳位 [0,64]，0 个返回合法空表。","稳定插入排序（保持相等元相对序，序号语义正确性关键）；索引数组与值数组分离，降序由 bDesc 翻转比较符而非后置反转，避免破坏稳定性。"),
 "FB_DL_HysteresisBandMon":("工艺区间监视：液位/温度相对 [fLow, fHigh] 带的区间态（eBelow/eIn/eAbove）判定，滞回 fHyst 消除边界抖动，越带沿脉冲驱动联锁。边界：组态非法（fLow>=fHigh、fHyst 越带宽）→ eCfg 故障且输出回中位；失能清零。","三态机 + 迁移判据对称化（进入带需越过 fLow+fHyst，离开带只需 fIn<fLow），单拍沿脉冲用锁存-清零范式。与 FC_DL_Hysteresis 分工互引：点值计算 vs 区间状态监视，勿混用。"),
 "FC_DL_AngleUnitConvert":("运动/光伏跟踪角度换算：deg/rad/grad 三单位互转，用于轴系标定与太阳跟踪角下发。边界：非有限输入 bValid=FALSE 输出 0.0；grad 系数 200/180 预乘防运行时除法。","统一桥接 rad：先归一到 rad 再转目标单位，避免 6 组直换系数表；系数全部编译期常量，零除法面。ENUM 双 CASE 各带 ELSE 兜底回 eDeg 语义。"),
 "FC_DL_TankVolumeHoriCyl":("卧式圆柱罐体积计量：由液位高度算瞬时体积与百分比，用于收发料平衡与库存盘点（无差压表罐）。边界：h 钳 [0,2r]；acos 入参钳 [-1,1]；sqrt 入参 max(0,·)；纵坡>0 报 bApprox 近似。","弓形面积解析式 fVol = L·(r²·acos((r−h)/r) − (r−h)·√(2rh−h²))；分母与满罐体积反证写死；与 FB_DL_TankLevelStrapping 查表法互引分工（解析法 vs 标定表法）。"),
 "FB_DL_AnalogSignalHealth":("4-20mA 信号健康诊断：断线（<3.6mA）/低限/超上限/卡滞四态判别，锁存报警 + 单拍沿 + 复位；供 DCS 联锁前置质量判据。边界：非有限 mA → eInvalid 且 bValid=FALSE；卡滞窗与电平判据分立源（R300）；失能清零（R303）。","电平判据（断线/饱和）与变化率判据（卡滞 TON 无条件刷新）分立；TON.IN := ABS(fMa−_fPrevMa) > fStuckBand 有变化即重置；锁存统一 bReset 上升沿解除并在头注声明解除沿；信息级码不置 bError。"),
 "FB_DL_PneuCylinderDiag":("双阀气缸行程诊断：伸出/缩回超时、中途卡滞、双传感器矛盾三类故障判别与状态机输出；供装配/上下料气动执行器维护预警。边界：tStall < min(tExtTo,tRetTo) 配比约束头注写死；bReset 清锁存回 eIdle；失能清零。","八态状态机 + 三计时源分立：超时窗（相驻留）与到位判据（反馈电平）不同源；6 个 TON/RT 实例段 0 顶层无条件刷新（R55 教训）；矛盾判据（bFbExt∧bFbRet）优先级最高锁存。"),
}
INSTR = {n: instr for (n, cat, ty, cx, src, om, tag, tags), (instr, at) in
         [(x, JSL_NEW[x[0]]) for x in NEW]}
# 更直白地建映射
NEWJ = {}
for (n, cat, ty, cx, srcdesc, om, tag, tags) in NEW:
    instr, at = JSL_NEW[n]
    NEWJ[n] = (cat, ty, cx, srcdesc, om, tag, tags, instr, at)

now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
shutil.copy2(REG, BAK)
reg = json.load(io.open(REG, encoding="utf-8"))
comps = reg["components"]
by_name = {c["name"]: c for c in comps}

# 1) 注册 10 新件
for (n, cat, ty, cx, srcdesc, om, tag, tags) in NEW:
    assert n not in by_name, "撞名: " + n
    p, src = st_read(cat, n)
    comps.append({
        "name": n, "category": cat, "type": ty, "file_path": p,
        "function_tags": tags, "complexity": cx, "version": "1.0.0",
        "registered_at": now, "line_count": src.count("\n") + 1,
        "code_segment": "", "source": "r65-plan",
        "origin": {"mode": om, "source": srcdesc, "license": "MIT" if om == "internal" else "cleanroom-ref",
                   "ref_tag": tag},
    })
    by_name[n] = comps[-1]

# 2) 三件升版回写（消除 VER_MISMATCH）
for n, cat, instr, at in FIX:
    c = by_name[n]
    p, src = st_read(c["category"], n)
    c["version"] = "1.0.1"
    c["line_count"] = src.count("\n") + 1

# 3) counts / total / library version
for n, cat, *_ in [(x[0], x[1]) for x in NEW]:
    pass
cnt = {}
for c in comps:
    cnt[c["category"]] = cnt.get(c["category"], 0) + 1
reg["counts"] = cnt
reg["total_components"] = len(comps)
reg["version"] = "2.57.0"
reg["last_updated"] = now
assert sum(cnt.values()) == len(comps), "counts sum mismatch"
json.dump(reg, io.open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

# 4) JSONL +13（10 新 + 3 返修重注入）
def jsl_line(instr, at, src):
    return json.dumps({"instruction": instr, "architecture_thought": at, "output": src},
                      ensure_ascii=False, separators=(",", ":"))

added = 0
with io.open(JSL, "a", encoding="utf-8", newline="\n") as f:
    for (n, cat, ty, cx, srcdesc, om, tag, tags) in NEW:
        _, src = st_read(cat, n)
        instr, at = JSL_NEW[n]
        f.write(jsl_line(instr, at, src) + "\n")
        added += 1
    for (n, cat, instr, at) in FIX:
        _, src = st_read(cat, n)
        f.write(jsl_line(instr, at, src) + "\n")
        added += 1

# 5) JSONL 全量校验
bad = 0
tot = 0
for ln in io.open(JSL, encoding="utf-8"):
    ln = ln.strip()
    if not ln:
        continue
    tot += 1
    try:
        d = json.loads(ln)
        assert d.get("instruction") and d.get("architecture_thought") and d.get("output")
    except Exception:
        bad += 1
print("R65 closeout OK: new=%d fix=%d registry=%d counts=%s lib=v2.57.0 jsonl=%d bad=%d"
      % (len(NEW), len(FIX), len(comps), json.dumps(cnt, ensure_ascii=False), tot, bad))
