(*
    FC_DL_SelEx —— 双通道选择泛型防御包装（REAL 域）
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
    功能说明  : 双通道选择：bG=FALSE 选 fI0、bG=TRUE 选 fI1，选择运算用比较与
                IF/ELSE 实现（IEC SEL 语义），不重实现任何数学内核；
                选中通道非有限（NaN 或 ±INF）判为故障级 16#0001_02AC，返回 0.0 且 bValid=FALSE；
                未选中通道（备用通道）非有限仅置信息级 16#0001_01D4 记录，
                不影响本拍输出（输出仍为选中通道的有效值，bError=FALSE、bValid=TRUE）；
                选中与未选中同时异常时，故障级优先（返回 0.0）；
                ±INF 采用平台安全幅值比较判定（阈值高于 REAL 最大有限值 3.402823E38），NaN 用自不等判定；
                钳位方向：无钳位（故障拦截 / 信息记录，输出为通道原值或 0.0）。
    错误码    : 16#0001_02AC 选中通道非有限（NaN 或 ±INF）——故障级，返回 0.0
                16#0001_01D4 未选中通道（备用通道）非有限，仅记录——信息级，不影响本拍输出
                16#0001_01D5 预留禁用（信息级，不得挪用）
                16#0001_02AD 预留禁用（故障级，不得挪用）
                16#0001_02AE 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_SelEx : REAL
VAR_INPUT
    bG  : BOOL; // 选择输入，FALSE 选 fI0、TRUE 选 fI1 / select input, FALSE picks fI0, TRUE picks fI1
    fI0 : REAL; // 通道 0 输入 [无量纲] / channel 0 input
    fI1 : REAL; // 通道 1 输入 [无量纲] / channel 1 input
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
    fSel      : REAL; // 选中通道值 [无量纲] / selected channel value
    bSelBad   : BOOL; // 选中通道非有限判定结果 / non-finite detection result of selected channel
    bIdleBad  : BOOL; // 未选中通道非有限判定结果 / non-finite detection result of unselected channel
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_SelEx := 0.0; // 故障缺省返回 0 [无量纲] / fault default returns 0
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 / preset invalid, set TRUE after guard passes

// 段 2｜通道选择与选中/未选中通道有限性判定 / segment 2, channel selection and finiteness check of both channels
IF bG THEN
    fSel := fI1; // TRUE 选通道 1 / TRUE picks channel 1
    bIdleBad := (fI0 <> fI0) OR (fI0 > DL_REAL_INF_GUARD) OR (fI0 < -DL_REAL_INF_GUARD); // 未选中通道 fI0 非有限判定 [无量纲] / unselected fI0 non-finite check
ELSE
    fSel := fI0; // FALSE 选通道 0 / FALSE picks channel 0
    bIdleBad := (fI1 <> fI1) OR (fI1 > DL_REAL_INF_GUARD) OR (fI1 < -DL_REAL_INF_GUARD); // 未选中通道 fI1 非有限判定 [无量纲] / unselected fI1 non-finite check
END_IF
bSelBad := (fSel <> fSel) OR (fSel > DL_REAL_INF_GUARD) OR (fSel < -DL_REAL_INF_GUARD); // 选中通道非有限判定（NaN 自不等 + 安全幅值判 ±INF） / selected channel non-finite check (NaN by self-inequality, +/-INF by safe magnitude)

// 段 3｜防御闸与输出（末段，故障级优先） / segment 3, guard and output (final, fault level first)
IF bSelBad THEN
    FC_DL_SelEx := 0.0;       // 故障级返回 0 [无量纲] / fault level returns 0
    eErr   := 16#0001_02AC;   // 选中通道非有限故障码 / selected channel non-finite fault id
    bError := TRUE;           // 置故障标志 / set fault flag
    bValid := FALSE;          // 输出无效 / output invalid
    RETURN;                   // 立即返回 / immediate return
ELSIF bIdleBad THEN
    FC_DL_SelEx := fSel;      // 输出选中通道原值，备用通道异常不影响本拍输出 / output selected value, idle channel anomaly does not affect this cycle
    eErr := 16#0001_01D4;     // 信息级：备用通道异常仅记录 / info level: idle channel anomaly recorded only
ELSE
    FC_DL_SelEx := fSel;      // 双通道均有限，正常输出选中值 / both channels finite, normal selected output
    eErr := 0; // 无错误 / no error
END_IF
bError := FALSE; // 信息级记录不置故障，故障分支已提前返回 / info-level record never raises fault, fault branch has returned
bValid := TRUE;  // 选中通道输出有效可用 / selected channel output is valid
END_FUNCTION
