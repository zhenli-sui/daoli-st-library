(*==============================================================================
 * 组件名称 (Component)  : FB_DL_GatedUpdateFilter
 * 所属子库 (Sublibrary) : DL_Algo
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON），零厂商私有库
 * 功能描述 (Function)   : 门控更新滤波：**仅在允许窗口内采样，窗口外保持上次值**。
 *                         与低通 / 限速不同，本件不做任何数值整形，只决定「这一拍要不要采纳」，
 *                         因此阶跃与斜率在窗口内原样通过（无失真、无滞后）。
 *                         典型用途：剔除运动段/换型段的动态值、只在静止窗口内采重量、
 *                         只在保压阶段记录压力稳态值。
 *                         窗口外持续时长用 TON 累计；超过 tMaxHold 置 bStale=TRUE（信息级），
 *                         提示上游「数据已陈旧」，但**输出仍保持**（保持语义不变）。
 *                         恢复路径：bGate 重新为 TRUE 即回到新鲜；故障态由 bEnable 跌落或 bReset 解除。
 * 接口     (Interface)  : 输入 bEnable 使能、bReset 复位到当前输入、fIn 采样输入 [EU]、
 *                         bGate 窗口使能（TRUE = 本拍采纳）、tMaxHold 允许的最大保持时长 [s]；
 *                         输出 fOut 输出值 [EU]、bStale 数据是否陈旧、tHeldElapsed 已保持时长 [s]、
 *                         bValid 输出有效、bError、uErrorId。
 * 边界     (Boundary)   : ① 属主边界：只做门控与保持，不做平滑、不做离群剔除（另件）。
 *                         ② 非有限输入防御：窗口内（bGate=TRUE）遇非有限值 → 故障态 16#0006_0002，
 *                         输出冻结；窗口外（bGate=FALSE）不读取 fIn，故非有限值不判故障
 *                         （这是本件的语义：窗口外输入无意义）。
 *                         ③ tMaxHold < 0 钳到 T#0S 并置信息码 16#0006_0001；T#0S 表示不判陈旧
 *                         （bStale 恒 FALSE，TON 的 Q 仍按 PT=0 立即为真，故显式屏蔽）。
 *                         ④ **TON 无条件每周期调用**（R7），位于 CASE 之外。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_HoldLastGoodFilter` 分工：坏值（判据失效）保持归那件、
 *                         时间窗门控归本件；与 `FB_DL_PeakHoldFilter` 分工：峰值保持归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 16#0006_0000 无故障 / 16#0006_0001 保持时长非法已钳位（信息级）/
 *                         16#0006_0002 窗口内输入非有限（故障级）/ 16#0006_0005 非法状态（故障级）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限拒绝（仅窗口内）+ 时长域闸 + 无除法 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ 四态 ENUM + CASE + ELSE 兜底 ｜ R7 ✓ TON 实例 CASE 外无条件刷新
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 12）
 * 验收向量 (Acceptance) : ① bGate=TRUE 时 fIn 由 10 变 20 → 当拍 fOut=20；
 *                         ② 随后 bGate=FALSE 且 fIn=99 → fOut 保持 20（不采纳）, bStale=FALSE（未超时）；
 *                         ③ bGate 持续 FALSE 超过 tMaxHold=T#1S → bStale=TRUE，fOut 仍保持 20；
 *                         ④ bGate=TRUE 且 fIn=NaN → uErrorId=16#0006_0002，bError=TRUE，fOut 冻结；
 *                         ⑤ tMaxHold=T#0S → bStale 恒 FALSE（显式屏蔽）。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_GatedUpdState（门控更新状态机，归属 DL_Algo，与本件同文件，全库唯一属主）
 *-----------------------------------------------------------------------------
 * 过渡态说明：eInit --(首拍)--> eRun；eRun --(bGate=TRUE)--> eRun（更新）；
 * eRun --(bGate=FALSE)--> eRun（保持）；任一态 --(bEnable=FALSE)--> eHold；
 * 任一态 --(非有限/非法参数)--> eFault；eFault --(bEnable=FALSE 或 bReset)--> eInit。
 *----------------------------------------------------------------------------*)
TYPE E_DL_GatedUpdState :
(
    eInit  := 0,    // 首扫 / 复位后：输出直取输入 / First scan or after reset: output follows input
    eRun   := 10,   // 运行态：窗口内更新、窗口外保持 / Running: update inside window, hold outside
    eHold  := 20,   // 保持态：未使能，输出冻结 / Hold: disabled, output frozen
    eFault := 99    // 故障态：输出冻结，等待 bEnable 跌落或 bReset / Fault: frozen until cleared
);
END_TYPE

FUNCTION_BLOCK FB_DL_GatedUpdateFilter
VAR_INPUT
    bEnable  : BOOL := FALSE;      // 使能，FALSE 冻结输出 / Enable, FALSE freezes output
    bReset   : BOOL := FALSE;      // 复位到当前输入（单拍有效） / Reset to current input, single scan
    fIn      : LREAL := 0.0;       // 采样输入 [EU] / Sampling input [EU]
    bGate    : BOOL := FALSE;      // 窗口使能，TRUE = 本拍采纳输入 / Gate, TRUE adopts the input this scan
    tMaxHold : TIME := T#5S;       // 允许的最大保持时长，T#0S = 不判陈旧 [s] / Max hold duration, zero disables staleness
END_VAR
VAR_OUTPUT
    fOut         : LREAL;   // 门控输出 [EU] / Gated output [EU]
    bStale       : BOOL;    // 数据陈旧标志（信息级） [-] / Data staleness flag, info level
    tHeldElapsed : TIME;    // 已保持时长 [s] / Elapsed hold duration
    bValid       : BOOL;    // 输出有效标志 [-] / Output valid flag
    bError       : BOOL;    // 故障标志，与 uErrorId 联动 [-] / Fault flag coupled with uErrorId
    uErrorId     : UDINT;   // 故障码，0 = 无故障 [-] / Error code, zero means healthy
END_VAR
VAR
    tonHold  : TON;                  // 保持时长计时器（无条件每周期刷新） / Hold timer, refreshed unconditionally
    eState   : E_DL_GatedUpdState;   // 状态机当前状态 [-] / Current state
END_VAR
VAR CONSTANT
    DL_GUF_ZERO_L : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_GUF_ZERO_T : TIME := T#0S;    // 时长零基准 [s] / Zero duration base
END_VAR

(* —— 段 1：时长域闸（不中断扫描，只钳位并置信息码） —— *)
uErrorId := 16#0006_0000;                          // 预置无故障 / Preset healthy
IF tMaxHold < DL_GUF_ZERO_T THEN
    tMaxHold := DL_GUF_ZERO_T;                     // 负时长钳到零 / Negative duration clamped
    uErrorId := 16#0006_0001;                      // 信息级：时长已钳位 / Info: duration clamped
END_IF

(* —— 段 2：非有限防御（仅窗口内读取 fIn；窗口外输入无意义，不判故障） —— *)
IF bEnable AND bGate THEN
    IF (fIn <> fIn) OR ((fIn - fIn) <> DL_GUF_ZERO_L) THEN
        eState   := eFault;                        // 强制故障态 / Force fault state
        uErrorId := 16#0006_0002;                  // 故障级：窗口内输入非有限 / Fault: non-finite input inside window
    END_IF
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

(* —— 段 5：计时器无条件每周期刷新（R7 硬要求，位于 CASE 之外） —— *)
(* 计时条件：已使能、非故障、且当前不在窗口内（窗口外才累计「陈旧」时长） *)
(* Timer runs only when enabled, healthy, and outside the gate window *)
tonHold(IN := bEnable AND (eState <> eFault) AND (NOT bGate), PT := tMaxHold);

(* —— 段 6：主状态机（CASE 覆盖 + ELSE 兜底） —— *)
CASE eState OF

    eInit:
        fOut         := fIn;                       // 首拍直取输入 / First scan follows input
        bStale       := FALSE;                     // 首拍不判陈旧 / No staleness on first scan
        tHeldElapsed := tonHold.ET;
        bValid       := TRUE;
        eState       := eRun;

    eRun:
        IF bGate THEN
            fOut   := fIn;                         // 窗口内：原样采纳（无失真、无滞后） / Inside window: adopt raw
            bStale := FALSE;                       // 数据新鲜 / Data fresh
        ELSE
            (* 窗口外：fOut 保持上拍值，不做任何改写（保持语义核心） *)
            (* Outside window: hold previous output unchanged, core hold semantics *)
            IF (tMaxHold = DL_GUF_ZERO_T) THEN
                bStale := FALSE;                   // T#0S = 不判陈旧（显式屏蔽） / Zero disables staleness
            ELSE
                bStale := tonHold.Q;               // 超时才置陈旧 / Stale only after timeout
            END_IF
        END_IF
        tHeldElapsed := tonHold.ET;
        bValid       := TRUE;

    eHold:
        (* 未使能：输出与计时保持冻结 / Disabled: output and timer frozen *)
        bStale       := bStale;
        tHeldElapsed := tonHold.ET;
        bValid       := FALSE;

    eFault:
        (* 故障态：输出冻结保持上拍值（不推 0），计时器仍刷新 / Fault: output frozen, timer refreshed *)
        tHeldElapsed := tonHold.ET;
        bValid       := FALSE;

    ELSE
        eState   := eFault;
        bValid   := FALSE;
        uErrorId := 16#0006_0005;                  // 故障级：非法状态 / Fault: illegal state

END_CASE;

(* —— 段 7：出口映射（bError 与 uErrorId 同源；bStale 为信息级不置 bError） —— *)
bError := (uErrorId <> 16#0006_0000) AND (uErrorId <> 16#0006_0001);

END_FUNCTION_BLOCK
