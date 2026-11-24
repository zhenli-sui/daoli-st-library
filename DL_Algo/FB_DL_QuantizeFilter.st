(*==============================================================================
 * 组件名称 (Component)  : FB_DL_QuantizeFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ROUND / ABS），零厂商私有库
 * 功能描述 (Function)   : **量化取整 + 回差防抖**（有状态件）。
 *                         第一步量化：fQ := ROUND(fIn / fStep) × fStep（就近取整到步距倍数）；
 *                         第二步回差：仅当 |fQ - fOut| > fHyst 时才把 fOut 更新为 fQ，
 *                         否则保持。两步合起来解决「量化值在相邻两档之间反复跳」的现场顽症
 *                         （典型：0.5 单位步距的设定值显示与控制字抖动）。
 *                         与无状态取整 FC（FC_DL_QuantizeStep）的差别：那件每拍直接输出
 *                         量化值、无记忆；本件带上一档记忆与回差，切换次数显著下降。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 复位到当前量化值、fIn 采样输入 [EU]、
 *                         fStep 量化步距（必须 > 0） [EU]、fHyst 切换回差（>= 0） [EU]；
 *                         输出 fOut 量化并防抖后的输出 [EU]、fQuantized 原始量化值（诊断） [EU]、
 *                         bUpdated 本拍是否切换档位、bValid 输出有效、bError、uErrorId。
 * 边界     (Boundary)   : ① 属主边界：只做步距量化与回差防抖，不做死区保持（另件）、不做限速（另件）。
 *                         ② **除零防护（R4 硬要求）**：fStep 参与除法 fIn / fStep，
 *                         必须先判 fStep > 0，否则故障级 16#0009_0003，输出冻结。
 *                         fStep = 0 不允许「静默当直通」，否则调用方看不出配置错误。
 *                         ③ fHyst < 0 → 故障级 16#0009_0003（负回差等于放大抖动）。
 *                         ④ 非有限防御：fIn / fStep / fHyst 三个浮点入参逐一枚举。
 *                         ⑤ 取整一律用 ROUND（禁止 TRUNC(x)+1 这类手工进位）。
 *                         ⑥ 恢复路径：bEnable=FALSE 或 bReset=TRUE 解除故障态。
 *                         ⑦ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与无状态 `FC_DL_QuantizeStep` 分工：单拍取整归那件、
 *                         带记忆的回差防抖归本件；与 `FB_DL_DeadbandFilter` 分工：
 *                         连续量死区归那件、离散档位回差归本件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0009_0000 无故障 / 16#0009_0002 入参非有限（故障级）/
 *                         16#0009_0003 步距或回差非法（故障级）/ 16#0009_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 步距前置判零（除零防护）+ 三浮点入参非有限判 + ROUND 取整 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 N/A（无 TON / 边沿实例）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 15）
 * 验收向量 (Acceptance) : ① fStep=0.5, fHyst=0.2, fIn=1.24 → fQ=ROUND(2.48)×0.5=2×0.5=1.0，
 *                         |1.0 - fOut(初 0)|=1.0 > 0.2 → fOut=1.0, bUpdated=TRUE；
 *                         ② 随后 fIn=1.26 → fQ=ROUND(2.52)×0.5=3×0.5=1.5，|1.5-1.0|=0.5 > 0.2 → fOut=1.5；
 *                         ③ 随后 fIn=1.30 → fQ=1.5，|1.5-1.5|=0 <= 0.2 → fOut 保持 1.5, bUpdated=FALSE；
 *                         ④ fStep=0.0 → uErrorId=16#0009_0003，bError=TRUE（不静默直通）；
 *                         ⑤ fHyst=-0.1 → uErrorId=16#0009_0003，bError=TRUE。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_QuantState（量化防抖状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_QuantState :
(
    eInit  := 0,    // 首扫 / 复位后：输出直取当前量化值 / First scan or after reset: output equals quantized value
    eRun   := 10,   // 运行态：量化 + 回差判定 / Running: quantize plus hysteresis decision
    eHold  := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_QuantizeFilter
VAR_INPUT
    bEnable : BOOL := FALSE;   // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset  : BOOL := FALSE;   // 复位到当前量化值（单拍有效） / Reset to current quantized value, single scan
    fIn     : LREAL := 0.0;    // 采样输入 [EU] / Sampling input [EU]
    fStep   : LREAL := 1.0;    // 量化步距，必须 > 0 [EU] / Quantisation step, must be positive [EU]
    fHyst   : LREAL := 0.0;    // 切换回差，必须 >= 0 [EU] / Switching hysteresis, must be non-negative [EU]
END_VAR
VAR_OUTPUT
    fOut       : LREAL;   // 量化并防抖后的输出 [EU] / Quantised and debounced output [EU]
    fQuantized : LREAL;   // 原始量化值（诊断用） [EU] / Raw quantised value for diagnostics [EU]
    bUpdated   : BOOL;    // 本拍是否切换档位 [-] / Whether the output switched this scan
    bValid     : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError     : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId   : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    _bNonFin : BOOL;              // 入参非有限标志 [-] / Non-finite input flag
    _fRatio  : LREAL;             // 步距倍数（取整前） [-] / Step multiple before rounding
    eState   : E_DL_QuantState;   // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_QTF_ZERO : LREAL := 0.0;   // 零基准（含非有限判零） [-] / Zero base including non-finite probe
END_VAR

(* —— 段 1：非有限防御（fIn / fStep / fHyst 三入参逐一枚举） —— *)
uErrorId := 16#0009_0000;                          // 预置无故障 / Preset healthy
_bNonFin := (fIn <> fIn) OR ((fIn - fIn) <> DL_QTF_ZERO);            // 输入非有限 / Input non-finite
_bNonFin := _bNonFin OR (fStep <> fStep) OR ((fStep - fStep) <> DL_QTF_ZERO);   // 步距非有限
_bNonFin := _bNonFin OR (fHyst <> fHyst) OR ((fHyst - fHyst) <> DL_QTF_ZERO);   // 回差非有限
IF _bNonFin THEN
    eState   := eFault;                            // 强制故障态 / Force fault state
    uErrorId := 16#0009_0002;                      // 故障级：入参非有限 / Fault: non-finite input
END_IF

(* —— 段 2：步距与回差域闸（步距必须严格正：它是除数；回差必须非负） —— *)
IF (fStep <= DL_QTF_ZERO) OR (fHyst < DL_QTF_ZERO) THEN
    eState   := eFault;                            // 参数非法进故障态 / Illegal parameter goes to fault
    uErrorId := 16#0009_0003;                      // 故障级：步距或回差非法 / Fault: illegal step or hysteresis
    fQuantized := DL_QTF_ZERO;                     // 诊断量回 0 / Diagnostic value zeroed
END_IF

(* —— 段 3：复位请求 → 回首扫 —— *)
IF bReset THEN
    eState := eInit;
END_IF

(* —— 段 4：状态派生 —— *)
IF NOT bEnable THEN
    eState := eHold;                               // 未使能：冻结 / Disabled: freeze
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
        _fRatio     := fIn / fStep;                // 步距倍数（fStep 已在段 2 判正） / Step multiple, step proven positive
        fQuantized  := ROUND(_fRatio) * fStep;     // 就近量化（禁止 TRUNC+1 手工进位） / Nearest quantisation
        fOut        := fQuantized;                 // 首拍直取量化值 / First scan adopts quantised value
        bUpdated    := TRUE;
        bValid      := TRUE;
        eState      := eRun;

    eRun:
        _fRatio    := fIn / fStep;                 // 步距倍数 / Step multiple
        fQuantized := ROUND(_fRatio) * fStep;      // 就近量化 / Nearest quantisation
        IF ABS(fQuantized - fOut) > fHyst THEN
            fOut     := fQuantized;                // 超出回差：切换档位 / Beyond hysteresis: switch
            bUpdated := TRUE;
        ELSE
            (* 回差内：保持原档位，避免相邻档反复跳变 / Inside hysteresis: hold current step *)
            bUpdated := FALSE;
        END_IF
        bValid := TRUE;

    eHold:
        (* 未使能：输出、量化诊断值、切换标志全部冻结 / Disabled: output, diagnostic and flag frozen *)
        bUpdated := FALSE;
        bValid   := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值（不推 0，避免下游误判） / Fault: output frozen *)
        bUpdated := FALSE;
        bValid   := FALSE;

    ELSE
        eState     := eFault;
        bUpdated   := FALSE;
        bValid     := FALSE;
        fQuantized := DL_QTF_ZERO;
        uErrorId   := 16#0009_0005;                // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 6：出口映射（bError 与 uErrorId 同源；本件无信息级码） —— *)
bError := (uErrorId <> 16#0009_0000);

END_FUNCTION_BLOCK
