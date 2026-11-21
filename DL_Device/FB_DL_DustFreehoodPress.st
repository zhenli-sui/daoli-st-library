(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DustFreehoodPress
 * 溯源说明 (Provenance) : 道莅 clean-room 防御性实现（路线图 L363 已登记项）
 * 所属子库 (Sublibrary) : DL_Device / CleanroomDiag
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop；
 *                         纯 IEC 61131-3（第 3 版），零标准库依赖
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 洁净风帽压差梯度监视
 * 功能一句话 (Summary)  : 多房间压差梯度校核 + 倒序最差相邻对定位 + 级联告警。
 * 边界与安全 (Boundary) : ①任一传感器失效 → 全列输出保持 + 告警（安全侧）；
 *                         ②房间数小于 2 → 配置非法码不判定；
 *                         ③压差非有限或负值 → 视同传感器失效（安全侧）；
 *                         ④相邻对下标全程钳位（禁越界访问）；
 *                         ⑤梯度约定：房间序号递增方向压差递减（洁净度梯度）。
 * 错误码    : 16#0003_0387 传感器失效（任一房间或通道失效）——故障级（持续态）
 *             16#0003_0388 级联梯度不足（最差相邻对低于门限）——故障级（持续态）
 *             16#0003_0389 配置非法（房间数不足 2）——故障级（持续态）
 * 码位总账  : 16#0003_0387 用 / 16#0003_0388 用 / 16#0003_0389 用
 * 修改记录  : v1.0.0 R26 初版
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_DustFreehoodPress
VAR_INPUT
    afPress     : ARRAY[*] OF LREAL; // 各房间压差 [Pa]（序号递增为洁净度递增方向）/ Room differential pressures [Pa]
    fMinCascade : LREAL; // 相邻级最小梯度 [Pa] / Minimum adjacent cascade step [Pa]
    bSensorOk   : BOOL;  // 传感器通道自诊断 OK / Sensor channel self-check OK
END_VAR
VAR_OUTPUT
    bCascadeOk : BOOL; // 梯度全部达标 / All cascade steps qualified
    uWorstPair : UINT; // 倒序最差相邻对索引（压差[i]-压差[i+1] 最小者的 i）/ Worst adjacent pair index
    bRankAlarm : BOOL; // 级联排序告警 / Cascade ranking alarm
    eErr       : UDINT; // 本周期错误码，0=无错 / Error code this cycle, 0 = none
END_VAR
VAR
    iRooms  : INT;  // 房间数 / Room count
    i       : INT;  // 相邻对游标 / Adjacent pair cursor
    iWorst  : INT;  // 最差对内部值 / Worst pair internal
    fStep   : LREAL; // 当前相邻对梯度 / Current adjacent step
    fWorst  : LREAL; // 最差梯度值 / Worst gradient value
    bHold   : BOOL;  // 保持态判据 / Hold-state predicate
    fGrd    : LREAL; // 压差守卫副本 / Pressure guard copy
END_VAR

// ---------- 周期起点：错误码先清（持续态随后重置） ----------
eErr := 0;

// ---------- 配置防御：房间数不足 2 不判定 ----------
iRooms := UPPER_BOUND(afPress, 1) + 1;        // 房间数 / Room count
IF iRooms < 2 THEN
    bCascadeOk := FALSE;                      // 不判定安全侧 / Safe-side default
    uWorstPair := 0;                          // 索引缺省 / Index default
    bRankAlarm := FALSE;
    eErr := 16#0003_0389;                     // 配置非法码 / Illegal configuration code
    RETURN;
END_IF

// ---------- 传感器失效防御：全列保持（安全侧） ----------
bHold := (NOT bSensorOk) OR (fMinCascade <= 0.0) OR (fMinCascade <> fMinCascade);
IF bHold THEN
    IF NOT bSensorOk THEN
        bRankAlarm := TRUE;                   // 失效告警 / Failure alarm
        eErr := 16#0003_0387;                 // 传感器失效码 / Sensor failure code
    ELSE
        eErr := 16#0003_0389;                 // 门限非法视同配置非法 / Illegal threshold as config fault
    END_IF
    // bCascadeOk 与 uWorstPair 保持上拍锁存值（禁清零防误放行）/ Outputs held, no clear
    RETURN;
END_IF

// ---------- 逐相邻对校核：梯度递减约定（下标钳位） ----------
bCascadeOk := TRUE;                           // 先假设全达标 / Assume all qualified
iWorst := 0;
fWorst := 1.0E30;                             // 哨兵极大值 / Sentinel huge
FOR i := 0 TO iRooms - 2 DO
    fGrd := afPress[i];                       // 上游房间压差 / Upstream pressure
    IF (fGrd <> fGrd) OR ((fGrd - fGrd) <> (fGrd - fGrd)) OR (fGrd < 0.0) THEN
        bHold := TRUE;                        // 非有限或负值视同失效 / Non-finite or negative as failure
        eErr := 16#0003_0387;                 // 传感器失效码 / Sensor failure code
    ELSE
        fStep := afPress[i] - afPress[i + 1]; // 相邻对梯度 / Adjacent step
        IF fStep < fWorst THEN
            fWorst := fStep;                  // 更新最差值 / Update worst value
            iWorst := i;                      // 更新最差对索引 / Update worst index
        END_IF
        IF fStep < fMinCascade THEN
            bCascadeOk := FALSE;              // 梯度不足 / Step below threshold
        END_IF
    END_IF
END_FOR

// ---------- 失效保持出口：输出锁存不清（防误放行） ----------
IF bHold THEN
    bRankAlarm := TRUE;                       // 保持态告警 / Hold-state alarm
    RETURN;                                   // bCascadeOk/uWorstPair 锁存 / Outputs latched
END_IF

// ---------- 结论输出：最差对索引与告警 ----------
uWorstPair := INT_TO_UINT(iWorst);            // 倒序最差对索引 / Worst pair index exposed
IF bCascadeOk THEN
    bRankAlarm := FALSE;                      // 全达标不告警 / No alarm when qualified
ELSE
    bRankAlarm := TRUE;                       // 梯度不足告警 / Under-threshold alarm
    eErr := 16#0003_0388;                     // 级联梯度不足码 / Cascade deficit code
END_IF

END_FUNCTION_BLOCK
