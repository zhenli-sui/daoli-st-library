(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TrayLoadVacuum
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / TOF / R_TRIG / F_TRIG），零厂商私有库
 * 功能描述 (Function)   : 电池片花篮真空取放顺控。吸取相开真空阀，真空反馈
 *                         在 tVacOnDelay 内不到达即吸取超时故障（独立成因）；
 *                         放片相关真空并以 TOF 定宽输出破真空吹气脉冲
 *                         （宽度 tBlowWidth + 1 扫描拍，头注释明示），吹气
 *                         结束沿收口 bPlaceDone。与 VacuumEjector（真空发生
 *                         设备件）分工：本件是取放顺控中破真空定宽脉冲的
 *                         时序件。
 * 来源标签 (Origin)     : ROADMAP §9.3 P2（L418），自研 clean-room
 * 边界语义 (Boundary)   : ① 吸取超时 TON 电平计时（非自复位周期窗）；
 *                         ② 吹气定宽用 TOF（触发单拍 → 展宽 tBlowWidth），
 *                         结束沿用 F_TRIG（段 0 无条件刷新）；
 *                         ③ 故障相真空阀强制关断（安全侧失真空）；
 *                         ④ 组态闸：两时间量正域 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 双阀输出强制 FALSE（阀类
 *                         出口失能必须收敛）；eFault 相 → 真空阀 FALSE +
 *                         bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/TOF/R_TRIG/F_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 取片申请沿 → 真空阀 TRUE，bVacFb 在 tVacOnDelay
 *                         内到达 → bPickDone 单拍进保持相；
 *                         V2 反馈超 tVacOnDelay 未到 → eVacFail 故障锁存，
 *                         真空阀关断；
 *                         V3 放片申请沿 → 真空阀关 + 吹气阀展宽 tBlowWidth
 *                         后 bPlaceDone 单拍回待机。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 4 · 序号 16）
 *==============================================================================*)
TYPE E_DL_TlvState :
(
    eIdle  := 0,                             (* 待机（双阀关） / Idle *)
    ePick  := 10,                            (* 真空吸取 / Vacuum pick *)
    eHold  := 20,                            (* 吸取保持（待放片申请） / Hold *)
    ePlace := 30,                            (* 破真空吹气放片 / Blow-off place *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_TlvCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：时间量越域 / Illegal config *)
    eVacFail  := 2,                          (* 吸取真空反馈超时 / Vacuum feedback timeout *)
    ePhaseBad := 3                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrayLoadVacuum
VAR_INPUT
    bPickReq   : BOOL := FALSE;              (* 取片申请沿 [-] / Pick request edge *)
    bPlaceReq  : BOOL := FALSE;              (* 放片申请沿 [-] / Place request edge *)
    bVacFb     : BOOL := FALSE;              (* 真空到达反馈电平 [-] / Vacuum feedback level *)
    tVacOnDelay: TIME := T#2S;               (* 真空建立超时，域 > T#0S [ms] / Vacuum build timeout *)
    tBlowWidth : TIME := T#500MS;            (* 破真空吹气定宽，域 > T#0S [ms] / Blow pulse width *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bVacValve  : BOOL;                       (* 真空阀输出 [-] / Vacuum valve outlet *)
    bBlowValve : BOOL;                       (* 破真空吹气阀输出（定宽脉冲）[-] / Blow valve outlet *)
    bPickDone  : BOOL;                       (* 吸取完成单拍位 [-] / Pick-done pulse *)
    bPlaceDone : BOOL;                       (* 放片完成单拍位 [-] / Place-done pulse *)
    nCycleCnt  : UDINT;                      (* 累计取放循环数 [次] / Cycle count *)
    eState     : E_DL_TlvState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_TlvCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_TlvState := E_DL_TlvState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_TlvCause := E_DL_TlvCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtPick    : R_TRIG;                      (* 取片沿实例，段 0 无条件调用 / Pick edge instance *)
    rtPlace   : R_TRIG;                      (* 放片沿实例，段 0 无条件调用 / Place edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonVac    : TON;                         (* 真空建立超时计时，段 0 无条件调用 / Vacuum timeout timer *)
    toBlow    : TOF;                         (* 吹气定宽展宽（TOF 下降沿后保持 PT）[ms] / Blow width stretcher *)
    ftBlow    : F_TRIG;                      (* 吹气结束沿实例，段 0 无条件调用 / Blow-end edge instance *)
    _bVacOn   : BOOL;                        (* 真空阀指令锁存 [-] / Vacuum valve latch *)
    _bBlowFire: BOOL;                        (* 吹气触发单拍量（TOF 输入）[-] / Blow fire pulse *)
    _bBlowAct : BOOL;                        (* 吹气进行中锁存（结束沿判据）[-] / Blow-active latch *)
    _nCycles  : UDINT;                       (* 循环计数锁存 [次] / Cycle count latch *)
    _bPickD   : BOOL;                        (* 吸取完成单拍量 [-] / Pick-done work *)
    _bPlaceD  : BOOL;                        (* 放片完成单拍量 [-] / Place-done work *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (tVacOnDelay <= T#0S) OR (tBlowWidth <= T#0S);   (* 组态闸（R151 全引脚） / Config gate *)
rtPick(CLK := bPickReq);                     (* 取片沿每拍必调 / Pick edge every scan *)
rtPlace(CLK := bPlaceReq);                   (* 放片沿每拍必调 / Place edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
tonVac(IN := (_eState = E_DL_TlvState.ePick) AND (NOT bVacFb), PT := tVacOnDelay);   (* 真空建立超时（电平计时非周期窗） / Vacuum timeout *)
toBlow(IN := _bBlowFire, PT := tBlowWidth);  (* 吹气展宽：单拍触发 → Q 保持 tBlowWidth（输出脉宽 = PT + 1 拍，头注释明示） / Blow stretcher *)
ftBlow(CLK := toBlow.Q);                     (* 吹气结束沿每拍必调 / Blow-end edge every scan *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bBlowFire := FALSE;                         (* 吹气触发预清，唯一分支置位 / Blow fire preset *)
_bPickD := FALSE;                            (* 吸取完成预清 / Pick-done preset *)
_bPlaceD := FALSE;                           (* 放片完成预清 / Place-done preset *)
bPickDone := FALSE;                          (* 吸取完成出口预清 / Pick-done outlet preset *)
bPlaceDone := FALSE;                         (* 放片完成出口预清 / Place-done outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清阀锁存 + 清吹气锁存 + 清计数 + 迁 eIdle，R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_TlvCause.eNone;          (* 清成因 / Clear cause *)
    _bVacOn := FALSE;                        (* 清真空阀锁存 / Clear valve latch *)
    _bBlowAct := FALSE;                      (* 清吹气锁存 / Clear blow latch *)
    _nCycles := 0;                           (* 清循环计数 / Clear count *)
    _eState := E_DL_TlvState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_TlvCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_TlvState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_TlvState.eIdle:                     (* 待机相 / Idle *)
        IF rtPick.Q AND bEnable AND (NOT _bFault) THEN
            _bVacOn := TRUE;                 (* 开真空阀 / Open vacuum valve *)
            _eState := E_DL_TlvState.ePick;  (* 进入吸取 / Enter pick *)
        END_IF
    E_DL_TlvState.ePick:                     (* 吸取相：等真空反馈或超时 / Pick *)
        IF bVacFb THEN                       (* 反馈到达：吸取完成（过渡态三段：本拍发完成脉冲并迁相/下拍预清，R80） / Feedback arrived *)
            _bPickD := TRUE;                 (* 内部完成量置位（统一出口映射单拍，R189 两段式） / Internal done set *)
            _eState := E_DL_TlvState.eHold;  (* 进保持相 / Enter hold *)
        ELSIF tonVac.Q THEN                  (* 建立超时：故障锁存（R190 独立成因） / Build timeout *)
            _eCause := E_DL_TlvCause.eVacFail;   (* 成因：真空超时 / Cause: vac timeout *)
            _bFault := TRUE;                 (* 故障锁存（R45 配对） / Latch fault *)
            _bVacOn := FALSE;                (* 故障相真空阀关断（安全侧，边界③） / Close valve safe side *)
            _eState := E_DL_TlvState.eFault; (* 迁故障相 / To fault *)
        END_IF
    E_DL_TlvState.eHold:                     (* 保持相：待放片申请 / Hold *)
        IF rtPlace.Q AND bEnable AND (NOT _bFault) THEN
            _bVacOn := FALSE;                (* 关真空阀（破真空） / Close vacuum valve *)
            _bBlowFire := TRUE;              (* 吹气触发单拍（TOF 展宽定宽） / Fire blow pulse *)
            _bBlowAct := TRUE;               (* 置吹气进行锁存 / Set blow-active *)
            _eState := E_DL_TlvState.ePlace; (* 进放片相 / Enter place *)
        END_IF
    E_DL_TlvState.ePlace:                    (* 放片相：吹气定宽至结束沿 / Place *)
        IF ftBlow.Q AND _bBlowAct THEN       (* 吹气结束沿：收口（过渡态三段：本拍发单拍/下拍预清，R80） / Blow-end edge: close out *)
            _bBlowAct := FALSE;              (* 清吹气锁存 / Clear blow latch *)
            _bPlaceD := TRUE;                (* 内部完成量置位 / Internal done set *)
            _nCycles := _nCycles + 1;        (* 循环计数（UDINT 回绕工程安全） / Count cycle *)
            _eState := E_DL_TlvState.eIdle;  (* 回待机 / Back to idle *)
        END_IF
    E_DL_TlvState.eFault:                    (* 故障相：阀已安全关断，仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_TlvState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_TlvCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（完成脉冲两段式统一出口，R189；阀出口与状态同源 R191） —— *)
bPickDone := _bPickD;                        (* 吸取完成单拍出口 / Pick-done outlet *)
bPlaceDone := _bPlaceD;                      (* 放片完成单拍出口 / Place-done outlet *)
bVacValve := _bVacOn AND bEnable AND (NOT _bFault);   (* 真空阀出口（失能/故障收敛 FALSE） / Vacuum valve outlet *)
bBlowValve := toBlow.Q AND _bBlowAct AND bEnable AND (NOT _bFault);   (* 吹气阀出口（定宽 + 门控收敛） / Blow valve outlet *)
nCycleCnt := _nCycles;                       (* 循环计数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
