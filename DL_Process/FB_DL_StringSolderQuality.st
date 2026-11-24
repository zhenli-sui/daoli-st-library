(*
  FB_DL_StringSolderQuality  —  串焊焊接质量在线判据 / String soldering quality online criteria
  分类 Category : DL_Process
  码位 Code     : 16#06_0_B4
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-technology — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : clean-room 实现，光伏串焊温度曲线公开工艺语义借鉴，未复制任何源码行（RESUME 承接 R36 §4 #19 规格）
                  （统计出口语义对齐 FB_DL_SignalStatistics；告警出口对齐 FB_DL_AlarmManager，均不实例化）
  功能 Function : 1) 逐通道三判据：峰值窗（fPeakMinC..fPeakMaxC）、升温斜率窗、保温时长窗，越窗记 abPeakViolate/abSlopeViolate
                     （保温越窗并入 abPeakViolate 位段，头注释声明）并聚合 nNgChannelMask（SHL 显式位号）；
                  2) 拉力抽检仅对抽中通道（abPullSampled）生效，抽检不合格整批 bLotReject；
                  3) 曲线 NG 通道与抽检通道双判据独立记账，不互相掩盖。
  边界 Boundary : ① 通道数 nChannelCount = 0 或超 32 判组态错返回；
                  ② 位掩码只在 nChannelCount <= 32 时生成（超 32 判组态错，禁静默截断，规格强制）；
                  ③ fSlopeMaxCs <= fSlopeMinCs / fPeakMaxC <= fPeakMinC 判组态错；
                  ④ 信号非有限（NaN 用 x<>x 自反）通道按 NG 记（安全侧）并置信息码；
                  ⑤ 整数位段赋值用 SHL 显式位号，禁魔法掩码（规格强制）；
                  ⑥ 本件无状态机 ENUM/CASE（批量判据件），判据每调用重算，无锁存码。
  依赖 Depends  : 仅 Standard.library（SHL/AND_MASK）；语义对齐 FB_DL_SignalStatistics / FB_DL_AlarmManager（已注册，不实例化）
  码表 Error codes（本件格 06_0_B4，子码步进 +0x100）:
    16#0006_01B4 信息级：拉力抽检不合格，整批判废
    16#0006_02B4 故障级：组态非法（通道数越域 / 峰值窗倒置 / 斜率窗倒置 / 时长窗倒置）
    16#0006_03B4 信息级：存在曲线越窗通道（nNgChannelMask <> 0）
    16#0006_04B4 信息级：存在非有限信号通道，按 NG 记（安全侧）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

FUNCTION_BLOCK FB_DL_StringSolderQuality
VAR_INPUT
    afPeakC       : ARRAY[0..31] OF REAL;   // 各通道峰值温度 [°C] / Per-channel peak temperature
    afSlopeCs     : ARRAY[0..31] OF REAL;   // 各通道升温斜率 [°C/s] / Per-channel ramp slope
    afHoldMs      : ARRAY[0..31] OF REAL;   // 各通道保温时长 [ms] / Per-channel hold duration
    abPullSampled : ARRAY[0..31] OF BOOL;   // 拉力抽中通道表 / Pull-test sampled channels
    afPullN       : ARRAY[0..31] OF REAL;   // 抽检拉力值 [N] / Pull test force
    nChannelCount : INT;                    // 有效通道数 [路]，域 1..32 / Valid channel count
    fPeakMinC     : REAL := 220.0;          // 峰值窗下限 [°C] / Peak window floor
    fPeakMaxC     : REAL := 260.0;          // 峰值窗上限 [°C] / Peak window ceiling
    fSlopeMinCs   : REAL := 2.0;            // 斜率窗下限 [°C/s] / Slope window floor
    fSlopeMaxCs   : REAL := 10.0;           // 斜率窗上限 [°C/s] / Slope window ceiling
    fHoldMinMs    : REAL := 800.0;          // 保温时长窗下限 [ms] / Hold window floor
    fHoldMaxMs    : REAL := 3000.0;         // 保温时长窗上限 [ms] / Hold window ceiling
    fPullMinN     : REAL := 1.5;            // 拉力抽检下限 [N] / Pull test force floor
END_VAR
VAR_OUTPUT
    abChannelOk    : ARRAY[0..31] OF BOOL;  // 逐通道合格 / Per-channel verdict
    abPeakViolate  : ARRAY[0..31] OF BOOL;  // 逐通道峰值越窗（含保温越窗并入位段）/ Per-channel peak violation
    abSlopeViolate : ARRAY[0..31] OF BOOL;  // 逐通道斜率越窗 / Per-channel slope violation
    nNgChannelMask : DWORD;                 // NG 通道位掩码（<= 32 路才生成）/ NG channel bit mask
    bLotReject     : BOOL;                  // 整批判废 / Lot reject verdict
    nErrId         : UDINT;                 // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    _nK        : INT;                       // 通道循环计数 / Channel loop counter
    _bFin      : BOOL;                      // 非有限筛查标志 / Non-finite screening flag
    _bPullFail : BOOL;                      // 拉力抽检失败聚合（独立记账）/ Pull failure aggregate
    _bAnyNg    : BOOL;                      // 任一通道 NG 聚合 / Any channel NG aggregate
    _bCfgBad   : BOOL;                      // 组态非法聚合 / Configuration invalid aggregate
    _uInfo     : UDINT;                     // 信息码，每拍重算 / Info code
END_VAR
VAR CONSTANT
    nMaxCh : INT := 32;           // 数组上界 = 掩码位宽 [路] / Array bound = mask width
END_VAR

(* —— 段 1：单拍量预清零（判据件每调用重算，无锁存量，R187①） —— *)
_uInfo := 16#0000_0000;              // 信息码每拍重算
nNgChannelMask := 0;                 // 掩码缺省 0
bLotReject := FALSE;                 // 判废缺省 FALSE
_bPullFail := FALSE;                 // 抽检失败预清零（独立记账）
_bAnyNg := FALSE;                    // 通道 NG 预清零
_bCfgBad := FALSE;                   // 组态非法预清零
nErrId := 16#0000_0000;              // 事件码缺省无事件
FOR _nK := 0 TO (nMaxCh - 1) DO
    abChannelOk[_nK] := FALSE;       // 通道结论缺省 FALSE（安全侧，段 3 单点置位）
    abPeakViolate[_nK] := FALSE;     // 峰值越窗缺省 FALSE
    abSlopeViolate[_nK] := FALSE;    // 斜率越窗缺省 FALSE
END_FOR

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (nChannelCount <= 0) OR (nChannelCount > nMaxCh) THEN
    _bCfgBad := TRUE;                // 通道数越域（超 32 禁生成掩码，规格强制）
END_IF
IF (fPeakMaxC <= fPeakMinC) OR (fSlopeMaxCs <= fSlopeMinCs)
   OR (fHoldMaxMs <= fHoldMinMs) OR (fPullMinN <= 0.0) THEN
    _bCfgBad := TRUE;                // 判据窗倒置或拉力下限非法
END_IF
IF _bCfgBad THEN
    nErrId := 16#0006_02B4;          // 故障级：组态非法
    RETURN;                          // 不进入判据（出口维持安全缺省）
END_IF

(* —— 段 3：逐通道三判据（峰值窗 / 斜率窗 / 保温时长窗）+ SHL 显式位号聚合 —— *)
FOR _nK := 0 TO (nChannelCount - 1) DO
    _bFin := (afPeakC[_nK] = afPeakC[_nK]) AND (afSlopeCs[_nK] = afSlopeCs[_nK])
             AND (afHoldMs[_nK] = afHoldMs[_nK])
             AND (ABS(afPeakC[_nK]) < 1.0E6) AND (ABS(afSlopeCs[_nK]) < 1.0E6)
             AND (ABS(afHoldMs[_nK]) < 1.0E9);      // NaN 用 x<>x 自反，Inf 用幅值上限兜
    IF NOT _bFin THEN
        abChannelOk[_nK] := FALSE;      // 非有限通道按 NG 记（安全侧）
        abPeakViolate[_nK] := TRUE;     // 归入峰值越窗位段（头注释已声明）
        _uInfo := 16#0006_04B4;         // 信息级：非有限信号通道
    ELSE
        IF (afPeakC[_nK] < fPeakMinC) OR (afPeakC[_nK] > fPeakMaxC) THEN
            abPeakViolate[_nK] := TRUE; // 峰值越窗
        END_IF
        IF (afSlopeCs[_nK] < fSlopeMinCs) OR (afSlopeCs[_nK] > fSlopeMaxCs) THEN
            abSlopeViolate[_nK] := TRUE;    // 斜率越窗
        END_IF
        IF (afHoldMs[_nK] < fHoldMinMs) OR (afHoldMs[_nK] > fHoldMaxMs) THEN
            abPeakViolate[_nK] := TRUE;     // 保温时长越窗并入峰值位段（规格三判据聚合声明）
        END_IF
        abChannelOk[_nK] := (NOT abPeakViolate[_nK]) AND (NOT abSlopeViolate[_nK]);   // 通道结论
    END_IF
    IF NOT abChannelOk[_nK] THEN
        nNgChannelMask := nNgChannelMask OR SHL(DWORD(1), UINT(_nK));   // SHL 显式位号（禁魔法掩码）
        _bAnyNg := TRUE;                // 通道 NG 聚合（独立记账）
    END_IF
END_FOR
IF _bAnyNg THEN
    _uInfo := 16#0006_03B4;             // 信息级：存在曲线越窗通道
END_IF

(* —— 段 4：拉力抽检（仅抽中通道生效，独立记账不互相掩盖） —— *)
FOR _nK := 0 TO (nChannelCount - 1) DO
    IF abPullSampled[_nK] THEN
        IF (afPullN[_nK] <> afPullN[_nK]) OR (afPullN[_nK] < fPullMinN) THEN
            _bPullFail := TRUE;         // 抽检不合格（非有限按不合格记，安全侧）
        END_IF
    END_IF
END_FOR

(* —— 段 5：出口单点映射（名实同源；双判据独立记账，禁互相掩盖） —— *)
bLotReject := _bPullFail OR _bAnyNg;    // 整批判废：抽检失败或存在 NG 通道（任一成立）
IF _bPullFail THEN
    _uInfo := 16#0006_01B4;             // 信息级：抽检不合格整批判废
END_IF
IF _uInfo <> 16#0000_0000 THEN
    nErrId := _uInfo;                   // 信息码
END_IF

END_FUNCTION_BLOCK
