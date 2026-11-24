# -*- coding: utf-8 -*-
"""R70 closeout: registry update + JSONL append (10 new components)."""
import json, io, os, shutil, datetime

TS = "2026-11-22T18:05:00+08:00"
LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
VER = "2.62.0"

# name, category, kind, complexity, lines, tags, ref_tag, origin_desc, instruction, arch
NEW = [
 ("FC_DL_ModPosWrap", "DL_MathData", "FC", 2, 89,
  ["modulo", "positive-wrap", "negative-handling", "divide-guard", "iec-std-wrapper", "r70-new"],
  "t0-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（MOD 的负数结果归正，模数零域闸）",
  "包装线分度盘按工位数取余定位：编码器累计值可能为负（反向点动后），需要取余结果恒落在 [0, nSlots) 才能直接当下标用；同时模数可能由组态传入 0。",
  "纯函数 FC 架构：先做模数零域闸（nMod=0 落 0002_0001 故障级并返回 0，杜绝平台 MOD 除零异常），再做负数归正——先取平台 MOD 结果，若为负则加模数一次（加后仍负说明模数本身为负域，落 0002_0002 并返回 0）；全链不用除法、不用乘法，仅比较与加减，跨平台一致。"),
 ("FC_DL_LerpClamped", "DL_MathData", "FC", 2, 125,
  ["interpolation", "lerp", "clamp", "tolerance", "self-std", "r70-new"],
  "self-std",
  "自研数值新增线（线性插值带参数域钳位，端点外不外推）",
  "温度-补偿系数曲线由两点标定给出，现场上位机下发的插值系数 t 可能因累计误差跑到 [0,1] 之外（0.9999999 或 1.0000001），直接外推会把补偿量放大成危险值。",
  "纯函数 FC 架构：t 先过非有限闸（NaN/Inf 落码返回起点值），再钳到 [0,1]（浮点比较用 1.0E-9 容差，避免 1.0-1.0E-10 被误推进端点分支导致端点值抖动），最后按 t 做一次乘加；起点终值任一非有限则回落 0.0 并落码，杜绝 NaN 沿链扩散。"),
 ("FB_DL_ScaleRangeWatch", "DL_MathData", "FB", 3, 183,
  ["scale", "range-watch", "hysteresis", "delay-confirm", "lgf-math", "r70-new"],
  "t2-1-lgf-math",
  "LGF Math 组「标定换算 + 区间监视」分类组织借鉴，clean-room 重写（工程量越界监视）",
  "压力变送器 4~20mA 经标定量程换算成 MPa 后需要判越界：量程两端各留 2% 死区防抖动，且必须持续超限 500ms 才算真越界（瞬时尖峰不报警）。",
  "FB 状态机（eIdle/eNormal/eHigh/eLow/eConfig）架构：段 1 组态闸（量程上下限反置、原始值域非有限 → eConfig + 结构 RETURN，不落除法）；段 2 线性换算（先判 rawMax-rawMin 非零）；段 3 回差比较（进入阈值与退出阈值分离，退出阈值内收 2%）；段 4 延时确认（TON 实例无条件周期刷新，IN 用段 3 的瞬时判据）；段 5 输出与锁存（越界锁存至 bReset 上升沿，失能相清全部输出）。CASE 含 ELSE 兜底回 eConfig。"),
 ("FB_DL_BatchDoseSeq", "DL_Process", "FB", 3, 310,
  ["batch", "dosing", "sequence", "weight-check", "isa88", "r70-new"],
  "t2-8-isa88",
  "ISA-88 批次程序「相→操作」分层语义借鉴，clean-room 重写（定量给料顺控）",
  "反应釜投料：目标 500kg，先快给料到 90%，再慢给料到 498kg，切落料后 3s 稳定窗读净重，净重与目标偏差超 ±0.5% 判欠重/超重并禁止放行到下一步。",
  "FB 状态机（eIdle/ePre/eFast/eSlow/eSettle/eCheck/eDone/eFault）架构：段 1 组态闸（目标重量、快给比例、容差全非正 → eFault + 结构 RETURN）；段 2 相推进（每相独立超时 TON，无条件刷新，超时落码并转 eFault）；段 3 快/慢切换判据（用实测净重与比例阈值比较，带 0.2% 回差防抖）；段 4 稳定窗（落料阀关后延时读净重，窗内净重波动超 0.05% 则重开窗，最多重试 2 次）；段 5 判定（欠重/超重分别落 0002_0103/0104，输出 bOk 与实测偏差）；段 6 失能/复位（bEnable 下降清全部执行输出与定时器，eFault 仅 bReset 上升沿解除）。CASE 含 ELSE 兜底。"),
 ("FB_DL_PumpAlternationLead", "DL_Process", "FB", 3, 250,
  ["pump", "alternation", "lead-lag", "runtime-hours", "fault-switch", "self-std", "r70-new"],
  "self-std",
  "自研工艺新增线（多泵轮换主备：运行小时选主 + 故障切备）",
  "循环水站 3 台泵两用一备，需要按累计运行小时自动选主（最少的当主用），主用故障时 1s 内切到次少的一台，且轮换周期到（如 168h）时强制换主，避免单泵长期磨损。",
  "FB 架构：段 1 组态闸（泵数 1~4、轮换周期非零、故障位数组有效 → 否则 eConfig + 结构 RETURN）；段 2 小时累计（每台运行位为 TRUE 时按 dElapsedSec/3600.0 累加，溢出前饱和到 1.0E9）；段 3 选主（遍历有效泵取小时最少者，同值取编号小者，全故障落 0002_0202 + eFault）；段 4 故障切换（主用故障上升沿立即重选，切换延时 1s 防抖，切换期输出 bSwitching）；段 5 轮换（累计运行时长超周期 → 强制换主并清该泵计数）；段 6 输出与失能（失能相清全部启泵输出）。各 TON 无条件刷新，CASE 含 ELSE。"),
 ("FB_DL_ValveSeatLeakTest", "DL_Device", "FB", 3, 280,
  ["valve", "leak-test", "pressure-decay", "temperature-comp", "lgf-measurement", "r70-new"],
  "t2-1-lgf-measurement",
  "LGF Measurement 组「压降测量 + 判据分层」分类组织借鉴，clean-room 重写（阀座泄漏测试）",
  "双座阀检修后做阀座密封试验：关阀、上游充压到 0.6MPa，保持 60s，压降超 0.02MPa 判泄漏；温度波动会改变压力读数，需要用温度修正后的压降判定，环境温度骤变时本拍判定无效。",
  "FB 状态机（eIdle/ePress/eStable/eHold/eJudge/ePass/eFail）架构：段 1 组态闸（保持时长、压降阈值、充压目标非正 → eConfig + 结构 RETURN）；段 2 充压相（上游压力到目标的 98% 转稳定相，充压超时落码）；段 3 稳定相（等压力波动 < 0.002MPa 持续 3s 才进保持相，防止充压扰动混入判据）；段 4 保持相（记录起始压力与温度，温度变化超 2K 则本拍作废重开窗，最多重试 1 次）；段 5 判定（压降 = 起始值 - 当前值，温度修正系数按理想气体近似线性折算，超阈值落 0002_0301 泄漏级）；段 6 结果锁存（ePass/eFail 锁至 bReset）。CASE 含 ELSE 兜底。"),
 ("FB_DL_ConveyorJamDetect", "DL_Device", "FB", 2, 154,
  ["conveyor", "jam", "current", "dual-criteria", "self-std", "r70-new"],
  "self-std",
  "自研设备新增线（输送线堵料检测：无件流转 + 电流偏高双判据）",
  "皮带输送机堵料：下游光电 8s 内无件通过，而电机电流同时高于空载基线 20%，两个条件同时成立 3s 判堵料并停线；只电流高（重载）不报警，只无件（正常空转）也不报警。",
  "FB 架构：段 1 组态闸（无件时长阈值、电流基线、电流比例全为非正或非有限 → eConfig + 结构 RETURN）；段 2 无件计时（下游件信号上升沿清 TON，TON 无条件刷新，IN = 运行位 AND NOT 件信号）；段 3 电流判据（实时电流 > 基线×(1+比例)，浮点容差 1.0E-3）；段 4 双判据与（两判据同时成立再进确认 TON，时长到置 bJam 并锁存）；段 5 输出（bJamLatched 锁存至 bReset，失能相清计时与锁存）。CASE 含 ELSE（本件无状态机，R6 标注 N/A，此处为纯判据组合，不使用 CASE）。"),
 ("FB_DL_AxisSoftLimitGuard", "DL_Motion", "FB", 3, 198,
  ["axis", "soft-limit", "decel-request", "direction-inhibit", "s7motion", "r70-new"],
  "t2-4-s7motion",
  "S7 Motion「轴监控 + 方向禁止」功能分层借鉴，clean-room 重写（软限位守卫）",
  "第三方伺服走位置模式，上位机偶尔下发越界目标：需要在接近软限位（剩余距离 < 减速距离）时提前给减速请求，越过限位立即禁止该方向并锁存，反向运动始终放行以便退出。",
  "FB 架构：段 1 组态闸（限位上下反置、减速距离非正、位置/速度非有限 → eConfig + 结构 RETURN，禁止在非有限值上做比较）；段 2 剩余距离计算（按运动方向分别算到上/下限的距离，负值钳零）；段 3 减速请求（剩余距离 < 减速距离 且 速度朝向限位 → bDecelReq，带回差 5%）；段 4 越限判定（位置 > 上限 + 容差 或 < 下限 - 容差 → 锁存 bLimitHit 并按方向置 bPosInhibit/bNegInhibit）；段 5 解除（仅 bReset 上升沿且当前位置已回到限位内侧软区才解锁，否则保持禁止）。CASE 不使用（纯判据，R6 N/A），TON 无。"),
 ("FB_DL_RecipeStepExec", "DL_Base", "FB", 3, 235,
  ["recipe", "step", "sequence", "step-timeout", "packml", "r70-new"],
  "t2-7-packml",
  "PackML 状态模型「执行/保持/中止」语义借鉴，clean-room 重写（配方步序执行器）",
  "灌装线配方 6 步（每步含目标值与步超时），要求：步超时报警并停在当前步、暂停后恢复从当前步继续（不重头）、跳步请求一律拒绝并落码，步号越界必须回第 1 步而不是崩。",
  "FB 状态机（eIdle/eRun/eHold/eStepFault/eDone）架构：段 1 组态闸（步数 1~16、步超时非零、当前步号越界 → 归 1 并落 0002_0402 信息级）；段 2 步推进（bStepDone 上升沿推进步号，本步 TON 复位并要求下一拍重启，用 _bTimerRestart 标记防跨步累计）；段 3 步超时（TON 无条件刷新，IN = eRun，超时转 eStepFault 并保持步号不变）；段 4 暂停/恢复（eHold 时停 TON 但保留剩余时长口径，恢复回 eRun 并从当前步继续）；段 5 跳步拒绝（bSkipReq 上升沿直接落 0002_0401 拒绝码，不改变步号）；段 6 完成与失能（最后一步完成转 eDone；bEnable 下降清执行输出与步号）。CASE 含 ELSE 兜底回 eIdle。"),
 ("FB_DL_CabinetTempDerate", "DL_Device", "FB", 2, 251,
  ["cabinet", "temperature", "derate", "sensor-fault", "ne107", "r70-new"],
  "t2-8-ne107",
  "NE107 诊断分级（Failure/OutOfSpec/Maintenance）语义借鉴，clean-room 重写（柜内温度降额）",
  "电控柜 3 个温度测点，任一测点超 45℃ 开始线性降额（45~60℃ 对应系数 1.0→0.6），测点断线（非有限）时保持上次有效值与系数最多 120s，超时按最坏情况取 0.6 并报 Maintenance 级。",
  "FB 架构：段 1 组态闸（测点数 1~4、降额起止温度反置、保持窗口非正 → eConfig + 结构 RETURN）；段 2 多点取最大（逐点判有限性，非有限点计入失效计数，不参与取最大）；段 3 保持逻辑（有效点数为 0 时启动保持 TON，窗口内沿用上次最大温度与系数，超窗落 0002_0503 并强制系数 0.6）；段 4 降额换算（分段线性：低于起始温度系数 1.0，超终止温度 0.6，中间线性，两端钳位）；段 5 分级诊断（系数 < 0.8 → OutOfSpec，传感器失效 → Maintenance，两者同置取高）；段 6 输出（fDerateCoef / nDiagLevel / bSensorFault，失能相系数回 1.0 并清诊断）。TON 无条件刷新，CASE 含 ELSE。"),
]

def main():
    reg = json.load(io.open(REG, encoding="utf-8"))
    names = {c["name"] for c in reg["components"]}
    dup = [n[0] for n in NEW if n[0] in names]
    assert not dup, "DUP: %s" % dup

    shutil.copy2(REG, os.path.join(LIB, "INDEX_REGISTRY.bak_r70.json"))

    added = 0
    for (name, cat, kind, cx, lines, tags, ref, desc, instr, arch) in NEW:
        p = os.path.join(LIB, cat, name + ".st")
        assert os.path.exists(p), p
        reg["components"].append({
            "name": name, "category": cat, "type": kind,
            "file_path": p, "function_tags": tags, "complexity": cx,
            "version": "1.0.0", "registered_at": TS, "line_count": lines,
            "code_segment": "", "source": "r70-plan",
            "origin": {"mode": "classification", "source": desc,
                       "license": "iec-std-wrapper", "ref_tag": ref},
        })
        added += 1

    cnt = {}
    for c in reg["components"]:
        cnt[c["category"]] = cnt.get(c["category"], 0) + 1
    reg["counts"] = cnt
    reg["total_components"] = len(reg["components"])
    reg["version"] = VER
    reg["last_updated"] = TS
    assert sum(cnt.values()) == reg["total_components"], "sum mismatch"
    io.open(REG, "w", encoding="utf-8").write(json.dumps(reg, ensure_ascii=False, indent=1))
    print("registry: +%d -> total %d, counts %s, v%s" % (added, reg["total_components"], cnt, VER))

    before = sum(1 for _ in io.open(JL, encoding="utf-8"))
    with io.open(JL, "a", encoding="utf-8") as f:
        for (name, cat, kind, cx, lines, tags, ref, desc, instr, arch) in NEW:
            src = io.open(os.path.join(LIB, cat, name + ".st"), encoding="utf-8").read()
            f.write(json.dumps({"instruction": instr, "architecture_thought": arch,
                                "output": src}, ensure_ascii=False) + "\n")
    after_lines = io.open(JL, encoding="utf-8").read().splitlines()
    assert len(after_lines) == before + len(NEW), "jsonl count"
    bad = 0
    for ln in after_lines[before:]:
        try:
            o = json.loads(ln)
            assert o["instruction"] and o["architecture_thought"] and o["output"].startswith("(*")
        except Exception as e:
            bad += 1
            print("BAD LINE:", e)
    print("jsonl: %d -> %d (new %d, bad %d)" % (before, len(after_lines), len(NEW), bad))

main()
