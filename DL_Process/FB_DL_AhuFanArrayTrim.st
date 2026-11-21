(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AhuFanArrayTrim
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 空调箱风机阵列静压微调。双层结构：外层按静压误差
 *                         越带（|Sp-Fb| > fBand）持续 tErrHold 后分级投切风机
 *                         台数 0..4（台间最小驻留 tStageDwell 防抖）；内层在
 *                         投切台数固定的间隙用积分微调 fTrimI 补残余静压偏差，
 *                         投切动作同拍微调清零重学习。与 FanArrayStageCtrl
 *                         （纯分级投切，既有件）分工：本件是「投切+连续调节」
 *                         双层，静压闭环语义新增。
 * 来源标签 (Origin)     : ROADMAP §16.5 R11 池 P1（L724），自研 clean-room
 * 边界语义 (Boundary)   : ① 压力 NaN/Inf 拍：冻结投切与微调（不推进累计）；
 *                         ② 微调积分双侧钳 ±fTrimLimit + 绝对安全上限兜底；
 *                         ③ 台数 0..4 结构性钳位，越带确认 TON 非自复位（电平
 *                         撤除即清，无周期窗语义）；
 *                         ④ 组态闸：死区/增益/限幅/两时间量域检查 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 台数与微调冻结保持末值
 *                         （阵列不宜跳变，由调用方决定停机卸载）；eFault 相
 *                         → 冻结 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零闸/NaN 冻结/钳位/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 Fb=49.0、Sp=50.0（差 0.5 = fBand）持续 tErrHold
 *                         → tonUp.Q → 台数 +1 且微调清零；
 *                         V2 台数 4 封顶后误差仍正 → 只积分微调不投切；
 *                         V3 误差反向越带持续 → 台数 -1（tonDwell 驻留内不动）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 1 · 序号 1）
 *==============================================================================*)
TYPE E_DL_AftState :
(
    eIdle  := 0,                             (* 待使能 / Idle *)
    eAuto  := 10,                            (* 投切+微调自动运行 / Auto staging + trim *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_AftCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：死区/增益/限幅/时间越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_AhuFanArrayTrim
VAR_INPUT
    fPressFb   : LREAL := 50.0;              (* 静压反馈 [kPa] / Static pressure feedback *)
    fPressSp   : LREAL := 50.0;              (* 静压设定 [kPa] / Static pressure setpoint *)
    fBand      : LREAL := 0.5;               (* 投切死区（|误差| 门限），域 > eps [kPa] / Staging deadband *)
    fTrimGain  : LREAL := 2.0;               (* 微调积分增益，域 > 0 [%/(kPa·拍)] / Trim gain *)
    fTrimLimit : LREAL := 10.0;              (* 微调限幅，域 > 0 [%] / Trim limit *)
    tErrHold   : TIME := T#5S;               (* 越带确认时长，域 > T#0S [ms] / Error confirm time *)
    tStageDwell: TIME := T#30S;              (* 投切最小驻留（台间间隔），域 > T#0S 且 >= tErrHold 配比 [ms] / Stage dwell *)
    bEnable    : BOOL := TRUE;               (* 使能，FALSE 冻结保持 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    nStageOut  : INT;                        (* 风机投运台数 0..4 [台] / Running fan stage count *)
    fTrimOut   : LREAL;                      (* 静压微调输出（钳 ±fTrimLimit）[%] / Trim output *)
    bTrimActive: BOOL;                       (* 微调参与指示（自动相且值有效）[-] / Trim active *)
    eState     : E_DL_AftState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_AftCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState    : E_DL_AftState := E_DL_AftState.eIdle;    (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause    : E_DL_AftCause := E_DL_AftCause.eNone;    (* 故障成因锁存量 / Latched cause *)
    rtReset    : R_TRIG;                     (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonUp      : TON;                        (* 越带正向（欠压）确认，段 0 无条件调用 / Under-pressure confirm *)
    tonDn      : TON;                        (* 越带反向（超压）确认，段 0 无条件调用 / Over-pressure confirm *)
    tonDwell   : TON;                        (* 投切驻留计时，段 0 无条件调用 / Stage dwell timer *)
    _fErr      : LREAL;                      (* 本拍静压误差 [kPa] / Pressure error this scan *)
    _fTrimI    : LREAL;                      (* 微调积分锁存 [%] / Trim integrator *)
    _nStage    : INT;                        (* 台数锁存 0..4 [台] / Stage latch *)
    _bStageMoved: BOOL;                      (* 本拍有投切动作（重启驻留计时）[-] / Stage moved this scan *)
    _bPressBad : BOOL;                       (* 压力非有限当拍量 [-] / Non-finite pressure *)
    _bFault    : BOOL;                       (* 故障锁存位 / Latched fault bit *)
    _bCfgBad   : BOOL;                       (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_AFT_EPS    : LREAL := 1.0E-9;        (* 死区判零容差 [kPa] / Deadband epsilon *)
    DL_AFT_SMAX   : INT   := 4;             (* 台数上限 [台] / Stage count max *)
    DL_AFT_TRIMCAP: LREAL := 100.0;         (* 微调绝对安全上限 [%] / Trim absolute cap *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fBand <= DL_AFT_EPS) OR (fTrimGain <= 0.0) OR (fTrimLimit <= 0.0)
            OR (tErrHold <= T#0S) OR (tStageDwell < tErrHold);   (* 组态闸：R100 配比 tStageDwell >= tErrHold / Config gate with ratio rule *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bPressBad := (fPressFb <> fPressFb) OR ((fPressFb - fPressFb) <> (fPressFb - fPressFb))
            OR (fPressSp <> fPressSp) OR ((fPressSp - fPressSp) <> (fPressSp - fPressSp));   (* 双压力 NaN 自反 + Inf 差判 / Non-finite pressure gates *)
tonUp(IN := (_eState = E_DL_AftState.eAuto) AND NOT _bPressBad AND ((fPressSp - fPressFb) > fBand), PT := tErrHold);   (* 欠压越带确认（电平计时非周期窗） / Under-band confirm *)
tonDn(IN := (_eState = E_DL_AftState.eAuto) AND NOT _bPressBad AND ((fPressFb - fPressSp) > fBand), PT := tErrHold);   (* 超压越带确认 / Over-band confirm *)
tonDwell(IN := (_eState = E_DL_AftState.eAuto) AND NOT _bStageMoved, PT := tStageDwell);   (* 驻留计时：投切拍 IN 断一拍重启 / Dwell restarts on stage move *)

(* —— 段 1：单拍量预清零（R107） —— *)
_fErr := 0.0;                                (* 误差预清（每拍全路径派生，R285） / Error preset *)
_bStageMoved := FALSE;                       (* 投切动作标志预清（单拍量） / Stage-moved preset *)
bTrimActive := FALSE;                        (* 微调参与预清 / Trim-active preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清台数 + 清微调积分 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_AftCause.eNone;          (* 清成因 / Clear cause *)
    _nStage := 0;                            (* 清台数 / Clear stage *)
    _fTrimI := 0.0;                          (* 清微调积分 / Clear trim integrator *)
    _eState := E_DL_AftState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_AftCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_AftState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_AftState.eIdle:                     (* 待机相 / Idle *)
        IF bEnable AND NOT _bFault AND NOT _bPressBad THEN
            _eState := E_DL_AftState.eAuto;  (* 进入自动 / Enter auto *)
        END_IF
    E_DL_AftState.eAuto:                     (* 自动相：投切外环 + 微调内环 / Auto *)
        IF NOT bEnable THEN
            _eState := E_DL_AftState.eIdle;  (* 失能回待机（台数/微调冻结保持，R191 声明） / Back to idle, held *)
        ELSIF NOT _bPressBad THEN
            _fErr := fPressSp - fPressFb;    (* 误差派生 / Error derive *)
            _fTrimI := _fTrimI + fTrimGain * _fErr;   (* 微调积分 / Trim integrate *)
            IF _fTrimI > fTrimLimit THEN
                _fTrimI := fTrimLimit;       (* 微调上限钳位 / Trim upper clamp *)
            ELSIF _fTrimI < (-fTrimLimit) THEN
                _fTrimI := (-fTrimLimit);    (* 微调下限钳位 / Trim lower clamp *)
            END_IF
            IF ABS(_fTrimI) > DL_AFT_TRIMCAP THEN
                _fTrimI := DL_AFT_TRIMCAP;   (* 绝对安全上限兜底 / Absolute cap *)
            END_IF
            IF tonUp.Q AND tonDwell.Q AND (_nStage < DL_AFT_SMAX) THEN   (* 欠压到时 + 驻留到时 + 未封顶 / Stage up gated *)
                _nStage := _nStage + 1;      (* 台数 +1 / Stage up *)
                _bStageMoved := TRUE;        (* 置动作标志：下拍重启驻留 / Mark moved *)
                _fTrimI := 0.0;              (* 投切同拍微调清零重学习 / Re-center trim *)
            ELSIF tonDn.Q AND tonDwell.Q AND (_nStage > 0) THEN   (* 超压到时 + 驻留到时 + 未到零 / Stage down gated *)
                _nStage := _nStage - 1;      (* 台数 -1 / Stage down *)
                _bStageMoved := TRUE;        (* 置动作标志 / Mark moved *)
                _fTrimI := 0.0;              (* 投切同拍微调清零 / Re-center trim *)
            END_IF
        END_IF                               (* 压力坏值拍：冻结不推进（边界①） / Bad pressure: freeze *)
    E_DL_AftState.eFault:                    (* 故障相：冻结保持，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_AftState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_AftCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（bError/eState 同源，R191） —— *)
nStageOut := _nStage;                        (* 台数出口镜像 / Stage mirror *)
fTrimOut := _fTrimI;                         (* 微调出口镜像 / Trim mirror *)
bTrimActive := (_eState = E_DL_AftState.eAuto) AND (NOT _bFault) AND (NOT _bPressBad);   (* 微调参与指示 / Trim active *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
