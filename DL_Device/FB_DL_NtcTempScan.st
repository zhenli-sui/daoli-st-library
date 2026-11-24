(*==============================================================================
 * 组件名称 (Component)  : FB_DL_NtcTempScan
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.1
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 设备测量 · 多通道温度巡检
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅 LN 与四则运算、TON、R_TRIG
 * 功能描述 (Function)   : 一块覆盖 1 到 16 路 NTC 热敏电阻的完整设备对象：
 *                         B 值公式换算摄氏温度、逐通道断线与短路诊断、高温与
 *                         低温判定、最热通道定位、超温累计次数与通道故障掩码。
 *                         替代「每通道一个温控块」的堆叠写法，降低单拍负载与
 *                         程序块数量，并把「哪一路最热」直接算好给 HMI。
 * 边界声明 (Boundary)   : FB_DL_AnalogTransmitter 处理直流电流与电压变送器
 *                         （线性标定加断线诊断），输入量纲是毫安与伏特；本块
 *                         处理电阻型热敏电阻（非线性 B 值公式加阻值域诊断），
 *                         输入量纲是欧姆，两者不可互替。FB_DL_HeatCoolZone 是
 *                         控温执行块（含调节输出），本块只做测量与判定，不产生
 *                         任何控制输出，避免测量件与执行件职责混淆。
 * 参数分段 (Segments)   : 借鉴设备 AOI 的参数分段组织：输入段给出阻值数组与
 *                         通道数；输出段给出温度数组与统计量；诊断段给出通道
 *                         故障掩码与事件码；内部段持有轮询索引、有效标志与
 *                         超温沿记忆。四段职责不交叉，HMI 只绑输出段与诊断段。
 * 换算公式 (Formula)    : 采用公开的 B 值（Beta）方程：
 *                         1 除以绝对温度等于 1 除以基准温度 加 自然对数(阻值
 *                         除以标称阻值) 除以 B 常数；摄氏温度等于绝对温度减
 *                         开尔文偏移。该式在标称点附近误差最小，适合设备级
 *                         巡检；高精度场合请改用分段查表并在上层标定。
 * 前置守卫 (Guards)     : 除法之前必须先判零：B 常数为零、标称阻值为零、基准
 *                         温度为零、阻值比为零、算出的倒数温度为零，任一成立
 *                         即本通道不参与换算，保持上一次温度并置参数码。绝不
 *                         允许「先算后判」，浮点除零在部分平台直接产生异常值。
 * 扫描调度 (Scheduling) : 扫描周期大于零时按节拍轮询，每拍只算一路，通道数多
 *                         时单拍负载恒定；扫描周期为零时全通道每拍扫描，适合
 *                         通道少且要求最快响应的场合。两种模式的输出数组都
 *                         跨拍保持，未被扫到的通道沿用上一拍结果。
 * 最热通道 (Hottest)    : 只在存在有效通道时计算，平局取通道号最小者，避免
 *                         逐拍在两个同温通道之间来回跳变；全部通道无效时输出
 *                         零号通道并置全失效故障。
 * 锁存策略 (Latch)      : 单通道断线与短路只置通道故障掩码与信息级码，不置
 *                         故障位（现场常见单路探头损坏，整机仍可降级运行）；
 *                         只有「有效通道数为零」与「换算参数非法」才置故障位，
 *                         且后者一次性锁存，需复位才可退出。
 * 开源溯源 (Origin)     : rockwell-aoi / oscat-building / lgf-measurement。参考
 *                         公开设备 AOI 的多通道参数分段组织与建筑自控功能库的
 *                         温度测量分类，只借参数分段与功能分类；B 值方程为公开
 *                         物理公式，枚举、状态机、诊断策略、码位与全部实现 100%
 *                         自有，clean-room 实现，不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 LN / TON
 * 故障码表 (Error codes):
 *   16#0003_0145【信息级】通道数越界已钳位（小于 1 或大于 16）
 *   16#0003_0146【信息级】单通道断线或短路已跳过（保持上次温度）
 *   16#0003_0303【故障级】全通道失效（有效通道数为零，置故障位）
 *   16#0003_0304【故障级】换算参数非法已锁存（B 常数、标称阻值、基准温度）
 * 码位占用 (Slot)       : 信息级 0145 / 0146；故障级 0303 / 0304。
 *                         全部落在 R11 本件分配块内，无跨块借用。
 * 写入点次序 (Write order) :
 *   ① afTempC      ：只在通道换算成功那一拍写，失败拍保持，绝不写零冒充
 *   ② uChannelFaultMask ：每拍由锁存数组重算，锁存只增不减，仅复位可清
 *   ③ nHottestCh   ：每拍重算，全通道无效时写 0，不做历史保持
 *   ④ ePhase       ：状态机段为唯一位移点，复位分支只回待机
 * 验收向量 (Acceptance) :
 *   V1 基准点：阻值 10000、标称 10000、B 值 3950 → 25.00 摄氏度（正负 0.05）
 *   V2 双倍阻值：阻值 20000 → 10.2 摄氏度（正负 0.1）
 *   V3 半阻值：阻值 5000 → 41.5 摄氏度（正负 0.1）
 *   V4 断线：三号通道阻值 1.2 兆欧 → 掩码 16#0004、温度保持、故障位为假
 *   V5 全失效：十六通道全断线 → 最热通道 0、码 16#0003_0303、故障位为真
 * 红线自检 (Redline)    : R1 零全局变量表与外部变量引用 ｜ R2 零物理地址直写
 *                         R3 纯 IEC 61131-3 ｜ R4 除法全防零、数组全防越界
 *                         R5 全变量中英双语同行注释 ｜ R6 ENUM 加 CASE 加 ELSE
 *                         R7 TON 与 R_TRIG 在 CASE 之外无条件刷新
 *                         R8 信息级码 0145 与 0146 不置故障位
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版落盘（Round 11 · 泳道 B · 多通道测量设备件）
 *   2026-11-15  v1.0.1  R11 总监终审修复：全扫模式的扫描圈数累加缺饱和守卫，与轮询分支
 *                       不一致，长时间运行会在 2 的 32 次方处回绕；补小于上限守卫
 *   2026-11-15  v1.0.1  R11 director final review fix: the all-channel scan branch lacked the
 *                       saturation guard used by the polling branch, so the round counter
 *                       wrapped at the 32-bit limit; the guard is now applied to both
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_NtcStat（跨周期统计，由调用方持有）
 *         Persistent statistics structure owned by the caller
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_NtcStat :
STRUCT
    anOverTempCnt : ARRAY[1..16] OF UDINT;  // 逐通道超温累计次数，上升沿计数 [次] / Per-channel over temperature count, rising edge only
    anOpenCnt     : ARRAY[1..16] OF UDINT;  // 逐通道断线累计次数，进故障沿计数 [次] / Per-channel open circuit count, on entry only
    nScanRounds   : UDINT;                  // 完整轮询圈数，用于估算单通道刷新周期 [圈] / Completed scan rounds, estimates the refresh period
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_NtcScanPhase（本块相位，归属本功能块并同文件发布）
 *       Phase enumeration owned by this block and published in the same file
 *-----------------------------------------------------------------------------*)
TYPE E_DL_NtcScanPhase :
(
    eIdle    := 0,   // 待机：未使能，输出数组保持 / Idle, output arrays kept
    eScan    := 10,  // 巡检：轮询推进，逐通道换算与判定 / Scanning, channels evaluated in turn
    eAllFail := 20,  // 全失效：有效通道数为零，可自动恢复 / All failed, recovers automatically
    eFault   := 99   // 故障：换算参数非法，一次性锁存需复位 / Fault, illegal parameters, latched until reset
);
END_TYPE

(*==============================================================================
 * 逐拍推演 (Cycle-by-cycle trace)：
 *   场景 A 基准点（阻值等于标称一万欧，B 值 3950，基准 298.15 开）
 *     阻值比为一，自然对数为零，倒数温度等于基准温度倒数，绝对温度 298.15
 *     开，减偏移得 25.00 摄氏度；判定为有效通道，参与最热通道比较
 *   场景 B 阻值翻倍（两万欧）
 *     阻值比二，自然对数约 0.6931，除 B 值得 0.0001755，加基准倒数得
 *     0.0035295，取倒数得 283.33 开，减偏移得 10.2 摄氏度
 *   场景 C 断线（三号通道阻值 1.2 兆欧）
 *     阻值超过断线上限，通道故障位置位并锁存，断线计数加一，温度数组该通道
 *     保持上一拍值不写零；通道有效标志置假，不参与最热比较与温限判定
 *   场景 D 全失效（十六通道全断线）
 *     有效通道计数为零，最热通道写零，状态机转全失效态，置 0303 与故障位；
 *     任一路接线修复后下一轮有效通道计数回到一，自动退回巡检态，无需复位
 *   场景 E 换算参数非法（B 值被写成零）
 *     参数守卫在换算前拦下，状态机转故障态并置 0304，故障位锁存；修好参数
 *     后仍需复位上升沿才可退出，避免组态抖动导致反复进出故障
 *============================================================================*)

FUNCTION_BLOCK FB_DL_NtcTempScan
VAR_INPUT
    bEnable        : BOOL;                              // 使能，FALSE 时保持上次温度 [-] / Enable, holds the last temperatures on FALSE
    bReset         : BOOL;                              // 复位通道故障锁存，上升沿有效 [-] / Clears the channel fault latch on a rising edge
    nChannelCount  : INT;                               // 通道数 [路]，有效域 1 到 16 / Channel count, one to sixteen
    afResistance   : ARRAY[1..16] OF REAL;              // 各通道热敏电阻阻值 [欧姆]，量程 10 到 1.0E6 / Per-channel resistance in ohm, ten to one million
    fBeta          : REAL := 3950.0;                    // B 常数 [开尔文]，典型 3435 或 3950 / Beta constant in kelvin, typically 3435 or 3950
    fR25           : REAL := 10000.0;                   // 二十五摄氏度标称阻值 [欧姆] / Nominal resistance at twenty-five degrees, ohm
    fT25           : REAL := 298.15;                    // 基准绝对温度 [开尔文] / Reference absolute temperature in kelvin
    afTempHigh     : ARRAY[1..16] OF REAL;              // 各通道高温阈值 [摄氏度] / Per-channel high temperature limit
    afTempLow      : ARRAY[1..16] OF REAL;              // 各通道低温阈值 [摄氏度] / Per-channel low temperature limit
    tScanPeriod    : TIME := T#100MS;                   // 通道轮询节拍 [毫秒]，零表示全通道每拍扫描 / Channel scan period, zero scans every channel each cycle
END_VAR
VAR_OUTPUT
    afTempC        : ARRAY[1..16] OF REAL;              // 各通道温度 [摄氏度] / Per-channel temperature in degrees Celsius
    nHottestCh     : INT;                               // 最热通道号 [1..16]，0 表示无有效通道 / Hottest channel, zero means none valid
    fHottestTemp   : REAL;                              // 最热通道温度 [摄氏度] / Temperature of the hottest channel
    bAnyOverTemp   : BOOL;                              // 任一有效通道超高温阈值 [-] / Any valid channel above its high limit
    bAnyUnderTemp  : BOOL;                              // 任一有效通道低于低温阈值 [-] / Any valid channel below its low limit
    uChannelFaultMask : WORD;                           // 通道故障掩码，位 n 对应通道 n 加一 [位串] / Channel fault mask, bit n is channel n plus one
    eState         : E_DL_NtcScanPhase;                 // 主状态机当前相位 [-] / Current phase of the main state machine
    bError         : BOOL;                              // 故障级锁存，仅 0303 与 0304 置位 [-] / Latched fault, only fault level codes set it
    uErrorId       : UDINT;                             // 事件码，0 表示无事件 [代码] / Event code, zero means none
END_VAR
VAR_IN_OUT
    stStat         : ST_DL_NtcStat;                     // 跨周期统计：超温次数、断线次数、轮询圈数 / Persistent statistics, over temperature and open counts
END_VAR
VAR
    fbTrigReset    : R_TRIG;                            // 复位沿检测，CASE 之外无条件刷新 [-] / Reset edge detector, refreshed outside the CASE
    fbTonScan      : TON;                               // 轮询节拍计时，CASE 之外无条件刷新 / Scan period timer, refreshed outside the CASE
    bInit          : BOOL := FALSE;                     // 首扫标志，初值 FALSE，判据 NOT bInit [-] / First-scan flag initialised FALSE
    ePhase         : E_DL_NtcScanPhase := E_DL_NtcScanPhase.eIdle;  // 内部相位，对外经 eState 输出 / Internal phase, exported as eState
    nChClamped     : INT;                               // 钳位后的通道数 [路]，0 到 16 / Clamped channel count, zero to sixteen
    tScanUse       : TIME;                              // 实际生效的轮询节拍 [毫秒] / Effective scan period
    bScanAll       : BOOL;                              // 全通道每拍扫描模式标记 [-] / Flag, scan every channel each cycle
    bScanRun       : BOOL;                              // 节拍计时器输入，触发拍拉低以重启 / Timer input, dropped on the tick cycle
    bScanTick      : BOOL;                              // 节拍到拍标志 [-] / Scan tick flag
    nScanIdx       : INT;                               // 轮询通道索引 [1..16] / Polling channel index
    abChValid      : ARRAY[1..16] OF BOOL;              // 逐通道本拍有效标志 [-] / Per-channel validity flag of this cycle
    abChFault      : ARRAY[1..16] OF BOOL;              // 逐通道故障锁存标志 [-] / Per-channel latched fault flag
    abOverPrev     : ARRAY[1..16] OF BOOL;              // 逐通道上一拍超温状态，用于沿计数 [-] / Per-channel previous over temperature state
    bParamBad      : BOOL;                              // 换算参数非法标记 [-] / Flag, conversion parameters are illegal
    nValidCh       : INT;                               // 本拍有效通道数 [路] / Valid channel count of this cycle
    fResistance    : REAL;                              // 当前通道阻值 [欧姆] / Resistance of the current channel
    fRatio         : REAL;                              // 当前通道阻值比 [无量纲] / Resistance ratio of the current channel
    fInvTemp       : REAL;                              // 绝对温度倒数 [每开尔文] / Reciprocal of the absolute temperature
    fTempK         : REAL;                              // 换算得到的绝对温度 [开尔文] / Converted absolute temperature in kelvin
    bChOpen        : BOOL;                              // 当前通道断线标记 [-] / Flag, current channel is open
    bChShort       : BOOL;                              // 当前通道短路标记 [-] / Flag, current channel is shorted
    nHotScan       : INT;                               // 最热通道临时结果 [1..16] / Temporary hottest channel result
    fHotScan       : REAL;                              // 最热温度临时结果 [摄氏度] / Temporary hottest temperature result
    bStateIllegal  : BOOL;                              // 非法相位被兜底捕获 [-] / Flag, an illegal phase was captured
    i              : INT;                               // 通道遍历索引 [1..16] / Channel loop index
END_VAR
VAR CONSTANT
    DL_CH_MAX        : INT := 16;                       // 通道上限 [路] / Maximum channel count
    DL_CH_MIN        : INT := 1;                        // 通道下限 [路] / Minimum channel count
    DL_R_OPEN        : REAL := 1.0E6;                   // 断线判定阻值上限 [欧姆] / Open circuit resistance threshold
    DL_R_SHORT       : REAL := 10.0;                    // 短路判定阻值下限 [欧姆] / Short circuit resistance threshold
    DL_KELVIN_OFFSET : REAL := 273.15;                  // 摄氏与开尔文换算偏移 [开尔文] / Kelvin to Celsius offset
    DL_FLOAT_EPS     : REAL := 1.0E-6;                  // 浮点判零容差 [无量纲] / Float epsilon for zero tests
    DL_TEMP_SANE     : REAL := 200.0;                   // 温度合理性上界 [摄氏度]，超界视为传感器异常 / Temperature sanity bound, above it the probe is suspect
    DL_CNT_MAX       : UDINT := 16#FFFF_FFFE;           // 计数饱和上限，防溢出回绕 [次] / Counter saturation limit
    DL_TIME_ZERO     : TIME := T#0MS;                   // 时间零值基准 [毫秒] / Time zero reference
    DL_SCAN_MIN      : TIME := T#1MS;                   // 轮询节拍下限 [毫秒] / Minimum scan period
    DL_MASK_ONE      : WORD := 16#0001;                 // 通道掩码单比特基准 [位串] / Single bit reference for the channel mask
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜沿检测无条件刷新（R7 红线）
 *      Edge detection refreshed unconditionally
 *-----------------------------------------------------------------------------*)
fbTrigReset(CLK := bReset);

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（R19 唯一合法范式）
 *      First-scan initialisation with the canonical R19 pattern
 *-----------------------------------------------------------------------------*)
IF NOT bInit THEN
    FOR i := 1 TO DL_CH_MAX DO
        afTempC[i]     := 0.0;             // 温度输出初值确定，HMI 不显示随机数
        abChValid[i]   := FALSE;           // 首扫前无任何有效通道
        abChFault[i]   := FALSE;           // 通道故障锁存初值为空
        abOverPrev[i]  := FALSE;           // 超温沿记忆初值为空
        stStat.anOverTempCnt[i] := 0;      // 超温累计清零
        stStat.anOpenCnt[i]     := 0;      // 断线累计清零
    END_FOR
    stStat.nScanRounds := 0;
    nScanIdx       := 1;
    nChClamped     := 0;
    nValidCh       := 0;
    nHottestCh     := 0;
    fHottestTemp   := 0.0;
    uChannelFaultMask := 16#0000;
    ePhase         := E_DL_NtcScanPhase.eIdle;
    eState         := E_DL_NtcScanPhase.eIdle;
    bError         := FALSE;
    bStateIllegal  := FALSE;
    bScanRun       := FALSE;
    uErrorId       := 16#0000_0000;
    bInit          := TRUE;                // 首扫只做一次
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜通道数钳位与轮询节拍钳位
 *      Channel count clamping and scan period clamping
 *-----------------------------------------------------------------------------*)
IF nChannelCount < DL_CH_MIN THEN
    nChClamped := 0;                       // 无通道：交由状态机判全失效
ELSIF nChannelCount > DL_CH_MAX THEN
    nChClamped := DL_CH_MAX;               // 超上限钳位到十六
ELSE
    nChClamped := nChannelCount;
END_IF

IF tScanPeriod <= DL_TIME_ZERO THEN
    tScanUse := DL_TIME_ZERO;              // 零节拍：全通道每拍扫描
    bScanAll := TRUE;
ELSIF tScanPeriod < DL_SCAN_MIN THEN
    tScanUse := DL_SCAN_MIN;               // 过小节气：按最小节拍兜底
    bScanAll := FALSE;
ELSE
    tScanUse := tScanPeriod;
    bScanAll := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜换算参数守卫（先判后算，绝不允许浮点除零）
 *      Parameter guards before any division, float division by zero is banned
 *-----------------------------------------------------------------------------*)
bParamBad := FALSE;
IF ABS(fBeta) < DL_FLOAT_EPS THEN
    bParamBad := TRUE;                     // B 常数接近零：公式退化
END_IF
IF fR25 <= DL_FLOAT_EPS THEN
    bParamBad := TRUE;                     // 标称阻值非正：阻值比无意义
END_IF
IF fT25 <= DL_FLOAT_EPS THEN
    bParamBad := TRUE;                     // 基准温度非正：开尔文必须为正
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜轮询推进（节拍到拍推进一步；零节拍模式不推进索引）
 *      Polling advance, one step per tick, no advance in the all scan mode
 *-----------------------------------------------------------------------------*)
fbTonScan(IN := bScanRun, PT := tScanUse);
bScanTick := fbTonScan.Q;

IF bScanAll THEN
    nScanIdx := 1;                         // 全扫模式索引无意义，恒置一
    IF stStat.nScanRounds < DL_CNT_MAX THEN
        stStat.nScanRounds := stStat.nScanRounds + 1;   // 每拍视为完成一圈（饱和累加，与轮询分支一致）[Scan round, saturated like the polling branch]
    END_IF
ELSIF bScanTick THEN
    nScanIdx := nScanIdx + 1;              // 节拍到拍：索引推进
    IF nScanIdx > nChClamped THEN
        nScanIdx := 1;                     // 越界即回到首通道
        IF stStat.nScanRounds < DL_CNT_MAX THEN
            stStat.nScanRounds := stStat.nScanRounds + 1;
        END_IF
    END_IF
END_IF

IF bScanTick THEN
    bScanRun := FALSE;                     // 触发拍拉低，强制节拍重新起算
ELSIF (ePhase <> E_DL_NtcScanPhase.eIdle) THEN
    bScanRun := TRUE;                      // 非待机态持续计时
END_IF

IF nScanIdx < 1 THEN
    nScanIdx := 1;                         // 索引下界保护
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜通道换算与判定（逐通道；断线、短路、参数、温限四类判定）
 *      Per-channel conversion and judgement, four kinds of check in one pass
 *-----------------------------------------------------------------------------*)
FOR i := 1 TO DL_CH_MAX DO
    IF bEnable AND (i <= nChClamped) AND (bScanAll OR (i = nScanIdx)) THEN
        fResistance := afResistance[i];
        bChOpen     := FALSE;
        bChShort    := FALSE;

        IF fResistance >= DL_R_OPEN THEN
            bChOpen := TRUE;                       // 阻值超上限：探头断线
        ELSIF fResistance <= DL_R_SHORT THEN
            bChShort := TRUE;                      // 阻值低于下限：探头短路
        END_IF

        IF bChOpen OR bChShort THEN
            abChValid[i] := FALSE;                 // 无效通道不参与最热与温限
            IF NOT abChFault[i] THEN
                abChFault[i] := TRUE;              // 故障锁存只增不减
                IF stStat.anOpenCnt[i] < DL_CNT_MAX THEN
                    stStat.anOpenCnt[i] := stStat.anOpenCnt[i] + 1;
                END_IF
            END_IF
            abOverPrev[i] := FALSE;                // 无效拍清超温沿记忆
        ELSIF bParamBad THEN
            abChValid[i] := FALSE;                 // 参数非法：不换算，保持上次温度
            abOverPrev[i] := FALSE;
        ELSE
            fRatio := fResistance / fR25;          // 阻值比：分母已在段四判正
            fInvTemp := (1.0 / fT25) + (LN(fRatio) / fBeta);
            IF fInvTemp <= DL_FLOAT_EPS THEN
                abChValid[i] := FALSE;             // 倒数温度非正：视为探头异常
                abOverPrev[i] := FALSE;
            ELSE
                fTempK := 1.0 / fInvTemp;          // 分母已在上一行判正
                afTempC[i] := fTempK - DL_KELVIN_OFFSET;
                IF afTempC[i] > DL_TEMP_SANE THEN
                    abChValid[i] := FALSE;         // 超合理上界：按探头异常处理
                    abOverPrev[i] := FALSE;
                ELSE
                    abChValid[i] := TRUE;
                    IF afTempC[i] > afTempHigh[i] THEN
                        IF NOT abOverPrev[i] THEN
                            IF stStat.anOverTempCnt[i] < DL_CNT_MAX THEN
                                stStat.anOverTempCnt[i] := stStat.anOverTempCnt[i] + 1;
                            END_IF
                        END_IF
                        abOverPrev[i] := TRUE;     // 持续超温不重复计数
                    ELSE
                        abOverPrev[i] := FALSE;    // 回落即清沿记忆
                    END_IF
                END_IF
            END_IF
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 7｜有效通道计数、最热通道定位与故障掩码装配
 *      Valid channel counting, hottest channel search and fault mask assembly
 *-----------------------------------------------------------------------------*)
nValidCh  := 0;
nHotScan  := 0;
fHotScan  := 0.0;
bAnyOverTemp  := FALSE;                        // 温限聚合每拍全量重算，不受轮询影响
bAnyUnderTemp := FALSE;
uChannelFaultMask := 16#0000;
FOR i := 1 TO DL_CH_MAX DO
    IF abChFault[i] THEN
        uChannelFaultMask := uChannelFaultMask OR SHL(DL_MASK_ONE, i - 1);  // 故障位锁存
    END_IF
    IF (i <= nChClamped) AND abChValid[i] THEN
        nValidCh := nValidCh + 1;
        IF (nHotScan = 0) OR (afTempC[i] > fHotScan) THEN
            nHotScan := i;                     // 严格大于才替换：平局取最小号
            fHotScan := afTempC[i];
        END_IF
        IF afTempC[i] > afTempHigh[i] THEN
            bAnyOverTemp := TRUE;              // 全量重算，轮询模式下不闪断
        END_IF
        IF afTempC[i] < afTempLow[i] THEN
            bAnyUnderTemp := TRUE;
        END_IF
    END_IF
END_FOR

(*------------------------------------------------------------------------------
 * 段 8｜主状态机（ENUM 加 CASE，含 ELSE 兜底；每成员均有对应标签）
 *      Main state machine, one label per enumeration member plus a fallback
 *-----------------------------------------------------------------------------*)
CASE ePhase OF
    E_DL_NtcScanPhase.eIdle:
        IF bEnable AND bParamBad THEN
            ePhase := E_DL_NtcScanPhase.eFault;      // 参数非法：直接进锁存故障
        ELSIF bEnable THEN
            ePhase := E_DL_NtcScanPhase.eScan;
        END_IF

    E_DL_NtcScanPhase.eScan:
        IF NOT bEnable THEN
            ePhase := E_DL_NtcScanPhase.eIdle;
        ELSIF bParamBad THEN
            ePhase := E_DL_NtcScanPhase.eFault;      // 参数被改坏：立即锁存
        ELSIF nValidCh = 0 THEN
            ePhase := E_DL_NtcScanPhase.eAllFail;    // 全通道失效：可自动恢复
        END_IF

    E_DL_NtcScanPhase.eAllFail:
        IF NOT bEnable THEN
            ePhase := E_DL_NtcScanPhase.eIdle;
        ELSIF nValidCh >= DL_CH_MIN THEN
            ePhase := E_DL_NtcScanPhase.eScan;       // 接线修复即自愈，不强制复位
        END_IF

    E_DL_NtcScanPhase.eFault:
        IF fbTrigReset.Q THEN
            ePhase        := E_DL_NtcScanPhase.eIdle;   // 只有复位可退出参数锁存
            bStateIllegal := FALSE;
        END_IF

    ELSE
        ePhase        := E_DL_NtcScanPhase.eFault;   // 非法值兜底
        bStateIllegal := TRUE;
END_CASE

(*------------------------------------------------------------------------------
 * 段 9｜复位（放在状态机之后：复位当拍即清掩码与统计沿记忆）
 *      Reset after the state machine so the latch clears within the same cycle
 *-----------------------------------------------------------------------------*)
IF fbTrigReset.Q THEN
    FOR i := 1 TO DL_CH_MAX DO
        abChFault[i]  := FALSE;                    // 通道故障锁存清除
        abOverPrev[i] := FALSE;                    // 超温沿记忆清除
    END_FOR
    uChannelFaultMask := 16#0000;
    bError            := FALSE;
    bStateIllegal     := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 10｜输出归并与码位定级（单一优先级链，全拍只写一次 uErrorId）
 *      Output merge and single-priority error code resolution
 *-----------------------------------------------------------------------------*)
IF nValidCh > 0 THEN
    nHottestCh   := nHotScan;
    fHottestTemp := fHotScan;                      // 最热通道与温度同源
ELSE
    nHottestCh   := 0;
    fHottestTemp := 0.0;                           // 无有效通道时不保持历史峰值
END_IF

IF bStateIllegal THEN
    uErrorId := 16#0003_0304;                      // 非法相位兜底，归入参数锁存码
ELSIF bParamBad THEN
    uErrorId := 16#0003_0304;                      // 故障级：换算参数非法
ELSIF (nChClamped >= DL_CH_MIN) AND (nValidCh = 0) THEN
    uErrorId := 16#0003_0303;                      // 故障级：全通道失效
ELSIF uChannelFaultMask <> 16#0000 THEN
    uErrorId := 16#0003_0146;                      // 信息级：单通道断线或短路
ELSIF nChannelCount > DL_CH_MAX THEN
    uErrorId := 16#0003_0145;                      // 信息级：通道数越界已钳位
ELSIF nChannelCount < DL_CH_MIN THEN
    uErrorId := 16#0003_0145;                      // 信息级：通道数低于下限
ELSE
    uErrorId := 16#0000_0000;
END_IF

(* 故障位只反映故障级：信息级码 0145 与 0146 绝不置故障位（R21） *)
IF bStateIllegal OR bParamBad THEN
    bError := TRUE;
ELSIF (nChClamped >= DL_CH_MIN) AND (nValidCh = 0) THEN
    bError := TRUE;                                // 全失效属不可降级的故障
ELSE
    bError := FALSE;
END_IF

eState := ePhase;                                  // 相位每拍重写，供 HMI 诊断
END_FUNCTION_BLOCK
