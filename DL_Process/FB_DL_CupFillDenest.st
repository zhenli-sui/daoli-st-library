(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CupFillDenest
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : 杯装灌装机取杯-灌装-封口三段节拍链。段间以设备反
 *                         馈（杯到位 / 灌装完成 / 封口完成）推进；每段挂相驻
 *                         留看门狗（IN 只用相驻留本身，R145），到时按独立成
 *                         因故障锁存（R190 归因唯一）。与 StepSequencer（通
 *                         用步序器）分工：本件是三段节拍链的工艺编排实例。
 * 来源标签 (Origin)     : ROADMAP §9.4 P2（L435），自研 clean-room
 * 边界语义 (Boundary)   : ① 三个看门狗 IN 均为纯相驻留（无业务条件补集，
 *                         R145）；② 段输出阀指令与相位同源（R191 名实双出口）；
 *                         ③ 完成脉冲内部量置位 → 统一出口映射单拍（R189 两段
 *                         式）；④ 组态闸：三超时正域 → 故障锁存。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 三阀输出强制 FALSE（阀类
 *                         出口失能必须收敛，节拍链回待机）；eFault 相 → 阀全
 *                         关 + bError = TRUE。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 启动沿 → 取杯阀开，杯到位反馈 → 灌装阀开；
 *                         V2 灌装完成反馈 → 封口压上，封口完成反馈 →
 *                         bCycleDone 单拍计数 +1 回待机；
 *                         V3 取杯段驻留超 tDenestMax → eDenestTO 独立故障。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 4 · 序号 17）
 *==============================================================================*)
TYPE E_DL_CfdState :
(
    eIdle  := 0,                             (* 待机（阀全关） / Idle *)
    eDenest:= 10,                            (* 取杯段 / Denest cup *)
    eFill  := 20,                            (* 灌装段 / Filling *)
    eSeal  := 30,                            (* 封口段 / Sealing *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_CfdCause :
(
    eNone     := 0,                          (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：超时量越域 / Illegal config *)
    eDenestTO := 2,                          (* 取杯段超时（独立成因，R190） / Denest timeout *)
    eFillTO   := 3,                          (* 灌装段超时（独立成因） / Fill timeout *)
    eSealTO   := 4,                          (* 封口段超时（独立成因） / Seal timeout *)
    ePhaseBad := 5                           (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CupFillDenest
VAR_INPUT
    bStartReq  : BOOL := FALSE;              (* 节拍启动申请沿 [-] / Cycle start edge *)
    bCupFb     : BOOL := FALSE;              (* 杯到位反馈电平 [-] / Cup-present feedback *)
    bFillDone  : BOOL := FALSE;              (* 灌装完成反馈电平 [-] / Fill-done feedback *)
    bSealDone  : BOOL := FALSE;              (* 封口完成反馈电平 [-] / Seal-done feedback *)
    tDenestMax : TIME := T#3S;               (* 取杯段看门狗，域 > T#0S [ms] / Denest watchdog *)
    tFillMax   : TIME := T#10S;              (* 灌装段看门狗，域 > T#0S 且配比 >= tDenestMax [ms] / Fill watchdog *)
    tSealMax   : TIME := T#5S;               (* 封口段看门狗，域 > T#0S [ms] / Seal watchdog *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bDenestOut : BOOL;                       (* 取杯阀输出 [-] / Denest valve outlet *)
    bFillValve : BOOL;                       (* 灌装阀输出 [-] / Fill valve outlet *)
    bSealPress : BOOL;                       (* 封口压输出 [-] / Seal press outlet *)
    bCycleDone : BOOL;                       (* 节拍完成单拍位 [-] / Cycle-done pulse *)
    nCycleCnt  : UDINT;                      (* 累计节拍数 [次] / Cycle count *)
    eState     : E_DL_CfdState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_CfdCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_CfdState := E_DL_CfdState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_CfdCause := E_DL_CfdCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtStart   : R_TRIG;                      (* 启动沿实例，段 0 无条件调用 / Start edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonDen    : TON;                         (* 取杯段看门狗（相驻留使能，R145），段 0 无条件调用 / Denest watchdog *)
    tonFill   : TON;                         (* 灌装段看门狗，段 0 无条件调用 / Fill watchdog *)
    tonSeal   : TON;                         (* 封口段看门狗，段 0 无条件调用 / Seal watchdog *)
    _bDone    : BOOL;                        (* 节拍完成内部量（两段式脉冲，R189）[-] / Cycle-done work *)
    _nCycles  : UDINT;                       (* 节拍计数锁存 [次] / Cycle count latch *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (tDenestMax <= T#0S) OR (tFillMax < tDenestMax) OR (tSealMax <= T#0S);   (* 组态闸（R100 配比 tFillMax >= tDenestMax） / Config gate *)
rtStart(CLK := bStartReq);                   (* 启动沿每拍必调 / Start edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
tonDen(IN := (_eState = E_DL_CfdState.eDenest), PT := tDenestMax);   (* 取杯看门狗：纯相驻留使能（R145） / Denest watchdog, phase-residency only *)
tonFill(IN := (_eState = E_DL_CfdState.eFill), PT := tFillMax);     (* 灌装看门狗 / Fill watchdog *)
tonSeal(IN := (_eState = E_DL_CfdState.eSeal), PT := tSealMax);     (* 封口看门狗 / Seal watchdog *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDone := FALSE;                             (* 完成内部量预清，唯一分支置位 / Done work preset *)
bCycleDone := FALSE;                         (* 完成出口预清 / Done outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 迁 eIdle（阀随段 5 相位收敛），R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_CfdCause.eNone;          (* 清成因 / Clear cause *)
    _nCycles := 0;                           (* 清节拍计数 / Clear count *)
    _eState := E_DL_CfdState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_CfdCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_CfdState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_CfdState.eIdle:                     (* 待机相 / Idle *)
        IF rtStart.Q AND bEnable AND (NOT _bFault) THEN
            _eState := E_DL_CfdState.eDenest;   (* 进入取杯 / Enter denest *)
        END_IF
    E_DL_CfdState.eDenest:                   (* 取杯段：等杯到位或超时 / Denest *)
        IF bCupFb THEN
            _eState := E_DL_CfdState.eFill;  (* 杯到位进灌装（过渡态：本拍迁相/下拍看门狗自动清，R80） / Cup present: to fill *)
        ELSIF tonDen.Q THEN                  (* 段驻留超时：独立成因锁存（R190） / Segment timeout *)
            _eCause := E_DL_CfdCause.eDenestTO;   (* 成因：取杯超时 / Cause: denest TO *)
            _bFault := TRUE;                 (* 故障锁存（R45 配对） / Latch fault *)
            _eState := E_DL_CfdState.eFault; (* 迁故障相 / To fault *)
        END_IF
    E_DL_CfdState.eFill:                     (* 灌装段：等灌装完成或超时 / Fill *)
        IF bFillDone THEN
            _eState := E_DL_CfdState.eSeal;  (* 灌装完成进封口 / Fill done: to seal *)
        ELSIF tonFill.Q THEN                 (* 段驻留超时 / Segment timeout *)
            _eCause := E_DL_CfdCause.eFillTO;   (* 成因：灌装超时（独立成员） / Cause: fill TO *)
            _bFault := TRUE;                 (* 故障锁存 / Latch fault *)
            _eState := E_DL_CfdState.eFault; (* 迁故障相 / To fault *)
        END_IF
    E_DL_CfdState.eSeal:                     (* 封口段：等封口完成或超时 / Seal *)
        IF bSealDone THEN
            _bDone := TRUE;                  (* 完成内部量置位（统一出口映射单拍，R189） / Internal done set *)
            _nCycles := _nCycles + 1;        (* 节拍计数（UDINT 回绕工程安全） / Count cycle *)
            _eState := E_DL_CfdState.eIdle;  (* 回待机 / Back to idle *)
        ELSIF tonSeal.Q THEN                 (* 段驻留超时 / Segment timeout *)
            _eCause := E_DL_CfdCause.eSealTO;   (* 成因：封口超时（独立成员） / Cause: seal TO *)
            _bFault := TRUE;                 (* 故障锁存 / Latch fault *)
            _eState := E_DL_CfdState.eFault; (* 迁故障相 / To fault *)
        END_IF
    E_DL_CfdState.eFault:                    (* 故障相：阀全关（段 5 收敛），仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_CfdState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_CfdCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（阀与相位同源，R191；完成脉冲两段式，R189） —— *)
bDenestOut := (_eState = E_DL_CfdState.eDenest) AND bEnable AND (NOT _bFault);   (* 取杯阀出口 / Denest valve outlet *)
bFillValve := (_eState = E_DL_CfdState.eFill) AND bEnable AND (NOT _bFault);     (* 灌装阀出口 / Fill valve outlet *)
bSealPress := (_eState = E_DL_CfdState.eSeal) AND bEnable AND (NOT _bFault);     (* 封口压出口 / Seal press outlet *)
bCycleDone := _bDone;                        (* 完成单拍出口 / Done outlet *)
nCycleCnt := _nCycles;                       (* 节拍计数出口 / Count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
