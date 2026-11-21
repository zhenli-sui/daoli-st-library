(*
    FC_DL_RealToDintSat —— LREAL/REAL 到 DINT 饱和防御降型
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托平台内建 LREAL_TO_DINT 转换语义，外围统一错误码/钳位/
                  双语文档；未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 将 LREAL 输入（REAL 实参按标准隐式升位传入）防御性降型为 DINT
                并作为返回值输出，转换内核委托平台内建 LREAL_TO_DINT（向零截断），
                不重实现任何转换内核；
                非有限输入（NaN 或 ±Inf）判为故障级 16#0001_03CD，返回 0 且
                bValid=FALSE（非有限值参与降型在三平台行为不一致，一律拦截）；
                越界双侧显式钳位（R55/R241：跨类型降型禁靠隐式回绕兜底）：
                fIn > 2147483647.0 钳至 DINT 上界，置信息级 16#0001_0493；
                fIn < −2147483648.0 钳至 DINT 下界，置信息级 16#0001_0494；
                双侧直比判定，禁用 ABS 单侧判据（有符号最小值取 ABS 回绕会漏判）；
                转换前置域闸（先判域后转换）：域闸命中不调内建转换，
                保证 LREAL_TO_DINT 只接收域内可表值，杜绝降型溢出方向翻转；
                信息级码属正常防御：bError=FALSE、bValid=TRUE，输出钳位后防御值。
    错误码    : 16#0001_03CD 非有限输入（NaN 或 ±Inf）——故障级，返回 0
                16#0001_0493 输入超 DINT 上界 2147483647，已钳至上界——信息级，正常防御
                16#0001_0494 输入低于 DINT 下界 −2147483648，已钳至下界——信息级，正常防御
                （R90 反证句：越上界与越下界两场景均无法由返回值加 bValid 组合区分——
                  钳位后输出为合法边界值，bValid=TRUE 与域内转换相同，若共用一码则
                  现场无法还原越界方向，故两侧各占一码）
    非有限口径 : NaN 用自不等 f <> f，±Inf 用 (f − f) <> (f − f) 差值自减判定（R15）；
                LREAL 最大有限值之上无可表常量，禁用近似幅值阈值。
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 2 · T0 快车道）
*)
FUNCTION FC_DL_RealToDintSat : DINT
VAR_INPUT
    fIn : LREAL; // 待降型输入 [无量纲]，REAL 实参按标准升位传入 ｜ input to down-convert, REAL arguments widen by standard rules
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_04XX=info, 16#0001_03XX=fault
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_DINT_MAX_R : LREAL := 2.147483647E9;  // DINT 上界 2147483647 的 LREAL 承载值 [无量纲] ｜ DINT upper bound 2147483647 carried in LREAL
    DL_DINT_MIN_R : LREAL := -2.147483648E9; // DINT 下界 −2147483648 的 LREAL 承载值 [无量纲] ｜ DINT lower bound −2147483648 carried in LREAL
END_VAR
VAR
    bNonFinite : BOOL; // 非有限（NaN 或 ±Inf）判定结果 ｜ non-finite (NaN or +/-Inf) detection result
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_RealToDintSat := 0; // 故障缺省返回 0 [无量纲] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸（命中不调内建转换，早退） ｜ segment 2, non-finite guard (early return, no built-in conversion)
bNonFinite := (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn)); // NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ NaN by self-inequality, +/-Inf by self-subtraction
IF bNonFinite THEN
    FC_DL_RealToDintSat := 0; // 故障级返回 0 [无量纲] ｜ fault level returns 0
    eErr   := 16#0001_03CD;   // 非有限输入故障码 ｜ non-finite input fault id
    bError := TRUE;           // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;          // 输出无效 ｜ output invalid
    RETURN;                   // 早退，不调内建转换 ｜ early return, no built-in conversion
END_IF

// 段 3｜越界双侧显式钳位与域内转换（末段，先判域后转换） ｜ segment 3, double-side explicit clamp and in-domain conversion (final, domain check before conversion)
IF fIn > DL_DINT_MAX_R THEN
    FC_DL_RealToDintSat := 2147483647;  // 越上界钳至 DINT 上界 [无量纲] ｜ above upper bound, clamp to the DINT upper bound
    eErr := 16#0001_0493;               // 信息级：越上界已钳位 ｜ info level: above upper bound, clamped
ELSIF fIn < DL_DINT_MIN_R THEN
    FC_DL_RealToDintSat := -2147483648; // 越下界钳至 DINT 下界 [无量纲] ｜ under lower bound, clamp to the DINT lower bound
    eErr := 16#0001_0494;               // 信息级：越下界已钳位 ｜ info level: under lower bound, clamped
ELSE
    FC_DL_RealToDintSat := LREAL_TO_DINT(fIn); // 域内委托平台内建降型转换（向零截断）｜ in-domain delegate to the built-in down-conversion (truncate toward zero)
    eErr := 0;                                 // 域内无错误 ｜ in-domain, no error
END_IF
bError := FALSE; // 信息级钳位不置故障，故障分支已提前返回 ｜ info-level clamp never raises fault, fault branch has returned
bValid := TRUE;  // 域内或钳位输出均有效可用 ｜ in-domain or clamped output is valid
END_FUNCTION
