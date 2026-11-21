(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CamTableInterp
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（PLCopen 凸轮族深化）
 * 所属子库 (Sublibrary) : DL_Motion / CamProfile
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 函数（FUNCTION）· 凸轮表主轴位置线性插值（无状态纯函数）
 * 功能一句话 (Summary)  : 按主轴位置在凸轮表线性插值取从轴位置，支持周期取模。
 * 边界与安全 (Boundary) : ①表点数小于 2 或未升序 → 表非法码；
 *                         ②主轴位置 NaN → 位置非法码；
 *                         ③非周期模式界外钳端点并 bInRange=FALSE；
 *                         ④周期模式先取模再插值，周期非正非法码；
 *                         ⑤纯函数：每个输出在全部路径（含提前返回）赋值。
 * 错误码    : 16#0004_0315 凸轮表非法（点数不足或未升序或周期非正）——故障级
 *             16#0004_0316 主轴位置 NaN——故障级
 *             16#0004_0317 保留禁用（不得挪用，本件零赋值）
 * 码位总账  : 16#0004_0315 用 / 16#0004_0316 用 ｜ 16#0004_0317 预留
 * 修改记录  : v1.0.0 R26 初版
 *             v1.0.1 R26 终审修复：周期参数补非有限闸——fPeriod=NaN 时
 *             `fPeriod <= 0.0` 判 FALSE 守卫穿透，NaN 经取模扩散至从轴输出
 *==============================================================================*)
TYPE ST_DL_CamPoint :
STRUCT
    fMaster : LREAL; // 主轴位置锚点 [mm] / Master position anchor [mm]
    fSlave  : LREAL  // 从轴位置锚点 [mm] / Slave position anchor [mm]
END_STRUCT
END_TYPE

FUNCTION FC_DL_CamTableInterp : BOOL
VAR_INPUT
    fMasterPos : LREAL; // 主轴当前位置 [mm] / Current master position [mm]
    bPeriodic  : BOOL;  // 周期模式使能 / Periodic mode enable
    fPeriod    : LREAL; // 周期模式主轴周期 [mm] / Master period [mm]
END_VAR
VAR_IN_OUT
    aCam : ARRAY[*] OF ST_DL_CamPoint; // 凸轮表，须按 fMaster 升序 / Cam table, ascending
END_VAR
VAR_OUTPUT
    fSlavePos : LREAL; // 从轴位置输出 [mm] / Slave position output [mm]
    bInRange  : BOOL;  // 主轴位置在表界内 / Master within table range
    eErr      : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    nPts    : INT;   // 表点数 / Table point count
    i       : INT;   // 分段搜索游标 / Segment search cursor
    fPos    : LREAL; // 插值用主轴位置（取模后）/ Master position used for interpolation
    fDen    : LREAL; // 段宽（前判零）/ Segment width (zero-guarded)
    fRatio  : LREAL; // 段内插值比例 / Interpolation ratio
    bTableOk: BOOL;  // 表合法性 / Table legality
END_VAR

// ---------- 全路径赋值缺省 ----------
fSlavePos := 0.0;
bInRange  := FALSE;
eErr      := 0;
FC_DL_CamTableInterp := TRUE; // 返回值：TRUE=已执行 / Result: TRUE = executed

// ---------- 表防御：点数与单调性 ----------
nPts := UPPER_BOUND(aCam, 1) + 1;             // 表点数 / Point count
bTableOk := nPts >= 2;                        // 至少两点 / At least two points
IF bTableOk THEN
    FOR i := 0 TO nPts - 2 DO
        IF NOT (aCam[i].fMaster < aCam[i + 1].fMaster) THEN
            bTableOk := FALSE;                // 严格升序被破坏 / Order violated
        END_IF
    END_FOR
END_IF
IF bPeriodic AND ((fPeriod <= 0.0) OR (fPeriod <> fPeriod)) THEN
    bTableOk := FALSE;                        // 周期非正或非有限视同表非法 / Non-positive or non-finite period illegal
END_IF
IF NOT bTableOk THEN
    eErr := 16#0004_0315;                     // 表非法码 / Illegal table code
    RETURN;                                   // 提前返回：输出已全赋值 / Early return, outputs assigned
END_IF

// ---------- 主轴位置 NaN 拦截 ----------
IF fMasterPos <> fMasterPos THEN
    eErr := 16#0004_0316;                     // 位置非法码 / Illegal position code
    RETURN;                                   // 提前返回：输出已全赋值 / Early return, outputs assigned
END_IF

// ---------- 周期模式取模（分母前判零） ----------
fPos := fMasterPos;
IF bPeriodic THEN
    fPos := fMasterPos - DINT_TO_LREAL(TRUNC(fMasterPos / fPeriod)) * fPeriod; // 取模 / Modulo
    IF fPos < 0.0 THEN
        fPos := fPos + fPeriod;               // 负余数钳回正域 / Negative remainder fixed
    END_IF
END_IF

// ---------- 界外处理：非周期钳端点并置界外标志 ----------
IF fPos <= aCam[0].fMaster THEN
    fSlavePos := aCam[0].fSlave;              // 界下钳首点 / Clamp to first point
    IF fPos < aCam[0].fMaster THEN
        bInRange := FALSE;                    // 严格界外标志 / Strictly out of range
    ELSE
        bInRange := TRUE;                     // 恰在首点界内 / Exactly at first point
    END_IF
    RETURN;
END_IF
IF fPos >= aCam[nPts - 1].fMaster THEN
    fSlavePos := aCam[nPts - 1].fSlave;       // 界上钳末点 / Clamp to last point
    IF fPos > aCam[nPts - 1].fMaster THEN
        bInRange := FALSE;
    ELSE
        bInRange := TRUE;
    END_IF
    RETURN;
END_IF

// ---------- 段定位与线性插值 ----------
bInRange := TRUE;                             // 界内插值 / In-range interpolation
i := 0;
WHILE (i < nPts - 2) AND (fPos > aCam[i + 1].fMaster) DO
    i := i + 1;                               // 定位所在段 / Locate segment
END_WHILE
fDen := aCam[i + 1].fMaster - aCam[i].fMaster; // 段宽 / Segment width
IF fDen > 0.0 THEN
    fRatio := (fPos - aCam[i].fMaster) / fDen; // 除法前判零 / Zero-guarded divide
    fSlavePos := aCam[i].fSlave + fRatio * (aCam[i + 1].fSlave - aCam[i].fSlave); // 插值 / Interpolate
ELSE
    fSlavePos := aCam[i].fSlave;              // 零段宽防御取左点 / Zero-width defensive
END_IF

END_FUNCTION
