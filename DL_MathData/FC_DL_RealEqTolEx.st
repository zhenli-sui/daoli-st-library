(*
    FC_DL_RealEqTolEx —— 浮点容差判等原子（LREAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Compare
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托 ABS 标准运算与比较语义，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 浮点容差判等原子：当 ABS(fA − fB) ≤ fTol 时判为相等（含边界，
                「差值不超过容差」即视为相等，全库口径统一按本件为准）；
                本件为红线 5「浮点判等禁用 = / <>」的库级原子化出口，
                全库判等口径以引用本件为准（语义引用，不强制实例化调用）；
                任一输入非有限（NaN 或 ±Inf）判为故障级 16#0001_03CB，
                返回 FALSE 且 bValid=FALSE（NaN 与任何值比较均无意义，一律拦截）；
                非有限判定口径（R15）：NaN 用自不等 f <> f，±Inf 用 (f − f) <> (f − f)；
                容差下限防死判：fTol 有限但小于容差下限 1.0E-9（含负值与 0）时
                钳至下限并置信息级 16#0001_0492——容差为 0 或近 0 会使判等恒 FALSE
                （浮点差值几乎不可能精确为 0，形成「死判」），下限钳位保证判等可用。
    错误码    : 16#0001_03CB 任一输入非有限（NaN 或 ±Inf）——故障级，返回 FALSE
                16#0001_0492 容差小于下限 1.0E-9（含负值与 0），已钳至下限——信息级，正常防御
                （R90 反证句：容差被钳这一事实无法由返回值观测——返回 TRUE 与 FALSE
                  均可能在钳位前后同时出现，现有输出组合无法还原「容差已被钳」场景，故占信息码）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 1 · T0 快车道）
*)
FUNCTION FC_DL_RealEqTolEx : BOOL
VAR_INPUT
    fA   : LREAL; // 比较左值 [无量纲] ｜ left comparand
    fB   : LREAL; // 比较右值 [无量纲] ｜ right comparand
    fTol : LREAL; // 容差 [无量纲]，小于下限或非正时钳至下限 ｜ tolerance, clamped to the floor when below it or non-positive
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_04XX=info, 16#0001_03XX=fault
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_TOL_FLOOR : LREAL := 1.0E-9; // 容差下限，防止零容差死判 [无量纲] ｜ tolerance floor, prevents the zero-tolerance dead comparison
END_VAR
VAR
    bBad    : BOOL;  // 三输入非有限判定结果（NaN 或 ±Inf）｜ non-finite detection result of the three inputs
    fTolEff : LREAL; // 整备后的有效容差 [无量纲] ｜ effective tolerance after preparation
    fDiff   : LREAL; // 两值差值绝对值 [无量纲] ｜ absolute difference of the two values
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_RealEqTolEx := FALSE; // 故障缺省返回不相等 ｜ fault default returns not-equal
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes

// 段 2｜三输入非有限防御闸（早退） ｜ segment 2, non-finite guard of the three inputs (early return)
bBad := (fA <> fA) OR ((fA - fA) <> (fA - fA))
     OR (fB <> fB) OR ((fB - fB) <> (fB - fB))
     OR (fTol <> fTol) OR ((fTol - fTol) <> (fTol - fTol)); // 三输入非有限判定：NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ non-finite check: NaN by self-inequality, +/-Inf by self-subtraction
IF bBad THEN
    FC_DL_RealEqTolEx := FALSE; // 故障级返回不相等 ｜ fault level returns not-equal
    eErr   := 16#0001_03CB;     // 非有限输入故障码 ｜ non-finite input fault id
    bError := TRUE;             // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;            // 输出无效 ｜ output invalid
    RETURN;                     // 早退 ｜ early return
END_IF

// 段 3｜容差下限钳位（防死判） ｜ segment 3, tolerance floor clamp (prevents the dead comparison)
IF fTol < DL_TOL_FLOOR THEN
    fTolEff := DL_TOL_FLOOR; // 容差钳至下限 [无量纲] ｜ tolerance clamped to the floor
    eErr    := 16#0001_0492; // 信息级：容差已钳下限 ｜ info level: tolerance clamped to the floor
ELSE
    fTolEff := fTol;         // 域内容差直通 [无量纲] ｜ in-domain tolerance pass-through
END_IF

// 段 4｜容差判等主体（末段） ｜ segment 4, tolerance equality body (final)
fDiff := ABS(fA - fB);       // 差值绝对值 [无量纲] ｜ absolute difference
IF fDiff <= fTolEff THEN
    FC_DL_RealEqTolEx := TRUE;  // 差值不超过有效容差，判相等（含边界）｜ difference within the effective tolerance, judged equal (boundary inclusive)
ELSE
    FC_DL_RealEqTolEx := FALSE; // 差值超容差，判不等 ｜ difference beyond the tolerance, judged not-equal
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 ｜ info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 判等输出有效可用 ｜ comparison output is valid
END_FUNCTION
