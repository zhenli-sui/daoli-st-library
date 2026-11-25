(*==============================================================================
 * 组件名称 (Component)  : FC_DL_TableLookupNearestIndex
 * 所属子库 (Sublibrary) : DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准数学（ABS），零厂商私有库
 * 功能描述 (Function)   : 最近节点索引查找（等距 / 非等距通用）。遍历 1..iCount 取
 *                         |afX[i] - fXin| 最小者，返回下标与最小距离。
 *                         用途：多档位选型（挡位表 → 最近挡）、配方就近匹配、故障码归类。
 *                         距离采用绝对差（非平方差），仅用于比较与展示，精度足够且无溢出风险。
 *                         并列最小（两节点等距）时保留**较小下标**（首个命中），
 *                         行为确定、可复现，便于验收与回归。
 * 接口     (Interface)  : 输入 afX 节点表（任意升/降序，无需有序） [任意工程量]、
 *                         iCount 有效点数 [个]（1..32）、fXin 查询点 [同 afX 单位]；
 *                         输出 iIndex 最近节点下标 [1..iCount]、fDist 最小绝对距离 [同 afX 单位]、
 *                         eErrCode（E_DL_TblNearErr）；
 *                         返回值 = bValid 查找可信标志（TRUE = iIndex/fDist 可信）。
 * 边界     (Boundary)   : ① 属主边界：只找最近节点，不做插值（插值归插值族）、不要求有序。
 *                         ② 点数域闸 1..32（1 点合法：恒返回该唯一点，距离为其绝对差）。
 *                         ③ 非有限双判：查询点与全部表元素逐个判，任一非有限 → 故障级 eNonFinite。
 *                         ④ 并列最小取较小下标（首个命中即锁定，后续用严格 < 比较），
 *                         保证同输入同输出（无浮点抖动导致的随机化）。
 *                         ⑤ 距离为绝对值，恒非负；复检 distance >= 0 且 < 非有限。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_TableLookupDescending` 分工：区间定位归那件、
 *                         最近点归本件；与 `FC_DL_TableIndexBinarySearch` 分工：
 *                         二分只适用于有序大表，本件为无序/小表通用件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + LREAL +
 *                         本文件内定义 enum E_DL_TblNearErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 点数域闸 + 全表非有限双判 + 距离非负复检 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B3 · 序号 2）
 * 验收向量 (Acceptance) : ① afX=[10,20,30], iCount=3, fXin=23.0 → iIndex=2, fDist=3.0, eOk, TRUE；
 *                         ② afX=[10,20,30], fXin=25.0 → 与 20/30 等距 5.0 → iIndex=2（取较小下标）, fDist=5.0；
 *                         ③ afX=[10,20,30], fXin=100.0 → iIndex=3, fDist=70.0；
 *                         ④ iCount=0 → 返回 FALSE, iIndex=0, eBadCount；
 *                         ⑤ afX[2]=NaN → 返回 FALSE, eNonFinite。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_TblNearErr（最近节点查找错误码，归属 DL_MathData，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_TblNearErr :
(
    eOk        := 0,   // 信息级：查找完成 / Info: lookup completed
    eBadCount  := 1,   // 故障级：点数越域 / Fault: point count out of domain
    eNonFinite := 2    // 故障级：查询点或表元素非有限 / Fault: query or table entry non-finite
);
END_TYPE

FUNCTION FC_DL_TableLookupNearestIndex : BOOL
VAR_INPUT
    afX    : ARRAY[1..32] OF LREAL;  // 节点表（无需有序） [任意工程量] / Node table, order not required
    iCount : INT;                    // 有效点数（1..32） [个] / Valid point count, 1..32
    fXin   : LREAL;                  // 查询点 [同 afX 单位] / Query value, same unit as afX
END_VAR
VAR_OUTPUT
    iIndex   : INT;    // 最近节点下标（1..iCount） [-] / Nearest node index
    fDist    : LREAL;  // 最小绝对距离 [同 afX 单位] / Minimum absolute distance
    eErrCode : E_DL_TblNearErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _i       : INT;    // 循环下标 [-] / Loop index
    _iBest   : INT;    // 当前最优下标 [-] / Current best index
    _bNonFin : BOOL;   // 非有限标志 [-] / Non-finite flag
    _fBest   : LREAL;  // 当前最优距离 [同 afX 单位] / Current best distance
    _fCur    : LREAL;  // 当前候选距离 [同 afX 单位] / Current candidate distance
END_VAR
VAR CONSTANT
    DL_TNC_CNT_MIN : INT := 1;        // 点数下限 [个] / Count lower bound
    DL_TNC_CNT_MAX : INT := 32;       // 点数上限（数组容量） [个] / Count upper bound
    DL_TNC_ZERO    : LREAL := 0.0;    // 零与距离下限 [-] / Zero and distance lower bound
    DL_TNC_BIG     : LREAL := 1.0E30; // 初值大数（保证首次必被更替） [-] / Large seed ensuring first replacement
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_TableLookupNearestIndex := FALSE;            // 返回值预置无效 / Return preset invalid
iIndex   := 0;                                     // 下标哨兵 0 / Index sentinel
fDist    := DL_TNC_ZERO;                           // 距离哨兵 0 / Distance sentinel
eErrCode := E_DL_TblNearErr.eBadCount;             // 预置最严码 / Preset strictest code

(* —— 段 1：点数域闸 —— *)
IF (iCount < DL_TNC_CNT_MIN) OR (iCount > DL_TNC_CNT_MAX) THEN
    RETURN;                                        // 点数越域：保持故障码与哨兵 / Count out of domain
END_IF

(* —— 段 2：非有限域闸（查询点 + 全部表元素逐项枚举） —— *)
_bNonFin := (fXin <> fXin) OR ((fXin - fXin) <> DL_TNC_ZERO);   // 查询点非有限 / Query non-finite
_i := 1;
WHILE _i <= iCount DO
    IF (afX[_i] <> afX[_i]) OR ((afX[_i] - afX[_i]) <> DL_TNC_ZERO) THEN
        _bNonFin := TRUE;                          // 表元素非有限 / Table entry non-finite
    END_IF
    _i := _i + 1;
END_WHILE
IF _bNonFin THEN
    eErrCode := E_DL_TblNearErr.eNonFinite;        // 故障级码 / Fault-level code
    RETURN;
END_IF

(* —— 段 3：最小绝对距离扫描（严格 < 比较 → 并列时保留较小下标） —— *)
_iBest := 1;                                       // 最优下标初值 / Best index seed
_fBest := DL_TNC_BIG;                              // 最优距离初值 / Best distance seed
_i     := 1;
WHILE _i <= iCount DO
    _fCur := ABS(afX[_i] - fXin);                  // 绝对距离（非负） / Absolute distance
    IF _fCur < _fBest THEN
        _fBest := _fCur;                           // 更优距离 / Better distance
        _iBest := _i;                              // 更新下标 / Update index
    END_IF
    _i := _i + 1;
END_WHILE

(* —— 段 4：结果复检（下标域 + 距离非负且有限） —— *)
IF (_iBest < DL_TNC_CNT_MIN) OR (_iBest > iCount) THEN
    eErrCode := E_DL_TblNearErr.eBadCount;         // 下标越域：内部不一致 / Index out of domain
    RETURN;
END_IF
IF (_fBest <> _fBest) OR ((_fBest - _fBest) <> DL_TNC_ZERO) OR (_fBest < DL_TNC_ZERO) THEN
    eErrCode := E_DL_TblNearErr.eNonFinite;        // 距离异常 / Abnormal distance
    RETURN;
END_IF

iIndex   := _iBest;                                // 导出最近下标 / Export nearest index
fDist    := _fBest;                                // 导出最小距离 / Export minimum distance
eErrCode := E_DL_TblNearErr.eOk;                   // 信息级成功 / Info success
FC_DL_TableLookupNearestIndex := TRUE;             // 查找可信 / Lookup trustworthy

END_FUNCTION
