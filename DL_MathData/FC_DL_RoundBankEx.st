(*
    FC_DL_RoundBankEx —— ROUND 明确口径包装（银行家/半进可选，LREAL 域）
    ------------------------------------------------------------------
    分类      : DL_MathData / Rounding
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现
                （内部委托 TRUNC 标准函数与比较语义，外围统一错误码/钳位/双语文档；
                  未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可）
    平台      : 纯 IEC 61131-3，CODESYS / TwinCAT / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R40）
    ------------------------------------------------------------------
    功能说明  : 将 fIn 舍入到最近整数（仍以 LREAL 返回），0.5 进位方向全平台
                显式统一，杜绝 ROUND 内建在三平台的半进/半退差异泄漏：
                bHalfUp = FALSE（缺省）：0.5 进位到最近的偶数（银行家口径）；
                bHalfUp = TRUE：0.5 一律进位（向远离零方向，半进口径）；
                非半点小数一律按最近整数舍入（>0.5 进、<0.5 退）；
                非有限输入（NaN 或 ±Inf）判为故障级 16#0001_03CF，返回 0.0 且
                bValid=FALSE（NaN 参与舍入在三平台行为不一致，一律拦截）；
                超整数分辨率恒等直通：|fIn| ≥ 2^53（9.007199254740992E15）时
                该幅值下 LREAL 相邻可表数间距已大于 1，输入必为整数值，
                舍入恒等直通并置信息级 16#0001_0496；
                溢出面分析（R63 反算句）：|fIn| < 2^53 时结果 |fRnd| ≤ |fIn| + 1 ≤ 2^53，
                恒在 LREAL 可表域内，无溢出路径，无需饱和钳位（算法已证）；
                半点检测口径：ABS(fFrac − 0.5) < 1.0E-9 视为半点（差值在 1E-9 内的
                近半点值按半点口径处理，取舍显式化，避免浮点表示误差致半点漏判）。
    错误码    : 16#0001_03CF 任一输入非有限（NaN 或 ±Inf）——故障级，返回 0.0
                16#0001_0496 输入幅值 ≥ 2^53，超整数分辨率，恒等直通——信息级，正常防御
                （R90 反证句：恒等直通场景无法由返回值观测——直通值与舍入结果同为
                  合法整数值，bValid=TRUE 组合相同，现有输出无法还原「分辨率已耗尽」
                  事实，故占信息码）
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，
                非法状态不可能出现，故以本节说明替代 ELSE 兜底
    修订记录  : 2026-11-19 v1.0.0 首次入库（R40 · 批 2 · T0 快车道）
*)
FUNCTION FC_DL_RoundBankEx : LREAL
VAR_INPUT
    fIn     : LREAL;         // 待舍入输入 [无量纲] ｜ input to round
    bHalfUp : BOOL := FALSE; // 半点口径，FALSE=进位到最近偶数（银行家），TRUE=一律半进 ｜ half-point mode, FALSE=round half to even (banker's), TRUE=round half away from zero
END_VAR
VAR_OUTPUT
    eErr   : UDINT; // 错误码，0=正常，16#0001_04XX=信息级，16#0001_03XX=故障级 ｜ error id, 0=ok, 16#0001_04XX=info, 16#0001_03XX=fault
    bError : BOOL;  // 是否出错，eErr 落故障级时为 TRUE ｜ fault flag, TRUE when eErr is fault level
    bValid : BOOL;  // 输出是否有效可用 ｜ output valid flag
END_VAR
VAR CONSTANT
    DL_ROUND_ID_LIMIT : LREAL := 9.007199254740992E15; // 恒等直通幅值限 = 2^53 [无量纲] ｜ identity pass-through magnitude limit = 2^53
    DL_ROUND_HALF     : LREAL := 0.5;                  // 半点判据常数 [无量纲] ｜ half-point constant
    DL_ROUND_TOL      : LREAL := 1.0E-9;               // 半点检测容差 [无量纲] ｜ half-point detection tolerance
    DL_ROUND_ONE      : LREAL := 1.0;                  // 进位步长 [无量纲] ｜ carry step
    DL_ROUND_TWO      : LREAL := 2.0;                  // 偶数判定基数 [无量纲] ｜ even-test radix
END_VAR
VAR
    bNonFinite : BOOL;  // 非有限（NaN 或 ±Inf）判定结果 ｜ non-finite (NaN or +/-Inf) detection result
    fAbs       : LREAL; // 输入绝对值 [无量纲] ｜ absolute value of the input
    fInt       : LREAL; // 绝对值的整数部分（TRUNC 向零截断）[无量纲] ｜ integer part of the magnitude (TRUNC toward zero)
    fFrac      : LREAL; // 绝对值的小数部分 [无量纲] ｜ fractional part of the magnitude
    fRnd       : LREAL; // 舍入后的绝对值结果 [无量纲] ｜ rounded magnitude result
END_VAR

// 段 1｜返回值与错误状态预置 ｜ segment 1, preset return value and error status
FC_DL_RoundBankEx := 0.0; // 故障缺省返回 0 [无量纲] ｜ fault default returns 0
eErr   := 0;     // 预置无错误 ｜ preset no error
bError := FALSE; // 预置无故障 ｜ preset no fault
bValid := FALSE; // 预置无效，通过防御闸后置位 ｜ preset invalid, set TRUE after guard passes

// 段 2｜非有限防御闸（早退） ｜ segment 2, non-finite guard (early return)
bNonFinite := (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn)); // NaN 自不等 + 差值自减判 ±Inf [无量纲] ｜ NaN by self-inequality, +/-Inf by self-subtraction
IF bNonFinite THEN
    FC_DL_RoundBankEx := 0.0; // 故障级返回 0 [无量纲] ｜ fault level returns 0
    eErr   := 16#0001_03CF;   // 非有限输入故障码 ｜ non-finite input fault id
    bError := TRUE;           // 置故障标志（R45 配对）｜ raise the fault flag (R45 pairing)
    bValid := FALSE;          // 输出无效 ｜ output invalid
    RETURN;                   // 早退 ｜ early return
END_IF

// 段 3｜超整数分辨率恒等直通（信息级） ｜ segment 3, identity pass-through beyond integer resolution (info level)
IF ABS(fIn) >= DL_ROUND_ID_LIMIT THEN
    FC_DL_RoundBankEx := fIn; // 分辨率耗尽，舍入恒等直通 [无量纲] ｜ resolution exhausted, rounding is identity
    eErr   := 16#0001_0496;   // 信息级：超分辨率恒等直通 ｜ info level: identity pass-through beyond resolution
    bError := FALSE;          // 信息级不置故障 ｜ info level raises no fault
    bValid := TRUE;           // 直通输出有效 ｜ pass-through output is valid
    RETURN;                   // 早退 ｜ early return
END_IF

// 段 4｜绝对域分解与舍入主体（末段） ｜ segment 4, magnitude decomposition and rounding body (final)
fAbs  := ABS(fIn);        // 取绝对值 [无量纲] ｜ take the magnitude
fInt  := TRUNC(fAbs);     // 整数部分（TRUNC 向零截断，绝对域恒非负）｜ integer part (TRUNC toward zero, non-negative in magnitude domain)
fFrac := fAbs - fInt;     // 小数部分（fInt ≥ fAbs/2 或 fInt=0，减法在 2^53 内精确，无消去误差）｜ fractional part (subtraction exact below 2^53, no cancellation error)
IF ABS(fFrac - DL_ROUND_HALF) < DL_ROUND_TOL THEN
    // 半点口径：按 bHalfUp 显式分流 ｜ half-point mode: explicit branch by bHalfUp
    IF bHalfUp THEN
        fRnd := fInt + DL_ROUND_ONE;  // 半进口径：一律进位（远离零）｜ half-up mode: always carry (away from zero)
    ELSE
        // 银行家口径：进位到最近偶数（偶数判定用差值容差比较，禁浮点直等）｜ banker's mode: round half to even (even test by difference tolerance, no direct float equality)
        IF ABS(fInt - DL_ROUND_TWO * TRUNC(fInt / DL_ROUND_TWO)) < DL_ROUND_TOL THEN
            fRnd := fInt;                 // 整数部分为偶，退位保持 ｜ integer part even, keep it
        ELSE
            fRnd := fInt + DL_ROUND_ONE;  // 整数部分为奇，进位到偶 ｜ integer part odd, carry to even
        END_IF
    END_IF
ELSIF fFrac > DL_ROUND_HALF THEN
    fRnd := fInt + DL_ROUND_ONE;  // 非半点且大于半点，进位 ｜ beyond the half-point, carry
ELSE
    fRnd := fInt;                 // 非半点且小于半点，退位 ｜ below the half-point, keep
END_IF

// 段 5｜出口装配：恢复符号并单点写出 ｜ segment 5, exit assembly: restore the sign and write once
IF fIn < 0.0 THEN
    FC_DL_RoundBankEx := -fRnd; // 负输入恢复负号 [无量纲] ｜ negative input restores the sign
ELSE
    FC_DL_RoundBankEx := fRnd;  // 非负输入直通 [无量纲] ｜ non-negative input passes through
END_IF
bError := FALSE; // 正常出口不置故障 ｜ normal exit raises no fault
bValid := TRUE;  // 舍入输出有效可用 ｜ rounding output is valid
END_FUNCTION
