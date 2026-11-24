(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DeadbandFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : **双向死区 + 输出保持**（有状态件）。规则：
 *                           |fIn - fOut| > fDeadband → fOut := fIn（采纳），bUpdated=TRUE；
 *                           否则 fOut 保持不动（抑制抖振），bUpdated=FALSE。
 *                         与无状态单值死区 FC（FC_DL_Deadband）的差别：那件每拍独立判断
 *                         「输入是否落在死区内并输出 0 或原值」，**不记忆历史**；
 *                         本件记忆上一输出，死区判定以**上一输出**为基准，
 *                         故能彻底消除阈值附近的来回抖动（迟滞特性），
 *                         但代价是引入 ≤ fDeadband 的稳态静差（现场需知悉）。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 复位输出到当前输入、fIn 采样输入 [EU]、
 *                         fDeadband 双向死区宽度 [EU]（>= 0）；
 *                         输出 fOut 输出值（保持语义） [EU]、bUpdated 本拍是否更新、
 *                         fDeviation 当前偏差 |fIn-fOut| [EU]、bValid 输出有效、
 *                         bError 故障标志、uErrorId 故障码。
 * 边界     (Boundary)   : ① 属主边界：只做死区保持，不做平滑 / 限速 / 量化（另件）。
 *                         ② fDeadband < 0 → 故障级 16#0008_0003（负死区会放大抖振，禁止钳位后静默放行）。
 *                         ③ fDeadband = 0 → 退化为直通（任何偏差都采纳），合法。
 *                         ④ 非有限防御：fIn 与 fDeadband 逐一枚举，命中即故障态 16#0008_0002，
 *                         输出冻结（不推 0）。
 *                         ⑤ 恢复路径：bEnable=FALSE 或 bReset=TRUE 均可解除故障态。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与无状态 `FC_DL_Deadband` 分工：单值死区归那件、带记忆的
 *                         死区保持归本件；与 `FB_DL_QuantizeFilter` 分工：量化+回差归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0008_0000 无故障 / 16#0008_0002 入参非有限（故障级）/
 *                         16#0008_0003 死区为负（故障级）/ 16#0008_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 双浮点入参非有限判 + 死区符号域闸 + 无除法 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 N/A（无 TON / 边沿实例）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 14）
 * 验收向量 (Acceptance) : ① fDeadband=2.0，fIn=10.0（fOut 初 0）→ |10-0|=10 > 2 → fOut=10.0, bUpdated=TRUE；
 *                         ② 随后 fIn=11.0 → |11-10|=1 <= 2 → fOut 保持 10.0, bUpdated=FALSE；
 *                         ③ 随后 fIn=12.5 → |12.5-10|=2.5 > 2 → fOut=12.5, bUpdated=TRUE；
 *                         ④ fDeadband=0.0 → 任何变化都采纳（直通），fOut=fIn；
 *                         ⑤ fDeadband=-1.0 → uErrorId=16#0008_0003，bError=TRUE，fOut 冻结。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DeadbandState（死区保持状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DeadbandState :
(
    eInit  := 0,    // 首扫 / 复位后：输出直取输入 / First scan or after reset: output follows input
    eRun   := 10,   // 运行态：死区外采纳、死区内保持 / Running: adopt outside band, hold inside band
    eHoldF := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_DeadbandFilter
VAR_INPUT
    bEnable   : BOOL := FALSE;   // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset    : BOOL := FALSE;   // 复位输出到当前输入（单拍有效） / Reset output to current input, single scan
    fIn       : LREAL := 0.0;    // 采样输入 [EU] / Sampling input [EU]
    fDeadband : LREAL := 0.5;    // 双向死区宽度，必须 >= 0 [EU] / Two-sided deadband width, must be non-negative [EU]
END_VAR
VAR_OUTPUT
    fOut      : LREAL;   // 输出值（死区内保持） [EU] / Output value, held inside the deadband [EU]
    bUpdated  : BOOL;    // 本拍是否更新输出 [-] / Whether the output updated this scan
    fDeviation: LREAL;   // 当前偏差 |fIn - fOut| [EU] / Current deviation [EU]
    bValid    : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError    : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId  : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    _bNonFin : BOOL;               // 入参非有限标志 [-] / Non-finite input flag
    eState   : E_DL_DeadbandState; // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_DBF_ZERO : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
END_VAR

(* —— 段 1：非有限防御（fIn 与 fDeadband 逐一枚举） —— *)
uErrorId := 16#0008_0000;                          // 预置无故障 / Preset healthy
_bNonFin := (fIn <> fIn) OR ((fIn - fIn) <> DL_DBF_ZERO);              // 输入非有限 / Input non-finite
_bNonFin := _bNonFin OR (fDeadband <> fDeadband) OR ((fDeadband - fDeadband) <> DL_DBF_ZERO);  // 死区非有限
IF _bNonFin THEN
    eState   := eFault;                            // 强制故障态 / Force fault state
    uErrorId := 16#0008_0002;                      // 故障级：入参非有限 / Fault: non-finite input
END_IF

(* —— 段 2：死区符号域闸（负死区会放大抖振，必须拒绝而非钳位） —— *)
IF fDeadband < DL_DBF_ZERO THEN
    eState   := eFault;
    uErrorId := 16#0008_0003;                      // 故障级：死区为负 / Fault: negative deadband
END_IF

(* —— 段 3：复位请求 → 回首扫 —— *)
IF bReset THEN
    eState := eInit;
END_IF

(* —— 段 4：状态派生 —— *)
IF NOT bEnable THEN
    eState := eHoldF;                              // 未使能：冻结 / Disabled: freeze
ELSIF eState = eFault THEN
    eState := eFault;                              // 故障态保持 / Fault holds
ELSIF eState = eInit THEN
    eState := eInit;                               // 首扫保持一拍 / Init holds one scan
ELSE
    eState := eRun;
END_IF

(* —— 段 5：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        fOut       := fIn;                         // 首拍直取输入 / First scan follows input
        fDeviation := DL_DBF_ZERO;
        bUpdated   := TRUE;
        bValid     := TRUE;
        eState     := eRun;

    eRun:
        fDeviation := ABS(fIn - fOut);             // 偏差以「上一输出」为基准（迟滞核心） / Deviation versus previous output
        IF fDeviation > fDeadband THEN
            fOut     := fIn;                       // 跳出死区：采纳新值 / Outside band: adopt
            bUpdated := TRUE;
        ELSE
            (* 死区内：fOut 保持不动，不做任何改写 / Inside band: hold unchanged *)
            bUpdated := FALSE;
        END_IF
        bValid := TRUE;

    eHoldF:
        (* 未使能：输出与偏差保持上拍值 / Disabled: output and deviation frozen *)
        bUpdated := FALSE;
        bValid   := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值（不推 0，避免下游误判为真实零） / Fault: output frozen *)
        bUpdated := FALSE;
        bValid   := FALSE;

    ELSE
        eState   := eFault;
        bUpdated := FALSE;
        bValid   := FALSE;
        uErrorId := 16#0008_0005;                  // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 6：出口映射（bError 与 uErrorId 同源；本件无信息级码） —— *)
bError := (uErrorId <> 16#0008_0000);

END_FUNCTION_BLOCK
