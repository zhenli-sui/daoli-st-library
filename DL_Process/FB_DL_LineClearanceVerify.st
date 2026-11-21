(*
  ==================================================================
  组件名 Component  : FB_DL_LineClearanceVerify
  分类   Category   : DL_Process
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 高
  版本   Version    : 1.0.1
  功能   Purpose    : 换型清线验证（清料确认 + 残留计数 + 阶段确认窗状态机 + 超窗升级码）。
  来源   Source     : self-std（换型清线公开工艺语义自研）
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / CASE），三平台通用
  分工声明 Split     : 与 FB_DL_ChangeoverSequence（换型顺控属主）与
                      FB_DL_ShiftHandoverCheck（交接检查属主）分工——本件只做
                      换型时点的清线验证闭环（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : E_DL_ClearPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 残留计数清零判据用整数精确比较（uResidueCnt = 0，禁浮点）；
                      二 同拍竞态先消化确认沿再判超窗（R275 模板：段 3 预消化
                         确认沿，段 4 才判窗口到期迁移）；
                      三 快照/计数出口纳入复位清单（R243）：复位沿清残留计数、
                         清阶段计数与迁相位（R311 作用域逐项声明）；
                      四 组态窗非法（tConfirmWin ≤ 0 或 nResidueMax < 0）判故障
                         锁存（3038）；超窗升级独立码 3037（R190 归因唯一）；
                      五 CASE 必带 ELSE 兜底；TON/R_TRIG 段 0 无条件刷新（R7），
                         TON IN 串故障锁存门控（FB50-1）；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0005_3036【信息级】清线确认窗内残留计数超过 nResidueMax 时逐拍提示
                            （默认 0 = 残留非零即提示）；不锁存、不置 bError、
                            不阻断放行（口径以实现为准，v1.0.1 注释订正）
    16#0005_3037【故障级】阶段确认窗到期仍未确认，升级锁存至复位沿
    16#0005_3038【故障级】组态非法（确认窗 ≤ 0 或残留上限 < 0），锁存至复位沿
  码位口径   Code Note :
    3036 为信息级，在段 5 的 ELSIF 链中固定排于故障回放之后（链末位），
    故故障相下 3036 不可能覆盖已置的故障码（R190 归因唯一 + R285 分级纪律）；
    3036 逐拍重算不锁存，残留计数回落至上限以内即自动消失。
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 无残留、窗内确认沿 → bClearOk 单拍、无故障
    V2 残留 3 件逐件出清后确认 → 计数 3、bClearOk 单拍
    V3 窗到期未确认 → 码 3037、eFault、锁存待复位
    V4 nResidueMax=0、残留 1 件 → eErr=3036、bError=FALSE（信息级不置故障）
    V5 nResidueMax=3、残留 2 件 → eErr=0（允许残留）；残留 4 件 → 3036
    V6 窗非法（tConfirmWin ≤ 0）且残留超限 → 3038 优先，3036 不覆盖
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 4 · 序号 16）
    2026-11-21  v1.0.1  R62-D6 返修：①头注释 3036 口径订正为「确认窗内残留超 nResidueMax 逐拍提示（默认 0 = 非零即提示）；不锁存、不置 bError、不阻断放行」；②引脚注释补默认语义；③复核 3036 在 ELSIF 链末位不覆盖故障码（行为零变更）
  ==================================================================
*)
TYPE E_DL_ClearPhase :
(
    eIdle     := 0,  // 空闲：等清线请求沿 / idle, waiting for the clearance request edge
    eSweep    := 10, // 清料相：残留逐件出清 / the sweeping phase, the residues leaving one by one
    eConfirm  := 20, // 确认相：阶段确认窗内等确认沿 / the confirm phase inside the window
    eFault    := 30  // 故障：超窗或组态非法，锁存待复位 / fault, the overrun or the illegal configuration latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_LineClearanceVerify
VAR_INPUT
    bClearReq    : BOOL := FALSE;  // 清线请求电平，上升沿发起 / the clearance request level
    bItemOut     : BOOL := FALSE;  // 出料口有料电平 [-] / the item present level at the outlet
    bClearConfirm: BOOL := FALSE;  // 清线确认电平，上升沿确认 / the clearance confirm level
    bReset       : BOOL := FALSE;  // 故障复位电平，上升沿清锁存 / the fault reset level
    tConfirmWin  : TIME := T#60S;  // 阶段确认窗时长 [毫秒] / the confirm window duration
    nResidueMax  : DINT := 0;      // 残留计数上限 [件]，≥ 0；默认 0 即残留非零即提示，调大则该量残留仍允许放行 / the residue count bound, non negative; zero means any residue hints, a larger bound tolerates that many residues
END_VAR
VAR_OUTPUT
    uResidueCnt : UDINT := 0;              // 本轮残留计数 [件] / the residue count of this round
    bClearOk    : BOOL := FALSE;           // 清线通过单拍脉冲 [-] / the clearance passed one shot pulse
    eState      : E_DL_ClearPhase;         // 主状态机当前态 [状态] / the current state
    bError      : BOOL := FALSE;           // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    eErr        : UDINT := 16#0000_0000;   // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit     : BOOL := FALSE;                            // 首拍初始化标志（R310）/ the first scan flag
    _eState    : E_DL_ClearPhase := E_DL_ClearPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFault    : BOOL := FALSE;                            // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _bCfgBad   : BOOL := FALSE;                            // 组态非法标记（逐拍重算入锁存）/ the configuration fault flag
    _uResidue  : UDINT := 0;                               // 残留计数副本 [件] / the residue count copy
    _bOk       : BOOL := FALSE;                            // 通过单拍内部位，段 1 预清段 5 映射 / the internal ok bit
    _bEvtTaken : BOOL := FALSE;                            // 本拍确认沿已消化标记（R275）/ the confirm edge consumed flag
    _bCfgLatch : BOOL := FALSE;                            // 组态锁存副本（与 _bCfgBad 区分：锁存型）/ the configuration latch copy
    rtReq      : R_TRIG;  // 清线请求沿实例，段 0 无条件刷新 / the request edge instance
    rtItem     : R_TRIG;  // 出料沿实例，段 0 无条件刷新 / the item out edge instance
    rtConfirm  : R_TRIG;  // 确认沿实例，段 0 无条件刷新 / the confirm edge instance
    rtReset    : R_TRIG;  // 复位沿实例，段 0 无条件刷新 / the reset edge instance
    tonWin     : TON;     // 阶段确认窗定时器，段 0 无条件刷新 / the confirm window timer
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；TON IN 串故障锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtReq(CLK := bClearReq); // 请求沿 / the request edge
rtItem(CLK := bItemOut); // 出料沿 / the item out edge
rtConfirm(CLK := bClearConfirm); // 确认沿 / the confirm edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
tonWin(IN := (_eState = E_DL_ClearPhase.eConfirm) AND (NOT _bFault), PT := tConfirmWin); // 确认窗：仅确认相且无锁存时计时 / the window timing only in the confirm phase

// 段 1｜首拍初始化与单拍标志预清（R310 / FB32-1 / R256）/ segment 1, the first scan init and the preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _bCfgLatch := FALSE; // 组态锁存显式清零 / clear the configuration latch explicitly
    _uResidue := 0; // 残留计数显式清零 / clear the residue count explicitly
    _eState := E_DL_ClearPhase.eIdle; // 状态显式落空闲 / place the state to idle
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清锁存 + 清计数 + 迁相位，R311 / R243 声明）/ the reset edge with the declared scope
    _bFault := FALSE; // 清故障锁存（解除路径：复位沿恒可达，R152 自证）/ clear the fault latch
    _bCfgLatch := FALSE; // 清组态锁存 / clear the configuration latch
    _uResidue := 0; // 清残留计数（R243 快照/计数出口入复位清单）/ clear the residue count
    _eState := E_DL_ClearPhase.eIdle; // 迁回空闲 / back to idle
END_IF
_bOk := FALSE; // 通过单拍预清零 / preset the ok bit false
_bEvtTaken := FALSE; // 确认沿消化标记预清零 / preset the consumed flag false
_bCfgBad := FALSE; // 组态标记预清零 / preset the configuration flag false

// 段 2｜组态域闸（边界四）/ segment 2, the configuration gate
IF (tConfirmWin <= T#0S) OR (nResidueMax < 0) THEN // 窗非法或上限负 / an illegal window or a negative bound
    _bCfgBad := TRUE; // 置组态标记 / raise the configuration flag
    _bCfgLatch := TRUE; // 锁存组态故障（3038）/ latch the configuration fault
    _bFault := TRUE; // 总锁存（段 4 迁移）/ latch the total fault
END_IF

// 段 3｜本拍确认沿预消化（R275：合法事件先于窗口到期迁移消化）/ segment 3, the confirm edge pre digest
IF rtConfirm.Q AND (_eState = E_DL_ClearPhase.eConfirm) AND (NOT _bFault) THEN // 确认相内的确认沿 / a confirm edge inside the confirm phase
    _bEvtTaken := TRUE; // 标记本拍已消化（段 4 不再判超窗）/ mark the edge consumed this scan
    _bOk := TRUE; // 置通过单拍 / raise the ok bit
    _eState := E_DL_ClearPhase.eIdle; // 迁回空闲（本轮通过）/ back to idle with the round passed
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 兜底；超窗迁移让位于本拍确认沿，边界二）/ segment 4, the main machine
CASE _eState OF
    E_DL_ClearPhase.eIdle: // 空闲相 / the idle phase
        IF rtReq.Q AND (NOT _bFault) THEN // 请求沿 + 闸位复检（R274）/ the request edge with the gate recheck
            _uResidue := 0; // 新一轮残留计数归零（整数精确） / reset the residue count by the exact integer
            _eState := E_DL_ClearPhase.eSweep; // 迁入清料相 / enter the sweeping phase
        END_IF
    E_DL_ClearPhase.eSweep: // 清料相：残留逐件出清 / the sweeping phase
        IF rtItem.Q THEN // 出料沿：残留计一件 / an item out edge counts one residue
            _uResidue := _uResidue + 1; // 残留计数推进 / advance the residue count
        END_IF
        IF (NOT bItemOut) AND (NOT rtItem.Q) THEN // 出料口已空且本拍无新出料沿（整数域判据，边界一）/ the outlet empty with no new edge
            _eState := E_DL_ClearPhase.eConfirm; // 迁入确认相（确认窗起算）/ enter the confirm phase
        ELSIF _bFault THEN // 前置条件消失出口 / the prerequisite gone exit
            _eState := E_DL_ClearPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_ClearPhase.eConfirm: // 确认相（本拍确认沿已在段 3 消化并迁出，边界二）/ the confirm phase, the edge already digested in segment three
        IF tonWin.Q AND (NOT _bEvtTaken) THEN // 窗口到期且本拍无确认沿（R275 同拍竞态口径）/ the window expired with no confirm edge this scan
            _bFault := TRUE; // 锁存超窗故障（3037，升级码）/ latch the overrun fault
        ELSIF _bFault THEN // 前置条件消失 / the prerequisite gone
            _eState := E_DL_ClearPhase.eFault; // 迁入故障相 / enter the fault phase
        END_IF
    E_DL_ClearPhase.eFault: // 故障相：等复位沿（解除可达，边界三）/ the fault phase until the reset
        IF NOT _bFault THEN // 锁存已清才迁出（防清锁同拍重锁，FB50-1）/ the exit after the latch cleared
            _eState := E_DL_ClearPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_ClearPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置锁存 / latch the fault
END_CASE

// 段 5｜统一出口（内部副本单点映射；故障码锁存回放，R187）/ segment 5, the unified outlet
uResidueCnt := _uResidue; // 残留计数出口 / the residue count outlet
bClearOk := _bOk; // 通过单拍出口 / the ok pulse outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    IF _bCfgLatch THEN // 组态成因（独立码值，R190）/ the configuration cause
        eErr := 16#0005_3038; // 故障级：组态非法 / fault grade, the illegal configuration
    ELSE // 超窗成因 / the overrun cause
        eErr := 16#0005_3037; // 故障级：确认窗到期未确认，升级 / fault grade, the overrun escalated
    END_IF
ELSIF (_uResidue > DINT_TO_UDINT(nResidueMax)) OR (nResidueMax < 0) THEN // 残留超限提示（信息级，排在故障回放之后即链末位，不覆盖故障码，R285）/ the residue over the bound, informational and last in the chain so it never covers a fault code
    eErr := 16#0005_3036; // 信息级：残留计数非零超提示限 / informational, the residues over the hint bound
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
