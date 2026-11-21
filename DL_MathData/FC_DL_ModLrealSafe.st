(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ModLrealSafe
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · LREAL 安全取模
 *                         iec-std-wrapper / math-safe
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 IEC 标准算术与 TRUNC 语义
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : LREAL 安全取模：除零与绝对小除数双闸、输入非有限闸、
 *                       结果非有限闸四道防线，防 NaN 沿数据链扩散。
 *
 * 功能描述 (Function)   : 四闸顺序：① 输入非有限闸（NaN 自反判据、Inf 实数上限
 *                         判据）；② 除零闸（除数绝对值小于 fEps 视为零，防浮点
 *                         下溢假非零）；③ 商域闸（商绝对值超过 DL_MAXQ 时 TRUNC
 *                         会溢出整数域，直接拒绝）；④ 结果非有限闸。合法路径用
 *                         标准 fA - fB * TRUNC(fA / fB) 表达式实现取模，零被除数
 *                         以信息级告知恒等余数零。
 * 与既有件边界 (Boundary): 与 FC_DL_DivLrealSafe 组成除/模对；本件不做浮点取整
 *                         方向选择（floor/ceil 变体归后续件），固定向零截断。
 * 码位说明 (Codes)      : 信息 16#0002_3050 零被除数恒等（余数为零）
 *                         故障 16#0002_3051 除数无效（零或绝对值小于 fEps）
 *                         故障 16#0002_3052 输入非有限（NaN 或 Inf）
 *                         故障 16#0002_3053 结果域外（商超界或结果非有限）
 *                         段 16#02_3_50~53 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 IEC 标准算术 / ABS / TRUNC。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         浮点比较全部带 fEps 容差 ｜ NaN/Inf 用精确判据
 *                         除法前强制判零 ｜ 全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 2）
 *============================================================================*)

FUNCTION FC_DL_ModLrealSafe : BOOL
VAR_INPUT
    fA    : LREAL;                  // 被除数 [实数域] / Dividend
    fB    : LREAL;                  // 除数 [实数域]，绝对值小于 fEps 视为零 / Divisor, near-zero by fEps
    fEps  : LREAL := 1.0E-12;       // 判零容差 [实数域] / Zero tolerance
END_VAR
VAR_OUTPUT
    fRem    : LREAL;                // 余数 [实数域]，故障路径为哨兵零 / Remainder, sentinel zero on fault
    bError  : BOOL;                 // 故障标志，与故障码 3051~3053 配对 / Fault flag paired with codes
    uErrorId: UDINT;                // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    fQ   : LREAL;   // 中间商 [实数域]，仅作域判定与截断 / Intermediate quotient
    uCode: UDINT;   // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_MLS_MAXQ : LREAL := 1.0E9;   // 商绝对值上限 [实数域]，保 TRUNC 不溢出 DINT / Quotient cap, keeps TRUNC inside DINT
END_VAR

(* 段 1｜输出预置 / Pre-set *)
FC_DL_ModLrealSafe := FALSE;
fRem     := 0.0;
bError   := FALSE;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜输入非有限闸：NaN 自反判据、Inf 实数上限判据 / Non-finite input gate *)
IF (fA <> fA) OR (fB <> fB) OR (ABS(fA) > 1.0E308) OR (ABS(fB) > 1.0E308) THEN
    fRem    := 0.0;              // 哨兵零 / Sentinel zero
    bError  := TRUE;             // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_3052;    // 故障级：输入非有限 / Fault: non-finite input
    RETURN;
END_IF

(* 段 3｜除零闸：精确零与绝对小除数一并拦截，防浮点下溢假非零 / Zero gate: exact zero and near-zero together *)
IF ABS(fB) < fEps THEN
    fRem    := 0.0;              // 哨兵零 / Sentinel zero
    bError  := TRUE;             // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_3051;    // 故障级：除数无效 / Fault: invalid divisor
    RETURN;
END_IF

(* 段 4｜零被除数恒等：信息级告知 / Zero dividend identity *)
IF ABS(fA) < fEps THEN
    fRem    := 0.0;              // 恒等余数零 / Identity remainder zero
    uErrorId := 16#0002_3050;    // 信息级：零被除数 / Info: zero dividend
    FC_DL_ModLrealSafe := TRUE;
    RETURN;
END_IF

(* 段 5｜商域闸：商超界时 TRUNC 会溢出整数域，拒绝而不硬算 / Quotient domain gate: refuse before TRUNC could overflow *)
fQ := fA / fB;
IF ABS(fQ) > DL_MLS_MAXQ THEN
    fRem    := 0.0;              // 哨兵零 / Sentinel zero
    bError  := TRUE;             // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_3053;    // 故障级：结果域外 / Fault: result out of domain
    RETURN;
END_IF

(* 段 6｜合法路径：标准向零截断取模表达式 / Legal path: standard truncation-based modulo *)
fRem := fA - fB * TRUNC(fQ);     // fA 减 fB 乘整数商得余数 / Dividend minus divisor times truncated quotient

(* 段 7｜结果非有限闸（防御校验，正常路径不可达）/ Result non-finite gate, belt and braces *)
IF (fRem <> fRem) OR (ABS(fRem) > 1.0E308) THEN
    fRem    := 0.0;              // 哨兵零 / Sentinel zero
    bError  := TRUE;             // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_3053;    // 故障级：结果非有限 / Fault: non-finite result
    RETURN;
END_IF
uErrorId := uCode;               // 码位单点写入 / Single write point
FC_DL_ModLrealSafe := TRUE;
END_FUNCTION
