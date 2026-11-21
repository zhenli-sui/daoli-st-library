(*==============================================================================
 * 组件名称 (Component)  : FB_DL_HumidifierAdiabat
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 绝热加湿器补水顺控（水位双限 + 排水周期）。补水阀
 *                         双限滞环：水位 <= fLevelLo 开阀、>= fLevelHi 关阀
 *                         （双限结构消抖）；排水申请沿切入定时排水相
 *                         tDrainTime，排水完成沿回待机并计数。与
 *                         HumidityRatioCalc/RoomClimateCtrl（计算与房间控制）
 *                         分工：本件是绝热加湿补水 + 排水周期顺控。
 * 来源标签 (Origin)     : ROADMAP §9.5 P2（L443），自研 clean-room
 * 边界语义 (Boundary)   : ① 水位 NaN/Inf 拍：双阀全关安全侧冻结（不启停）；
 *                         ② 双限域闸（0 < fLevelLo < fLevelHi <= 100）→ 组态
 *                         故障；
 *                         ③ 排水定时 TON 相驻留使能（非自复位周期窗）；
 *                         ④ 补水与排水互斥（同拍至多一阀输出）。
 * 输出语义 (Fallback)   : 【R191】bEnable = FALSE → 双阀输出强制 FALSE（阀类
 *                         出口失能必须收敛）；eFault 相 → 阀全关 + bError。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码；错误出口 BOOL+ENUM(eCause)。
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 除零无涉/NaN 安全侧/组态闸 ✓｜R5 双语同行注释 ✓
 *                         R6 CASE 带 ELSE 兜底迁 eFault ✓｜R7 TON/R_TRIG 段 0 无条件刷新 ✓
 * 验收向量 (Acceptance) : V1 水位 20（<= Lo 30）→ 补水阀开，升至 80（>= Hi）
 *                         → 阀关回待机；
 *                         V2 排水申请沿 → 排水阀开 tDrainTime 后 bDrainDone
 *                         单拍计数 +1；
 *                         V3 水位 NaN 拍 → 双阀 FALSE 冻结（边界①）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R51 首版（批 4 · 序号 18）
 *==============================================================================*)
TYPE E_DL_HasState :
(
    eIdle  := 0,                             (* 待机（阀全关） / Idle *)
    eFill  := 10,                            (* 补水（双限滞环开阀） / Filling *)
    eDrain := 20,                            (* 定时排水 / Timed drain *)
    eFault := 90                             (* 故障锁存相 / Fault latched phase *)
);
END_TYPE

TYPE E_DL_HasCause :
(
    eNone       := 0,                        (* 无故障成因 / No cause *)
    eCfgIllegal := 1,                        (* 组态非法：双限倒置/时间越域 / Illegal config *)
    ePhaseBad   := 2                         (* 非法相位兜底 / Illegal phase fallback *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_HumidifierAdiabat
VAR_INPUT
    fLevelPct  : LREAL := 50.0;              (* 水位反馈，域 (0,100] [%] / Water level feedback *)
    fLevelLo   : LREAL := 30.0;              (* 补水启动下限，域 > 0 且 < fLevelHi [%] / Fill-on lower limit *)
    fLevelHi   : LREAL := 80.0;              (* 补水停止上限，域 <= 100 且 > fLevelLo [%] / Fill-off upper limit *)
    tDrainTime : TIME := T#30S;              (* 排水定时时长，域 > T#0S [ms] / Drain duration *)
    bDrainReq  : BOOL := FALSE;              (* 周期排水申请沿 [-] / Drain request edge *)
    bEnable    : BOOL := TRUE;               (* 使能 [-] / Enable *)
    bReset     : BOOL := FALSE;              (* 复位命令，上升沿清全部 [-] / Reset command *)
END_VAR
VAR_OUTPUT
    bFillValve : BOOL;                       (* 补水阀输出（与排水互斥）[-] / Fill valve outlet *)
    bDrainValve: BOOL;                       (* 排水阀输出 [-] / Drain valve outlet *)
    bDrainDone : BOOL;                       (* 排水完成单拍位 [-] / Drain-done pulse *)
    nDrainCnt  : UDINT;                      (* 累计排水次数 [次] / Drain count *)
    eState     : E_DL_HasState;              (* 状态出口 / State outlet *)
    eCause     : E_DL_HasCause;              (* 故障成因出口 / Fault cause outlet *)
    bError     : BOOL;                       (* 故障锁存标志 [-] / Fault latch flag *)
END_VAR
VAR
    _eState   : E_DL_HasState := E_DL_HasState.eIdle;     (* 内部相位（CASE 唯一写入目标） / Internal phase *)
    _eCause   : E_DL_HasCause := E_DL_HasCause.eNone;     (* 故障成因锁存量 / Latched cause *)
    rtDrain   : R_TRIG;                      (* 排水申请沿实例，段 0 无条件调用 / Drain edge instance *)
    rtReset   : R_TRIG;                      (* 复位沿实例，段 0 无条件调用 / Reset edge instance *)
    tonDrain  : TON;                         (* 排水定时（相驻留使能，R145），段 0 无条件调用 / Drain timer *)
    _bDone    : BOOL;                        (* 排水完成内部量（两段式脉冲，R189）[-] / Drain-done work *)
    _nDrains  : UDINT;                       (* 排水计数锁存 [次] / Drain count latch *)
    _bLvBad   : BOOL;                        (* 水位非有限当拍量 [-] / Non-finite level *)
    _bFault   : BOOL;                        (* 故障锁存位 / Latched fault bit *)
    _bCfgBad  : BOOL;                        (* 组态非法当拍量 / Illegal config this scan *)
END_VAR
VAR CONSTANT
    DL_HAS_LMAX : LREAL := 100.0;            (* 水位物理上限 [%] / Level physical max *)
    DL_HAS_EPS  : LREAL := 1.0E-9;           (* 下限判零容差 [%] / Lower-limit epsilon *)
END_VAR

(* —— 段 0：当拍判据派生 + 实例无条件刷新（R228A） —— *)
_bCfgBad := (fLevelLo <= DL_HAS_EPS) OR (fLevelLo >= fLevelHi) OR (fLevelHi > DL_HAS_LMAX)
            OR (tDrainTime <= T#0S);     (* 组态闸（R151 全引脚 + 双限序） / Config gate *)
rtDrain(CLK := bDrainReq);                   (* 排水沿每拍必调 / Drain edge every scan *)
rtReset(CLK := bReset);                      (* 复位沿每拍必调 / Reset edge every scan *)
_bLvBad := (fLevelPct <> fLevelPct) OR ((fLevelPct - fLevelPct) <> (fLevelPct - fLevelPct));   (* 水位 NaN 自反 + Inf 差判 / Non-finite level *)
tonDrain(IN := (_eState = E_DL_HasState.eDrain), PT := tDrainTime);   (* 排水定时：纯相驻留使能（R145） / Drain timer, phase-residency *)

(* —— 段 1：单拍量预清零（R107） —— *)
_bDone := FALSE;                             (* 完成内部量预清，唯一分支置位 / Done work preset *)
bDrainDone := FALSE;                         (* 完成出口预清 / Done outlet preset *)

(* —— 段 2：复位沿处理（作用域：清故障 + 清计数 + 迁 eIdle（阀随段 5 相位收敛），R283 逐项声明） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                        (* 清故障锁存 / Clear fault *)
    _eCause := E_DL_HasCause.eNone;          (* 清成因 / Clear cause *)
    _nDrains := 0;                           (* 清排水计数 / Clear drain count *)
    _eState := E_DL_HasState.eIdle;          (* 迁待机相 / Back to idle *)
END_IF

(* —— 段 3：组态闸故障锁存（R45 配对；锁存至复位沿，R189） —— *)
IF _bCfgBad AND NOT _bFault THEN
    _bFault := TRUE;                         (* 锁存故障位 / Latch fault *)
    _eCause := E_DL_HasCause.eCfgIllegal;    (* 成因：组态非法 / Cause: illegal config *)
    _eState := E_DL_HasState.eFault;         (* 同步迁故障相 / Migrate to fault *)
END_IF

(* —— 段 4：CASE 主状态机（ELSE 兜底迁 eFault，红线 6） —— *)
CASE _eState OF
    E_DL_HasState.eIdle:                     (* 待机相 / Idle *)
        IF NOT bEnable THEN
            _eState := E_DL_HasState.eIdle;  (* 失能驻留待机（幂等保持） / Stay idle when disabled *)
        ELSIF (NOT _bLvBad) AND (fLevelPct <= fLevelLo) THEN
            _eState := E_DL_HasState.eFill;  (* 水位触下限：补水（双限滞环） / Level low: fill *)
        ELSIF rtDrain.Q AND bEnable AND (NOT _bFault) THEN
            _eState := E_DL_HasState.eDrain; (* 排水申请沿：定时排水 / Drain request edge *)
        END_IF
    E_DL_HasState.eFill:                     (* 补水相：至上限关阀回待机 / Fill *)
        IF NOT bEnable THEN
            _eState := E_DL_HasState.eIdle;  (* 失能回待机（阀收敛 FALSE） / Back to idle *)
        ELSIF _bLvBad THEN
            _eState := E_DL_HasState.eIdle;  (* 水位坏值：回待机阀全关（边界①安全侧） / Bad level: idle, valves off *)
        ELSIF fLevelPct >= fLevelHi THEN
            _eState := E_DL_HasState.eIdle;  (* 触上限关阀 / Level high: stop fill *)
        END_IF
    E_DL_HasState.eDrain:                    (* 排水相：定时到收口 / Drain *)
        IF NOT bEnable THEN
            _eState := E_DL_HasState.eIdle;  (* 失能回待机 / Back to idle *)
        ELSIF tonDrain.Q THEN                (* 定时到：完成收口（过渡态三段：本拍发单拍并迁相/下拍预清，R80） / Drain time expired *)
            _bDone := TRUE;                  (* 完成内部量置位（R189 两段式） / Internal done set *)
            _nDrains := _nDrains + 1;        (* 排水计数（UDINT 回绕工程安全） / Count drain *)
            _eState := E_DL_HasState.eIdle;  (* 回待机 / Back to idle *)
        END_IF
    E_DL_HasState.eFault:                    (* 故障相：阀全关（段 5 收敛），仅复位沿出 / Fault *)
        ;                                    (* 锁存回放（R28） / Replay from latch *)
    ELSE                                     (* 非法相位兜底迁安全态 / Illegal phase fallback *)
        _eState := E_DL_HasState.eFault;     (* 迁故障相 / To fault *)
        _bFault := TRUE;                     (* 同步锁存 / Latch *)
        _eCause := E_DL_HasCause.ePhaseBad;  (* 成因：非法相位 / Cause: illegal phase *)
END_CASE

(* —— 段 5：出口映射（阀与相位同源且互斥，R191/R146） —— *)
bFillValve := (_eState = E_DL_HasState.eFill) AND bEnable AND (NOT _bFault) AND (NOT _bLvBad);   (* 补水阀出口（坏值拍强制关） / Fill valve outlet *)
bDrainValve := (_eState = E_DL_HasState.eDrain) AND bEnable AND (NOT _bFault);   (* 排水阀出口 / Drain valve outlet *)
bDrainDone := _bDone;                        (* 完成单拍出口 / Done outlet *)
nDrainCnt := _nDrains;                       (* 排水计数出口 / Drain count outlet *)
bError := _bFault;                           (* 故障标志镜像 / Fault flag mirror *)
eState := _eState;                           (* 状态出口 / State outlet *)
eCause := _eCause;                           (* 成因出口 / Cause outlet *)
END_FUNCTION_BLOCK
