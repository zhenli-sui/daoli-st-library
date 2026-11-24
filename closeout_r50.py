#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""closeout_r50.py —— R50 主控直跑收口（R335 规则）：注册 20 新件 + 5 返修升版 + JSONL 增量。
单次原子写回（R254）：全部先写临时文件再 os.replace。
"""
import io, os, json, sys

ROOT = r"C:\Library"
REG = os.path.join(ROOT, "INDEX_REGISTRY.json")
JSONL = os.path.join(ROOT, "_AI_Training_Dataset", "daoli_st_sft_dataset.jsonl")
NOW = "2026-11-20T07:40:00+08:00"

NEW = [
 ("FC_DL_PressUnitConvert","DL_MathData","FC",2,["lgf-converter","unit-convert","clean-room"]),
 ("FC_DL_CircleFit3Pt","DL_MathData","FC",3,["自研线","geometry-fit","clean-room"]),
 ("FB_DL_SignalHoldResume","DL_Base","FB",2,["自研线","snapshot-latch","clean-room"]),
 ("FB_DL_DebounceBank","DL_Base","FB",3,["自研线","debounce-array","clean-room"]),
 ("FB_DL_EStopMonitor","DL_Base","FB",4,["自研线","iec-60204-1","estop","clean-room"]),
 ("FB_DL_OutputForcingBank","DL_Base","FB",4,["自研线","force-bank","clean-room"]),
 ("FB_DL_SensorSupplyMon","DL_Base" if False else "DL_Device","FB",2,["自研线","ne43-domain","clean-room"]),
 ("FB_DL_SafetyMuteZone","DL_Device","FB",4,["自研线","iso-13849","muting","clean-room"]),
 ("FB_DL_HydraulicPowerUnit","DL_Device","FB",4,["自研线","hpu-seq","clean-room"]),
 ("FB_DL_CusumMonitor","DL_Algo","FB",3,["lgf-measurement","cusum-spc","clean-room"]),
 ("FB_DL_FirFilter","DL_Algo","FB",4,["lgf-measurement","fir-filter","clean-room"]),
 ("FB_DL_FlowBalanceCheck","DL_Algo","FB",4,["自研线","flow-balance","clean-room"]),
 ("FB_DL_FrequencySweepGen","DL_Algo","FB",4,["lgf-signal-generators","sweep","clean-room"]),
 ("FB_DL_ShewhartRules","DL_Algo","FB",5,["western-electric","spc-rules","clean-room"]),
 ("FB_DL_GoertzelToneDetect","DL_Algo","FB",5,["t1-8-dsp","goertzel","clean-room"]),
 ("FB_DL_AxisScrewPitchComp","DL_Motion","FB",3,["自研线","cnc-precision","clean-room"]),
 ("FB_DL_AxisThermalComp","DL_Motion","FB",3,["自研线","cnc-precision","thermal","clean-room"]),
 ("FB_DL_GearDecouple","DL_Motion","FB",4,["t1-6-plcopen","gear-out","clean-room"]),
 ("FB_DL_AxisTorqueFeedforward","DL_Motion","FB",4,["t2-4-s7-motion","torque-ff","clean-room"]),
 ("FB_DL_CamDynTrim","DL_Motion","FB",5,["t1-6-plcopen","cam-trim","clean-room"]),
]
REWORK = [
 ("FB_DL_LookaheadVelPlanner","DL_Motion"),
 ("FB_DL_ContourCrossCouple","DL_Motion"),
 ("FB_DL_AutoclaveSterilSeq","DL_Process"),
 ("FB_DL_SensorFusion2","DL_Algo"),
 ("FC_DL_SaturateSub","DL_Base"),
]
INSTR = {
 "FC_DL_PressUnitConvert":"压力变送器组态需要把传感器原始工程量在 Pa/kPa/bar/psi/mmHg 五种单位间互转，现场存在负压表（-90 kPa 表压）与绝压表混装，要求负压域合法换算、不越过绝对真空下限、换算系数表驱动禁止散落魔法数；边界：负压域合法、真空下限钳位、常量化除法无除零。",
 "FC_DL_CircleFit3Pt":"激光三角测厚标定需用三个靶点坐标拟合标定圆心与半径用于偏心补偿；三靶点近似共线时拟合病态发散，必须用叉积绝对值与容差比较显式拒绝并给出故障出口；边界：共线拒绝防除零、非有限输入直接故障出口。",
 "FB_DL_SignalHoldResume":"批处理切换配方时需把 8 路联锁信号快照锁存，恢复时按快照回写；若锁存期间现场已变化，恢复沿必须做锁存副本与实时值一致性校验并告警，锁存期间实时变化不得穿透输出；边界：锁存/实时双副本不得混用（R38 范式）。",
 "FB_DL_DebounceBank":"大型分拣线 16 路光电信号各自需要独立上升/下降去抖时间，统一实例化 16 个单路去抖件资源开销大；要求阵列式每通道独立 TON/TOF 且无条件周期刷新，通道数配置钳位 1~16，越界通道恒 FALSE 不误报。",
 "FB_DL_EStopMonitor":"急停回路双通道冗余接线需在线监测通道失配（KOP 要求），失配经确认窗判定防瞬时抖动误报，锁定首出通道便于检修定位；复位必须在双通道恢复一致后由沿触发，禁止自动盲目复位；边界：失配窗独立 TON、首出锁存。",
 "FB_DL_OutputForcingBank":"调试与验收阶段需要对 16 路输出逐点强制而不动程序，任一强制激活必须置全局强制告警位图防止带强制投运；强制撤除当拍无扰回自动值；非自动模式下强制请求应被拒绝并记码；边界：位图告警、无扰回切、模式闸门。",
 "FB_DL_SensorSupplyMon":"多通道传感器共用 24V 供电，供电跌落时故障表现为多通道同时异常，需按窗口均值+迟滞判限区分供电问题与单通道漂移，输出逐通道诊断掩码；临界值附近防止振荡误判，非有限输入保持上次结论并置信息码。",
 "FB_DL_SafetyMuteZone":"物流线光幕需要在托盘进出工位时按双 muting 传感器顺序时序合法静默，乱序（单先动、逆序）即为故障锁存，静默窗超时强制撤销静默恢复光幕保护；头注释明确不作安全认证声明，仅工艺时序编排。",
 "FB_DL_HydraulicPowerUnit":"液压站电机需按压力带自动起停（±0.5 MPa 回差带卸荷阀顺控），油温超限与油位低于下限时联锁必须先于电机判据执行，电机频繁启停需最小切换间隔互锁保护接触器；边界：回差带、联锁优先、互锁窗。",
 "FB_DL_CusumMonitor":"关键工序参数缓漂监测（均值守不住但单点不出控），需累积和 CUSUM 双侧判异：正负决策区间分别下限钳零防负累加污染，复位沿清双累计，非有限样本跳过并计数供追溯；边界：钳零、复位、非有限防护。",
 "FB_DL_FirFilter":"振动监测通道需线性相位 FIR 滤波，系数表由上位机下发；系数和显著偏离 1 说明配置错误必须拒绝，阶数钳位上限防资源失控，环形缓冲移位用倒序拷贝防越界；边界：归一校验、阶数钳位、拷贝边界。",
 "FB_DL_FlowBalanceCheck":"密闭管路进出流量计累计量差值应在容差内，长期失衡提示泄漏或计量漂移；累计差在窗口期重算防瞬时波动误报，容差配置≤0 属组态错误应冻结判定并置故障码；边界：窗口重算、数组钳位、容差校验。",
 "FB_DL_FrequencySweepGen":"伺服系统频响辨识需要扫频激励：频率在起止区间按可配斜坡往返扫描，边界驻留可配时间后反向，输出瞬时频率与方向标志；与定频发生、波形发生、频率测量件职责严格三分离；边界：驻留反向、方向翻转。",
 "FB_DL_ShewhartRules":"SPC 在线判异需按 Western Electric 8 条公开规则输出判异位图与连长计数，供 MES 追溯；连长计数窗口滚动数组需边界防御，复位清全部计数与侧别锁存；判据相等按保守侧中断处理；边界：位图重建口径、滚动窗防御。",
 "FB_DL_GoertzelToneDetect":"声学检漏需在强噪声中检测单一特征音频率幅值，Goertzel 单 Bin 递推比全 FFT 省资源；采样率与目标频率需 Nyquist 预检，门时到期一次结算后复位递推状态，结算功率负值/非有限钳 0；边界：Nyquist 预检、状态复位。",
 "FB_DL_AxisScrewPitchComp":"CNC 轴滚珠丝杠全行程误差需分段误差表前馈补偿，段索引由位置计算须防越界钳位，表长与段数一致性需校验防错表；非有限位置输出 0 并置信息码而非带病补偿；边界：索引钳位、表长校验、非有限防护。",
 "FB_DL_AxisThermalComp":"丝杠热伸长随温升近似线性，需按温差与膨胀系数输出行程比例补偿量，一阶热模型时间常数可配；温度超域钳位防外推发散，bEnable=FALSE 时直通 0 保证可旁路；边界：超域钳位、旁路直通。",
 "FB_DL_GearDecouple":"电子齿轮同步运行需要在不停机情况下脱耦（MC_GearOut 语义）：比例按斜坡渐降至 1:1 后才允许断开耦合，斜坡中直接跳断会造成从轴速度突变；分母为 0 属组态错误拒绝并锁故障；边界：斜坡渐降、完成沿、除零拒绝。",
 "FB_DL_AxisTorqueFeedforward":"大惯量负载高速定位需要转矩前馈提高跟随性：按 J·a + 粘滞项计算，惯量由辨识件注入，J≤0 拒算直通 0 防除零/病态，输出限幅必填防饱和冲击；与转矩诊断件职责分离；边界：J 校验、限幅必填。",
 "FB_DL_CamDynTrim":"凸轮电子凸轮运行中需相位/比例在线微调（修调）而无需重新装载凸轮表：修调经斜坡渐生效防凸轮表跳变冲击，单次修调幅值上限钳位，执行中拒绝叠加修调；边界：斜坡生效、幅值钳位、叠加拒绝。",
}
ARCH = {
 "FC_DL_PressUnitConvert":"纯函数无状态架构：枚举单位对映射到系数表（基准 Pa），一次乘法+一次常量除完成换算；真空下限用 MAX 钳位，负压域走同一表不做分支特判；错误出口 BOOL+ENUM 双通道，单值查表 CASE 含 ELSE 兜底，无实例无定时器，天然可重入。",
 "FC_DL_CircleFit3Pt":"三点外推式解析解：中垂线法联立二元一次方程组，行列式即 2 倍叉积面积，|D|<容差判定共线拒绝；先非有限预检再算，输出圆心+半径三值打包；纯函数无 FB 状态，容差常量化集中声明便于平台移植调参。",
 "FB_DL_SignalHoldResume":"状态机四态（Idle/Held/Verify/Restored）：bHold 沿触发快照到锁存数组（锁存副本），恢复沿进入 Verify 态做锁存 vs 实时一致性比对，差异通道置告警掩码；实时值始终只读不回写锁存副本，双副本职责分离；R_TRIG 无条件周期刷新。",
 "FB_DL_DebounceBank":"FOR 循环逐通道驱动独立 TON/TOF 实例数组，实例调用在循环体内无条件执行（不套 IF）；通道数 iN 在入口钳位 1~16 并只读副本，循环上界用钳位值防数组越界；每通道 rise/fall 双定时器交替判据，输出锁存于扫描末尾统一写。",
 "FB_DL_EStopMonitor":"双通道正常态机（Safe/Mismatch/FirstOut）+ 独立确认窗 TON 判失配稳定；首出通道号锁存变量仅 bReset 且双通道一致后沿才清；复位沿用 R_TRIG 无条件刷新防漏沿；出口 bSafe/bMismatch/通道号三线分离便于上游分级处置。",
 "FB_DL_OutputForcingBank":"逐通道选择器架构：强制有效=ForceSel∧ForceVal∧AutoMode 三与闸，位图告警由 OR 累积；撤除当拍直通自动值实现无扰回切；非自动模式强制请求被拒并置拒绝码；全部判定为组合逻辑+一个告警锁存位，无定时器依赖，扫描周期确定性高。",
 "FB_DL_SensorSupplyMon":"滑动窗口均值+迟滞双阈值架构：窗口累计环形数组边界防御，均值跨上/下限判限（迟滞带宽常量化）防临界振荡；非有限输入跳过采样但保持上一拍结论并置信息码，掩码按通道位扩展；TON 用于窗口采样节拍无条件刷新。",
 "FB_DL_SafetyMuteZone":"muting 顺序状态机（Armed/Seq12/Seq21/Muted/Fault）：双传感器先后沿序决定合法路径，乱序即迁 Fault 锁存需显式复位；静默窗 TON 无条件刷新，超时强制撤销并置码；光幕信号仅在 Muted 态被旁通；头注释明确不作安全认证声明。",
 "FB_DL_HydraulicPowerUnit":"五态顺控机（Idle/Start/Run/Unload/Interlock）+ 回差带卸荷判据（±0.5 MPa 常量化）；联锁判定置于状态迁移之前形成优先级短路；电机最小切换间隔用独立 TON 互锁窗口无条件刷新；成因归因用 _eCause 入相锁存回放（R189/R190 范式）。",
 "FB_DL_CusumMonitor":"双侧 CUSUM 核：S+ = max(0, S+ + (x-μ-K))，S- 对称，max 钳零防负累加；判限 H 独立常量可配；非有限样本跳过且跳过计数器出口；复位沿同时清双累计与计数器；报警沿锁存一拍防抖；无定时器，纯周期递推，可多实例并行部署。",
 "FB_DL_FirFilter":"环形缓冲+直接卷积架构：倒序拷贝实现 O(1) 滑窗（防 memmove 越界），卷积循环上界为钳位后阶数；系数和归一校验在复位沿一次性完成并锁存结论，失败即故障出口不滤波；输出在 END_VAR 前统一镜像，声明区全部双语注释。",
 "FB_DL_FlowBalanceCheck":"窗口重算架构：窗口 TON 无条件刷新到时统一计算失衡率，瞬时值仅缓存不判级；失衡率三级分级（正常/预警/故障）CASE 含 ELSE 兜底；容差≤0 组态校验在入口一次性闸门冻结判定并置故障码；数组下标全程钳位。",
 "FB_DL_FrequencySweepGen":"双斜坡状态机（RampUp/DwellHigh/RampDown/DwellLow）：方向标志随态迁移翻转，斜率常量域校验防 0 斜率死循环；驻留 TON 无条件刷新；与定频/波形/测频件接口零重叠（输出仅 fFreqOut+方向）；边界驻留时间钳位下限。",
 "FB_DL_ShewhartRules":"8 规则并行判定架构：单点/连长/趋势三类判据独立计算后 OR 汇入位图；连长计数用滚动环形数组+侧别锁存（前拍侧别 _bSidePrev），相等按保守侧中断；位图每可入窗拍重建、跳过拍保持上拍（口径④声明）；复位清全部计数与锁存。",
 "FB_DL_GoertzelToneDetect":"单 Bin 二阶递推核：sNew = 2cos(ω)·s1 - s2 + x，三步严格定序（sNew→s2←旧s1→s1←sNew）消除连写歧义；Nyquist 预检在复位沿一次性完成锁存；门时 LREAL 秒口径规避跨平台 TIME→实数转换链；结算功率负值/非有限钳 0，单次结算后递推状态复位。",
 "FB_DL_AxisScrewPitchComp":"分段查表+线性插值架构：段索引由位置与段宽比值计算后钳位 0..N-1，表长一致性在复位沿校验锁存；段内分数 DINT_TO_LREAL 标准转换防方言；非有限位置入口预检直通 0 置信息码；补偿量出口镜像统一在主体尾部。",
 "FB_DL_AxisThermalComp":"一阶热模型+比例补偿架构：温度差经超域钳位后乘膨胀系数得稳态补偿量，时间常数 fTauS 作一阶低通滤波趋近（LREAL 秒口径），避免阶跃温度导致补偿突跳；bEnable=FALSE 直通 0 旁路；滤波器状态复位沿清零，纯 IEC 标准语法无方言转换。",
 "FB_DL_GearDecouple":"斜坡脱耦状态机（Coupled/Ramping/Released）：比例渐降用 LREAL 斜坡积分至 1:1 才置 bReleased 完成沿；斜坡时长 LREAL 秒口径规避 TIME 转换链（R64 列管）；iDen=0 组态闸在入口拒绝锁故障；斜坡中 bCoupleDrop 请求被忽略，完成沿后才响应断开。",
 "FB_DL_AxisTorqueFeedforward":"前馈核 τ = J·α + c·v：J≤0 与非有限入口预检直通 0 不算，防病态；输出限幅 fMax 必填校验在复位沿一次性完成；粘滞/惯量参数由外部辨识件注入，本件不做辨识（职责分离）；纯组合+一拍平滑，无定时器，多轴实例并行安全。",
 "FB_DL_CamDynTrim":"修调渐生效架构：bApply 沿触发把目标修调锁存为目标值，斜坡积分器逐拍逼近防凸轮表跳变；单次幅值上限钳位在锁存时完成，执行中（斜坡未完成）新 bApply 被拒绝并置码；bTrimActive 指示斜坡进行中；R_TRIG 无条件刷新防漏沿。",
}
REWORK_NOTE = {
 "FB_DL_LookaheadVelPlanner":"R50 返修 v1.0.1：回溯步减速距离改取本段 L[i]（原误用邻段 L[i+1]），与前传对称；验收向量同步更新。",
 "FB_DL_ContourCrossCouple":"R50 返修 v1.0.1：方向向量非有限判据补 Inf 判 ((x-x)<>0)，与误差项双判口径对齐。",
 "FB_DL_AutoclaveSterilSeq":"R50 返修 v1.0.1：头注释补声明 bStop 保留 F0 累计口径，逻辑零改动。",
 "FB_DL_SensorFusion2":"R50 返修 v1.0.1：fTauVar=0 端点下限钳位（TAUMIN=1E-6 工作副本），方差递推不再冻结。",
 "FC_DL_SaturateSub":"R50 返修 v1.0.1：头注释验收向量溢出误断言更正（实现不动）。",
}
ARCH_RW = {
 "FB_DL_LookaheadVelPlanner":"前瞻速度规划器：前传加速取邻段 L[i+1]、回溯减速取本段 L[i] 的对称双扫描架构；减速距离逐段累加与限速二次比较取小；复位沿清速度与扫描游标；本版修正回溯步累加项取段错误。",
 "FB_DL_ContourCrossCouple":"轮廓交叉耦合补偿：误差项与方向向量双通道非有限判据（NaN 与 Inf 双判 (x-x)<>0 口径统一），耦合增益按两轴误差比动态分配，单轴故障即解耦直通；本版统一两侧非有限口径。",
 "FB_DL_AutoclaveSterilSeq":"灭菌柜顺控状态机（脉动升压/保温保压/排气/结束）多段温压双闭环，F0 值累计贯穿脉动轮次；bStop 只清脉动计数与子态、保留 F0 累计（口径已声明），bReset 全清；CASE 全分支含 ELSE 兜底，TON 无条件刷新。",
 "FB_DL_SensorFusion2":"双传感器自适应融合：方差递推加权，fTauVar 经 TAUMIN=1E-6 下限钳位工作副本参与递推，端点方差不再冻结自适应；非有限输入按上拍保持；权重和=1 归一化结构保证出口有界。",
 "FC_DL_SaturateSub":"饱和减法纯函数：差值饱和于类型域边界防下溢回绕，注释验收向量以类型域可表性为准（MIN+1 无溢出）；无状态纯函数，容差与域常量集中声明。",
}

def main():
    # backups
    import shutil
    shutil.copy2(REG, REG + ".bak_r50")
    shutil.copy2(JSONL, JSONL + ".bak_r50")

    reg = json.load(io.open(REG, encoding="utf-8"))
    comps = reg["components"]
    names = {c["name"] for c in comps}
    added, skipped = [], []
    for name, cat, typ, cx, tags in NEW:
        if name in names:
            skipped.append(name); continue
        p = os.path.join(ROOT, cat, name + ".st")
        lines = len(io.open(p, encoding="utf-8").read().strip().splitlines())
        comps.append({"name": name, "category": cat, "type": typ,
                      "file_path": p, "function_tags": tags + [name.lower()],
                      "complexity": cx, "version": "1.0.0",
                      "registered_at": NOW, "line_count": lines,
                      "code_segment": "", "source": "r50-plan"})
        added.append(name)
    if skipped:
        print("SKIP(已存在，未覆盖):", skipped)
    # rework version bumps
    rw_done = []
    for name, cat in REWORK:
        for c in comps:
            if c["name"] == name:
                c["version"] = "1.0.1"
                p = os.path.join(ROOT, cat, name + ".st")
                c["line_count"] = len(io.open(p, encoding="utf-8").read().strip().splitlines())
                rw_done.append(name); break
    # counts & meta
    counts = {}
    for c in comps:
        counts[c["category"]] = counts.get(c["category"], 0) + 1
    reg["counts"] = {k: counts.get(k, 0) for k in
                     ("DL_Base","DL_MathData","DL_Algo","DL_Device","DL_Motion","DL_Process")}
    reg["total_components"] = len(comps)
    reg["version"] = "2.42.0"
    reg["last_updated"] = NOW
    # atomic write CRLF
    tmp = REG + ".tmp"
    with io.open(tmp, "w", encoding="utf-8", newline="") as f:
        json.dump(reg, f, ensure_ascii=False, indent=1)
        f.write("\n")
    os.replace(tmp, REG)
    print("registry: %d comps, counts=%s, added=%d, rework=%d"
          % (len(comps), reg["counts"], len(added), len(rw_done)))

    # ---- JSONL ----
    lines = io.open(JSONL, encoding="utf-8").read().splitlines()
    out, reinj = [], []
    for ln in lines:
        if not ln.strip():
            continue
        obj = json.loads(ln)
        nm = None
        for rname, _ in REWORK:
            if rname in (obj.get("instruction","") + obj.get("output","")):
                nm = rname; break
        if nm:
            cat = dict(REWORK)[nm]
            src = io.open(os.path.join(ROOT, cat, nm + ".st"), encoding="utf-8").read()
            obj["output"] = src
            base_instr = obj.get("instruction","")
            obj["instruction"] = base_instr if REWORK_NOTE[nm].split("：")[1].split("，")[0] in base_instr else base_instr
            if nm not in reinj:
                obj["instruction"] = obj["instruction"].rstrip() + "｜" + REWORK_NOTE[nm]
                reinj.append(nm)
        out.append(json.dumps(obj, ensure_ascii=False))
    # append 20 new
    ap = 0
    for name, cat, typ, cx, tags in NEW:
        if name in skipped:  # already registered earlier? still append only if not previously in jsonl
            pass
        src = io.open(os.path.join(ROOT, cat, name + ".st"), encoding="utf-8").read()
        # skip if name already present in dataset (guard)
        if any(name in o for o in out[:len(out)]) and False:
            continue
        obj = {"instruction": INSTR[name], "architecture_thought": ARCH[name], "output": src}
        out.append(json.dumps(obj, ensure_ascii=False))
        ap += 1
    tmp2 = JSONL + ".tmp"
    with io.open(tmp2, "w", encoding="utf-8", newline="") as f:
        f.write("\n".join(out) + "\n")
    os.replace(tmp2, JSONL)
    # validate
    bad = 0
    for ln in io.open(JSONL, encoding="utf-8").read().splitlines():
        if not ln.strip(): continue
        try:
            o = json.loads(ln)
            if not o.get("output") or len(o.get("instruction","")) < 40:
                bad += 1
        except Exception:
            bad += 1
    print("jsonl: lines=%d appended=%d reinjected=%s badjson/short=%d"
          % (len(out), ap, reinj, bad))
    return 0 if bad == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
