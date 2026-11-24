(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ZoneSpeedTrim
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（MIN / MAX / ABS），零厂商私有库
 * 功能描述 (Function)   : 轴位置区段差异化限速：按轴实际位置命中区段表（fStartMm/fEndMm/
 *                         fVmaxMmS）改写指令速度上限：命中 → fVCmd = MIN(fVout, fVmaxZone)；
 *                         表外 → MIN(fVout, fVDefault)。eCurZone 出当前命中区段号
 *                         （0=表外）。适用机械臂/桁架近人区、近件区、换向区差异化限速。
 * 接口     (Interface)  : 输入 fPosMm 轴实际位置（mm）、aZone 区段表（定长 1..nZoneMax）、
 *                         nZoneCount 有效区段数、fVDefaultMmS 表外默认限速（mm/s）、
 *                         fVoutMmS 当前指令速度（mm/s）、bReset 复位；输出 fVCmdMmS 限幅
 *                         后指令（mm/s）、eCurZone 当前命中区段号（0=表外）、bCapped
 *                         触限幅、bCfgBad 区段表非法（锁存）、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做区段限速改写，不做静态软限位
 *                         报警、不接管轴使能**（静态软限位归 `FB_DL_SoftLimitGuard`）。
 *                         ② 区段表校验锁存 bCfgBad（表非法比静默错限速危险）：fStart>fEnd
 *                         （倒序）、fVmax<=0、任两区段重叠（含区间闭端相交）→ 锁存；
 *                         bCfgBad 期输出保守限速 MIN(fVout, fVDefault)，解除沿 =
 *                         bReset 上升沿。
 *                         ③ fStart<=fEnd 判据用浮点 < / > 比较，禁 = 判等（R28）。
 *                         ④ 表满 nZoneMax 钳位：nZoneCount > nZoneMax 按上限处理并置
 *                         组态当拍错。
 *                         ⑤ 非有限位置 → 冻结上次输出并置当拍 bError（R245）。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_SoftLimitGuard` 分工：动态区段限速（本件）≠ 静态软
 *                         限位报警（那件）；与 `FB_DL_ConveyorZone` 分工：运动限速 ≠
 *                         输送段跟踪。
 * 来源标签 (Source Tag) : T1-6 ◐（PLCopen MC 语义只借限速语义，区段表结构自研）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 LREAL 限速 + UDINT 区号 +
 *                         BOOL 组；数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 表校验锁存 + 浮点禁等 + 非有限冻结 + 表满钳位 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（查表无状态机） ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 3 · 序号 15）
 *                         验收向量：命中区段按 fVmax 限幅；表外用默认值；倒序/重叠表 →
 *                         bCfgBad 锁存保守限速；nZoneCount 超上限钳位。
 *==============================================================================*)

TYPE ST_DL_ZoneSpeed :
STRUCT
    fStartMm  : LREAL;   // 区段起点（含端点） [mm] / Zone start, inclusive [mm]
    fEndMm    : LREAL;   // 区段终点（含端点） [mm] / Zone end, inclusive [mm]
    fVmaxMmS  : LREAL;   // 区段速度上限，域 > 0 [mm/s] / Zone speed ceiling [mm/s]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_ZoneSpeedTrim
VAR_INPUT
    fPosMm      : LREAL := 0.0;   // 轴实际位置 [mm] / Axis actual position [mm]
    aZone       : ARRAY[1..8] OF ST_DL_ZoneSpeed;   // 区段表（定长，nZoneCount 指明有效前段） / Zone table, fixed length
    nZoneCount  : UDINT := 0;     // 有效区段数（0=全表外） [段] / Valid zone count
    fVDefaultMmS: LREAL := 500.0; // 表外默认限速，域 > 0 [mm/s] / Default speed ceiling outside table [mm/s]
    fVoutMmS    : LREAL := 0.0;   // 当前指令速度（限幅前） [mm/s] / Command speed before capping [mm/s]
    bReset      : BOOL := FALSE;  // 复位，上升沿清 bCfgBad 锁存 [-] / Reset, rising edge clears cfg latch
END_VAR
VAR_OUTPUT
    fVCmdMmS : LREAL;            // 限幅后指令速度 [mm/s] / Capped command speed [mm/s]
    eCurZone : UDINT;            // 当前命中区段号（1..n，0=表外） [段] / Current zone number, 0 = outside
    bCapped  : BOOL;             // 本拍触限幅（fVCmd < fVout） [-] / Capped this scan
    bCfgBad  : BOOL;             // 区段表非法（锁存） [-] / Illegal zone table, latched
    bError   : BOOL;             // 故障标志（组态锁存 ∨ 非有限当拍） [-] / Error flag
END_VAR
VAR
    _nCount  : DINT;             // 钳位后有效区段数 [段] / Clamped valid zone count
    _nHit    : DINT;             // 命中区段号（0=表外） [段] / Hit zone number
    _fCap    : LREAL;            // 当拍生效速度上限 [mm/s] / Effective speed ceiling
    _fVCmd   : LREAL := 0.0;     // 输出锁存镜像（非有限冻结源） / Output latch mirror
    _bCfgLatch: BOOL;            // 表非法锁存位（解除沿 = bReset 上升沿） / Latched table fault
    _bErrScan: BOOL;             // 当拍错误内部量（钳位超限/非有限） / Per-scan error internal
    _bNonFin : BOOL;             // 位置非有限当拍量 [-] / Non-finite position this scan
    i        : DINT;             // 区段循环索引 / Zone loop index
    j        : DINT;             // 重叠校验内层索引 / Overlap check inner index
    rtReset  : R_TRIG;           // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_ZST_NMAX : DINT  := 8;        // 区段表定长上限 [段] / Zone table length ceiling
    DL_ZST_EPS  : LREAL := 0.0;      // 非有限差值判零基准 [-] / Non-finite difference zero base
END_VAR

(* —— 段 0：非有限判 + 表满钳位 + 沿刷新 —— *)
_bNonFin := (fPosMm <> fPosMm) OR ((fPosMm - fPosMm) <> DL_ZST_EPS);   // 位置非有限（R245） / Non-finite position
_nCount := UDINT_TO_DINT(nZoneCount);        // 区段数转 DINT（UDINT 超界由下步钳位） / Convert count
IF _nCount > DL_ZST_NMAX THEN
    _nCount := DL_ZST_NMAX;                  // 表满钳位（头注释④） / Clamp to table ceiling
    _bErrScan := TRUE;                       // 超限置当拍组态错 / Mark per-scan error
END_IF
IF _nCount < 0 THEN
    _nCount := 0;                            // UDINT 溢出到 DINT 负值兜底 / Overflow fallback to zero
    _bErrScan := TRUE;                       // 记当拍错 / Mark per-scan error
END_IF
IF fVDefaultMmS <= 0.0 THEN
    _bErrScan := TRUE;                       // 默认限速组态闸（当拍报） / Default ceiling gate
END_IF
rtReset(CLK := bReset);                      // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 —— *)
IF rtReset.Q THEN
    _bCfgLatch := FALSE;                     // 清表非法锁存 / Clear table latch
END_IF

(* —— 段 2：区段表校验（倒序 / 非正限速 / 重叠 → 锁存） —— *)
IF NOT _bCfgLatch THEN
    FOR i := 1 TO _nCount DO
        IF (aZone[i].fStartMm > aZone[i].fEndMm) OR (aZone[i].fVmaxMmS <= 0.0) THEN
            _bCfgLatch := TRUE;              // 倒序或非正限速：表非法锁存（头注释②） / Reversed or bad ceiling: latch
        END_IF
    END_FOR
    FOR i := 1 TO _nCount DO
        FOR j := (i + 1) TO _nCount DO
            IF (aZone[j].fStartMm <= aZone[i].fEndMm) AND (aZone[i].fStartMm <= aZone[j].fEndMm) THEN
                _bCfgLatch := TRUE;          // 任两区段闭区间相交：重叠非法锁存 / Overlapping zones: latch
            END_IF
        END_FOR
    END_FOR
END_IF

(* —— 段 3：限速主算（表非法期保守限速；非有限冻结） —— *)
_nHit := 0;                                  // 命中区号预清 / Hit preset
_fCap := fVDefaultMmS;                       // 上限预置默认值 / Preset default ceiling
IF (NOT _bCfgLatch) AND (NOT _bNonFin) AND (NOT _bErrScan) THEN
    FOR i := 1 TO _nCount DO
        IF (fPosMm >= aZone[i].fStartMm) AND (fPosMm <= aZone[i].fEndMm) THEN
            _nHit := i;                      // 位置命中区段（闭区间含端点，浮点仅用 < > 比较） / Position hits zone
            _fCap := aZone[i].fVmaxMmS;      // 区段限速生效 / Zone ceiling effective
        END_IF
    END_FOR
    _fVCmd := fVoutMmS;                      // 基准指令速度 / Base command speed
    IF _fVCmd > _fCap THEN
        _fVCmd := _fCap;                     // 超区段限速：限幅 / Cap to zone ceiling
    END_IF
ELSIF _bCfgLatch OR _bErrScan THEN
    _fVCmd := fVoutMmS;                      // 组态病期从默认保守限速出发 / Config fault: conservative base
    IF _fVCmd > fVDefaultMmS THEN
        _fVCmd := fVDefaultMmS;              // 保守限幅到表外默认值 / Conservative cap
    END_IF
END_IF
(* 非有限位置分支：无赋值 → _fVCmd 冻结上次值（头注释⑤） *)

(* —— 段 4：出口单点映射（名实双出口同源，R191） —— *)
fVCmdMmS := _fVCmd;                          // 限速输出 / Capped speed outlet
eCurZone := DINT_TO_UDINT(_nHit);            // 命中区号出口（0=表外） / Zone number outlet
bCapped  := _fVCmd < fVoutMmS;               // 触限幅判定（严格小于，浮点禁等兼容） / Capped flag
bCfgBad  := _bCfgLatch;                      // 表非法出口 / Table fault outlet
bError   := _bCfgLatch OR _bErrScan OR _bNonFin;   // 故障标志三源合一 / Error flag

END_FUNCTION_BLOCK
