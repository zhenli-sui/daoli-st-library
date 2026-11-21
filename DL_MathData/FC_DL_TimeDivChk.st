(*
    FC_DL_TimeDivChk —— TIME 整数除法除零拦截与模长防御包装
    ------------------------------------------------------------------
    分类      : DL_MathData / TimeArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R16）
    ------------------------------------------------------------------
    功能说明  : TIME 整数除法：返回 tIn ÷ nDiv，TIME 算术委托 `÷` 运算符，
                不重实现任何时间运算内核；
                nDiv = 0 判为故障级 16#0001_02C7，返回 T#0S 且 bValid=FALSE（除零故障）；
                nDiv < 0 时取模长参与运算并置信息级 16#0001_01E6
                （TIME 无负语义，方向取模长，bError=FALSE、bValid=TRUE）；
                模长取负回绕防御：先将 INT 除子升位复制到 DINT 再取负，
                规避 INT 最小值 -32768 直接取负的回绕未定义行为；
                除法前已强制判定除子非零（nDiv = 0 分支提前拦截），满足除法前判除子红线；
                钳位方向：无钳位（除零故障拦截 / 负除子模长化记录）。
    错误码    : 16#0001_02C7 除数为 0（除零故障）——故障级，返回 T#0S
                16#0001_01E6 负除子输入，已按模长参与运算——信息级，正常防御
                16#0001_01E7 预留禁用（信息级，不得挪用）
                16#0001_02C8 预留禁用（故障级，不得挪用）
                16#0001_02C9 预留禁用（故障级，不得挪用）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-16 v1.0.0 首次入库（R16）
*)
FUNCTION FC_DL_TimeDivChk : TIME
VAR_INPUT
    tIn  : TIME; // 输入时长（被除数） [ms] / input duration (dividend)
    nDiv : INT;  // 除子 [倍]，非 0，除零为故障 / divisor [x], nonzero, div-by-zero is a fault
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常 / error id, 0=ok
    bError : BOOL;  // 是否出错，eErr 非 0 时为 TRUE / error flag, TRUE when eErr is nonzero
    bValid : BOOL;  // 输出是否有效可用 / output valid flag
END_VAR
VAR CONSTANT
    DL_TIME_ZERO : TIME := T#0S; // TIME 零值（故障缺省返回） [ms] / TIME zero value (fault default return)
END_VAR
VAR
    nWiden : DINT; // 升位到 DINT 的除子副本 [倍] / divisor copy widened to DINT
    nAbs   : DINT; // 除子模长 [倍] / divisor magnitude
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_TimeDivChk := DL_TIME_ZERO; // 故障缺省返回 T#0S [ms] / fault default returns T#0S
eErr   := 0;     // 预置无错误 / preset no error
bError := FALSE; // 预置无故障 / preset no fault
bValid := FALSE; // 预置无效，通过除零闸后置位 / preset invalid, set TRUE after divide-by-zero guard

// 段 2｜除零故障闸 / segment 2, divide-by-zero fault guard
IF nDiv = 0 THEN
    FC_DL_TimeDivChk := DL_TIME_ZERO; // 故障级返回 T#0S [ms] / fault level returns T#0S
    eErr   := 16#0001_02C7;           // 除零故障码 / divide-by-zero fault id
    bError := TRUE;                   // 置故障标志 / set fault flag
    bValid := FALSE;                  // 输出无效 / output invalid
    RETURN;                           // 立即返回 / immediate return
END_IF

// 段 3｜除子模长整备（含取负回绕防御） / segment 3, divisor magnitude preparation with negation-wrap defense
nWiden := nDiv; // 先升位复制到 DINT / widen copy to DINT first
IF nDiv < 0 THEN
    nAbs := -nWiden; // DINT 域内取模长（规避 INT 最小值 -32768 取负回绕） / magnitude in DINT domain (avoids INT minimum -32768 negation wrap)
    eErr := 16#0001_01E6; // 信息级：负除子按模长处理（TIME 无负语义，方向取模长） / info level: negative divisor handled by magnitude (TIME has no negative semantics)
ELSE
    nAbs := nWiden; // 正除子模长即原值 / positive divisor, magnitude equals original
END_IF

// 段 4｜主体除法计算（末段） / segment 4, main division calculation (final)
FC_DL_TimeDivChk := tIn / nAbs; // 除子已判非零，模长参与委托 `÷` 运算符除法 / divisor checked nonzero, division via `÷` operator with magnitude
bError := FALSE; // 信息级模长化不置故障，除零分支已提前返回 / info-level magnitude never raises fault, divide-by-zero branch has returned
bValid := TRUE;  // 域内或模长化输出均有效可用 / in-domain or magnitude output is valid
END_FUNCTION
