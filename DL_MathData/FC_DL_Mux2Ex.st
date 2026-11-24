(*
    FC_DL_Mux2Ex —— 2 通道多路选择泛型防御包装（REAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Sel
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 2 通道多路选择：uK=0 选 fI0、uK=1 选 fI1，选择运算用比较与
                IF/ELSE 实现（IEC MUX 语义），不重实现任何数学内核；
                uK 超出 0~1 时防御性钳位至 1，置信息级 16#0001_01D6（bError=FALSE、bValid=TRUE）；
                钳位方向：选择子越界单侧钳至上界 1；
                选中通道非有限（NaN 或 ±INF）判为故障级 16#0001_02AF，返回 0.0 且 bValid=FALSE；
                ±INF 采用平台安全幅值比较判定（阈值高于 REAL 最大有限值 3.402823E38），NaN 用自不等判定。
    错误码    : 16#0001_01D6 选择子 uK 越界，已钳位至 1——信息级，正常防御
                16#0001_02AF 选中通道非有限（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_01D7 预留禁用（信息级，不得挪用）
                16#0001_02B0 预留禁用（故障级，不得挪用）
                16#0001_02B1 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_Mux2Ex : REAL
VAR_INPUT
    uK  : USINT; // 选择子 [通道号]，0~1，越界钳 1 / selector index [channel], 0~1, clamped to 1
    fI0 : REAL;  // 通道 0 输入 [无量纲] / channel 0 input
    fI1 : REAL;  // 通道 1 输入 [无量纲] / channel 1 input
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_MUX2_CH_MAX    : USINT := 1;     // 通道选择子上界 [通道号] / selector index upper bound
    DL_REAL_INF_GUARD : LREAL := 4.0E38; // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    uIdx      : USINT; // 钳位后的本地选择子 [通道号] / clamped local selector index
    fSel      : REAL;  // 选中通道值 [无量纲] / selected channel value
    bSelBad   : BOOL;  // 选中通道非有限判定结果 / non-finite detection result of selected channel
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_Mux2Ex := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜选择子越界钳位与通道选择 / segment 2, selector out-of-range clamp and channel selection
IF uK > DL_MUX2_CH_MAX THEN
    uIdx := DL_MUX2_CH_MAX; // 越界钳位至上界 1 / out-of-range clamped to upper bound 1
    eErr := 16#0001_01D6;   // 信息级：选择子越界已钳位 / info level: selector out of range, clamped
ELSE
    uIdx := uK; // 选择子在域内直通 / in-range selector passes through
END_IF
IF uIdx = 0 THEN
    fSel := fI0; // 通道 0 选中 / channel 0 selected
ELSE
    fSel := fI1; // 通道 1 选中（钳位后 uIdx 仅剩 0 或 1） / channel 1 selected (uIdx is only 0 or 1 after clamp)
END_IF

// 段 3｜选中通道防御闸与输出（末段） / segment 3, selected channel guard and output (final)
bSelBad := (fSel <> fSel) OR (fSel > DL_REAL_INF_GUARD) OR (fSel < -DL_REAL_INF_GUARD); // 选中通道非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / selected channel non-finite check (NaN by self-inequality, +/-INF by safe magnitude)
IF bSelBad THEN
    FC_DL_Mux2Ex := 0.0;      // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_02AF;   // 选中通道非有限故障码 / selected channel non-finite fault id
    bError := TRUE;           // 置故障标志 / set fault flag
    bValid := FALSE;          // 输出无效 / output invalid
    RETURN;                   // 立即返回 / immediate return
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 / info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 选中通道输出有效可用 / selected channel output is valid
FC_DL_Mux2Ex := fSel; // 输出选中通道值 [无量纲] / output selected channel value
END_FUNCTION
