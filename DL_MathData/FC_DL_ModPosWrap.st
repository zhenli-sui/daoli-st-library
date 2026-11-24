(*
    FC_DL_ModPosWrap —— 取模正值回绕（负余数归正）
    ------------------------------------------------------------------
    组件名称  : FC_DL_ModPosWrap
    分类      : DL_MathData / IntegerArith
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— IEC 61131-3 第 3 版整数 MOD 运算符的标准语义
                （余数符号随被除数，即截断除法口径）；本件把该口径**归一到
                非负区间**，即数学意义上的「正模」语义，供环形缓冲下标、
                角度索引、多工位轮转相位等需要恒非负余数的场合使用。
                clean-room 声明 —— 零代码行复制，仅调用平台内建 MOD 运算符，
                外围的域闸 / 归正 / 码位 / 双语文档全部自有。
                许可证 —— 本件 MIT；标准文本仅作语义引用，不构成代码许可继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 1 · N1）
    ------------------------------------------------------------------
    功能说明  : 计算 liValue 对 liMod 的非负取模，结果恒落在 [0, |liMod|) 区间。
                与库内既有件的分工（防止重复实现）：
                  FC_DL_ModPos（DL_MathData）为 DINT 版同类语义；
                  本件为 LINT 64 位版，并把「负模数」也纳入契约：libs 内建 MOD
                  在模数为负时余数符号不可直接用，本件显式归一，故返回值区间
                  与模数符号无关。
                归正算法的双语义兼容性（关键设计）：内建 MOD 在截断除法口径下
                返回负余数，在部分平台的实现中也可能已返回非负余数。本件仅做
                一次条件补正 —— 余数 < 0 时按模数符号分别 +m 或 -m —— 对两种
                内建语义均得到同一正确结果，不依赖平台细节。
                溢出安全性（逐分支论证）：设 m = |liMod| > 0，内建余数 r 满足
                |r| < m。r < 0 且 liMod > 0 时取 r + liMod，落在 (0, m) 内；
                r < 0 且 liMod < 0 时取 r - liMod 即 r + m，落在 (0, m) 内；
                两条路径的结果绝对值均小于 2^63，不存在 LINT 溢出；
                模数为 LINT 下界时 m 不可直接取绝对值，故本件**不对模数取绝对值**，
                只按符号选择运算方向，从而绕开 |LINT_MIN| 不可表示的问题。
    错误码    : 16#0002_0101 模数为 0（除零禁入），返回 0 —— 故障级
                16#0002_0102 保留（LINT 下界模数无需特殊处理，见上论证）—— 未用
    码位总账  : 16#0002_0101 用 ｜ 16#0002_0102 保留未用
    状态机    : R6 N/A —— 纯函数无状态，无跨周期驻留，无 CASE 可写
    边界与披露: 一 无定时器 / 无边沿实例 / 无除法 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址，纯引脚契约；
                三 bNegAdjusted 仅在「内建余数为负并被补正」时为 TRUE，
                   供上层统计平台语义差异，不参与任何判据；
                四 模数为 0 时按契约返回 0 且置故障级码，bValid = FALSE，
                   调用方必须用 bValid 或 bError 门控返回值，不得直取。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 1 · N1）
*)
FUNCTION FC_DL_ModPosWrap : LINT
VAR_INPUT
    liValue : LINT;                        (* 被除数（可为负），[计数] / the dividend, may be negative *)
    liMod   : LINT;                        (* 模数（非零），[计数]，符号自动归一 / the modulus, non-zero, sign normalised *)
END_VAR
VAR_OUTPUT
    eErr         : UDINT;                  (* 错误码，0 = 正常 / the error id, 0 = ok *)
    bError       : BOOL;                   (* 故障标志，故障级码时 TRUE / the error flag, TRUE on fault level *)
    bValid       : BOOL;                   (* 返回值可用，故障级为 FALSE / the return usable, FALSE on fault level *)
    bNegAdjusted : BOOL;                   (* 内建余数为负且已补正，[标志] / the negative remainder was corrected *)
END_VAR

// 段 1｜返回值与状态预置（四段式第一段）/ segment 1, preset the return and the status
FC_DL_ModPosWrap := 0;                 // 故障缺省返回 0 / the fault default returns 0
eErr         := 0;                     // 预置无错误 / preset no error
bError       := FALSE;                 // 预置无故障 / preset no fault
bValid       := FALSE;                 // 预置不可用，过闸后置位 / preset unusable, set TRUE after the gates
bNegAdjusted := FALSE;                 // 预置未补正 / preset not corrected

// 段 2｜除零域闸：模数为 0 结构早退，绝不落除法内核 / segment 2, the zero modulus gate, structural early return
IF liMod = 0 THEN                      // 模数为零即除零，禁入 / a zero modulus means a division by zero
    eErr   := 16#0002_0101;            // 故障级：模数为 0 / fault level: the modulus is zero
    bError := TRUE;                    // R45 配对置故障标志 / paired with the code
    bValid := FALSE;                   // 返回值不可用 / the return is unusable
    RETURN;                            // 结构早退，内建 MOD 不被触碰 / structural exit, the MOD kernel is never touched
END_IF

// 段 3｜委托内建 MOD 内核（模数已证非零）/ segment 3, delegate to the built-in MOD kernel
FC_DL_ModPosWrap := liValue MOD liMod; // 内建取模，余数符号随平台口径 / the built-in remainder, sign per the platform

// 段 4｜负余数归正：按模数符号选择补正方向，避免对 LINT 下界取绝对值 / segment 4, normalise a negative remainder
IF FC_DL_ModPosWrap < 0 THEN           // 内建余数为负（截断除法口径）/ a negative remainder, the truncated convention
    bNegAdjusted := TRUE;              // 记录已补正 / record the correction
    IF liMod > 0 THEN                  // 正模数：加模数即入正域 / a positive modulus, add it
        FC_DL_ModPosWrap := FC_DL_ModPosWrap + liMod;   // 结果落 (0, m) / the result lands in (0, m)
    ELSE                               // 负模数：减模数即加 |m|（不取绝对值，避开 LINT_MIN）/ a negative modulus, subtract it
        FC_DL_ModPosWrap := FC_DL_ModPosWrap - liMod;   // 结果落 (0, |m|) / the result lands in (0, |m|)
    END_IF
END_IF

// 段 5｜出口状态：域内委托结果恒可用 / segment 5, the outlet status, an in-domain result is always usable
bError := FALSE;                       // 本路径无故障 / no fault on this path
bValid := TRUE;                        // 余数可用 / the remainder is usable
END_FUNCTION
