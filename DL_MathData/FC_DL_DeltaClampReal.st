(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DeltaClampReal
 * 所属子库 (Sublibrary) : DL_MathData ｜ 版本 (Version) : 1.0.0 ｜ 2026-11-23
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 算术运算符与 ABS，零厂商私有库
 * 功能描述 (Function)   : 相邻两拍增量钳位（FC 形态）：|fX − fXPrev| 超过 fMaxDelta 时，
 *                         输出改为 fXPrev 沿增量方向叠加 fMaxDelta（钳位后叠加，非就地截断），
 *                         未超限则直通 fX。用于抑制单拍测量跳变（尖峰 / 通信抖动）。
 *                         **契约声明**：本件使用 VAR_IN_OUT 引脚 fXPrev 持有上一拍输出，
 *                         首拍或被污染时以本拍 fX 重建（信息级 ePrevRebuilt）。
 * 接口     (Interface)  : 输入 fX 本拍输入 [工程单位]、fMaxDelta 单拍允许最大增量，有效域 ≥ 0
 *                         [工程单位/拍]；VAR_IN_OUT fXPrev 上一拍输出（本件写回）；
 *                         输出 fY 钳位后输出 [工程单位]、eErrCode（E_DL_DeltaClampErr）；
 *                         返回值 = 数值可信标志。
 * 边界     (Boundary)   : ① fMaxDelta < 0 → 故障级 eBadLimit（负增量上限无物理意义），
 *                            输出回退 fXPrev，返回 FALSE。
 *                         ② fMaxDelta = 0 → 合法（信息级 eFrozen）：输出恒等于 fXPrev，即冻结。
 *                         ③ 任一浮点入参非有限 → 故障级 eNonFinite，fY = 0 哨兵，返回 FALSE。
 *                         ④ 钳位后结果复检非有限 → 回退 fXPrev 并报故障。
 *                         ⑤ 浮点同值比较使用容差 DL_DCLP_EPS（1E-6），禁浮点判等（R4）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 码表     (Codes)      : 本件不占用全局数字码位（R297 零码位范式）；出口为 BOOL + REAL +
 *                         本文件内 enum E_DL_DeltaClampErr（全库唯一属主）。
 * 分工声明 (Scope)      : 多拍滑动平均去抖归 FB_DL_MovingAverage 与 FB_DL_MedianFilter；
 *                         本件为单拍硬钳位，不做滤波、不做趋势判断。
 * 归属     (Ownership)  : E_DL_DeltaClampErr 归属本文件（全库唯一属主，R264）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL ｜ R2 ✓ 零 %I/%Q ｜ R3 ✓ 纯 IEC ｜ R4 ✓ 非有限双判 +
 *                         容差比较 + 无除法 ｜ R5 ✓ 逐行同行双语注释 ｜ R6 N/A（纯函数）
 *                         R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R78-B2 首版
 * 验收向量 (Acceptance) :
 *   A1 fX=10.0, fPrev=10.0, fMaxDelta=2.0 → fY=10.0, eOk；
 *   A2 fX=15.0, fPrev=10.0, fMaxDelta=2.0 → 增量 5.0 > 2.0 → fY=12.0, eClamped；
 *   A3 fX=6.0,  fPrev=10.0, fMaxDelta=2.0 → 增量 −4.0 → fY=8.0, eClamped；
 *   A4 fX=12.0, fPrev=10.0, fMaxDelta=0.0 → fY=10.0, eFrozen（冻结）；
 *   A5 fX=12.0, fPrev=10.0, fMaxDelta=-1.0 → fY=10.0, eBadLimit, 返回 FALSE。
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_DeltaClampErr（增量钳位出口码；信息级 = 0..9，故障级 = 10 起）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DeltaClampErr :
(
    eOk          := 0,   // 信息级：增量未超限，直通 / Info: delta within limit, pass-through
    eClamped     := 1,   // 信息级：本拍增量已钳位 / Info: delta clamped this scan
    eFrozen      := 2,   // 信息级：增量为 0，输出冻结在前值 / Info: zero limit, output frozen at previous value
    ePrevRebuilt := 3,   // 信息级：前值未初始化或被污染，已重建 / Info: previous value rebuilt
    eBadLimit    := 10,  // 故障级：增量上限为负 / Fault: negative delta limit
    eNonFinite   := 11   // 故障级：入参或结果非有限 / Fault: non-finite input or result
);
END_TYPE

FUNCTION FC_DL_DeltaClampReal : BOOL
VAR_INPUT
    fX        : REAL;   // 本拍输入 [工程单位] / Input this scan in engineering unit
    fMaxDelta : REAL;   // 单拍允许最大增量，有效域 ≥ 0 [工程单位/拍] / Max delta per scan, valid domain >= 0
END_VAR
VAR_IN_OUT
    fXPrev : REAL;      // 上一拍输出，本件写回新值 [工程单位] / Previous output, written back by this function
END_VAR
VAR_OUTPUT
    fY       : REAL;               // 钳位后输出 [工程单位] / Delta-clamped output in engineering unit
    eErrCode : E_DL_DeltaClampErr;  // 出口码 [-] / Outlet code
END_VAR
VAR
    _bBadX     : BOOL;   // fX 非有限标志 [-] / Non-finite flag of fX
    _bBadLimit : BOOL;   // fMaxDelta 非有限标志 [-] / Non-finite flag of fMaxDelta
    _bBadPrev  : BOOL;   // fXPrev 非有限标志 [-] / Non-finite flag of fXPrev
    _fDelta    : REAL;   // 原始增量 = fX − fXPrev [工程单位] / Raw delta
    _fAbsDelta : REAL;   // 增量绝对值 [工程单位] / Absolute delta
END_VAR
VAR CONSTANT
    DL_DCLP_ZERO : REAL := 0.0;     // 零基准与符号分界 [-] / Zero base and sign boundary
    DL_DCLP_EPS  : REAL := 1.0E-6;  // 浮点同值判定容差 [-] / Float equality tolerance
END_VAR

(* —— 段 0：出口预置安全侧 —— *)
FC_DL_DeltaClampReal := FALSE;                       // 返回值预置不可信 / Return preset not trustworthy
fY      := DL_DCLP_ZERO;                             // 输出哨兵 0 / Output sentinel
eErrCode := E_DL_DeltaClampErr.eNonFinite;           // 预置最严码 / Preset strictest code

(* —— 段 1：入参非有限闸（R272 全量枚举 fX / fMaxDelta） —— *)
_bBadX     := (fX <> fX) OR ((fX - fX) <> DL_DCLP_ZERO);                     // 输入非有限 / Input non-finite
_bBadLimit := (fMaxDelta <> fMaxDelta) OR ((fMaxDelta - fMaxDelta) <> DL_DCLP_ZERO);  // 上限非有限 / Limit non-finite
IF _bBadX OR _bBadLimit THEN
    RETURN;                                          // 故障出口：fY 保持 0 哨兵 / Fault exit, sentinel kept
END_IF

(* —— 段 2：上一拍输出有效性闸（未初始化或被污染 → 用本拍输入重建） —— *)
_bBadPrev := (fXPrev <> fXPrev) OR ((fXPrev - fXPrev) <> DL_DCLP_ZERO);      // 前值非有限 / Previous value non-finite
IF _bBadPrev THEN
    fXPrev   := fX;                                  // 重建起点 / Rebuild the starting point
    eErrCode := E_DL_DeltaClampErr.ePrevRebuilt;     // 信息级：前值已重建 / Info: previous value rebuilt
END_IF

(* —— 段 3：增量上限域闸（负上限为组态缺陷；零上限即冻结） —— *)
IF fMaxDelta < DL_DCLP_ZERO THEN
    fY      := fXPrev;                               // 回退前值（安全侧）/ Fall back to previous value
    eErrCode := E_DL_DeltaClampErr.eBadLimit;        // 故障级码 / Fault-level code
    RETURN;                                          // 返回 FALSE / Fault exit
END_IF
IF (fMaxDelta - DL_DCLP_ZERO) < DL_DCLP_EPS THEN
    fY       := fXPrev;                              // 零上限：输出恒为前值（冻结）/ Zero limit: freeze at previous
    fXPrev   := fY;                                  // 前值保持不变（唯一写入点） / Single write-back point
    eErrCode := E_DL_DeltaClampErr.eFrozen;          // 信息级：冻结 / Info: frozen
    FC_DL_DeltaClampReal := TRUE;                    // 冻结输出可信 / Frozen output is trustworthy
    RETURN;
END_IF

(* —— 段 4：增量比较与钳位叠加（方向分列，R146） —— *)
_fDelta    := fX - fXPrev;                           // 原始增量 / Raw delta
_fAbsDelta := ABS(_fDelta);                          // 增量绝对值 / Absolute delta
IF _fAbsDelta <= (fMaxDelta + DL_DCLP_EPS) THEN
    fY       := fX;                                  // 未超限：直通 / Within limit: pass-through
    eErrCode := E_DL_DeltaClampErr.eOk;              // 信息级：正常 / Info: normal
ELSE
    IF _fDelta > DL_DCLP_ZERO THEN
        fY := fXPrev + fMaxDelta;                    // 上行钳位叠加 / Clamped addition upward
    ELSE
        fY := fXPrev - fMaxDelta;                    // 下行钳位叠加 / Clamped addition downward
    END_IF
    eErrCode := E_DL_DeltaClampErr.eClamped;         // 信息级：已钳位 / Info: clamped
END_IF

(* —— 段 5：结果复检（钳位后非有限 → 回退前值并报故障） —— *)
IF (fY <> fY) OR ((fY - fY) <> DL_DCLP_ZERO) THEN
    fY      := fXPrev;                               // 回退上一有效值 / Fall back to the last valid value
    eErrCode := E_DL_DeltaClampErr.eNonFinite;       // 故障级码 / Fault-level code
    RETURN;                                          // 返回 FALSE / Fault exit
END_IF

fXPrev := fY;                                        // 前值写回（唯一写入点）/ Single write-back point
FC_DL_DeltaClampReal := TRUE;                        // 输出可信 / Output trustworthy
END_FUNCTION
