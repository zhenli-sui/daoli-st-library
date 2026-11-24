# -*- coding: utf-8 -*-
"""R66 收口脚本：registry 注册 + JSONL 追加 + 断言"""
import io, json, os, shutil, datetime

LIB = r"C:\Library"
REG = os.path.join(LIB, "INDEX_REGISTRY.json")
JSL = os.path.join(LIB, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
BAK = os.path.join(LIB, "_archive", "registry_backups", "INDEX_REGISTRY.json.bak_r66")

def st_read(cat, name):
    p = os.path.join(LIB, cat, name + ".st")
    src = io.open(p, encoding="utf-8").read()
    return p, src

NEW = [
 ("FC_DL_HammingDist","DL_Base","FC",4,"西门子 LGF BitLogic 分类语义借鉴，clean-room 重写","classification","lgf-bitlogic",["bitwise","hamming-distance","popcount","lword","compare","lgf-bitlogic","cleanroom","r66-new"],
  ("两版批次号/配置字比对：对两个 LWORD 位串计算汉明距离（不同位数 0~64），用于配方字比对、IO 镜像一致性核查、冗余通道数据差异量化。边界：纯位运算无除零浮点风险；分治计数 FOR 有界禁无界 WHILE。","64 位分治计数（高低 32 位折半累加）等价 popcount，无查表内存依赖跨平台一致；纯函数无状态无定时器；与 FC_DL_ReverseBitsLword 位族正交互引（位序反转 vs 位差计数）。")),
 ("FB_DL_DutyCycleMeasure","DL_Base","FB",5,"西门子 LGF Measurement 分类语义借鉴，clean-room 重写","classification","lgf-measurement",["duty-cycle","period-measure","pulse-width","r-trig","quality","lgf-measurement","cleanroom","r66-new"],
  ("PWM/加热占空比在线测量：对 BOOL 信号测周期(ms)与占空比(%)，用于 PWM 输出验证、固态继电器负载率统计、脉宽工艺核查。边界：首周期未闭合不出数；分母周期≤0 时 bValid=FALSE 保持上次值；fDutyPct 钳位 [0,100]；禁浮点判等闭合周期。","双沿计时架构：R_TRIG→R_TRIG 周期、R_TRIG→F_TRIG 高电平宽度，触发实例段 0 无条件刷新（R55）；周期闭合判据用累计值>0 整数事实而非浮点等值；注入周期引脚 fCallCycleMs 对齐 OeeCalculator 先例（平台时刻函数拒绝纪律）；失能相串清账（R303）。")),
 ("FC_DL_CircularMeanCalc","DL_MathData","FC",5,"西门子 LGF Measurement 分类语义借鉴，clean-room 重写","classification","lgf-measurement",["circular-mean","angle","statistics","wrap-around","atan2","lgf-measurement","cleanroom","r66-new"],
  ("多传感器角度融合：对角度数组(度)计算循环均值（正确处理 350°/10° 均值=0° 而非 180°），用于多编码器融合、风向前馈、回转工位对位统计。边界：空数组=01、非有限元素=02、零向量退化(|R|<1E-6)=03 不出均值；输出归一 [0,360) 条件加减不用负数取模。","向量合成法：Σsin/Σcos → ATAN2 求均值角；元素级非有限闸先行；零向量退化显式码防角度随机跳变；与 FC_DL_WrapAngleDeg/FC_DL_AngleDiffWrap 互引（点对差 vs 多点均值分工）；ATAN2 依赖三平台 MATH 内建已头注声明。")),
 ("FC_DL_WeekNumIsoCalc","DL_MathData","FC",6,"西门子 LGF DateAndTime 分类语义借鉴，clean-room 重写","classification","lgf-dateandtimer",["iso-week","calendar","date-validate","leap-year","jdn","lgf-dateandtimer","cleanroom","r66-new"],
  ("ISO 8601 周号计算：由年月日算 ISO 周号(1~53)与所属 ISO 年（12/29 前后跨年场景），用于周计划排产、周度 OEE 报表、维护周历。边界：月/日域闸+当月天数闰年校验非法=01；1990~2100 域外=02；禁 TRUNC(x)+1 技巧。","全整数儒略日数(JDN)法：date→JDN→周号=(JDN-锚点+偏移)/7 整数分支推导，全程无浮点；闰年判定与 FC_DL_LeapYearChk 同口径常量；4 个手算验收向量头注留档（2026-11-22=47 周、2027-01-01=2026 年 53 周）；防御性锚点闸结构性不可达留档声明。")),
 ("FC_DL_BilinearInterp","DL_MathData","FC",6,"西门子 LGF Math 分类语义借鉴，clean-room 重写","classification","lgf-math",["bilinear","interpolation","2d-table","clamp","grid","lgf-math","cleanroom","r66-new"],
  ("二维等距网格查表插值：阀门特性曲线、电机效率图、温度-压力补偿表等 ny×nx 表双线性插值。边界：fDx/fDy≤0 配置非法=01；越界钳位到边界单元并置码 02 不静默；末端格点 ABS 容差 1E-9 处理防越界行；非有限输入=03。","下标闸先行（防 n=1 时 UDINT 下标 -1 回绕，编码期自纠）；行列分数加权四点合成；越界属信息级钳位仍可用（附码报告）；与 FC_DL_InterpolateTable3D 互引（2D 平面表 vs 3D 立体表分工）；容量常量 32×32 头注声明。")),
 ("FC_DL_QuadPolyFit","DL_MathData","FC",7,"西门子 LGF Math 分类语义借鉴，clean-room 重写","classification","lgf-math",["polynomial-fit","least-squares","quadratic","gauss-elimination","regression","lgf-math","cleanroom","r66-new"],
  ("二次多项式最小二乘拟合：传感器标定曲线（非线性段）、流量计特性校准、工艺参数-品质关系建模，输出 y=a0+a1x+a2x² 三系数。边界：点数<3=01；非有限=02；3×3 正规方程列主元<1E-10 判奇异=03 不输出系数（防病态噪声放大）。","正规方程 Σ 矩阵法 + 列主元高斯消元；矩累加前非有限复核；三重 FOR 常量封顶禁 WHILE 死循环；与 FC_DL_LinearRegression2Var 互引（线性 vs 二次分工）；系数输出仅在 bValid=TRUE 时语义有效。")),
 ("FB_DL_AnalogOutFailsafe","DL_Device","FB",7,"IEC/NE43 输出侧安全语义借鉴 + 道莅原创架构","classification","ne43",["analog-output","failsafe","watchdog","ramp","freeze","safe-value","ne43","cleanroom","r66-new"],
  ("模拟量输出故障安全通道：上位心跳超时或请求失效时按 eFreeze 冻结/eSafeValue 安全值两种模式处置，带回程斜坡限速，用于阀门/变频器给定的失效安全设计。边界：fRampRatePctS≤0 配置非法；输出全程钳位 [0,100]；非有限请求按安全侧处理；故障锁存解除可达（心跳恢复沿+复位）。","TON 看门狗段 0 无条件刷新（R55）；三成因独立码（R190：心跳超时/请求非有限/配置非法分立）；斜坡与冻结模式仲裁沿一次落位不抖动；与 FB_DL_AnalogSignalHealth 互引（进侧诊断 vs 出侧安全）；失能相串清账（R303）。")),
 ("FB_DL_FeedOverrideRamp","DL_Motion","FB",6,"PLCopen 运动控制语义借鉴，clean-room 重写","classification","plcopen",["feed-override","ramp","rate-limit","zero-fast","motion","plcopen","cleanroom","r66-new"],
  ("进给倍率斜坡：旋钮/上位倍率请求(0~150%)按升/降分离速率平滑生效，快速归零指令最高优先，用于 CNC/专机进给安全减速。边界：输入钳位 [0,150]；三速率任一≤0 配置非法=01；到达判 1E-6 容差；失能相冻结保持+撤 bAtCmd 显式声明。","bZeroFast 显式最高优先仲裁；升/降/归零三速率分离选择支路；与 FB_DL_RateLimiter（通用斜坡原子）、FB_DL_OverrideSelector（倍率源选择）双向互引分工；失能相语义写死并头注声明不静默。")),
 ("FB_DL_LotMergeGate","DL_Process","FB",6,"ISA-88 批次语义借鉴，clean-room 重写","classification","isa88",["lot-merge","batch-accumulate","state-machine","recall","overflow","isa88","cleanroom","r66-new"],
  ("多批合一放行闸：按批数与数量双条件齐套判定（nLotsReq 批数 + uQtyReq 数量），齐套后 bRelease 放行、bRecall 可回迁，用于合批装柜、集批发运、批次配比投料。边界：nLotsReq/uQtyReq=0 配置非法 eFault；UDINT 溢出先闸后加禁回绕；eReleased 经 bRecall 回迁 eCollecting 可达。","六态状态机（eIdle/eCollecting/eReady/eReleased/eRecalled/eFault）；4×R_TRIG 段 0 无条件刷新；CASE 含 ELSE 兜底锁存 03；故障相台账保留审计回放、复位沿统一清账；与 FB_DL_ReworkLotGate（返工）/FB_DL_LotGenealogyLink（谱系）三分工互引。")),
 ("FB_DL_TaktPaceMonitor","DL_Process","FB",6,"ISO 22400-2 公开口径复用（self-std）","internal","self-std",["takt-time","ewma","pace-monitor","backlog","iso22400","internal","r66-new"],
  ("节拍达成度监视：单件完成脉冲流 → EWMA 实测节拍(s/件) 与目标节拍偏差(%)，窗口内累计欠产件数与落后判定位，供产线节拍预警与班组长看板。边界：fTaktTargetS≤0=01；fAlpha 域闸 (0,1] 端点容差=02；首件前不出数；缺口钳上限附码 03 防溢出。","推进判据（配置闸）与计时（注入周期）不同源（R300）；EWMA 增量更新零历史缓冲；欠产按窗口理论产量-实际产量全额计（产量不进分母防除零）；TIME_TO_DINT 依赖 TIME 毫秒口径三平台一致已头注声明；与 FB_DL_CycleTimeMeasure（单件测量）、FB_DL_OeeCalculator（OEE 聚合）三向互引。")),
]

now = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
shutil.copy2(REG, BAK)
reg = json.load(io.open(REG, encoding="utf-8"))
comps = reg["components"]
by_name = {c["name"]: c for c in comps}

for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
    instr, at = spec
    assert n not in by_name, "撞名: " + n
    p, src = st_read(cat, n)
    comps.append({
        "name": n, "category": cat, "type": ty, "file_path": p,
        "function_tags": tags, "complexity": cx, "version": "1.0.0",
        "registered_at": now, "line_count": src.count("\n") + 1,
        "code_segment": "", "source": "r66-plan",
        "origin": {"mode": om, "source": srcdesc, "license": "MIT" if om == "internal" else "cleanroom-ref",
                   "ref_tag": tag},
    })
    by_name[n] = comps[-1]

cnt = {}
for c in comps:
    cnt[c["category"]] = cnt.get(c["category"], 0) + 1
reg["counts"] = cnt
reg["total_components"] = len(comps)
reg["version"] = "2.58.0"
reg["last_updated"] = now
assert sum(cnt.values()) == len(comps), "counts sum mismatch"
json.dump(reg, io.open(REG, "w", encoding="utf-8"), ensure_ascii=False, indent=2)

def jsl_line(instr, at, src):
    return json.dumps({"instruction": instr, "architecture_thought": at, "output": src},
                      ensure_ascii=False, separators=(",", ":"))

added = 0
with io.open(JSL, "a", encoding="utf-8", newline="\n") as f:
    for (n, cat, ty, cx, srcdesc, om, tag, tags, spec) in NEW:
        instr, at = spec
        _, src = st_read(cat, n)
        f.write(jsl_line(instr, at, src) + "\n")
        added += 1

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
print("R66 closeout OK: new=%d registry=%d counts=%s lib=v2.58.0 jsonl=%d bad=%d"
      % (len(NEW), len(comps), json.dumps(cnt, ensure_ascii=False), tot, bad))
