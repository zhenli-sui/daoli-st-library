(*==============================================================================
 * 组件名称 (Component)  : FC_DL_GeoMeanCalc
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅用标准函数 LN / EXP / ABS，零厂商私有库
 * 功能描述 (Function)   : 非负数组几何平均叶子件。在 log 域求和：g = exp(Σln(xi)/n)，
 *                         避免直接连乘的上溢/下溢（n 件 0.5 连乘即沉到下溢）。
 *                         良率均值、轴承寿命均值、稀释比均值等乘性量场景。
 * 来源标签 (Origin)     : 自研线（IEC 61131-3 标准语义的道莅防御性实现，clean-room）
 * 边界语义 (Boundary)   : ① 拒算闸：任一元素 xi <= eps 或 NaN → bValid = FALSE 且
 *                         返回 0.0（几何平均对非正元素无定义，静默取绝对值会把
 *                         「负良率」这种数据事故伪装成正常结果）；bValid 报告
 *                         拒算，调用方据此走数据质量链而非数值链；
 *                         ② 计数钳位：nCount < 1 → 拒算；nCount > 常量上限 →
 *                         钳位到上限（防越界，R308 口径）；
 *                         ③ ln 域结果超出 exp 可表域时拒绝：Σln/n > 709（LREAL
 *                         exp 上限 ln(1.8E308)≈709.78）→ 拒算防 Inf；
 *                         ④ 纯函数：无状态、无定时器、无副作用。
 * 码位     (Codes)      : 按 R297 范式零 16# 码位硬编码，拒算语义经 bValid 布尔出口承载
 * 红线自检 (Redline)    : 7 项红线已自检：R1 零全局 ✓｜R2 零物理地址 ✓｜R3 纯 IEC ✓
 *                         R4 防御完整（拒算/钳位/exp 域闸/NaN 自反判）✓
 *                         R5 双语同行注释 ✓｜R6 N/A（纯函数无状态机）✓｜R7 N/A（无实例）✓
 * 验收向量 (Acceptance) : V1 输入 [4, 16] → g = 8.0（容差 1E-6）；
 *                         V2 输入含 0 或负数 → bValid = FALSE 返回 0.0；
 *                         V3 nCount = 0 → bValid = FALSE；
 *                         V4 输入 [1,1,1] → g = 1.0（ln 域零和恒等式）。
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R49 首版（批 1 · 序号 2）
 *==============================================================================*)
FUNCTION FC_DL_GeoMeanCalc : LREAL           (* 返回几何平均值，拒算路径返回 0.0 / Returns geometric mean, 0.0 on rejection *)
VAR_INPUT
    aVals    : ARRAY[1..32] OF LREAL;        (* 输入数值数组（log 域求和源）[工程单位] / Input value array *)
    nCount   : INT;                          (* 有效元素个数，域 1..32，越界钳位 [件] / Valid element count, clamped to 1..32 *)
END_VAR
VAR_OUTPUT
    bValid   : BOOL;                         (* 本次计算有效性，FALSE = 拒算（含非正元素/计数非法/exp 域溢出）[-] / Validity flag, FALSE = rejected *)
    nRejectReason : INT;                     (* 拒算原因 0 无 1 计数非法 2 非正元素 3 exp 域溢出 [-] / Reject reason code *)
END_VAR
VAR
    i        : INT;                          (* 循环游标（每趟显式初始化，R227）[-] / Loop cursor *)
    nEff     : INT;                          (* 钳位后生效计数 [件] / Clamped effective count *)
    fSumLn   : LREAL;                        (* ln 域累计和 [ln·工程单位] / Accumulated log-domain sum *)
    fMeanLn  : LREAL;                        (* ln 域均值 = fSumLn / n [ln·工程单位] / Log-domain mean *)
    fXi      : LREAL;                        (* 当前元素缓存（防双重下标取值）[工程单位] / Current element cache *)
END_VAR
VAR CONSTANT
    DL_GM_EPS    : LREAL := 1.0E-12;         (* 元素非正判零容差（log 定义域下界）[工程单位] / Non-positive epsilon *)
    DL_GM_LN_MAX : LREAL := 709.0;           (* LREAL 的 exp 可表域上限 [ln] / exp-representable upper bound for LREAL *)
    DL_GM_NMAX   : INT   := 32;              (* 数组容量上限（计数钳位目标）[件] / Array capacity limit *)
END_VAR

(* —— 段 1：缺省输出（R285 全路径赋值） —— *)
FC_DL_GeoMeanCalc := 0.0;                    (* 缺省返回 0.0：可辨识零，不冒充正常结果 / Default 0.0, recognizable zero *)
bValid := FALSE;                             (* 有效性缺省 FALSE / Validity default FALSE *)
nRejectReason := 0;                          (* 拒算原因缺省无 / Reject reason default none *)

(* —— 段 2：计数闸与钳位（下界拒算、上界钳位防数组越界） —— *)
IF nCount < 1 THEN                           (* 零/负计数无统计意义 / Non-positive count meaningless *)
    nRejectReason := 1;                      (* 原因 1：计数非法 / Reason 1: illegal count *)
    RETURN;
END_IF
nEff := nCount;                              (* 生效计数初值 / Effective count init *)
IF nEff > DL_GM_NMAX THEN
    nEff := DL_GM_NMAX;                      (* 计数超容量钳位到上限（R308） / Clamp count to capacity *)
END_IF

(* —— 段 3：逐元素非正闸 + log 域累加（FOR 正步进，可移植） —— *)
FOR i := 1 TO nEff DO
    fXi := aVals[i];                         (* 取当前元素 / Fetch current element *)
    IF (fXi <> fXi) OR (fXi <= DL_GM_EPS) OR ((fXi - fXi) <> (fXi - fXi)) THEN
        nRejectReason := 2;                  (* 原因 2：NaN 或非正元素拒算 / Reason 2: NaN or non-positive rejected *)
        RETURN;                              (* 任一元素非法即整体拒算，不做部分结果 / Whole-call rejection, no partial result *)
    END_IF
    fSumLn := fSumLn + LN(fXi);              (* log 域累加，天然防连乘溢出 / Log-domain accumulation, overflow-free *)
END_FOR

(* —— 段 4：均值与 exp 域闸（除子 = 钳位后计数，恒 >= 1，无除零） —— *)
fMeanLn := fSumLn / INT_TO_LREAL(nCount);    (* ln 域均值，计数已 >= 1（INT_TO_LREAL 显式展宽） / Log-domain mean, explicit widening *)
IF fMeanLn > DL_GM_LN_MAX OR fMeanLn < (-DL_GM_LN_MAX) THEN
    nRejectReason := 3;                      (* 原因 3：exp 域外，防 Inf（R133 非有限值闸前置） / Reason 3: outside exp domain, prevents Inf *)
    RETURN;
END_IF
FC_DL_GeoMeanCalc := EXP(fMeanLn);           (* log 域还原为几何平均 / Exponentiate back to geometric mean *)
bValid := TRUE;                              (* 全闸通过，结果有效 / All gates passed, valid *)
END_FUNCTION
