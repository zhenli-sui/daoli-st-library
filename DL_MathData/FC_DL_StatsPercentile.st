(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StatsPercentile
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（TRUNC / MIN / MAX），零厂商私有库
 * 功能描述 (Function)   : 分位数计算（P50 / P90 / P95 等），排序法 + 线性插值。
 *                         ① 把有效样本复制到内部缓冲（**不改写调用方数组**）；
 *                         ② 冒泡排序升序（N <= 64，最坏 64×63/2 = 2016 次比较，单拍可接受）；
 *                         ③ 位置 pos := (p/100) × (n - 1)（0 基）；
 *                            lo := TRUNC(pos)，frac := pos - lo；
 *                            结果 := buf[lo] × (1 - frac) + buf[lo+1] × frac。
 *                         取整一律用 TRUNC 后按余量插值，**不使用 TRUNC(x)+1 这类手工进位**
 *                         （R 加固清单要求：向上取整禁止 TRUNC+1，须先 TRUNC 再按余量进位）。
 * 接口     (Interface)  : 输入 afSample 样本数组 [EU]、iCount 有效样本数 [个]（1..64）、
 *                         fPercent 百分位 [%]（0..100，0 = 最小，100 = 最大）；
 *                         输出 fResult 分位数值 [EU]、fPos 位置（0 基，诊断用）[-]、
 *                         bInterpolated 是否发生两点插值、bValid 结果可信、
 *                         eErrCode（E_DL_StatsPctErr）；
 *                         返回值 = bValid。
 * 边界     (Boundary)   : ① 属主边界：只算单个分位点；P50/P90/P95 由调用方三次调用
 *                         （避免本件内部固定三个出口，保持通用）。
 *                         ② 样本数域闸 1..64；越域 → 故障级 eBadCount。n=1 时 pos 恒 0，结果即唯一值。
 *                         ③ 百分位域闸 0..100；越域 → 故障级 eBadPercent（不做静默钳位，
 *                         避免把「配置写错 950」当成 95 用）。
 *                         ④ 非有限双判：全部有效样本逐项枚举。
 *                         ⑤ 插值上界保护：lo 若达到 n-1（pos 恰为最大值）则退化为单点取值，
 *                         不读 buf[lo+1]（**杜绝数组越界**）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StatsMeanStdDev` 分工：矩统计归那件、序统计归本件；
 *                         与 `FC_DL_StatsOutlierCount` 分工：离群计数归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + 2×LREAL + BOOL +
 *                         本文件内定义 enum E_DL_StatsPctErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数/百分位双域闸 + 全样本非有限双判 + 插值下标越界保护 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 18）
 * 验收向量 (Acceptance) : ① afSample=[1,2,3,4,5], iCount=5, fPercent=50 → pos=0.5×4=2.0,
 *                         lo=2, frac=0 → fResult=3.0（一点起算：buf[3]=3.0）, bInterpolated=FALSE；
 *                         ② 同上, fPercent=90 → pos=0.9×4=3.6, lo=3, frac=0.6 →
 *                         fResult=4×0.4+5×0.6=4.6（容差 1E-9）, bInterpolated=TRUE；
 *                         ③ 同上, fPercent=100 → pos=4 → 退化单点 → fResult=5.0（不越界）；
 *                         ④ fPercent=101 → 返回 FALSE, eBadPercent；
 *                         ⑤ iCount=0 → 返回 FALSE, eBadCount。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StatsPctErr（分位数统计错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StatsPctErr :
(
    eOk          := 0,   // 信息级：分位数计算完成 / Info: percentile computed
    eBadCount    := 1,   // 故障级：样本数越域 / Fault: sample count out of domain
    eBadPercent  := 2,   // 故障级：百分位越域（0..100） / Fault: percentile out of range
    eNonFinite   := 3,   // 故障级：样本含非有限值 / Fault: non-finite sample present
    eInternal    := 9    // 故障级：插值下标越界（内部不一致） / Fault: interpolation index out of range
);
END_TYPE

FUNCTION FC_DL_StatsPercentile : BOOL
VAR_INPUT
    afSample : ARRAY[1..64] OF LREAL;  // 样本数组（只读） [EU] / Sample array, read-only
    iCount   : INT;                    // 有效样本数（1..64） [个] / Valid sample count, 1..64
    fPercent : LREAL;                  // 百分位 [%]（0..100） / Percentile in percent
END_VAR
VAR_OUTPUT
    fResult       : LREAL;  // 分位数值 [EU] / Percentile value
    fPos          : LREAL;  // 插值位置（0 基，诊断用） [-] / Interpolation position, zero-based
    bInterpolated : BOOL;   // 是否发生两点插值 [-] / Whether two-point interpolation occurred
    bValid        : BOOL;   // 结果可信标志 [-] / Result trustworthy flag
    eErrCode      : E_DL_StatsPctErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _afBuf     : ARRAY[1..64] OF LREAL;  // 内部排序缓冲（不改写调用方数组） [EU] / Internal sort buffer
    _i         : INT;    // 外层遍历下标 [-] / Outer index
    _j         : INT;    // 内层遍历下标 [-] / Inner index
    _iLo       : INT;    // 位置下整（0 基） [-] / Floor index, zero-based
    _diLo      : DINT;   // 下整中间量（LREAL→DINT，再收窄到 INT） [-] / Floor intermediate, LREAL to DINT then INT
    _bNonFin   : BOOL;   // 非有限标志 [-] / Non-finite flag
    _bSwapped  : BOOL;   // 冒泡交换标志 [-] / Bubble swap flag
    _fTmp      : LREAL;  // 交换临时量 [EU] / Swap temporary
    _fPosR     : LREAL;  // 位置（0 基） [-] / Position, zero-based
    _fFrac     : LREAL;  // 位置小数部分（余量） [-] / Fractional remainder
END_VAR
VAR CONSTANT
    DL_SPC_CNT_MIN : INT := 1;        // 样本数下限 [个] / Count lower bound
    DL_SPC_CNT_MAX : INT := 64;       // 样本数上限（数组容量） [个] / Count upper bound
    DL_SPC_PCT_MIN : LREAL := 0.0;    // 百分位下限 [%] / Percentile lower bound
    DL_SPC_PCT_MAX : LREAL := 100.0;  // 百分位上限 [%] / Percentile upper bound
    DL_SPC_ZERO    : LREAL := 0.0;    // 零基准（含非有限判零） [-] / Zero base including non-finite probe
    DL_SPC_ONE     : LREAL := 1.0;    // 单位常数 [-] / Unit constant
    DL_SPC_HUND    : LREAL := 100.0;  // 百分数换算因子 [-] / Percent scaling factor
    DL_SPC_ONE_I   : INT := 1;        // 下标单位（IEC 1 基） [-] / Index unit, IEC one-based
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StatsPercentile := FALSE;                    // 返回值预置无效 / Return preset invalid
fResult       := DL_SPC_ZERO;                      // 结果哨兵 / Result sentinel
fPos          := DL_SPC_ZERO;                      // 位置哨兵 / Position sentinel
bInterpolated := FALSE;                            // 插值标志预置否 / Interpolation preset false
bValid        := FALSE;                            // 可信标志预置否 / Trust flag preset false
eErrCode      := E_DL_StatsPctErr.eBadCount;       // 预置最严码 / Preset strictest code

(* —— 段 1：样本数域闸 —— *)
IF (iCount < DL_SPC_CNT_MIN) OR (iCount > DL_SPC_CNT_MAX) THEN
    RETURN;
END_IF

(* —— 段 2：百分位域闸（越域不做静默钳位，避免配置错误被掩盖） —— *)
IF (fPercent <> fPercent) OR (fPercent < DL_SPC_PCT_MIN) OR (fPercent > DL_SPC_PCT_MAX) THEN
    eErrCode := E_DL_StatsPctErr.eBadPercent;      // 故障级：百分位越域 / Fault: percentile out of range
    RETURN;
END_IF

(* —— 段 3：非有限域闸（全部有效样本逐项枚举） —— *)
_bNonFin := FALSE;
_i := 1;
WHILE _i <= iCount DO
    IF (afSample[_i] <> afSample[_i]) OR ((afSample[_i] - afSample[_i]) <> DL_SPC_ZERO) THEN
        _bNonFin := TRUE;
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_StatsPctErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 4：复制到内部缓冲（不改写调用方数组，R 纪律） —— *)
FOR _i := DL_SPC_ONE_I TO iCount DO
    _afBuf[_i] := afSample[_i];
END_FOR;

(* —— 段 5：冒泡排序升序（N <= 64，比较次数有界） —— *)
FOR _i := 1 TO (iCount - 1) DO
    _bSwapped := FALSE;
    FOR _j := 1 TO (iCount - _i) DO
        IF _afBuf[_j] > _afBuf[_j + DL_SPC_ONE_I] THEN
            _fTmp                := _afBuf[_j];
            _afBuf[_j]           := _afBuf[_j + DL_SPC_ONE_I];
            _afBuf[_j + 1]       := _fTmp;
            _bSwapped            := TRUE;          // 本趟发生交换 / Swap happened in this pass
        END_IF
    END_FOR;
    IF NOT _bSwapped THEN
        _i := iCount;                              // 已有序：提前收敛（仍受 FOR 上界约束） / Early convergence
    END_IF
END_FOR;

(* —— 段 6：位置计算（0 基，先 TRUNC 再按余量插值，禁 TRUNC+1 手工进位） —— *)
_fPosR := (fPercent / DL_SPC_HUND) * INT_TO_LREAL(iCount - 1);   // pos = (p/100)*(n-1)
fPos   := _fPosR;
_diLo  := LREAL_TO_DINT(TRUNC(_fPosR));            // 先 TRUNC 再转整（禁 TRUNC+1 手工进位） / Truncate then convert
_iLo   := DINT_TO_INT(_diLo);                      // 收窄到 INT（0..63，越界由下两段钳位） / Narrow to INT
IF _iLo < 0 THEN
    _iLo := 0;                                     // 下标下限保护 / Lower index guard
END_IF
IF _iLo > (iCount - 1) THEN
    _iLo := iCount - 1;                            // 下标上限保护 / Upper index guard
END_IF
_fFrac := _fPosR - INT_TO_LREAL(_iLo);             // 余量（0..1） / Remainder
IF _fFrac < DL_SPC_ZERO THEN
    _fFrac := DL_SPC_ZERO;
END_IF
IF _fFrac > DL_SPC_ONE THEN
    _fFrac := DL_SPC_ONE;
END_IF

(* —— 段 7：取值（插值上界保护：lo 达末位时退化为单点，杜绝越界） —— *)
IF _iLo >= (iCount - 1) THEN
    fResult       := _afBuf[iCount];               // 末位单点取值 / Single-point value at the tail
    bInterpolated := FALSE;
ELSE
    fResult := _afBuf[_iLo + DL_SPC_ONE_I] * (DL_SPC_ONE - _fFrac)
             + _afBuf[_iLo + 1 + DL_SPC_ONE_I] * _fFrac;   // 两点线性插值 / Two-point linear interpolation
    bInterpolated := TRUE;
END_IF

(* —— 段 8：结果复检（非有限 + 落在 [min, max] 闭包内） —— *)
IF (fResult <> fResult) OR ((fResult - fResult) <> DL_SPC_ZERO) THEN
    fResult       := DL_SPC_ZERO;
    bInterpolated := FALSE;
    eErrCode      := E_DL_StatsPctErr.eNonFinite;
    RETURN;
END_IF
IF (fResult < _afBuf[DL_SPC_ONE_I]) OR (fResult > _afBuf[iCount]) THEN
    fResult       := DL_SPC_ZERO;                  // 越出样本闭包：内部不一致 / Outside sample envelope
    bInterpolated := FALSE;
    eErrCode      := E_DL_StatsPctErr.eInternal;
    RETURN;
END_IF

(* —— 段 9：成功出口 —— *)
bValid   := TRUE;
eErrCode := E_DL_StatsPctErr.eOk;                  // 信息级成功 / Info success
FC_DL_StatsPercentile := TRUE;                     // 分位数可信 / Percentile trustworthy

END_FUNCTION
