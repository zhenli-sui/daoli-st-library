(*
    FC_DL_MinNanEx —— 三输入取小内建防御包装（LREAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / MinMax
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建函数 MIN，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 三输入取小：返回 fA、fB、fC 中的最小值，比较内核委托平台
                内建 MIN，不重实现任何数学内核；
                四段式口径（R45①）：返回值与错误码预置安全值 → 非有限域闸命中
                不调内建直接 RETURN → 域内委托内建 MIN → 结果非有限复检兜底；
                任一输入非有限判为故障级 16#0001_03CA，返回 0.0 且 bValid=FALSE
                （NaN 参与 MIN 比较在三平台传播行为不一致，一律拦截）；
                非有限判定口径（R15）：NaN 用自不等 f <> f 判定；±Inf 用
                (f − f) <> (f − f) 差值自减判定（有限值差恒为 0，无穷处产 NaN），
                禁用近似幅值阈值——LREAL 最大有限值 1.7976931348623157E308 之上
                无可表常量，近似阈值会在近似带内制造假阳性。
    错误码    : 16#0001_03CA 任一输入非有限（NaN 或 ±Inf）——故障级，返回 0.0
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 1 · T0 快车道）
*)
FUNCTION FC_DL_MinNanEx : LREAL
VAR_INPUT
    fA : LREAL; // 候选值一 [无量纲] ｜ first candidate value
    fB : LREAL; // 候选值二 [无量纲] ｜ second candidate value
    fC : LREAL; // 候选值三 [无量纲] ｜ third candidate value
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_03XX=fault level
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR
    bBad : BOOL;  // 三输入非有限判定结果（NaN 或 ±Inf）｜ non-finite detection result of the three inputs
    fOut : LREAL; // 内建 MIN 结果暂存，供出口复检 ｜ staging of the MIN result for exit recheck
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_MinNanEx := 0.0; // 故障缺省返回 0 [无量纲] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes
fOut   := 0.0;   // 暂存清零 ｜ clear the staging value

// 段 2｜三输入非有限防御闸（命中不调内建，早退） ｜ segment 2, non-finite guard of the three inputs (early return, no built-in call)
bBad := (fA <> fA) OR ((fA - fA) <> (fA - fA))
     OR (fB <> fB) OR ((fB - fB) <> (fB - fB))
     OR (fC <> fC) OR ((fC - fC) <> (fC - fC)); // 三输入非有限判定：NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ non-finite check: NaN by self-inequality, +/-Inf by self-subtraction
IF bBad THEN
    FC_DL_MinNanEx := 0.0;  // 故障级返回 0 [无量纲] ｜ fault level returns 0
    eErr   := 16#0001_03CA; // 非有限输入故障码 ｜ non-finite input fault id
    bError := TRUE;         // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;        // 输出无效 ｜ output invalid
    RETURN;                 // 早退，不调内建 ｜ early return, no built-in call
END_IF

// 段 3｜域内委托内建 MIN 内核 ｜ segment 3, delegate to the built-in MIN kernel in domain
fOut := MIN(fA, fB, fC); // 三输入取小委托内建 [无量纲] ｜ three-input minimum delegated to the built-in

// 段 4｜结果复检兜底（理论不可达：有限值的 MIN 恒有限） ｜ segment 4, exit recheck (unreachable: MIN of finite values is finite)
IF (fOut <> fOut) OR ((fOut - fOut) <> (fOut - fOut)) THEN
    FC_DL_MinNanEx := 0.0;  // 复检失败按非有限处置 [无量纲] ｜ recheck failure treated as non-finite
    eErr   := 16#0001_03CA; // 复用非有限输入码（同因同码，不新占码位）｜ reuse the non-finite code (same cause, no new code)
    bError := TRUE;         // 置故障标志 ｜ raise the fault flag
    bValid := FALSE;        // 输出无效 ｜ output invalid
    RETURN;                 // 早退 ｜ early return
END_IF

// 段 5｜出口装配 ｜ segment 5, exit assembly
FC_DL_MinNanEx := fOut; // 取小结果直通 ｜ minimum result pass-through
bError := FALSE;        // 正常出口不置故障 ｜ normal exit raises no fault
bValid := TRUE;         // 输出有效可用 ｜ output valid
END_FUNCTION
