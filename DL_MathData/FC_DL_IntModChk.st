(*
    FC_DL_IntModChk —— DINT 整数取模防御包装
    ------------------------------------------------------------------
    组件名称  : FC_DL_IntModChk
    分类      : DL_MathData / IntegerMod
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（IEC 61131-3 第三版
                整数除法「截断向零」条款 + 余数恒等式 r = a − trunc(a/b)·b
                的防御性落地）；取模语义与判据顺序参照库内 LREAL 域属主
                FC_DL_ModLrealSafe 的闸序（库内复用口径），实现 / 引脚名 /
                码位 100% 自有；clean-room 声明 —— 零代码行复制，无闭源参考。
    平台      : 纯 IEC 61131-3（LINT 64 位整数 + 标准 MOD / DIV 运算符），
                CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 1 · 序号 1）
    ------------------------------------------------------------------
    功能说明  : DINT 整数取模 a MOD b 的防御包装，真实工况：齿轮比约分、
                卷绕圈数余量、分度索引回绕前的余数预判。
                判据链顺序：
                ① 除零闸（b = 0 → 故障级早退，输出 0）——先判后除（红线 2）；
                ② DINT_MIN / −1 溢出面闸：被除数 = −2147483648 且除数 = −1 时
                   商 = +2147483648 超出 DINT 可表域（数学余数恒为 0，但三平台
                   MOD 内部实现可能经「先除后乘」路径内溢），此组合显式拦截出
                   信息级，输出确定值 0（数学事实不受影响）；
                ③ 负操作数语义写死：本件**不直接使用平台 MOD 运算符出结果**，
                   而是把两操作数升位到 LINT（64 位，全 DINT 域无损），按
                   IEC 61131-3「整数除法截断向零」标准条款以
                   r = a − trunc(a / b) × b 恒等式自算余数——结果符号**随被除数**
                   （与 C 系 % 口径一致，IEC MOD 主流口径），绝不依赖平台默认；
                ④ 出口（LINT_TO_DINT 降位前已证 |r| < |b| ≤ 2147483648 且
                   r ≠ −2147483648，降位无回绕面）。
                升位理由（可表性反算，R63 口径）：DINT_MIN 取绝对值会在 DINT
                域内回绕（|−2147483648| = 2147483648 > DINT_MAX），任何在
                DINT 域内自算绝对值的写法都带隐藏回绕面；LINT 域内
                ±2147483648 完全可表，升位后全部中间量无回绕。
    错误码    : 16#0002_3900 除数为 0（除零闸命中，输出 0）—— 故障级
                16#0002_3901 被除数 = DINT_MIN 且除数 = −1 的溢出面组合，
                            数学余数恒 0，输出确定值 0、bValid = TRUE —— 信息级，
                            不置 bError（R45）
                加码反证句（R90）：3901 场景（DINT_MIN/−1 组合）无法由「除零码 +
                正常返回值」组合观测——除零码下输出同为 0 但 bValid = FALSE 且
                语义是「除不了」，3901 语义是「可除但实现面危险」，输出组合不可
                互换观测，故立独立码。
    码位总账  : 16#0002_3900 用 ｜ 16#0002_3901 用
    状态机    : N/A —— 纯函数无状态，无 CASE 可写，非法状态不可能出现
    边界与披露: 一 无定时器 / 无沿检测实例 / 无数组下标，周期安全规则 N/A；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 整数进位点（终审两式 #2）验收向量：「除子恰为 0」→ 3900
                   故障级输出 0；「被除数 = DINT_MIN 且除子 = −1」→ 3901
                   信息级输出 0；负操作数四象限向量见验收段；
                四 除法面唯一（LINT 域 trunc(a/b)），除数已在段 3 闸为非零，
                   先判后除，无裸除法暴露；
                五 与 FC_DL_ModLrealSafe（DL_MathData，LREAL 浮点域）分工互引：
                   本件只做 DINT 整数域（DINT_MIN/−1 溢出面为浮点域不存在的
                   独立语义），浮点取模一律走属主件，本件不接 LREAL；
                六 依赖声明：仅 Standard.library（无内建函数依赖，LINT 运算符
                   与 DINT_TO_LINT / LINT_TO_DINT 标准转换），三平台无编译门槛。
    验收向量  : V1 (17, 5) → 2；V2 (−17, 5) → −2（符号随被除数）；
                V3 (17, −5) → 2；V4 (−17, −5) → −2；
                V5 (−2147483648, 5) → −3；V6 (−2147483648, −1) → 0 + 3901；
                V7 (x, 0) → 0 + 3900 故障级；V8 (0, 7) → 0。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 1 · 序号 1）
*)
FUNCTION FC_DL_IntModChk : DINT
VAR_INPUT
    nDividend : DINT;                      (* 被除数，[无量纲整数域] / the dividend, dimensionless integer *)
    nDivisor  : DINT;                      (* 除数，[无量纲整数域]，禁 0 / the divisor, must not be zero *)
END_VAR
VAR_OUTPUT
    bValid    : BOOL;                      (* 返回值（余数）可用标志，故障级为 FALSE / the remainder usable flag, FALSE on fault *)
    bError    : BOOL;                      (* 故障标志，仅故障级码置位（R45 配对）/ the fault flag, raised only on fault level codes *)
    nInfoCode : UDINT;                     (* 信息 / 错误码，0 = 正常 / the info or error id, 0 = ok *)
END_VAR
VAR CONSTANT
    DL_IMD_ZERO   : DINT := 0;             (* 整数零哨兵，除零闸用 [无量纲] / the integer zero sentinel for the divide gate *)
    DL_IMD_DMIN   : DINT := -2147483648;   (* DINT 下界常量（-2^31），溢出面闸用 [无量纲] / the DINT lower bound constant for the overflow gate *)
    DL_IMD_MONE   : DINT := -1;            (* 溢出面除数哨兵 −1 [无量纲] / the overflow gate divisor sentinel *)
END_VAR
VAR
    nLA      : LINT;                       (* 升位被除数（全 DINT 域无损）[无量纲] / the widened dividend *)
    nLB      : LINT;                       (* 升位除数 [无量纲] / the widened divisor *)
    nLQ      : LINT;                       (* LINT 域截断向零商（中间量）[无量纲] / the widened truncating quotient *)
    nLR      : LINT;                       (* LINT 域余数恒等式结果 [无量纲] / the widened remainder *)
END_VAR

// 段 1｜返回值与状态预置（统一出口预置，R256）/ segment 1, preset the return and the status
FC_DL_IntModChk := 0;                      // 故障缺省返回零余数 / the fault default is zero remainder
bValid    := FALSE;                        // 预置不可用，过闸后置位 / preset unusable, set TRUE after the gates
bError    := FALSE;                        // 预置无故障 / preset no fault
nInfoCode := 0;                            // 预置无错 / preset no error
nLA := 0;                                  // 升位中间量清零 / clear the widened dividend
nLB := 0;                                  // 升位中间量清零 / clear the widened divisor
nLQ := 0;                                  // 商中间量清零 / clear the quotient temporary
nLR := 0;                                  // 余数中间量清零 / clear the remainder temporary

// 段 2｜除零闸（先判后除，红线 2；除子恰为 0 验收向量在此命中）/ segment 2, the divide by zero gate
IF nDivisor = DL_IMD_ZERO THEN             // 除数为 0，取模无定义 / the divisor is zero, modulo undefined
    nInfoCode := 16#0002_3900;             // 故障级：除零 / fault level: divide by zero
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / the return unusable
    FC_DL_IntModChk := 0;                  // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / structural exit
END_IF

// 段 3｜DINT_MIN / −1 溢出面闸（商 +2147483648 超 DINT 可表域，防御性拦截）/ segment 3, the DINT_MIN over minus one overflow gate
IF (nDividend = DL_IMD_DMIN) AND (nDivisor = DL_IMD_MONE) THEN // 溢出面组合 / the overflow surface pair
    nInfoCode := 16#0002_3901;             // 信息级：溢出面组合拦截（数学余数恒 0）/ info level: the overflow pair intercepted, the remainder is zero
    bError := FALSE;                       // 信息级不置故障（R45 配对纪律）/ info level never raises a fault
    bValid := TRUE;                        // 数学余数恒为 0，值可用 / the mathematical remainder is zero, usable
    FC_DL_IntModChk := 0;                  // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF

// 段 4｜升位与余数恒等式（负操作数语义写死：r = a − trunc(a/b)·b，符号随被除数）/ segment 4, widen and apply the remainder identity
nLA := DINT_TO_LINT(nDividend);            // 被除数升位（全 DINT 域无损）/ widen the dividend lossless
nLB := DINT_TO_LINT(nDivisor);             // 除数升位 / widen the divisor
nLQ := nLA / nLB;                          // IEC 整数除法截断向零（除数已过闸非零）/ the IEC truncating division, divisor gated non zero
nLR := nLA - (nLQ * nLB);                  // 余数恒等式（符号随被除数，不依赖平台 MOD 口径）/ the remainder identity, sign follows the dividend

// 段 5｜降位可表性防线（|r| < |b| ≤ 2147483648 且 r ≠ −2147483648，结构性可证）/ segment 5, the narrowing guard
IF (nLR > DINT_TO_LINT(2147483647)) OR (nLR < DINT_TO_LINT(DL_IMD_DMIN)) THEN // 降位越域防御兜底（不可达，R151 收口纪律）/ the narrowing overflow guard, structurally unreachable
    nInfoCode := 16#0002_3900;             // 复用除零故障级（同属「结果不可信」类，R90 反证：不可达无观测需求）/ reuse the fault code, unreachable
    bError := TRUE;                        // R45 配对置故障标志 / paired with the fault flag
    bValid := FALSE;                       // 返回值不可用 / unusable
    FC_DL_IntModChk := 0;                  // 确定值零出口 / a deterministic zero outlet
    RETURN;                                // 结构早退 / exit
END_IF

// 段 6｜正常出口 / segment 6, the normal outlet
FC_DL_IntModChk := LINT_TO_DINT(nLR);      // 降位发布余数（符号随被除数）/ publish the remainder
bValid := TRUE;                            // 结果可用 / the result usable
END_FUNCTION
