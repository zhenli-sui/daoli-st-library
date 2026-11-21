(*
  FB_DL_ToggleButtonBank  —  多路启停按钮组解算 / Multi-channel toggle button bank solver
  分类 Category : DL_Base
  码位 Code     : 16#01_0_01
  版本 Version  : 1.0.0
  来源 Source   : t1-5-tcopen — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : TCopen 按钮组/选择器公开语义借鉴，clean-room 实现，未复制任何源码行
  功能 Function : 1) 三种解算模式：Toggle 单按钮逐通道翻转锁存 / SingleAct 双按钮点动直通 / Selector3 三位置选择互斥；
                  2) Selector3 通道互斥：新通道置位时旧通道清零；同拍多键按「低通道号优先」并置信息码（不静默双通）；
                  3) 失电来电恢复策略 eRestorePolicy：Hold 保持（RETAIN 语义由上层承载）/ Reset 全清 / Pulse 上电首拍单周期 TRUE；
                  4) nActiveChannel 输出当前活动通道（0 = 无，1..n = 最低活动通道号，Selector3 即唯一互斥通道）。
  边界 Boundary : ① uChannelCount = 0 或 > nMaxCh 判组态错 bCfgFault，全输出 FALSE（安全侧）；
                  ② 8 路 R_TRIG 在主周期无条件刷新（调用语句不置于 IF/CASE 内，R182）；
                  ③ SingleAct 点动直通不锁存：输出 = 按钮实时电平（松开即断，无保持）；
                  ④ 解除式自证：bCfgFault 解除 = 下一拍 uChannelCount 落回合法域（每拍重算，无锁存）；
                  ⑤ Pulse 脉冲语义：仅上电首拍 abOut 全 TRUE 一个 PLC 周期，第二拍起恢复正常解算（注释标明，防误用为持续使能）。
  依赖 Depends  : 仅 Standard.library（R_TRIG）；枚举 E_DL_BtnMode / E_DL_RestorePolicy 随本件发布
  码表 Error codes（本件格 01_0_01，子码步进 +0x100）:
    16#0001_0101 信息级：Selector3 同拍多键，低通道号优先（不置故障）
    16#0001_0201 故障级：组态非法 uChannelCount = 0 或超数组上界
    16#0001_0301 信息级：Pulse 恢复策略上电首拍单周期脉冲（不置故障）

  修订历史 Revision :
    2026-11-18  v1.0.0  R38 首版
*)

TYPE E_DL_BtnMode :
(
    eToggle    := 0,   // 单按钮翻转锁存 / Single-button toggle with latch
    eSingleAct := 1,   // 点动直通（不锁存）/ Momentary passthrough, no latch
    eSelector3 := 2    // 三位置选择互斥 / Three-position selector, mutually exclusive
);
END_TYPE

TYPE E_DL_RestorePolicy :
(
    eHold  := 0,   // 上电保持断电前状态（RETAIN 由上层承载）/ Hold pre-power-loss state, retainment owned upstream
    eReset := 1,   // 上电全清零 / Clear all outputs at power-up
    ePulse := 2    // 上电首拍单周期 TRUE / Single-scan TRUE pulse at power-up
);
END_TYPE

FUNCTION_BLOCK FB_DL_ToggleButtonBank
VAR_INPUT
    abBtn          : ARRAY[0..7] OF BOOL;   // 按钮输入组 [0..nMaxCh-1] / Button inputs
    uChannelCount  : INT;                   // 有效通道数 [路]，域 1..nMaxCh / Valid channel count
    eMode          : E_DL_BtnMode;          // 解算模式 / Solver mode
    eRestorePolicy : E_DL_RestorePolicy;    // 失电来电恢复策略 / Power-restore policy
END_VAR
VAR_OUTPUT
    abOut          : ARRAY[0..7] OF BOOL;   // 通道输出组 / Channel outputs
    nActiveChannel : INT;                   // 活动通道号（0 = 无，1..n 最低活动）/ Active channel, 0 = none
    bCfgFault      : BOOL;                  // 组态非法（每拍重算）/ Configuration fault, recomputed
    nErrId         : UDINT;                 // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    artBtn     : ARRAY[0..7] OF R_TRIG;     // 逐通道按钮上升沿，段 0 无条件刷新 / Per-channel rising edges
    _abState   : ARRAY[0..7] OF BOOL;       // Toggle 模式锁存状态 / Toggle latched states
    _bFirstScan: BOOL := TRUE;              // 上电首拍标志 / First-scan-after-power-up flag
    _bSimulKey : BOOL;                      // 同拍多键标志（本拍重算）/ Simultaneous keys flag
    _k         : INT;                       // 循环计数器 / Loop counter
END_VAR
VAR CONSTANT
    nMaxCh : INT := 8;                      // 数组上界 [路] / Array upper bound
END_VAR

(* —— 段 0：R_TRIG 无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
FOR _k := 0 TO (nMaxCh - 1) DO
    artBtn[_k](CLK := abBtn[_k]);           // 逐通道上升沿，每拍必调
END_FOR

(* —— 段 1：单拍量预清零 —— *)
nErrId     := 16#0000_0000;               // 事件码缺省无事件
_bSimulKey := FALSE;                      // 多键标志预清零
FOR _k := 0 TO (nMaxCh - 1) DO
    abOut[_k] := FALSE;                   // 输出缺省 FALSE（安全侧缺省，段 4 单点置位）
END_FOR
nActiveChannel := 0;                      // 活动通道缺省无

(* —— 段 2：组态域闸（uChannelCount 全覆盖，每拍重算） —— *)
IF (uChannelCount <= 0) OR (uChannelCount > nMaxCh) THEN
    bCfgFault := TRUE;                    // 组态非法：全输出维持 FALSE（段 1 已清）
    nErrId    := 16#0001_0201;            // 故障级：组态非法
ELSE
    bCfgFault := FALSE;                   // 解除式自证：下一拍通道数合法即解除
END_IF

(* —— 段 3：上电首拍恢复策略（仅在组态合法时生效） —— *)
IF (NOT bCfgFault) AND _bFirstScan THEN
    CASE eRestorePolicy OF

    E_DL_RestorePolicy.eHold:
        ;                                  // 保持：_abState 维持 RETAIN 语义值（上层持久化承载）
    E_DL_RestorePolicy.eReset:
        FOR _k := 0 TO (nMaxCh - 1) DO
            _abState[_k] := FALSE;         // 上电全清
        END_FOR
    E_DL_RestorePolicy.ePulse:
        FOR _k := 0 TO (nMaxCh - 1) DO
            abOut[_k] := TRUE;             // 脉冲语义：置位 1 个 PLC 周期（规格强制，防误用为持续使能）
        END_FOR
        nErrId := 16#0001_0301;            // 信息级：Pulse 上电单拍脉冲
    ELSE
        nErrId := 16#0001_0201;            // 未知恢复策略按组态错兜底（安全侧全 FALSE）
        bCfgFault := TRUE;
    END_CASE
END_IF
_bFirstScan := FALSE;                     // 首拍标志自清

(* —— 段 4：三模式解算（组态合法才执行） —— *)
IF NOT bCfgFault THEN
    CASE eMode OF

    E_DL_BtnMode.eToggle:
        FOR _k := 0 TO (uChannelCount - 1) DO
            IF artBtn[_k].Q THEN
                _abState[_k] := NOT _abState[_k];   // 单按钮翻转锁存
            END_IF
            abOut[_k] := _abState[_k];              // 输出锁存态
        END_FOR

    E_DL_BtnMode.eSingleAct:
        FOR _k := 0 TO (uChannelCount - 1) DO
            abOut[_k] := abBtn[_k];                 // 点动直通：输出 = 按钮实时电平，松开即断
        END_FOR

    E_DL_BtnMode.eSelector3:
        FOR _k := 0 TO (uChannelCount - 1) DO
            IF abBtn[_k] THEN
                IF nActiveChannel = 0 THEN
                    nActiveChannel := _k + 1;       // 记录最低按下的通道号（低通道号优先）
                ELSE
                    _bSimulKey := TRUE;             // 同拍多键：置信息码（不做静默双通）
                END_IF
            END_IF
        END_FOR
        IF _bSimulKey THEN
            nErrId := 16#0001_0101;                 // 信息级：同拍多键，低通道号优先
        END_IF
        IF nActiveChannel > 0 THEN
            FOR _k := 0 TO (uChannelCount - 1) DO
                _abState[_k] := (_k = (nActiveChannel - 1));   // 互斥：仅选中通道保持
                abOut[_k] := _abState[_k];
            END_FOR
        ELSE
            FOR _k := 0 TO (uChannelCount - 1) DO
                _abState[_k] := FALSE;              // 无键按下：互斥组全清
            END_FOR
        END_IF

    ELSE
        bCfgFault := TRUE;                          // 未知模式兜底：全 FALSE 安全侧
        nErrId := 16#0001_0201;                     // 故障级：组态非法（模式越界并入组态错）
    END_CASE
END_IF

(* —— 段 5：活动通道出口（Toggle/SingleAct 取最低活动通道） —— *)
IF (eMode = E_DL_BtnMode.eToggle) OR (eMode = E_DL_BtnMode.eSingleAct) THEN
    nActiveChannel := 0;                            // 缺省无
    FOR _k := 0 TO (uChannelCount - 1) DO
        IF abOut[_k] THEN
            nActiveChannel := _k + 1;               // 最低活动通道号
            EXIT;                                    // 找到即止
        END_IF
    END_FOR
END_IF

END_FUNCTION_BLOCK
