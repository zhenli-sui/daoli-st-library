(*
    FC_DL_LimitEx —— 三输入限幅泛型防御包装（REAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / MinMax
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : 三输入限幅：将 fIn 限制在 [fMin, fMax] 区间内，比较与选择
                运算用 IF/ELSE 实现（IEC LIMIT 语义），不重实现任何数学内核；
                防御性交换声明：fMin > fMax 时自动交换上下限并置信息级 16#0001_01DE
                （bError=FALSE、bValid=TRUE，保证限幅区间恒有效）；
                三输入任一非有限（NaN 或 ±INF）判为故障级 16#0001_02BB，
                返回 0.0 且 bValid=FALSE（非有限值参与限幅语义未定义，一律拦截）；
                钳位方向：域内值钳至 [下限, 上限] 区间（LIMIT 本义钳位）；
                ±INF 采用平台安全幅值比较判定（阈值高于 REAL 最大有限值 3.402823E38），NaN 用自不等判定。
    错误码    : 16#0001_02BB 任一输入非有限（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_01DE 上下限倒置，已自动交换（fMin 与 fMax 互换）——信息级，正常防御
                16#0001_01DF 预留禁用（信息级，不得挪用）
                16#0001_02BC 预留禁用（故障级，不得挪用）
                16#0001_02BD 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_LimitEx : REAL
VAR_INPUT
    fMin : REAL; // 限幅下限 [无量纲]，大于上限时自动交换 / lower limit, auto-swapped when greater than upper
    fIn  : REAL; // 限幅输入值 [无量纲] / value to be limited
    fMax : REAL; // 限幅上限 [无量纲]，小于下限时自动交换 / upper limit, auto-swapped when less than lower
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_REAL_INF_GUARD : LREAL := 4.0E38; // REAL 域 ±INF 判定阈值，高于 REAL 最大有限值 3.402823E38 [无量纲] / REAL +/-INF guard above max finite REAL 3.402823E38
END_VAR
VAR
    fLo    : REAL; // 整备后的限幅下限 [无量纲] / prepared lower bound
    fHi    : REAL; // 整备后的限幅上限 [无量纲] / prepared upper bound
    bBad   : BOOL; // 任一输入非有限判定结果 / non-finite detection result of any input
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LimitEx := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜三输入非有限防御闸 / segment 2, three-input non-finite guard
bBad := (fMin <> fMin) OR (fMin > DL_REAL_INF_GUARD) OR (fMin < -DL_REAL_INF_GUARD)
     OR (fIn  <> fIn)  OR (fIn  > DL_REAL_INF_GUARD) OR (fIn  < -DL_REAL_INF_GUARD)
     OR (fMax <> fMax) OR (fMax > DL_REAL_INF_GUARD) OR (fMax < -DL_REAL_INF_GUARD); // 三输入非有限判定（NaN 自不等 + 安全幅值判 ±INF） [无量纲] / all three inputs non-finite check (NaN by self-inequality, +/-INF by safe magnitude)
IF bBad THEN
    FC_DL_LimitEx := 0.0;     // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_02BB;   // 非有限输入故障码 / non-finite input fault id
    bError := TRUE;           // 置故障标志 / set fault flag
    bValid := FALSE;          // 输出无效 / output invalid
    RETURN;                   // 立即返回 / immediate return
END_IF

// 段 3｜上下限整备（含防御性交换） / segment 3, bound preparation with defensive swap
IF fMin > fMax THEN
    fLo := fMax; // 倒置时下限取原上限 / swapped: lower takes original upper
    fHi := fMin; // 倒置时上限取原下限 / swapped: upper takes original lower
    eErr := 16#0001_01DE; // 信息级：上下限倒置已自动交换 / info level: bounds inverted, auto-swapped
ELSE
    fLo := fMin; // 正常序下限直通 / normal order, lower passes through
    fHi := fMax; // 正常序上限直通 / normal order, upper passes through
END_IF

// 段 4｜主体限幅计算（末段） / segment 4, main limiting calculation (final)
IF fIn < fLo THEN
    FC_DL_LimitEx := fLo; // 低于下限，钳至下限 / below lower bound, clamp to lower
ELSIF fIn > fHi THEN
    FC_DL_LimitEx := fHi; // 高于上限，钳至上限 / above upper bound, clamp to upper
ELSE
    FC_DL_LimitEx := fIn; // 区间内直通 / inside bounds, pass through
END_IF
bError := FALSE; // 信息级交换不置故障，故障分支已提前返回 / info-level swap never raises fault, fault branch has returned
bValid := TRUE;  // 域内或限幅输出均有效可用 / in-domain or limited output is valid
END_FUNCTION
