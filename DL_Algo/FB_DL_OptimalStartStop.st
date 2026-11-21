(*
  ==================================================================
  组件名 Component  : FB_DL_OptimalStartStop
  分类   Category   : DL_Algo
  复杂度 Complexity  : cx5
  版本   Version    : 1.0.0
  功能   Purpose    : 最优启停预调度。按建筑热惯性差值提前启动：占用前依据
                      室内外温差与设定差预测恢复时长（_learned 系数在线修正
                      ——上一恢复周期实测对预测的比值按学习增益钳位推进），
                      依预测提前量给出预启动建议；占用期给出预停止建议。
                      与 EnergySavingMode 空闲节能分工互引。
  来源   Source     : t1-oscat-building（HVAC optimal start 公开语义）
  溯源   Origin     : IEC 61131-3 标准语义的道莅防御性实现；optimal start
                      预测恢复为公开暖通空调节能语义，clean-room 自研实现，
                      未复制 OSCAT 或任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（Standard.library: R_TRIG，无私有库）
  分工声明 Split     : 与 FB_DL_NightPurgeSeq 分工——后者利用夜间冷量做无源
                      预冷顺控，本件为有源 HVAC 启停时刻预测调度；与存量
                      EnergySavingMode 分工——后者做占用空闲期设备降级节能，
                      本件只做启停时刻预测建议，不执行任何设备命令。
  作者   Author     : 道莅代码库 · PLC 编程专家（R58）
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 代理量三句声明（R95）：fScanPeriodMin 为每次调用的
                         代表时长（代理值）；覆盖任务周期 0.1..10 分钟的调
                         用节拍；覆盖不到的区间（调用节拍外事件）由调用方
                         的占用信号沿精度兜尾；
                      二 学习系数域 [0.5..2.0]（无量纲比），越域钳定（两级
                         回退 FB32-3：先回默认 1.0，再按域钳定），学习仅在
                         bLearnEn 且恢复周期完整（启动建议发出 → 占用沿到
                         达）时推进；
                      三 预启动建议判据：占用前且预测恢复时长 ≥ 实际提前
                         余量（由剩余时间折算）——本件不接实时时钟，余量由
                         调用方经 fLeadTimeMin 传入 [分钟]；
                      四 三温度引脚（室内 / 室外 / 设定）非有限即冻结建议
                         输出为 FALSE 并置域闸故障锁存（解除 = bReset 沿）；
                      五 无全局变量、无外部变量声明、无物理地址寻址。
  修订记录 Revision  :
    2026-11-21  v1.0.0  R58 首版（批 3 · 序号 9）
  ==================================================================
*)

FUNCTION_BLOCK FB_DL_OptimalStartStop
VAR_INPUT
    bEnable       : BOOL := TRUE;   // 使能，失能建议输出安全侧 FALSE [-] / enable, disabling clears the advice
    bReset        : BOOL := FALSE;  // 复位上升沿清故障锁存与学习累计 [-] / reset rising edge clears the latch and the learning
    bOccupied     : BOOL := FALSE;  // 占用信号电平 [-] / the occupancy level
    bLearnEn      : BOOL := TRUE;   // 学习使能 [-] / the learning enable
    fTinC         : LREAL := 20.0;  // 室内温度实测 [摄氏度] / the indoor temperature [degree celsius]
    fToutC        : LREAL := 5.0;   // 室外温度实测 [摄氏度] / the outdoor temperature [degree celsius]
    fTsetC        : LREAL := 22.0;  // 占用期设定温度 [摄氏度] / the occupied setpoint [degree celsius]
    fLeadTimeMin  : LREAL := 30.0;  // 调用方传入的提前余量 [分钟] / the lead time margin fed by the caller [minute]
    fScanPeriodMin: LREAL := 1.0;   // 每次调用的代表时长 [分钟]（代理量，边界一）/ the representative duration per call [minute]
    fOptCoef      : LREAL := 4.0;   // 基础恢复系数 [分钟每开尔文每开尔文温差] / the base recovery coefficient [minute per kelvin per kelvin]
    fLearnGain    : LREAL := 0.2;   // 学习增益 [无量纲]，域 0..0.5 / the learning gain, zero through point five
END_VAR
VAR_OUTPUT
    bPreStartAdvise  : BOOL := FALSE; // 预启动建议出口 [-] / the pre start advice outlet
    bPreStopAdvise   : BOOL := FALSE; // 预停止建议出口 [-] / the pre stop advice outlet
    fPredRecoveryMin : LREAL := 0.0;  // 预测恢复时长出口 [分钟] / the predicted recovery duration outlet [minute]
    fLearnedK        : LREAL := 1.0;  // 在线学习系数出口 [无量纲] / the learned coefficient outlet, dimensionless
    bError           : BOOL := FALSE; // 域闸故障锁存标志 [-] / the domain gate fault latch flag
END_VAR
VAR
    rtOccUp  : R_TRIG; // 占用上升沿检测，段 0 无条件刷新 / the occupancy rising edge
    rtReset  : R_TRIG; // 复位沿检测，段 0 无条件刷新 / the reset edge
    _bInit   : BOOL := FALSE; // 首扫初始化完成标志（R310）/ the first scan flag
    _bLatch  : BOOL := FALSE; // 域闸故障锁存位 [-] / the domain gate latch bit
    _bRecRun : BOOL := FALSE; // 恢复期计时进行中（建议发出 → 占用沿）/ the recovery timing active
    _fRecAcc : LREAL := 0.0;  // 恢复期实测累计时长 [分钟] / the measured recovery duration accumulator [minute]
    _fPred   : LREAL := 0.0;  // 本恢复期预测值快照 [分钟] / the predicted value snapshot of this recovery
    _bPredOK : BOOL := FALSE; // 预测快照有效（学习推进前置）[-] / the prediction snapshot valid
END_VAR
VAR CONSTANT
    DL_OSS_KMIN : LREAL := 0.5; // 学习系数域下界 [无量纲] / the learned coefficient floor
    DL_OSS_KMAX : LREAL := 2.0; // 学习系数域上界 [无量纲] / the learned coefficient ceiling
    DL_OSS_GMAX : LREAL := 0.5; // 学习增益域上界 [无量纲] / the learning gain ceiling
END_VAR

// 段 0｜沿检测无条件周期刷新（禁入分支）/ segment 0, the unconditional refresh
rtOccUp(CLK := bOccupied); // 占用沿 / the occupancy edge
rtReset(CLK := bReset); // 复位沿 / the reset edge

// 段 1｜首扫初始化（R310）：学习系数回默认域内点 / segment 1, the first scan init
IF NOT _bInit THEN // 首扫一拍 / the first scan
    _bInit := TRUE; // 置首扫标志 / raise the flag
    fLearnedK := 1.0; // 学习系数回默认（FB32-3 一级回退值）/ the coefficient to the default
END_IF

// 段 2｜复位沿作用域：清故障锁存 / 清学习累计与恢复期快照 / 清建议出口（三项逐项声明）/ segment 2, the reset edge scope
IF rtReset.Q THEN // 复位沿 / the reset edge
    _bLatch := FALSE; // 作用域一：清域闸锁存 / scope one, clear the latch
    _fRecAcc := 0.0; // 作用域二：清恢复累计 / scope two, clear the recovery accumulator
    _fPred := 0.0; // 作用域二：清预测快照 / scope two, clear the prediction snapshot
    _bPredOK := FALSE; // 作用域二：清快照有效 / scope two, clear the snapshot valid
    _bRecRun := FALSE; // 作用域二：清恢复期计时 / scope two, clear the recovery timing
    bPreStartAdvise := FALSE; // 作用域三：清建议出口 / scope three, clear the advice
    bPreStopAdvise := FALSE; // 作用域三：清建议出口 / scope three, clear the advice
END_IF

// 段 3｜输入域闸（R151 全覆盖：三温度 + 系数 + 代理周期非有限与域判定，边界四）/ segment 3, the input domain gate
IF (fTinC <> fTinC) OR ((fTinC - fTinC) <> (fTinC - fTinC)) // 室内非有限 / a non finite indoor
OR (fToutC <> fToutC) OR ((fToutC - fToutC) <> (fToutC - fToutC)) // 室外非有限 / a non finite outdoor
OR (fTsetC <> fTsetC) OR ((fTsetC - fTsetC) <> (fTsetC - fTsetC)) // 设定非有限 / a non finite setpoint
OR (fScanPeriodMin <> fScanPeriodMin) OR ((fScanPeriodMin - fScanPeriodMin) <> (fScanPeriodMin - fScanPeriodMin)) // 代理周期非有限 / a non finite period
OR (fScanPeriodMin <= 0.0) // 代理周期域（≤0 无法累计）/ the period domain
OR (fLeadTimeMin <> fLeadTimeMin) OR ((fLeadTimeMin - fLeadTimeMin) <> (fLeadTimeMin - fLeadTimeMin)) // 余量非有限 / a non finite margin
OR (fOptCoef <> fOptCoef) OR ((fOptCoef - fOptCoef) <> (fOptCoef - fOptCoef)) // 系数非有限 / a non finite coefficient
OR (fOptCoef <= 0.0) // 系数域 / the coefficient domain
THEN // 任一命中 / any hit
    IF NOT _bLatch THEN // 未锁存才置位（锁存回放 R152，解除 = bReset 沿）/ latch only while unlatched
        _bLatch := TRUE; // 置域闸锁存 / raise the latch
    END_IF
END_IF
bError := _bLatch OR (fLearnGain < 0.0) OR (fLearnGain > DL_OSS_GMAX); // 故障标志聚合（锁存项 OR 增益域项，R191 名实双出口）/ the flag aggregation

// 段 4｜预测恢复时长（热惯性差值式：设定差 × 内外差因子 × 学习系数）/ segment 4, the predicted recovery
IF (NOT _bLatch) AND bEnable THEN // 域内且使能才预测 / predict only inside the domain and enabled
    IF fTinC < fTsetC THEN // 需升温场景（采暖恢复）/ a warming scenario
        fPredRecoveryMin := fOptCoef * fLearnedK * (fTsetC - fTinC) * ((fTsetC - fToutC) / (fTinC - fToutC + 20.0)); // 差值因子式（除子恒 ≥20，已证无除零）/ the delta factor form, the divisor proven at least twenty
    ELSE // 已达标或超温：恢复时长为零 / already met, the recovery zero
        fPredRecoveryMin := 0.0; // 预测零 / the prediction zero
    END_IF
ELSE // 域闸锁存或失能：预测出口清零（安全侧）/ latched or disabled, the outlet cleared
    fPredRecoveryMin := 0.0; // 清零 / cleared
END_IF

// 段 5｜学习推进（恢复周期闭合沿：占用上升沿结算，边界二）/ segment 5, the learning settlement
IF _bRecRun THEN // 恢复期计时中 / while timing the recovery
    _fRecAcc := _fRecAcc + fScanPeriodMin; // 实测累计推进（代理量，边界一）/ advance the measured accumulator
END_IF
IF rtOccUp.Q AND _bPredOK THEN // 占用沿且预测快照有效：结算学习 / the occupation edge with a valid snapshot
    _bRecRun := FALSE; // 恢复期闭合 / close the recovery
    IF (_fPred > 0.0) AND (_fRecAcc > 0.0) AND bLearnEn AND (NOT _bLatch) THEN // 四前置才推进 / the four preconditions
        IF fLearnGain > DL_OSS_GMAX THEN // 增益越域钳定（FB32-3 二级）/ the gain clamped
            fLearnGain := DL_OSS_GMAX; // 钳到上界 / clamp to the ceiling
        END_IF
        IF fLearnGain < 0.0 THEN // 增益负值钳零 / the negative gain clamped to zero
            fLearnGain := 0.0; // 钳到零 / clamp to zero
        END_IF
        fLearnedK := fLearnedK + fLearnGain * ((_fRecAcc / _fPred) - 1.0); // 比值误差推进（除子 _fPred 已证 >0）/ advance by the ratio error
        IF fLearnedK < DL_OSS_KMIN THEN // 学习系数域钳定（边界二）/ the coefficient clamped
            fLearnedK := DL_OSS_KMIN; // 钳到下界 / clamp to the floor
        ELSIF fLearnedK > DL_OSS_KMAX THEN // 越上界 / above the ceiling
            fLearnedK := DL_OSS_KMAX; // 钳到上界 / clamp to the ceiling
        END_IF
    END_IF
    _bPredOK := FALSE; // 快照消费 / consume the snapshot
    _fRecAcc := 0.0; // 累计清零备下一周期 / clear the accumulator
END_IF

// 段 6｜建议出口（边界三：不接时钟，余量由调用方传入）/ segment 6, the advice outlets
IF (NOT _bLatch) AND bEnable AND (NOT bOccupied) THEN // 占用前建议评估 / the advice before occupancy
    IF _fPred = 0.0 THEN // 本周期尚无快照（首个占用前周期）——发建议同时落快照 / no snapshot yet, raise and snapshot
        _fPred := fPredRecoveryMin; // 落预测快照 / snapshot the prediction
        _bPredOK := fPredRecoveryMin > 0.0; // 快照有效性 / the snapshot validity
        _bRecRun := fPredRecoveryMin > 0.0; // 启动恢复期计时 / start the recovery timing
    END_IF
    bPreStartAdvise := (_fPred >= fLeadTimeMin); // 预测恢复时长 ≥ 提前余量才建议 / advise when the prediction covers the margin
ELSE // 占用期或域外：预启动建议清除 / during occupancy or outside the domain
    bPreStartAdvise := FALSE; // 建议清除 / the advice cleared
END_IF
bPreStopAdvise := (NOT _bLatch) AND bEnable AND bOccupied AND (fTinC >= fTsetC); // 占用期达标预停止建议 / the pre stop advice when met during occupancy
END_FUNCTION_BLOCK
