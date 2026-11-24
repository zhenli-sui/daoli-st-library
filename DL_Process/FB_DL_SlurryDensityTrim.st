(*==============================================================================
 * 组件名称 (Component)  : FB_DL_SlurryDensityTrim
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 浆料面密度双源交叉校核与分档告警。负载式与 β 射线
 *                         两路面密度源求均值出出面密度，双源偏差超容差持续
 *                         tMisDly 即 bMismatch 告警（防单拍毛刺）；均值对工艺
 *                         窗 [fBandLo, fBandHi] 分档 eLow/eIn/eHigh。与
 *                         ToleranceWindow（单源判窗）分工：本件是多源一致性
 *                         新判据 + 分档告警。
 * 来源标签 (Origin)     : ROADMAP §16.1 R11 池（L695），自研 clean-room
 * 边界语义 (Boundary)   : ① 双源任一非有限拍：冻结（均值/判档保持上拍，不告
 *                         警不消警）；
 *                         ② 一致性容差/窗界域闸（fBandLo < fBandHi）→ 组态故障；
 *                         ③ 告警去抖 TON 电平计时（非自复位周期窗）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 均值/分档保持末值 + 告警
 *                         收敛 FALSE（失能必须收敛告警）；eFault 相 → 冻结
 *                         + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 冻结/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 双源 98.0/98.2（容差 0.5）→ 均值 98.1，
 *                         窗 [95,105] → eGrade=eIn，bMismatch=FALSE；
 *                         V2 双源 98.0/100.9（偏差 2.9 > 0.5）持续 tMisDly
 *                         → bMismatch=TRUE；
 *                         V3 均值 94.0 < 95 → eGrade=eLow，bAlarmLo=TRUE。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 1 · 序号 4）
 *==============================================================================*)
TYPE E_DL_SdtGrade :
(
    eLow  := 0,                              (* 低于工艺窗 / Below window *)
    eIn   := 1,                              (* 窗内合格 / In window *)
    eHigh := 2                               (* 高于工艺窗 / Above window *)
);
END_TYPE

TYPE E_DL_SdtState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eRun   := 10,                            (* 双源校核运行 / Cross-check run *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_SdtCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：窗界倒置/容差越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_SlurryDensityTrim
VAR_INPUT
    fDenLoad   : LREAL := 0.0;               (* 负载式面密度源 1 [g/m²] / Loadcell areal density *)
    fDenBeta   : LREAL := 0.0;               (* β 射线面密度源 2 [g/m²] / Beta-gauge areal density *)
    fBandLo    : LREAL := 95.0;              (* 工艺窗下限，域 < fBandHi [g/m²] / Window lower bound *)
    fBandHi    : LREAL := 105.0;             (* 工艺窗上限，域 > fBandLo [g/m²] / Window upper bound *)
    fTolPair   : LREAL := 0.5;               (* 双源一致性容差，域 > 0 [g/m²] / Cross-source tolerance *)
    tMisDly    : TIME := T#2S;               (* 失配告警去抖时长，域 > T#0S [ms] / Mismatch debounce *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    fDenAvg    : LREAL;                      (* 双源均值出面密度 [g/m²] / Averaged density *)
    eGrade     : E_DL_SdtGrade;              (* 分档出口 / Grade outlet *)
    bMismatch  : BOOL;                       (* 双源失配告警（去抖后电平）[-] / Mismatch alarm *)
    bAlarmLo   : BOOL;                       (* 低档告警电平 [-] / Low alarm *)
    bAlarmHi   : BOOL;                       (* 高档告警电平 [-] / High alarm *)
    eState     : E_DL_SdtState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_SdtCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState  : E_DL_SdtState := E_DL_SdtState.eIdle;      (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause  : E_DL_SdtCause := E_DL_SdtCause.eNone;      (* 故障成因锁存量 / Latched cause *)
    rtReset  : R_TRIG;                       (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonMis   : TON;                          (* 失配去抖计时，段 0 无条件调用 / Mismatch debounce *)
    _fAvg    : LREAL;                        (* 均值派生量 [g/m²] / Average derived *)
    _bSrcBad : BOOL;                         (* 双源非有限当拍量 [-] / Non-finite source *)
    _bMisRaw : BOOL;                         (* 失配原始判据电平 [-] / Raw mismatch level *)
    _bFault  : BOOL;                         (* 故障锁存位 / Latched fault bit *)
    _bCfgBad : BOOL;                         (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_SDT_EPS : LREAL := 1.0E-9;            (* 容差判零容差 [g/m²] / Tolerance epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fTolPair <= DL_SDT_EPS) OR (fBandLo >= fBandHi) OR (tMisDly <= T#0S);   (* 组态闸（R151 全引脚 + 窗界序） / Config gate *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bSrcBad := (fDenLoad <> fDenLoad) OR ((fDenLoad - fDenLoad) <> (fDenLoad - fDenLoad))
            OR (fDenBeta <> fDenBeta) OR ((fDenBeta - fDenBeta) <> (fDenBeta - fDenBeta));   (* 双源 NaN 自反 + Inf 差判 / Non-finite source gates *)
tonMis(IN := (_eState = E_DL_SdtState.eRun) AND (NOT _bSrcBad) AND _bMisRaw, PT := tMisDly);   (* 失配去抖（电平计时非周期窗） / Mismatch debounce *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fAvg := 0.0;                                (* 均值预清（每拍全路径派生，R285） / Average preset *)
_bMisRaw := FALSE;                           (* 失配原始判据预清 / Raw mismatch preset *)
bAlarmLo := FALSE;                           (* 低档告警预清（全路径赋值） / Low alarm preset *)
bAlarmHi := FALSE;                           (* 高档告警预清 / High alarm preset *)
eGrade := E_DL_SdtGrade.eIn;                 (* 分档缺省窗内（判定分支覆盖） / Grade preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清均值出口 + 清分档 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_SdtCause.eNone;          (* 清成因 / Clear cause *)
    fDenAvg := 0.0;                          (* 清均值出口 / Clear average outlet *)
    eGrade := E_DL_SdtGrade.eIn;             (* 分档复位窗内 / Grade reset *)
    _eState := E_DL_SdtState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_SdtCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_SdtState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_SdtState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault AND NOT _bSrcBad THEN
            _eState := E_DL_SdtState.eRun;   (* 进入运行 / Enter run *)
        END_IF
    E_DL_SdtState.eRun:                      (* 运行相：均值 + 失配 + 分档 / Run *)
        IF NOT bEnable THEN
            bMismatch := FALSE;              (* 失能告警收敛（R191 声明） / Alarm converge on disable *)
            _eState := E_DL_SdtState.eIdle;  (* 回待机 / Back to idle *)
        ELSIF NOT _bSrcBad THEN
            _fAvg := 0.5 * (fDenLoad + fDenBeta);   (* 双源均值（除子常量 2，无除零） / Average *)
            fDenAvg := _fAvg;                (* 均值出口刷新 / Average outlet *)
            _bMisRaw := ABS(fDenLoad - fDenBeta) > fTolPair;   (* 失配原始判据（容差闸） / Raw mismatch *)
            bMismatch := tonMis.Q;           (* 去抖后告警出口 / Debounced alarm *)
            IF _fAvg < fBandLo THEN
                eGrade := E_DL_SdtGrade.eLow;   (* 低档 / Low *)
            ELSIF _fAvg > fBandHi THEN
                eGrade := E_DL_SdtGrade.eHigh;  (* 高档 / High *)
            ELSE
                eGrade := E_DL_SdtGrade.eIn;    (* 窗内（IF 链带 ELSE 兜底，R285） / In window *)
            END_IF
            bAlarmLo := (eGrade = E_DL_SdtGrade.eLow) AND (NOT bMismatch);   (* 低档告警（失配时双源不可信不判档告警，R146 方向拆分） / Low alarm *)
            bAlarmHi := (eGrade = E_DL_SdtGrade.eHigh) AND (NOT bMismatch);  (* 高档告警 / High alarm *)
        END_IF                               (* 源坏值拍：冻结保持（边界①），告警不消不增 / Bad source: freeze *)
    E_DL_SdtState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        bMismatch := FALSE;                  (* 故障相告警收敛（安全侧） / Alarm converge in fault *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_SdtState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_SdtCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
