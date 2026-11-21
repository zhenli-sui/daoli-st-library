(*
    FC_DL_RealToRealSat —— LREAL 到 REAL 饱和防御降型
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建 LREAL_TO_REAL 转换语义，外围统一错误码/钳位/
                  双语文档；未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 将 LREAL 输入防御性降型为 REAL 并作为返回值输出，转换内核
                委托平台内建 LREAL_TO_REAL，不重实现任何转换内核；
                非有限输入（NaN 或 ±Inf）判为故障级 16#0001_03CE，返回 0.0 且
                bValid=FALSE（非有限值参与降型在三平台行为不一致，一律拦截）；
                幅值越 REAL 域钳位：|fIn| 大于 REAL 最大有限值
                3.4028234663852886E38 时钳至 ±REAL 最大有限值，置信息级 16#0001_0495；
                判定阈值取 REAL 最大有限值的 LREAL 精度字面量（可表且不低于真值），
                阈值等于真上界，不存在近似假阳性带（R15 口径自证）；
                转换前置域闸（先判域后转换）：域闸命中不调内建转换，
                保证 LREAL_TO_REAL 只接收域内可表值，杜绝降型产出 Inf；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_03CE 非有限输入（NaN 或 ±Inf）或域闸后的转换复检失败——故障级，返回 0.0
                16#0001_0495 输入幅值超 REAL 最大有限值，已钳至 ±3.4028234663852886E38——信息级，正常防御
                （R90 反证句：幅值钳位场景无法由故障级组合观测——钳位输出 bValid=TRUE 且
                  值为有限边界值，与域内转换的输出组合（bValid=TRUE）在幅值贴近 REAL 上界时
                  仅凭返回值无法区分「原值近似」与「已钳位」，故占信息码）
    非有限口径 : NaN 用自不等 f <> f，±Inf 用 (f − f) <> (f − f) 差值自减判定（R15）。
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 2 · T0 快车道）
*)
FUNCTION FC_DL_RealToRealSat : REAL
VAR_INPUT
    fIn : LREAL; // 待降型输入 [无量纲] ｜ input to down-convert
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_04XX=info, 16#0001_03XX=fault
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_REAL_MAX_FIN : LREAL := 3.4028234663852886E38; // REAL 最大有限值（LREAL 精度字面量，恰为真上界）[无量纲] ｜ largest finite REAL as an LREAL literal (the true upper bound)
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±Inf）判定结果 ｜ non-finite (NaN or +/-Inf) detection result
    fOut       : REAL; // 降型结果暂存，供出口复检 ｜ staging of the converted result for exit recheck
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_RealToRealSat := 0.0; // 故障缺省返回 0 [无量纲] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes
fOut   := 0.0;   // 暂存清零 ｜ clear the staging value

// 段 2｜非有限防御闸（命中不调内建转换，早退） ｜ segment 2, non-finite guard (early return, no built-in conversion)
bNonFinite := (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn)); // NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ NaN by self-inequality, +/-Inf by self-subtraction
IF bNonFinite THEN
    FC_DL_RealToRealSat := 0.0; // 故障级返回 0 [无量纲] ｜ fault level returns 0
    eErr   := 16#0001_03CE;     // 非有限输入故障码 ｜ non-finite input fault id
    bError := TRUE;             // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;            // 输出无效 ｜ output invalid
    RETURN;                     // 早退，不调内建转换 ｜ early return, no built-in conversion
END_IF

// 段 3｜幅值域闸与降型转换（先判域后转换） ｜ segment 3, magnitude domain gate and down-conversion (domain check before conversion)
IF fIn > DL_REAL_MAX_FIN THEN
    fOut := 3.4028235E38;     // 正幅值越域钳至 REAL 最大有限值 [无量纲] ｜ positive magnitude clamped to the largest finite REAL
    eErr := 16#0001_0495;     // 信息级：幅值越 REAL 域已钳位 ｜ info level: magnitude beyond the REAL domain, clamped
ELSIF fIn < -DL_REAL_MAX_FIN THEN
    fOut := -3.4028235E38;    // 负幅值越域钳至 REAL 最小有限值 [无量纲] ｜ negative magnitude clamped to the smallest finite REAL
    eErr := 16#0001_0495;     // 信息级：幅值越 REAL 域已钳位（双侧共用幅值钳位码，方向由输出符号还原）｜ info level: clamped (both sides share the magnitude code, direction recovered from the output sign)
ELSE
    fOut := LREAL_TO_REAL(fIn); // 域内委托平台内建降型转换 ｜ in-domain delegate to the built-in down-conversion
    eErr := 0;                  // 域内无错误 ｜ in-domain, no error
END_IF

// 段 4｜结果复检兜底（理论不可达：域闸后的降型恒产出有限 REAL） ｜ segment 4, exit recheck (unreachable: in-domain down-conversion always yields a finite REAL)
IF (fOut <> fOut) OR ((LREAL_TO_REAL(fOut) - LREAL_TO_REAL(fOut)) <> (LREAL_TO_REAL(fOut) - LREAL_TO_REAL(fOut))) THEN
    FC_DL_RealToRealSat := 0.0; // 复检失败按非有限处置 [无量纲] ｜ recheck failure treated as non-finite
    eErr   := 16#0001_03CE;     // 复用非有限码（同因同码，不新占码位）｜ reuse the non-finite code (same cause, no new code)
    bError := TRUE;             // 置故障标志 ｜ raise the fault flag
    bValid := FALSE;            // 输出无效 ｜ output invalid
    RETURN;                     // 早退 ｜ early return
END_IF

// 段 5｜出口装配 ｜ segment 5, exit assembly
FC_DL_RealToRealSat := fOut; // 降型结果直通 ｜ converted result pass-through
bError := FALSE;             // 信息级钳位不置故障，故障分支已提前返回 ｜ info-level clamp never raises fault, fault branch has returned
bValid := TRUE;              // 域内或钳位输出均有效可用 ｜ in-domain or clamped output is valid
END_FUNCTION
