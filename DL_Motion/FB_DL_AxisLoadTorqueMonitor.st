(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisLoadTorqueMonitor
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（PLCopen 安全层深化）
 * 所属子库 (Sublibrary) : DL_Motion / LoadMonitor
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），仅用标准库 TON
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 轴负载扭矩 RMS 滑窗监视
 * 功能一句话 (Summary)  : 扭矩滑窗 RMS + 峰值 + 堵转/过载预警分级，不触轴状态。
 * 边界与安全 (Boundary) : ①采样绝对值大于 200% 拒收并置采样非法码；
 *                         ②NaN/Inf 采样拒收（自反双判）；
 *                         ③bEnable 下降沿清全部统计（重新起窗）；
 *                         ④RMS 双代滑窗（旧半窗+新半窗近似整窗）；
 *                         ⑤警告/跳闸分级各自独立锁存判定；
 *                         ⑥本件只监视，不向轴控制器发送任何指令。
 * 错误码    : 16#0004_0312 警告级超限确认（RMS 大于警告限）——故障级（持续态）
 *             16#0004_0313 跳闸级超限确认（RMS 大于跳闸限）——故障级（持续态）
 *             16#0004_0314 采样值非法（超 200% 或非有限）——故障级（持续态）
 * 码位总账  : 16#0004_0312 用 / 16#0004_0313 用 / 16#0004_0314 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_AxisLoadTorqueMonitor
VAR_INPUT
    fTorqueFb  : LREAL; // 扭矩反馈 [% 额定] / Torque feedback [% of rated]
    fWarnLimit : LREAL; // 警告限 [%] / Warning limit [%]
    fTripLimit : LREAL; // 跳闸限 [%] / Trip limit [%]
    tWindow    : TIME;  // RMS 滑窗时长 [ms] / RMS sliding window [ms]
    bEnable    : BOOL;  // 监视使能 / Monitoring enable
END_VAR
VAR_OUTPUT
    fTorqueRms  : LREAL; // 扭矩滑窗均方根 [%] / Torque RMS over window [%]
    fTorquePeak : LREAL; // 窗内峰值 [%]（窗轮转时清）/ Peak within window [%]
    bWarn       : BOOL;  // 警告级超限 / Warning level exceeded
    bTrip       : BOOL;  // 跳闸级超限 / Trip level exceeded
    eErr        : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR CONSTANT
    cHalves   : DINT  := 10;    // 窗内半代数（轮转近似滑窗）/ Window generations
    cAbsLimit : LREAL := 200.0; // 采样绝对值上限 [%] / Absolute sample limit [%]
END_VAR
VAR
    fSqOld  : LREAL; // 旧代平方和累积 / Previous generation sum of squares
    fSqNew  : LREAL; // 新代平方和累积 / Current generation sum of squares
    uCntOld : UDINT; // 旧代样本数 / Previous generation sample count
    uCntNew : UDINT; // 新代样本数 / Current generation sample count
    iGen    : INT;   // 当前代序号 / Current generation index
    tonGen  : TON;   // 代轮转定时器（无条件刷新）/ Generation rotation timer
    dwGenMs : DINT;  // 单代时长 [ms] / Generation duration [ms]
    fAbs    : LREAL; // 采样绝对值临时量 / Sample absolute temp
    fMeanSq : LREAL; // 平均平方临时量 / Mean-square temp
END_VAR

// ---------- 代时长：窗 / 半代数（除零与下限防御） ----------
dwGenMs := TIME_TO_DINT(tWindow) / cHalves;
IF dwGenMs < 1 THEN
    dwGenMs := 1;                             // 最小 1 ms 代 / Minimum 1 ms generation
END_IF
tonGen(IN := bEnable, PT := DINT_TO_TIME(dwGenMs));

// ---------- 使能下降沿清统计（重新起窗） ----------
IF NOT bEnable THEN
    fSqOld := 0.0;  fSqNew := 0.0;
    uCntOld := 0;   uCntNew := 0;
    iGen := 0;
    fTorqueRms := 0.0;
    fTorquePeak := 0.0;
    bWarn := FALSE;
    bTrip := FALSE;
    eErr := 0;
END_IF

// ---------- 采样防御：非有限或超 200% 拒收 ----------
eErr := 0;
fAbs := fTorqueFb;
IF fAbs < 0.0 THEN
    fAbs := -fAbs;                            // 手工绝对值 / Manual absolute
END_IF
IF (fTorqueFb <> fTorqueFb) OR ((fTorqueFb - fTorqueFb) <> (fTorqueFb - fTorqueFb))
   OR (fAbs > cAbsLimit) THEN
    eErr := 16#0004_0314;                     // 采样非法码 / Illegal sample code
ELSE
    // ---------- 合法采样入新代累积 ----------
    fSqNew := fSqNew + fTorqueFb * fTorqueFb; // 平方累积 / Square accumulation
    uCntNew := uCntNew + UDINT#1;             // 计数累积 / Count accumulation
    IF fAbs > fTorquePeak THEN
        fTorquePeak := fAbs;                  // 峰值更新 / Peak update
    END_IF
END_IF

// ---------- 代轮转：旧代平移，新代清零，峰值随轮转衰减 ----------
IF tonGen.Q THEN
    iGen := iGen + 1;                         // 代序推进 / Generation advance
    IF iGen >= cHalves THEN
        iGen := cHalves / 2;                  // 折半轮转维持双代近似 / Halved rotation
        fSqOld := fSqNew;  uCntOld := uCntNew; // 新代平移为旧代 / Current becomes previous
        fSqNew := 0.0;     uCntNew := 0;      // 新代清零 / Current cleared
        fTorquePeak := fTorquePeak * 0.5;     // 峰值随轮转衰减 / Peak decayed on rotation
    END_IF
END_IF

// ---------- RMS 计算：双代平方和 / 双代样本数（分母前判零） ----------
IF (uCntOld + uCntNew) > UDINT#0 THEN
    fMeanSq := (fSqOld + fSqNew) / UDINT_TO_LREAL(uCntOld + uCntNew); // 平均平方 / Mean square
    IF fMeanSq >= 0.0 THEN
        fTorqueRms := SQRT(fMeanSq);          // 均方根 / Root mean square
    ELSE
        fTorqueRms := 0.0;                    // 负数防御（理论不可达）/ Defensive
    END_IF
ELSE
    fTorqueRms := 0.0;                        // 无样本缺省 / No-sample default
END_IF

// ---------- 分级判定（跳闸优先级高于警告） ----------
IF fTorqueRms > fTripLimit THEN
    bTrip := TRUE;                            // 跳闸级 / Trip level
    bWarn := TRUE;
    eErr  := 16#0004_0313;                    // 跳闸级码 / Trip code
ELSIF fTorqueRms > fWarnLimit THEN
    bWarn := TRUE;                            // 警告级 / Warning level
    bTrip := FALSE;
    eErr  := 16#0004_0312;                    // 警告级码 / Warning code
ELSE
    bWarn := FALSE;                           // 带内双清 / In-band both cleared
    bTrip := FALSE;
END_IF

END_FUNCTION_BLOCK
