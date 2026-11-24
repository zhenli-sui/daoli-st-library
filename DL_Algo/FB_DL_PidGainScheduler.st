(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PidGainScheduler
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（LGF Technology 深化 + 规划新增线）
 * 所属子库 (Sublibrary) : DL_Algo / ControlParams
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 增益调度查表插值
 * 功能一句话 (Summary)  : 按调度变量查增益表线性插值输出 Kp/Ti/Td，仅出参数不控回路。
 * 边界与安全 (Boundary) : ①调度变量低于首点/高于末点 → 端点钳位并置码 3705；
 *                         ②表未按 fVar 严格升序 → 码 3701 且 bHoldLast 生效保持上次输出；
 *                         ③调度变量 NaN → 码 3702 保持上次输出；
 *                         ④表点数不足 2 → 视同表非法（3701 复用）；
 *                         ⑤本件只产出参数，不内嵌控制回路（与 PID 件正交解耦）。
 * 错误码    : 16#0002_3701 增益表非法（未升序或点数不足）——故障级（持续态）
 *             16#0002_3702 调度变量 NaN（保持上次输出）——故障级（持续态）
 *             16#0002_3705 端点钳位发生——信息级（持续态）
 * 码位总账  : 16#0002_3701 用 / 16#0002_3702 用 / 16#0002_3705 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
TYPE ST_DL_GainPoint :
STRUCT
    fVar : LREAL; // 调度变量锚点 / Scheduling variable anchor
    fKp  : LREAL; // 该锚点比例增益 / Proportional gain at anchor
    fTi  : LREAL; // 该锚点积分时间 [s] / Integral time at anchor [s]
    fTd  : LREAL; // 该锚点微分时间 [s] / Derivative time at anchor [s]
END_STRUCT
END_TYPE

FUNCTION_BLOCK FB_DL_PidGainScheduler
VAR_INPUT
    fSchedVar  : LREAL; // 调度变量（如流量/温度工况）/ Scheduling variable
    bEnable    : BOOL;  // 使能：FALSE 保持上次输出 / Enable: FALSE holds last output
    bHoldLast  : BOOL;  // 表非法时保持上次输出 / Hold last output on illegal table
END_VAR
VAR_IN_OUT
    aGainTable : ARRAY[*] OF ST_DL_GainPoint; // 增益表，须按 fVar 升序 / Gain table, ascending by fVar
END_VAR
VAR_OUTPUT
    fKp   : LREAL; // 插值输出比例增益 / Interpolated proportional gain
    fTi   : LREAL; // 插值输出积分时间 [s] / Interpolated integral time [s]
    fTd   : LREAL; // 插值输出微分时间 [s] / Interpolated derivative time [s]
    eErr  : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    nPts    : INT;  // 表点数 / Table point count
    i       : INT;  // 分段搜索游标 / Segment search cursor
    fDen    : LREAL; // 分段分母（前判零）/ Segment denominator (zero-guarded)
    fRatio  : LREAL; // 段内插值比例 / Interpolation ratio
    bTableOk: BOOL; // 表合法性中间判据 / Table legality intermediate
    bHold   : BOOL; // 本拍保持输出判据 / Hold-output predicate this cycle
END_VAR

// ---------- 周期起点：错误码清零（持续态随后重置） ----------
eErr := 0;
bHold := FALSE;

// ---------- 使能为假：纯保持，不查表不刷新 ----------
IF NOT bEnable THEN
    bHold := TRUE;                            // 保持上次输出 / Hold last output
ELSE
    // ---------- 表点数与单调性防御 ----------
    nPts := UPPER_BOUND(aGainTable, 1) + 1;   // 表点数 / Point count
    bTableOk := nPts >= 2;                    // 至少两点 / At least two points
    IF bTableOk THEN
        FOR i := 0 TO nPts - 2 DO
            IF NOT (aGainTable[i].fVar < aGainTable[i + 1].fVar) THEN
                bTableOk := FALSE;            // 严格升序被破坏 / Strict order violated
            END_IF
        END_FOR
    END_IF
    IF NOT bTableOk THEN
        eErr  := 16#0002_3701;                // 表非法码 / Illegal table code
        bHold := bHoldLast;                   // 按调用方策略保持 / Hold per caller policy
    ELSE
        // ---------- NaN 调度变量：保持 ----------
        IF fSchedVar <> fSchedVar THEN
            eErr  := 16#0002_3702;            // NaN 码 / NaN code
            bHold := TRUE;                    // 强制保持 / Forced hold
        ELSE
            // ---------- 端点钳位与段内插值 ----------
            IF fSchedVar <= aGainTable[0].fVar THEN
                fKp := aGainTable[0].fKp;     // 低于首点钳端点 / Below first: clamp endpoint
                fTi := aGainTable[0].fTi;
                fTd := aGainTable[0].fTd;
                IF fSchedVar < aGainTable[0].fVar THEN
                    eErr := 16#0002_3705;     // 端点钳位码 / Endpoint clamp code
                END_IF
            ELSIF fSchedVar >= aGainTable[nPts - 1].fVar THEN
                fKp := aGainTable[nPts - 1].fKp; // 高于末点钳端点 / Above last: clamp endpoint
                fTi := aGainTable[nPts - 1].fTi;
                fTd := aGainTable[nPts - 1].fTd;
                IF fSchedVar > aGainTable[nPts - 1].fVar THEN
                    eErr := 16#0002_3705;     // 端点钳位码 / Endpoint clamp code
                END_IF
            ELSE
                i := 0;
                WHILE (i < nPts - 2) AND (fSchedVar > aGainTable[i + 1].fVar) DO
                    i := i + 1;               // 定位所在段 / Locate segment
                END_WHILE
                fDen := aGainTable[i + 1].fVar - aGainTable[i].fVar; // 段宽 / Segment width
                IF fDen > 0.0 THEN
                    fRatio := (fSchedVar - aGainTable[i].fVar) / fDen; // 除法前判零 / Zero-guarded divide
                    fKp := aGainTable[i].fKp + fRatio * (aGainTable[i + 1].fKp - aGainTable[i].fKp);
                    fTi := aGainTable[i].fTi + fRatio * (aGainTable[i + 1].fTi - aGainTable[i].fTi);
                    fTd := aGainTable[i].fTd + fRatio * (aGainTable[i + 1].fTd - aGainTable[i].fTd);
                ELSE
                    fKp := aGainTable[i].fKp; // 段宽为零防御取左点 / Zero-width defensive left point
                    fTi := aGainTable[i].fTi;
                    fTd := aGainTable[i].fTd;
                END_IF
            END_IF
        END_IF
    END_IF
END_IF

// ---------- 保持路径显式化：bHold 时三输出不动（锁存语义注释） ----------
// bHold=TRUE 期间 fKp/fTi/fTd 为上次有效锁存值，内部不引入实时镜像副本，
// 输出与内部判定共用同一组锁存变量，避免双口径混用。

END_FUNCTION_BLOCK
