(*==============================================================================
  Component : FB_DL_DieCastCycleSupervise
  Category  : DL_Device
  Type      : FB
  Complexity: C4
  VERSION   : v1.0.0
  功能      : 压铸单循环监控与三级异常分级停机（黄记录 / 红判废 / 黑停机）
  开源溯源  : 道莅原创 clean-room 自研（无外部代码引用）｜License: MIT
  边界条件  : ① 压射曲线四点监控：慢速终点位置偏差（eSlowEndDev）、快射峰值速度（eFastVelLow）、
                 增压建立时间（eBuildSlow）、保压压力（eHoldLow）；四点各自独立判据与独立成因，
                 分级动作经 ApplyDefect 单点施加，禁共用枚举成员（R190）。
              ② 分级语义（写进契约）：黄 = 记录成因、本模继续；红 = 置 _bRejectMark 判废并单拍告警，
                 机械流程仍走到 eDone 才结算（废件必须被顶出取走，不得停在模内）；
                 黑 = 立即停机（超压 / 信号非有限 / 急停 / 安全门开），等 bReset 复位。
              ③ 判据限值配比约束（R100）：fSlowEndWarnMm ≤ fSlowEndTolMm、fFastVelWarnMps ≥ fFastVelMinMps、
                 fBuildWarnS ≤ fBuildMaxS、fHoldWarnMpa ≥ fHoldMinMpa；违反即组态非法（E2 黑前哨）。
              ④ 默认引脚组合自证（R114）：过程握手类（bClampClosed / bClampOpened / bEjectDone /
                 bPartTaken / bSprayDone / bRejectAck）默认 FALSE，默认组合无法推进任何相；使能类
                 （bEStopHealthy / bGuardClosed）默认 TRUE 与 bEnable 同族，断线由硬件安全回路保证。
              ⑤ 复位作用域（R311）：bReset 沿清 E2/E3 锁存 + 判废标记 + 分级 + 曲线锁存；bStop 只清 E2 与相位。
  状态机    : eIdle 待机 / eClampClose 合模 / eShotSlow 慢压射 / eShotFast 快压射 / eIntensify 增压 /
              eHold 保压 / eClampOpen 开模 / eEject 顶出 / eTakeOut 取件 / eSpray 喷涂 / eDone 结算拍 /
              eFault 停机待复位(E2) / eSafeStop 安全断能(E3)
  自检      : R1 零 GVL ｜ R2 零物理地址 ｜ R3 纯 IEC 61131-3 ｜ R4 非有限自反判 + 除法先判分母 ｜
              R6 CASE 含 ELSE ｜ R7 九 TON 两沿段 0 无条件刷新 ｜ R10 仅标准转换函数 ｜ R14 无属性件
==============================================================================*)
TYPE E_DL_DcsPhase :
(
    eIdle       := 0,   (* 待机：等启动沿 / Idle, waiting for start edge *)
    eClampClose := 10,  (* 合模：等合模到位 / Clamp closing *)
    eShotSlow   := 20,  (* 慢压射：到慢速终点 / Slow shot *)
    eShotFast   := 30,  (* 快压射：到快射终点 / Fast shot *)
    eIntensify  := 40,  (* 增压：建压到门限 / Intensification *)
    eHold       := 50,  (* 保压：保压到时 / Pressure hold *)
    eClampOpen  := 60,  (* 开模：等开模到位 / Clamp opening *)
    eEject      := 70,  (* 顶出：等顶出到位 / Ejecting *)
    eTakeOut    := 80,  (* 取件：等取件完成 / Take-out *)
    eSpray      := 90,  (* 喷涂：等喷涂完成 / Spraying *)
    eDone       := 100, (* 结算拍：模次与良率统计 / Settlement, one-scan *)
    eFault      := 120, (* 停机待复位（E2）/ Stop awaiting reset, E2 *)
    eSafeStop   := 130  (* 安全侧断能（E3）/ Safety energy cut, E3 *)
);
END_TYPE
TYPE E_DL_DcsCause :
(
    eNone       := 0,   (* 无异常 / No anomaly *)
    eSlowEndDev := 1,   (* 慢速终点位置偏差超限（红）/ Slow-shot end position deviation *)
    eFastVelLow := 2,   (* 快射速度偏低（黄或红）/ Fast-shot velocity low *)
    eBuildSlow  := 3,   (* 增压建立时间超限（黄或红）/ Intensification build too slow *)
    eHoldLow    := 4,   (* 保压压力偏低（黄或红）/ Hold pressure low *)
    ePressOver  := 5,   (* 压力超上限（黑）/ Over-pressure, black *)
    eSigBad     := 6,   (* 压力或位置信号非有限（黑）/ Non-finite signal, black *)
    eEStopOpen  := 7,   (* 急停回路断开（黑）/ E-stop open, black *)
    eGuardOpen  := 8,   (* 安全门未闭合（黑）/ Guard door open, black *)
    eClampTmo   := 9,   (* 合模或开模超时（黑）/ Clamp timeout, black *)
    eShotTmo    := 10,  (* 压射超时（黑）/ Shot timeout, black *)
    eBuildTmo   := 11,  (* 增压超时（黑）/ Intensify timeout, black *)
    eFastTmo    := 12,  (* 快射超时（黑）/ Fast-shot timeout, black *)
    eEjectTmo   := 13,  (* 顶出超时（黑）/ Eject timeout, black *)
    eTakeTmo    := 14,  (* 取件超时（黑）/ Take-out timeout, black *)
    eSprayTmo   := 15,  (* 喷涂超时（黑）/ Spray timeout, black *)
    eCfgBad     := 16,  (* 组态非法（E2）/ Illegal configuration, E2 *)
    ePhaseBad   := 17   (* 非法相位兜底（E2）/ Illegal phase fallback, E2 *)
);
END_TYPE
TYPE E_DL_DcsGrade :
(
    eOk     := 0,       (* 无异常：本模继续 / OK, continue *)
    eYellow := 1,       (* 黄：记录并继续，不置 bError / Yellow, recorded only *)
    eRed    := 2,       (* 红：本模判废并告警 / Red, part rejected with alarm *)
    eBlack  := 3        (* 黑：立即停机 / Black, immediate stop *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_DieCastCycleSupervise
VAR_INPUT
    bStart          : BOOL := FALSE;    (* 启动沿（eIdle 入 eClampClose） [-] / Start rising edge *)
    bStop           : BOOL := FALSE;    (* 中止：回 eIdle 并清 E2 锁存 [-] / Abort, clears E2 only *)
    bReset          : BOOL := FALSE;    (* 复位沿：清全部锁存 + 曲线锁存（R311） [-] / Reset edge *)
    bRejectAck      : BOOL := FALSE;    (* 废模确认（只清告警标记，不推进相） [-] / Reject acknowledge *)
    bClampClosed    : BOOL := FALSE;    (* 合模到位（默认 FALSE 禁跳步） [-] / Clamp closed *)
    bClampOpened    : BOOL := FALSE;    (* 开模到位（默认 FALSE 禁跳步） [-] / Clamp opened *)
    bEjectDone      : BOOL := FALSE;    (* 顶出到位（默认 FALSE 禁跳步） [-] / Eject done *)
    bPartTaken      : BOOL := FALSE;    (* 取件完成（默认 FALSE 禁跳步） [-] / Part taken *)
    bSprayDone      : BOOL := FALSE;    (* 喷涂完成（默认 FALSE 禁跳步） [-] / Spray done *)
    bGuardClosed    : BOOL := TRUE;     (* 安全门闭合（使能类引脚，默认 TRUE） [-] / Guard door closed *)
    bEStopHealthy   : BOOL := TRUE;     (* 急停回路正常（使能类引脚，默认 TRUE） [-] / E-stop healthy *)
    fShotPosMm      : LREAL := 0.0;     (* 冲头实时位置（0 = 起始位） [mm] / Shot position [mm] *)
    fShotVelMps     : LREAL := 0.0;     (* 冲头实时速度 [m/s] / Shot velocity [m/s] *)
    fHoldPressMpa   : LREAL := 0.0;     (* 压射缸压力实测 [MPa] / Shot pressure [MPa] *)
    fSlowEndSetMm   : LREAL := 250.0;   (* 慢速终点设定位置，域 > 0 [mm] / Slow-end setpoint [mm] *)
    fShotEndMm      : LREAL := 320.0;   (* 快射终点位置，域 > fSlowEndSetMm [mm] / Fast-shot end [mm] *)
    fSlowEndWarnMm  : LREAL := 10.0;    (* 慢速终点偏差预警限（黄），域 >= 0 [mm] / Slow-end warn limit [mm] *)
    fSlowEndTolMm   : LREAL := 25.0;    (* 慢速终点偏差硬限（红），域 > 0 [mm] / Slow-end hard limit [mm] *)
    fFastVelMinMps  : LREAL := 2.5;     (* 快射速度硬下限（红），域 > 0 [m/s] / Fast velocity hard min [m/s] *)
    fFastVelWarnMps : LREAL := 3.0;     (* 快射速度预警下限（黄），域 > 0 [m/s] / Fast velocity warn min [m/s] *)
    fIntensifyMpa   : LREAL := 18.0;    (* 增压建立压力门限，域 > 0 [MPa] / Build threshold [MPa] *)
    fBuildWarnS     : LREAL := 0.08;    (* 增压建立时间预警限（黄），域 >= 0 [s] / Build warn limit [s] *)
    fBuildMaxS      : LREAL := 0.15;    (* 增压建立时间硬限（红），域 > 0 [s] / Build hard limit [s] *)
    fHoldMinMpa     : LREAL := 12.0;    (* 保压压力硬下限（红），域 > 0 [MPa] / Hold pressure hard min [MPa] *)
    fHoldWarnMpa    : LREAL := 14.0;    (* 保压压力预警下限（黄），域 > 0 [MPa] / Hold pressure warn min [MPa] *)
    fPressOverMpa   : LREAL := 30.0;    (* 压力超上限（黑断能），域 > 0 [MPa] / Over-pressure limit [MPa] *)
    atPhaseTmo      : ARRAY[0..8] OF TIME := [T#10S, T#5S, T#5S, T#5S, T#30S, T#10S, T#10S, T#15S, T#15S];   (* 超时窗 [ms]，下标 0..8 = 合模/慢射/快射/增压/保压/开模/顶出/取件/喷涂 / Phase windows [ms] *)
    fCycleSec       : LREAL := 0.0;     (* 扫描周期（<=0 用缺省 0.01s） [s] / Scan cycle [s] *)
END_VAR
VAR_OUTPUT
    eState          : E_DL_DcsPhase;    (* 当前相（HMI 诊断） [-] / Present phase *)
    eCause          : E_DL_DcsCause;    (* 成因（锁存回放，R189） [-] / Latched cause playback *)
    eGrade          : E_DL_DcsGrade;    (* 本模判据分级（黄/红/黑）；组态 E2 不改分级、由 bError 表达 [-] / Criterion grade, E2 config fault expressed by bError *)
    bError          : BOOL;             (* 故障标志（仅黑与 E2 置位，黄/红不置） [-] / Error flag *)
    bSafeCut        : BOOL;             (* 安全侧断能指令（黑常 TRUE 至复位） [-] / Safety energy cut *)
    bReject         : BOOL;             (* 本模判废标告警（红级置位，结算或确认后清） [-] / Reject alarm *)
    bDone           : BOOL;             (* 单拍结算脉冲 [-] / One-scan done pulse *)
    bShotActive     : BOOL;             (* 压射段指示（供 IO 层驱动压射阀） [-] / Shot indicator *)
    nShotCount      : UDINT;            (* 累计模次（饱和） [模] / Shot count, saturating *)
    nGoodCount      : UDINT;            (* 累计良品（饱和） [模] / Good part count *)
    fYieldPct       : LREAL;            (* 良率（无模次输出 0） [%] / Yield [%] *)
    fSlowEndLastMm  : LREAL;            (* 最近一模慢速终点实测 [mm] / Last slow-end position [mm] *)
    fFastVelLastMps : LREAL;            (* 最近一模快射峰值速度 [m/s] / Last peak velocity [m/s] *)
    fBuildLastS     : LREAL;            (* 最近一模增压建立时间 [s] / Last build time [s] *)
    fHoldLastMpa    : LREAL;            (* 最近一模保压压力 [MPa] / Last hold pressure [MPa] *)
END_VAR
VAR
    _ePhase      : E_DL_DcsPhase := E_DL_DcsPhase.eIdle;     (* 内部相（CASE 唯一写入目标） [-] / Internal phase *)
    _eCause      : E_DL_DcsCause := E_DL_DcsCause.eNone;     (* 成因锁存量 [-] / Latched cause *)
    _eGrade      : E_DL_DcsGrade := E_DL_DcsGrade.eOk;       (* 本模分级锁存量 [-] / Latched grade *)
    _bFault      : BOOL := FALSE;       (* E2 锁存位（解除 = bReset 沿或 bStop） [-] / E2 latch *)
    _bSafeLatch  : BOOL := FALSE;       (* E3 锁存位（解除 = bReset 沿且安全恢复） [-] / E3 latch *)
    _bFaultReq   : BOOL := FALSE;       (* 单拍 E2 请求（段 1 预清，段 6 落地） [-] / One-scan E2 request *)
    _bSafeReq    : BOOL := FALSE;       (* 单拍 E3 请求（段 1 预清，段 6 落地） [-] / One-scan E3 request *)
    _bDonePulse  : BOOL := FALSE;       (* 单拍结算标志（段 1 预清） [-] / One-scan done flag *)
    _bRejectMark : BOOL := FALSE;       (* 本模判废标记（红级置位，结算清零） [-] / Reject mark for this shot *)
    _bPressBad   : BOOL := FALSE;       (* 压力信号非有限当拍量 [-] / Pressure non-finite *)
    _bPosBad     : BOOL := FALSE;       (* 位置信号非有限当拍量 [-] / Position non-finite *)
    _bVelBad     : BOOL := FALSE;       (* 速度信号非有限当拍量 [-] / Velocity non-finite *)
    _bBuilt      : BOOL := FALSE;       (* 增压已建立（当拍判据） [-] / Intensification built *)
    _bCfgBad     : BOOL := FALSE;       (* 组态非法当拍量 [-] / Configuration bad *)
    _nIdxChk     : INT := 0;            (* 相窗遍历索引（循环变量） [-] / Loop index *)
    _fCy         : LREAL := 0.0;        (* 当拍有效周期 [s] / Effective cycle *)
    _fVelPeak    : LREAL := 0.0;        (* 快射峰值速度（入快射相清零） [m/s] / Fast-shot peak [m/s] *)
    _fBuildS     : LREAL := 0.0;        (* 增压建立时间累加（入增压相清零） [s] / Build time accumulator [s] *)
    _fSlowEndMm  : LREAL := 0.0;        (* 慢速终点位置锁存 [mm] / Slow-end position latch *)
    _fHoldMpa    : LREAL := 0.0;        (* 保压压力锁存 [MPa] / Hold pressure latch *)
    _nShot       : UDINT := 0;          (* 模次累计锁存（饱和） [模] / Shot count latch *)
    _nGood       : UDINT := 0;          (* 良品累计锁存（饱和） [模] / Good count latch *)
    tonClampClose: TON;                 (* 合模超时（段 0 无条件调用） / Clamp-close timeout *)
    tonShotSlow  : TON;                 (* 慢压射超时 / Slow-shot timeout *)
    tonShotFast  : TON;                 (* 快压射超时 / Fast-shot timeout *)
    tonIntensify : TON;                 (* 增压超时 / Intensify timeout *)
    tonHold      : TON;                 (* 保压计时与超时 / Hold timer *)
    tonClampOpen : TON;                 (* 开模超时 / Clamp-open timeout *)
    tonEject     : TON;                 (* 顶出超时 / Eject timeout *)
    tonTakeOut   : TON;                 (* 取件超时 / Take-out timeout *)
    tonSpray     : TON;                 (* 喷涂超时 / Spray timeout *)
    rtStart      : R_TRIG;              (* 启动沿（段 0 无条件调用） / Start edge *)
    rtReset      : R_TRIG;              (* 复位沿（段 0 无条件调用） / Reset edge *)
END_VAR
VAR CONSTANT
    DL_DCS_CYDEF   : LREAL := 0.01;         (* 缺省扫描周期 [s] / Default scan cycle [s] *)
    DL_DCS_CNTMAX  : UDINT := 4294967295;   (* 模次与良品计数饱和上限 [模] / Count ceiling *)
    DL_DCS_PCTOP   : LREAL := 100.0;        (* 良率百分比满量程 [%] / Yield full scale [%] *)
END_VAR

(*-----------------------------------------------------------------------------
  方法 GradeFault：单点判据分级（纯分类，不修改任何 FB 状态）
  契约：fValue 为「按变差方向已归一」的判据量（偏差取绝对值后传入）；
        bLowerWorse = TRUE 表示低于限值变差，FALSE 表示高于限值变差；
        fWarnLimit 必须落在「正常侧」，fHardLimit 落在「变差侧」（配比由组态闸保证）。
        非有限实测（NaN 自反 / Inf 差值自减）一律返回 eBlack：信号失效必须停机。
-----------------------------------------------------------------------------*)
METHOD PUBLIC GradeFault : E_DL_DcsGrade
VAR_INPUT
    fValue      : LREAL := 0.0;     (* 判据实测值（已按方向归一） [工程单位] / Measured criterion *)
    fWarnLimit  : LREAL := 0.0;     (* 预警限（黄级） [工程单位] / Warning limit *)
    fHardLimit  : LREAL := 0.0;     (* 硬限（红级） [工程单位] / Hard limit *)
    bLowerWorse : BOOL := FALSE;    (* TRUE = 低于限值变差 [-] / Lower is worse when TRUE *)
END_VAR

GradeFault := E_DL_DcsGrade.eOk;    (* 预置：无异常 / Preset OK *)
IF (fValue <> fValue) OR ((fValue - fValue) <> (fValue - fValue)) THEN
    GradeFault := E_DL_DcsGrade.eBlack;     (* 非有限 -> 黑级停机 / Non-finite, black *)
    RETURN;
END_IF
IF bLowerWorse THEN
    IF fValue < fHardLimit THEN
        GradeFault := E_DL_DcsGrade.eRed;   (* 低于硬限 -> 红 / Below hard limit *)
    ELSIF fValue < fWarnLimit THEN
        GradeFault := E_DL_DcsGrade.eYellow;(* 低于预警限 -> 黄 / Below warn limit *)
    END_IF
ELSE
    IF fValue > fHardLimit THEN
        GradeFault := E_DL_DcsGrade.eRed;   (* 高于硬限 -> 红 / Above hard limit *)
    ELSIF fValue > fWarnLimit THEN
        GradeFault := E_DL_DcsGrade.eYellow;(* 高于预警限 -> 黄 / Above warn limit *)
    END_IF
END_IF
END_METHOD

(*-----------------------------------------------------------------------------
  方法 ApplyDefect：分级动作单点施加（唯一写入 _eGrade / _bRejectMark / _bSafeReq 的位置）
  契约：eOk 不写任何量；eBlack 只请求 E3（由段 6 落地并迁相）；eRed 置判废标记与告警；
        eYellow 只在尚未升级到红/黑时记录。分级只升不降（本模内单调）。
-----------------------------------------------------------------------------*)
METHOD PRIVATE ApplyDefect
VAR_INPUT
    xGrade : E_DL_DcsGrade := E_DL_DcsGrade.eOk;    (* 分级结果 [-] / Grade result *)
    xCause : E_DL_DcsCause := E_DL_DcsCause.eNone;  (* 归因（各判据点独立传入） [-] / Cause per point *)
END_VAR

IF xGrade = E_DL_DcsGrade.eOk THEN
    RETURN;                                     (* 无异常：不写任何量 / Nothing to apply *)
END_IF
_eCause := xCause;                              (* 归因：调用点唯一指定 / Cause assigned by caller *)
IF xGrade = E_DL_DcsGrade.eBlack THEN
    _bSafeReq := TRUE;                          (* 黑级：请求 E3 断能 / Black: request E3 *)
ELSIF xGrade = E_DL_DcsGrade.eRed THEN
    IF _eGrade <> E_DL_DcsGrade.eBlack THEN
        _eGrade := E_DL_DcsGrade.eRed;          (* 红级：判废（黑级不被降级）/ Red, never downgrade black *)
    END_IF
    _bRejectMark := TRUE;                       (* 本模判废标记 / Reject mark *)
ELSIF _eGrade = E_DL_DcsGrade.eOk THEN
    _eGrade := E_DL_DcsGrade.eYellow;           (* 黄级：仅当尚未升级时记录 / Yellow only if still OK *)
END_IF
END_METHOD

(*-----------------------------------------------------------------------------
  方法 ResetCycle：本模曲线锁存与分级复位（不清累计模次与良品数）
  契约：返回 TRUE 表示复位执行；作用于分级、判废标记与四点曲线锁存；
        累计计数（_nShot / _nGood）属生产资料，只能由 bReset 沿清除，本方法不动。
-----------------------------------------------------------------------------*)
METHOD PUBLIC ResetCycle : BOOL
ResetCycle := FALSE;                            (* 预置 / Preset *)
_eGrade := E_DL_DcsGrade.eOk;                   (* 清分级 / Clear grade *)
_eCause := E_DL_DcsCause.eNone;                 (* 清成因 / Clear cause *)
_bRejectMark := FALSE;                          (* 清判废标记 / Clear reject mark *)
_fVelPeak := 0.0;                               (* 清快射峰值 / Clear peak *)
_fBuildS := 0.0;                                (* 清建立时间 / Clear build time *)
_fSlowEndMm := 0.0;                             (* 清慢速终点锁存 / Clear slow-end latch *)
_fHoldMpa := 0.0;                               (* 清保压压力锁存 / Clear hold latch *)
ResetCycle := TRUE;                             (* 复位已执行 / Reset performed *)
END_METHOD

(* —— 段 0：三测量量非有限判定 + 组态闸 + 周期派生 + 峰值与建压跟踪 + 九 TON 两沿无条件刷新（R7） —— *)
_bPressBad := (fHoldPressMpa <> fHoldPressMpa)
           OR ((fHoldPressMpa - fHoldPressMpa) <> (fHoldPressMpa - fHoldPressMpa));   (* NaN 自反 + Inf 差值 / NaN and Inf *)
_bPosBad := (fShotPosMm <> fShotPosMm)
         OR ((fShotPosMm - fShotPosMm) <> (fShotPosMm - fShotPosMm));
_bVelBad := (fShotVelMps <> fShotVelMps)
         OR ((fShotVelMps - fShotVelMps) <> (fShotVelMps - fShotVelMps));
_bCfgBad := (fSlowEndSetMm <= 0.0) OR (fShotEndMm <= fSlowEndSetMm) OR (fSlowEndTolMm <= 0.0) OR (fSlowEndWarnMm < 0.0)
         OR (fSlowEndWarnMm > fSlowEndTolMm)                       (* 限值配比① / Ratio 1 *)
         OR (fFastVelMinMps <= 0.0) OR (fFastVelWarnMps <= 0.0)
         OR (fFastVelWarnMps < fFastVelMinMps)                     (* 限值配比② / Ratio 2 *)
         OR (fIntensifyMpa <= 0.0) OR (fBuildMaxS <= 0.0) OR (fBuildWarnS < 0.0)
         OR (fBuildWarnS > fBuildMaxS)                             (* 限值配比③ / Ratio 3 *)
         OR (fHoldMinMpa <= 0.0) OR (fHoldWarnMpa <= 0.0)
         OR (fHoldWarnMpa < fHoldMinMpa)                           (* 限值配比④ / Ratio 4 *)
         OR (fPressOverMpa <= fHoldWarnMpa);                       (* 超压限须高于保压下限 / Over limit above hold *)
FOR _nIdxChk := 0 TO 8 DO
    IF atPhaseTmo[_nIdxChk] <= T#0S THEN
        _bCfgBad := TRUE;                                          (* 任一相窗非正 -> 组态非法 / Non-positive window *)
    END_IF
END_FOR
IF fCycleSec > 0.0 THEN
    _fCy := fCycleSec;                                             (* 组态周期有效 / Configured cycle *)
ELSE
    _fCy := DL_DCS_CYDEF;                                          (* 周期缺省兜底 / Default cycle *)
END_IF
_bBuilt := (_ePhase = E_DL_DcsPhase.eIntensify) AND (NOT _bPressBad) AND (fHoldPressMpa >= fIntensifyMpa);
IF (_ePhase = E_DL_DcsPhase.eIntensify) AND (NOT _bBuilt) THEN
    _fBuildS := _fBuildS + _fCy;                                   (* 增压建立时间累加 [s] / Build time accumulation *)
END_IF
IF (_ePhase = E_DL_DcsPhase.eShotFast) AND (NOT _bVelBad) THEN
    IF fShotVelMps > _fVelPeak THEN
        _fVelPeak := fShotVelMps;                                  (* 快射峰值跟踪 / Peak tracking *)
    END_IF
END_IF
rtStart(CLK := bStart);                                            (* 启动沿，每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                                            (* 复位沿，每拍必调 / Reset edge every scan *)
tonClampClose(IN := (_ePhase = E_DL_DcsPhase.eClampClose), PT := atPhaseTmo[0]);   (* 合模窗 / Clamp window *)
tonShotSlow(IN := (_ePhase = E_DL_DcsPhase.eShotSlow), PT := atPhaseTmo[1]);       (* 慢射窗 / Slow shot window *)
tonShotFast(IN := (_ePhase = E_DL_DcsPhase.eShotFast), PT := atPhaseTmo[2]);       (* 快射窗 / Fast shot window *)
tonIntensify(IN := (_ePhase = E_DL_DcsPhase.eIntensify), PT := atPhaseTmo[3]);     (* 增压窗 / Intensify window *)
tonHold(IN := (_ePhase = E_DL_DcsPhase.eHold), PT := atPhaseTmo[4]);               (* 保压窗 / Hold window *)
tonClampOpen(IN := (_ePhase = E_DL_DcsPhase.eClampOpen), PT := atPhaseTmo[5]);     (* 开模窗 / Open window *)
tonEject(IN := (_ePhase = E_DL_DcsPhase.eEject), PT := atPhaseTmo[6]);             (* 顶出窗 / Eject window *)
tonTakeOut(IN := (_ePhase = E_DL_DcsPhase.eTakeOut), PT := atPhaseTmo[7]);         (* 取件窗 / Take-out window *)
tonSpray(IN := (_ePhase = E_DL_DcsPhase.eSpray), PT := atPhaseTmo[8]);             (* 喷涂窗 / Spray window *)

(* —— 段 1：单拍量预清零（不含锁存/计数/曲线量，R107） —— *)
_bFaultReq := FALSE;                                               (* E2 请求预清 / E2 request preset *)
_bSafeReq := FALSE;                                                (* E3 请求预清 / E3 request preset *)
_bDonePulse := FALSE;                                              (* 结算标志预清 / Done preset *)
bError := FALSE;                                                   (* 故障标志预清（出口汇总）/ Error preset *)

(* —— 段 2：黑级安全侧（急停 / 安全门 / 超压 / 压力与位置信号非有限）——最高优先级 —— *)
IF (NOT bEStopHealthy) OR (NOT bGuardClosed) THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;                                         (* 落地于段 6 / Landed in segment 6 *)
        IF NOT bEStopHealthy THEN
            _eCause := E_DL_DcsCause.eEStopOpen;                   (* 归因：急停断开 / Cause: E-stop *)
        ELSE
            _eCause := E_DL_DcsCause.eGuardOpen;                   (* 归因：安全门开 / Cause: guard *)
        END_IF
    END_IF
ELSIF _bPressBad OR _bPosBad THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;
        _eCause := E_DL_DcsCause.eSigBad;                          (* 归因：信号非有限 / Cause: non-finite *)
    END_IF
ELSIF (NOT _bPressBad) AND (fHoldPressMpa > fPressOverMpa) THEN
    IF NOT _bSafeLatch THEN
        _bSafeReq := TRUE;
        _eCause := E_DL_DcsCause.ePressOver;                       (* 归因：超压 / Cause: over-pressure *)
    END_IF
END_IF

(* —— 段 3：组态闸入 E2（黑级优先，安全相内不重复置因） —— *)
IF _bCfgBad AND (NOT _bSafeLatch) AND (NOT _bFault) THEN
    _bFaultReq := TRUE;                                            (* 落地于段 6 / Landed in segment 6 *)
    _eCause := E_DL_DcsCause.eCfgBad;                              (* 归因：组态非法 / Cause: config *)
END_IF

(* —— 段 4：迁出链（复位沿 > 中止 > 废模确认；作用域逐项声明 R311） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                              (* 作用域①：清 E2 锁存 / Clear E2 *)
    IF NOT ((NOT bEStopHealthy) OR (NOT bGuardClosed) OR _bPressBad OR _bPosBad
            OR ((NOT _bPressBad) AND (fHoldPressMpa > fPressOverMpa))) THEN
        _bSafeLatch := FALSE;                                      (* 作用域②：安全恢复才清 E3 / Clear E3 only if safe *)
    END_IF
    _eCause := E_DL_DcsCause.eNone;                                (* 作用域③：清成因与分级 / Clear cause and grade *)
    _eGrade := E_DL_DcsGrade.eOk;
    _bRejectMark := FALSE;                                         (* 作用域④：清判废标记 / Clear reject mark *)
    _fVelPeak := 0.0;                                              (* 作用域⑤：清曲线锁存 / Clear curve latches *)
    _fBuildS := 0.0;
    _nShot := 0;                                                   (* 作用域⑥：清模次与良品（生产资料复位）/ Clear counters *)
    _nGood := 0;
    IF NOT _bSafeLatch THEN
        IF (_ePhase = E_DL_DcsPhase.eFault) OR (_ePhase = E_DL_DcsPhase.eSafeStop) THEN
            _ePhase := E_DL_DcsPhase.eIdle;                        (* 作用域⑦：故障相迁回待机 / Back to idle *)
        END_IF
    END_IF
ELSIF bStop AND (_ePhase <> E_DL_DcsPhase.eIdle) AND (_ePhase <> E_DL_DcsPhase.eSafeStop) THEN
    IF _ePhase = E_DL_DcsPhase.eFault THEN
        _bFault := FALSE;                                          (* 中止清 E2（E3 只由复位清）/ Abort clears E2 only *)
        _eCause := E_DL_DcsCause.eNone;
        _eGrade := E_DL_DcsGrade.eOk;
    END_IF
    _ePhase := E_DL_DcsPhase.eIdle;                                (* 回待机 / Back to idle *)
ELSIF bRejectAck THEN
    _bRejectMark := FALSE;                                         (* 废模确认只清告警标记 / Ack clears alarm only *)
END_IF

(* —— 段 5：主状态机（四点曲线判据在相迁移点判定，动作经 ApplyDefect 单点施加） —— *)
CASE _ePhase OF
E_DL_DcsPhase.eIdle:
    IF rtStart.Q AND (NOT _bFault) AND (NOT _bSafeLatch) THEN
        _eGrade := E_DL_DcsGrade.eOk;                              (* 新模起算 / New shot *)
        _eCause := E_DL_DcsCause.eNone;
        _bRejectMark := FALSE;
        _ePhase := E_DL_DcsPhase.eClampClose;                      (* 入合模相 / To clamp close *)
    END_IF
E_DL_DcsPhase.eClampClose:
    IF bClampClosed THEN
        _ePhase := E_DL_DcsPhase.eShotSlow;                        (* 合模到位 -> 慢压射 / Clamped, slow shot *)
    ELSIF tonClampClose.Q THEN
        _eCause := E_DL_DcsCause.eClampTmo;                        (* 归因：合模超时 / Cause: clamp timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eShotSlow:
    IF (NOT _bPosBad) AND (fShotPosMm >= fSlowEndSetMm) THEN
        _fSlowEndMm := fShotPosMm;                                 (* 慢速终点锁存 / Latch slow end *)
        ApplyDefect(GradeFault(ABS(_fSlowEndMm - fSlowEndSetMm), fSlowEndWarnMm, fSlowEndTolMm, FALSE),
                    E_DL_DcsCause.eSlowEndDev);                    (* 判据点①：慢速终点偏差 / Point 1 *)
        _fVelPeak := 0.0;                                          (* 快射峰值起算 / Peak restart *)
        _ePhase := E_DL_DcsPhase.eShotFast;                        (* 入快压射相 / To fast shot *)
    ELSIF tonShotSlow.Q THEN
        _eCause := E_DL_DcsCause.eShotTmo;                         (* 归因：慢射超时 / Cause: slow-shot timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eShotFast:
    IF (NOT _bPosBad) AND (fShotPosMm >= fShotEndMm) THEN
        ApplyDefect(GradeFault(_fVelPeak, fFastVelWarnMps, fFastVelMinMps, TRUE),
                    E_DL_DcsCause.eFastVelLow);                    (* 判据点②：快射峰值速度 / Point 2 *)
        _fBuildS := 0.0;                                           (* 建压计时起算 / Build restart *)
        _ePhase := E_DL_DcsPhase.eIntensify;                       (* 入增压相 / To intensify *)
    ELSIF tonShotFast.Q THEN
        _eCause := E_DL_DcsCause.eFastTmo;                         (* 归因：快射超时 / Cause: fast-shot timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eIntensify:
    IF _bBuilt THEN
        ApplyDefect(GradeFault(_fBuildS, fBuildWarnS, fBuildMaxS, FALSE),
                    E_DL_DcsCause.eBuildSlow);                     (* 判据点③：增压建立时间 / Point 3 *)
        _ePhase := E_DL_DcsPhase.eHold;                            (* 建压完成 -> 保压 / Built, hold *)
    ELSIF tonIntensify.Q THEN
        _eCause := E_DL_DcsCause.eBuildTmo;                        (* 归因：增压超时 / Cause: build timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eHold:
    IF tonHold.Q THEN
        _fHoldMpa := fHoldPressMpa;                                (* 保压压力锁存 / Latch hold pressure *)
        ApplyDefect(GradeFault(_fHoldMpa, fHoldWarnMpa, fHoldMinMpa, TRUE),
                    E_DL_DcsCause.eHoldLow);                       (* 判据点④：保压压力 / Point 4 *)
        _ePhase := E_DL_DcsPhase.eClampOpen;                       (* 保压到时 -> 开模 / Hold done, open *)
    END_IF
E_DL_DcsPhase.eClampOpen:
    IF bClampOpened THEN
        _ePhase := E_DL_DcsPhase.eEject;                           (* 开模到位 -> 顶出 / Opened, eject *)
    ELSIF tonClampOpen.Q THEN
        _eCause := E_DL_DcsCause.eClampTmo;                        (* 归因：开模超时 / Cause: open timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eEject:
    IF bEjectDone THEN
        _ePhase := E_DL_DcsPhase.eTakeOut;                         (* 顶出到位 -> 取件 / Ejected, take out *)
    ELSIF tonEject.Q THEN
        _eCause := E_DL_DcsCause.eEjectTmo;                        (* 归因：顶出超时 / Cause: eject timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eTakeOut:
    IF bPartTaken THEN
        _ePhase := E_DL_DcsPhase.eSpray;                           (* 取件完成 -> 喷涂 / Taken, spray *)
    ELSIF tonTakeOut.Q THEN
        _eCause := E_DL_DcsCause.eTakeTmo;                         (* 归因：取件超时 / Cause: take-out timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eSpray:
    IF bSprayDone THEN
        _ePhase := E_DL_DcsPhase.eDone;                            (* 喷涂完成 -> 结算 / Sprayed, settle *)
    ELSIF tonSpray.Q THEN
        _eCause := E_DL_DcsCause.eSprayTmo;                        (* 归因：喷涂超时 / Cause: spray timeout *)
        _bSafeReq := TRUE;
    END_IF
E_DL_DcsPhase.eDone:
    _bDonePulse := TRUE;                                           (* 单拍结算（段 1 预清）/ One-scan done *)
    IF _nShot < DL_DCS_CNTMAX THEN
        _nShot := _nShot + 1;                                      (* 模次推进（容量载体判上限）/ Saturating shot count *)
    END_IF
    IF (NOT _bRejectMark) AND (_nGood < DL_DCS_CNTMAX) THEN
        _nGood := _nGood + 1;                                      (* 良品推进（判废模不计良）/ Saturating good count *)
    END_IF
    _ePhase := E_DL_DcsPhase.eIdle;                                (* 回待机迎下一模 / Back to idle *)
E_DL_DcsPhase.eFault:
    bError := TRUE;                                                (* 故障相驻留（锁存回放）/ Fault residency *)
E_DL_DcsPhase.eSafeStop:
    bError := TRUE;                                                (* 安全相驻留（锁存回放）/ Safety residency *)
ELSE
    _eCause := E_DL_DcsCause.ePhaseBad;                            (* 非法相位兜底 / Illegal phase fallback *)
    _bFaultReq := TRUE;                                            (* 由段 6 落地 / Landed in segment 6 *)
END_CASE

(* —— 段 6：E2/E3 请求统一落地（分支内只写成因与请求，落地仅此一处，R187/R252） —— *)
IF _bSafeReq AND (NOT _bSafeLatch) THEN
    _bSafeLatch := TRUE;                                           (* E3 锁存（黑级）/ Latch E3 *)
    _eGrade := E_DL_DcsGrade.eBlack;                               (* 分级黑 / Grade black *)
    _ePhase := E_DL_DcsPhase.eSafeStop;                            (* 同步迁相 / Migrate *)
    bError := TRUE;                                                (* 故障标志同段置位（R45 配对）/ Error pairing *)
ELSIF _bFaultReq AND (NOT _bSafeLatch) THEN
    _bFault := TRUE;                                               (* E2 锁存 / Latch E2 *)
    _ePhase := E_DL_DcsPhase.eFault;                               (* 同步迁相（R252）/ Migrate *)
    bError := TRUE;                                                (* 故障标志同段置位（R45 配对）/ Error pairing *)
END_IF

(* —— 段 7：统一出口（电平量由 _ePhase 派生，计数与良率带零除守卫） —— *)
eState := _ePhase;                                                 (* 相出口 / Phase outlet *)
eCause := _eCause;                                                 (* 成因回放 / Cause playback *)
eGrade := _eGrade;                                                 (* 分级出口 / Grade outlet *)
bError := bError OR _bFault OR _bSafeLatch;                        (* 故障标志汇总（黄/红不置）/ Error summary *)
bSafeCut := _bSafeLatch;                                           (* 安全断能指令 / Safety energy cut *)
bReject := _bRejectMark;                                           (* 判废告警（红级）/ Reject alarm *)
bDone := _bDonePulse;                                              (* 单拍结算脉冲 / One-scan done *)
bShotActive := (_ePhase = E_DL_DcsPhase.eShotSlow) OR (_ePhase = E_DL_DcsPhase.eShotFast)
            OR (_ePhase = E_DL_DcsPhase.eIntensify);               (* 压射段指示 / Shot indicator *)
nShotCount := _nShot;                                              (* 模次出口 / Shot count outlet *)
nGoodCount := _nGood;                                              (* 良品出口 / Good count outlet *)
IF _nShot > 0 THEN
    fYieldPct := (UDINT_TO_LREAL(_nGood) / UDINT_TO_LREAL(_nShot)) * DL_DCS_PCTOP;   (* 良率（分母已判非零）/ Guarded yield *)
ELSE
    fYieldPct := 0.0;                                              (* 无模次输出 0 / No shot, zero *)
END_IF
fSlowEndLastMm := _fSlowEndMm;                                     (* 慢速终点出口 / Slow-end outlet *)
fFastVelLastMps := _fVelPeak;                                      (* 快射峰值出口 / Peak velocity outlet *)
fBuildLastS := _fBuildS;                                           (* 建立时间出口 / Build time outlet *)
fHoldLastMpa := _fHoldMpa;                                         (* 保压压力出口 / Hold pressure outlet *)
END_FUNCTION_BLOCK
