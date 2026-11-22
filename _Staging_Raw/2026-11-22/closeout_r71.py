# -*- coding: utf-8 -*-
"""R71 closeout: registry update (7 new + 1 点修) + JSONL append (8 件)."""
import json, os, shutil, datetime, hashlib

TS = datetime.datetime.now().astimezone().strftime("%Y-%m-%dT%H:%M:%S+08:00")
LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
VER = "2.63.0"

# name, category, kind, complexity, tags, ref_tag, origin_desc, code_segment, instruction, arch
NEW = [
 ("FC_DL_AirSpecificVolume", "DL_MathData", "FC", 2,
  ["psychrometrics", "specific-volume", "humidity", "magnus-tetens", "owner-reuse", "t1-2-oscat-building", "r71-new"],
  "t1-2-oscat-building",
  "OSCAT Building 湿空气族「状态参量派生」分类组织借鉴，clean-room 重写；Magnus 常量不复制，复用库内属主件 FC_DL_VaporPressureSat",
  "16#0002_3760~3763",
  "冷库送风段要按当前温湿度算风机的实际体积风量与比容（m³/kg 干空气）：温度 -5℃、相对湿度 85%、大气压 101325 Pa 的常态工况，但上位机下发的湿度偶发越界到 105%，气压引压管堵塞时读到 2 kPa。比容用于把质量流量折算成体积流量，一旦算出负值或 NaN，风阀开度会被算成负值直接反吹。",
  "纯函数 FC 十段架构：段 1 返回值/状态统一预置（R256）；段 2 三入参非有限闸（NaN 自反判 + Inf 差值自反判 + 幅值上界，逐项点名）；段 3 压力硬域闸（<10 kPa 承诺段下界直接拒绝，防引压管堵塞时低压分母翻号）；段 4 温度域闸与湿度钳位（[0,100]% 钳位照算并置 bClamped，不因越界拒算）；段 5 饱和水汽压**复用属主件** FC_DL_VaporPressureSat（常量单源，绝不内联 Magnus 系数，防两处口径漂移）；段 6-7 比容式分母 p−φ·p_sat·(1−Ra/Rv) **先组装后判再除**——分母 ≤0 即过饱和/低压非法，信息级早退输出 0.0，除法面全在判据之后；段 8 比容主体 v=Ra·T_K/p_d；段 9 结果非有限闸 + 上下界饱和（绝不把非有限值送下游）；段 10 域内正常出口。全链无变量除零面，浮点判等一律容差口径。"),
 ("FC_DL_DurationFormat", "DL_Base", "FC", 2,
  ["time", "duration", "hmi-format", "decomposition", "iec-std-wrapper", "r71-new"],
  "iec-std-wrapper",
  "IEC 61131-3 标准语义的道莅防御性实现（TIME 时长四分量分解，T0-2 时间族补口；HMI 显示专用纯函数）",
  "N/A（纯函数不出码位，bTruncated 标志承载截断语义）",
  "设备运行时长要在 HMI 上显示成「3天 04:17:52」这种形式，运维要看懂「已经连续跑了几天」。TIME 上限约 49.7 天（32 位 ms），但现场上位机传入值偶发为负（换算错位），负值直接整除会得到 -1 天这种荒谬显示。",
  "纯函数五段架构：段 1 返回值与四分量（天/时/分/秒）统一预置；段 2 容器换算与**负值防御闸**——TIME 是无符号语义，负值不可表示，防御性复检后按 0 处理并置 bValid=FALSE（名实对齐，不静默）；段 3 整除分解用**常量除子级联**（86400000 / 3600000 / 60000 / 1000），无变量除零面；段 4 毫秒余量舍弃并置 bTruncated（名实对齐，明确告知调用方精度损失），不做四舍五入（HMI 显示舍入会造成「跑了 1 天 0 秒」的错觉）；段 5 正常出口。全件不出码位（信息件），浮点面为零，纯整数运算跨平台一致。"),
 ("FB_DL_AxisEncBatteryWatch", "DL_Device", "FB", 2,
  ["encoder", "battery", "absolute-encoder", "undervoltage", "ne107", "hysteresis", "t2-6-rockwell-aoi", "r71-new"],
  "t2-6-rockwell-aoi",
  "Rockwell AOI「设备健康前置预警」封装组织借鉴（次源 NE107 诊断分级），clean-room 重写；判据/阈值/码位 100% 自有",
  "16#0002_3770~3773",
  "七轴加工中心的绝对值编码器靠锂电池保持多圈数据，电池电压掉到 3.0V 以下时断电就会丢参考点，重新回零要停线两小时。电池电压由 24V 电源模块分压后经模拟量输入采集（0~5V 域），采样线松脱时读到 0V 或 NaN——这时「电压低」和「测不到」是两件事，但都不能当成正常。",
  "FB 九段架构（单判据链，无 CASE 状态机）：段 1 出口统一预置；段 2 复位沿 R_TRIG 无条件调用（规则⑦）；段 3 锁存解除仅 bReset 上升沿且锁存码同步清零（唯一解除边，R188）；段 4 组态守卫逐项点名（fWarnV ≤ fFaultV 阈值倒置、回差为负、确认延时非正）；段 5 **输入守卫安全侧收紧**——电压非有限即视为危险（状态不明比欠压更危险），直接锁存故障而不走延时确认；段 6 首次成因锁存（故障期不重推断，回放锁存码，R189）；段 7 运行许可与双阈值迟滞条件计算（分支内不调用任何定时器）；段 8 **定时器无条件周期调用**（规则⑦，IN 取段 7 显式条件）；段 9 出口映射（名实双出口同源，R191）：bFault→NE107 eMaintenanceReq、bWarn→eOutOfSpec、bReplaceSoon 由剩余裕度判据链给出。失能不清锁存（R303）。"),
 ("FB_DL_FlyingShearSync", "DL_Motion", "FB", 3,
  ["flying-shear", "line-synchronization", "cam", "motion-sequence", "plcopen", "t1-6-plcopen", "r71-new"],
  "t1-6-plcopen",
  "PLCopen Motion「同步运动 + 相序列」状态组织借鉴（PLCOpenState 语义分层，不自造轴状态枚举），clean-room 重写；判据/码位 100% 自有",
  "16#0002_3790~3796",
  "包装线飞剪：产品连续以 0.8 m/s 走料，切刀要在产品行进中同步追上并切断，切完退回原点等下一件。切长设定 250mm，同步窗 60mm（进入窗后必须与线速误差 <2% 才能下刀），加速度受伺服限幅。现场最大风险是「同步窗内线速突然掉档」，此时若照旧下刀会把产品切成斜口甚至撞刀。",
  "FB 十段架构（ENUM 相状态机）：段 1 出口统一预置 + 单拍位两段式第一段（R256）；段 2 沿检测实例无条件调用（规则⑦）；段 3 复位解除为唯一可到达的锁存解除边（R188）；段 4 组态守卫逐项点名 + 配比约束（切长 < 窗长、加速度非正等）；段 5 线速守卫（非有限或负值即无效，待机期拒收）；段 6 首次成因锁存（R189）；段 7 **斜坡基值换算走 TIME→ms→s 显式两步**，不依赖平台 TIME_TO_LREAL 语义差（跨平台一致性）；段 8 相计时器 PT 按相选择后无条件调用（规则⑦，选相不依赖可跳过分支，杜绝跨相累计）；段 9 ENUM+CASE 相状态机（eIdle/eWait/eEnter/eSync/eCut/eRet）仅运行许可时执行，**同步窗内线速失配立即退相到 eRet 并落码**，不给「带病下刀」留路径；段 10 出口映射单点写入（名实双出口同源，R191）。CASE 含 ELSE 兜底回 eIdle。"),
 ("FB_DL_LaneDivertCtrl", "DL_Process", "FB", 2,
  ["conveyor", "diverter", "lane", "sequence", "packml", "r71-new"],
  "s9-conv",
  "PackML 工站相语义次源借鉴（岔口三段骨架 + 态组织），clean-room 重写；岔口判据/码位 100% 自有",
  "16#0002_37A0~37A3",
  "分拣线道岔：光电到件后 80ms 内岔口气缸必须动作到位，尾件通过后 500ms 恢复直行。气缸到位靠磁性开关反馈，反馈丢失时不能一直吹气（气路憋压），也不能直接放行（会把件送错道）。件间距最小 400mm，误动作会砸到前一件的尾部。",
  "FB 九段架构（ENUM 相状态机）：段 1 出口统一预置；段 2 沿检测无条件调用（规则⑦）；段 3 复位解除唯一解除边（R188）；段 4 组态守卫（tActTimeout 非正即延时不可表示）；段 5 首次成因锁存（R189）；段 6 **相反馈超时 PT 按相选择后无条件调用**（规则⑦，选相不依赖可跳过分支）；段 7 **失能相输出回夹先于状态机执行**（R57+R303：气缸输出/使能归零与故障锁存分开写）；段 8 ENUM+CASE 相状态机（eIdle/eAct/eHold/eTail/eReturn/eFault）仅运行许可时执行，**相反馈超时落码转 eFault 并放掉气缸**（不憋压、不放行双约束）；段 9 出口映射单点写入（R191）。CASE 含 ELSE 兜底。"),
 ("FC_DL_TriangleSolveSSS", "DL_MathData", "FC", 2,
  ["geometry", "trigonometry", "triangle", "law-of-cosines", "lgf-math", "r71-new"],
  "t2-1-lgf-math",
  "LGF Math 组「几何解算」方向借鉴（三角族待挖首件），clean-room 重写；公式取公开余弦定理，判据/码位自有",
  "16#0002_37B0~37B2",
  "三点定位机构：三个测距传感器各自给出到目标点的距离，需要反解出目标点在机构坐标系里的夹角，用于判断抓取姿态。三边由激光测距给出，被测物贴边时会出现「两边之和恰等于第三边」的共线退化（距离和相等但实际是直线排列），此时余弦定理分母仍为正但解出的角度为 0/π，直接反余弦会得到数学上成立、几何上无意义的姿态。",
  "纯函数九段架构：段 1 返回值与三角度统一预置（R256）；段 2 三边非有限闸（NaN 自反判 + Inf 差值自反判 + 幅值上界，逐项点名 R272）；段 3 三边非正闸（零边/负边无几何意义）；段 4 **三角不等式闸用严格不等 + 容差双口径**（恰等号即共线退化，拒收并落 37B1，绝不放行给反余弦）；段 5 余弦定理逐角求解（分母 2·b·c 已由段 3 前置保证恒正，先判后除纪律已履行）；段 6 **反余弦入参域钳位 [-1,1]**（浮点舍入导致 1.0000000002 会让 ACOS 返 NaN，R45 口径）；段 7 反余弦求解（域已钳位无 NaN 面）；段 8 **三角和复验** |Σ−π| < 1E-6 rad 才置返回值 TRUE（自校验出口，防单角算错却整体看起来正常）；段 9 域内正常出口。"),
 ("FB_DL_PumpPrimingWatch", "DL_Device", "FB", 2,
  ["pump", "priming", "dry-run", "centrifugal", "sequence", "t2-2-lbp", "r71-new"],
  "t2-2-lbp",
  "LBP 泵组「启动前状态确认」分层组织借鉴（self 判据），clean-room 重写；灌泵窗口/双判据/码位 100% 自有",
  "16#0002_37C0~37C3",
  "循环水泵启动前必须先灌泵排气：开补水阀，等泵壳内充满（出口压力建立且流量计有轻微读数），确认后才可以合闸启动。干转 30 秒就能烧机械密封。现场常见两种坏情况——补水管路阀门没开时压力永远建不起来（要等超时报警），以及压力传感器零点漂移导致「没满却显示满了」（要双判据交叉验证）。",
  "FB 十段架构（ENUM 相状态机）：段 1 出口统一预置；段 2 沿检测无条件调用（规则⑦）；段 3 锁存解除唯一解除边（R188）；段 4 组态守卫逐项点名 + **双窗配比约束**（灌泵窗口与确认延时不可倒置，窗口过短即判据不成立）；段 5 首次成因锁存（R189）；段 6 **起立判据本拍复验**（R42 先判后信，显式条件同时供定时器与状态机使用，杜绝两处各算一遍导致口径漂移）；段 7 **双定时器无条件周期调用**（规则⑦，IN 取段 6 显式条件）；段 8 失能相输出回夹先于状态机（R57+R303）；段 9 ENUM+CASE 相状态机（eIdle/ePrime/eConfirm/eReady/eFault）仅运行许可时执行，**双判据（压力建立 AND 流量微读）交叉验证**，单判据成立不置 eReady（防零点漂移误判）；段 10 出口映射单点写入（R191）。CASE 含 ELSE 兜底。"),
]

FIX = ("FB_DL_ScaleRangeWatch", "v1.0.1", "16#0002_0121（复用，不新开）")


def main():
    reg = json.load(open(REG, encoding="utf-8"))
    bak = REG + ".bak_r71"
    shutil.copy2(REG, bak)
    names = {c["name"] for c in reg["components"]}

    added = []
    for (name, cat, kind, cx, tags, ref, origin, seg, instr, arch) in NEW:
        assert name not in names, "撞名: " + name
        fp = os.path.join(LIB, cat, name + ".st")
        assert os.path.exists(fp), "缺文件: " + fp
        src = open(fp, encoding="utf-8").read()
        lines = src.count("\n") + (0 if src.endswith("\n") else 1)
        reg["components"].append({
            "name": name, "category": cat, "type": kind,
            "file_path": fp, "function_tags": tags, "complexity": cx,
            "version": "1.0.0", "registered_at": TS, "line_count": lines,
            "code_segment": seg, "source": "r71-plan",
            "origin": {"mode": "classification", "source": origin,
                       "license": "iec-std-wrapper" if ref.startswith("iec") else ref,
                       "ref_tag": ref},
        })
        added.append((name, cat, fp, lines, instr, arch))

    # 点修件版本升级
    fixed = None
    for c in reg["components"]:
        if c["name"] == FIX[0]:
            c["version"] = FIX[1]
            c["registered_at"] = TS
            fp = c["file_path"]
            src = open(fp, encoding="utf-8").read()
            c["line_count"] = src.count("\n") + (0 if src.endswith("\n") else 1)
            c["function_tags"] = [t for t in c.get("function_tags", []) if t != "r70-new"] + ["r71-fix", "zero-gain-guard"]
            fixed = (c["name"], c["category"], fp, c["line_count"])
            break
    assert fixed, "未找到点修件"

    counts = {}
    for c in reg["components"]:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["total_components"] = len(reg["components"])
    reg["counts"] = counts
    reg["version"] = VER
    reg["last_updated"] = TS
    assert sum(counts.values()) == reg["total_components"]
    json.dump(reg, open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print("registry ->", reg["total_components"], counts, VER)

    # JSONL：7 新 + 1 点修重注入
    with open(JL, "a", encoding="utf-8") as f:
        for (name, cat, fp, lines, instr, arch) in added:
            rec = {"instruction": instr, "architecture_thought": arch,
                   "output": open(fp, encoding="utf-8").read()}
            f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        rec = {"instruction": "压力变送器 4~20mA 标定后工程量越界监视：量程上下限、回差、增益/偏置由组态传入；现场把增益算错成 0（标定表全 0 导出）时，工程值被钉死在偏置值上，上下限报警永久不触发——保护静默失效且无任何故障码，比除零更隐蔽。",
               "architecture_thought": "FB 点修 v1.0.1（缺陷 H4 增益零域）：段 4 组态闸在原有非有限性逐项点名之外**并联 `ABS(fGain) <= DL_SRW_GMIN`**（GMIN=1.0E-15，新增 VAR CONSTANT 声明同行双语注释），增益零域与上下限反置/回差吞带同归组态非法，**码位沿用 16#0002_0121 不新开**（同一根因同一码，避免码位膨胀）；段 6 首次成因锁存 → 段 7 运行许可 _bRun=FALSE → 段 8 换算段结构性不可达 → 报警臂不可能静默；头注释「边界防错」补披露条目（增益零域路径 + 复位当拍重锁存语义），不改引脚、不改其他段行为。",
               "output": open(fixed[2], encoding="utf-8").read()}
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")

    n = sum(1 for _ in open(JL, encoding="utf-8"))
    bad = 0
    for i, line in enumerate(open(JL, encoding="utf-8"), 1):
        try:
            json.loads(line)
        except Exception:
            bad += 1
            print("BAD line", i)
    print("jsonl lines", n, "bad", bad)
    print("added", [a[0] for a in added])
    print("fixed", fixed[0], fixed[1])


if __name__ == "__main__":
    main()
