// =====================================================================
// FB_DL_WaferScanRouter.st
// 晶圆盒扫码路由（扫码契约 + 花篮位取模索引 + 分道路由）
// Wafer cassette scan routing with modulo slot index
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_0467 ~ 16#0005_046B (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: semiconductor, barcode-routing, modulo-index, wafer
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 6)
// =====================================================================
FUNCTION_BLOCK FB_DL_WaferScanRouter
VAR_INPUT
    bScanTrigger : BOOL  := FALSE;  // 扫码触发沿 / Scan trigger edge
    sBarcode     : STRING := '';    // 条码内容（扫码器回读注入）/ Barcode content injected
    bReadOk      : BOOL  := FALSE;  // 读码有效标志 / Read valid flag
    uStationMod  : USINT := 1;      // 花篮位号 1~25, 0 = 组态非法 / Station number 1..25
    abRouteEn    : ARRAY[1..8] OF BOOL;  // 分道允许表, 位序对应分道 1..8 / Route enable table 1..8
    tScanTimeout : TIME  := T#2S;   // 扫码超时窗 T#10MS~T#60S / Scan timeout window [s]
END_VAR
VAR_OUTPUT
    uRouteSel    : USINT := 0;      // 选中分道 1~8, 0 = 拒收 / Selected route, 0 = reject
    bRouteOk     : BOOL  := FALSE;  // 路由成功标志 / Route accepted flag
    uSlotIdx     : USINT := 0;      // 花篮位取模索引 1~8 / Modulo slot index 1..8
    eErr         : UDINT := 16#0005_0467;  // 错误码 / Error code
END_VAR
VAR
    rtrScan      : R_TRIG;          // 扫码触发沿检测, 每拍无条件刷新 / Scan trigger edge, refreshed every cycle
    rtrRead      : R_TRIG;          // 读码有效沿检测, 每拍无条件刷新 / Read-valid edge, refreshed every cycle
    tonScan      : TON;             // 扫码超时定时器, 每拍无条件刷新 / Scan timeout timer, refreshed every cycle
    xBusy        : BOOL  := FALSE;  // 扫码窗进行中标志 / Scan window busy flag
    uRouteCnt    : USINT := 0;      // 使能分道计数 0~8 / Enabled route count 0..8
    uSlotCalc    : USINT := 1;      // 取模索引计算临时量 / Slot index calculation temporary
    uGuard       : USINT := 0;      // 条件减法守卫计数 / Conditional subtraction guard counter
    uZi          : INT   := 1;      // 1..8 数组下标 / Array subscript 1..8
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_0467 信息 路由成功
//   16#0005_0468 信息 组态非法拒收（花篮位号为 0 或分道全禁用）
//   16#0005_0469 故障 扫码超时未读（拒收）; 码随最近一次判定保持, 重新触发扫码即刷新解除
//   16#0005_046A 信息 读码失败拒收（条码数据在而有效标志为假, 与空串语义分离）
//   16#0005_046B 信息 空条码拒收（读码有效但条码长度为零）
// ---------------------------------------------------------------------

// ---- 分道使能计数 / Enabled route count ----
uRouteCnt := 0;                     // 计数复位 / Reset count
FOR uZi := 1 TO 8 DO
    IF abRouteEn[uZi] THEN
        uRouteCnt := uRouteCnt + 1; // 累计使能分道 / Count enabled route
    END_IF
END_FOR

// ---- 边沿与定时器实例无条件周期刷新（调用不进任何 IF 分支）/ Unconditional edge and timer refresh ----
rtrScan(CLK := bScanTrigger);       // 扫码触发沿 / Scan trigger edge
rtrRead(CLK := bReadOk);            // 读码有效沿 / Read valid edge
tonScan(IN := xBusy, PT := tScanTimeout);   // 扫码窗计时 / Scan window timing

// ---- 触发沿启动扫码窗 / Trigger edge starts scan window ----
IF rtrScan.Q THEN
    xBusy := TRUE;                  // 拍 N 进入扫码窗 / Enter scan window
END_IF

// ---- 扫码窗内判定 / Judgement inside scan window ----
IF xBusy THEN
    IF tonScan.Q THEN
        // 本拍行为: 超时拒收并关窗 / Timeout reject and close window
        uRouteSel := 0;             // 拒收 / Reject
        uSlotIdx  := 0;             // 索引无效 / Index void
        bRouteOk  := FALSE;         // 路由失败 / Route failed
        eErr      := 16#0005_0469;  // 扫码超时 / Scan timeout
        xBusy     := FALSE;         // 拍 N+1 窗关闭, 等下次触发 / Window closed
    ELSIF bReadOk AND (LEN(sBarcode) = 0) THEN
        // 空条码: 读码有效但无内容 / Empty barcode: valid flag but no content
        uRouteSel := 0;
        uSlotIdx  := 0;
        bRouteOk  := FALSE;
        eErr      := 16#0005_046B;  // 空条码拒收 / Empty barcode reject
        xBusy     := FALSE;
    ELSIF (NOT bReadOk) AND (LEN(sBarcode) > 0) THEN
        // 读码失败: 数据在而有效标志为假 / Read failed: data present, valid flag false
        uRouteSel := 0;
        uSlotIdx  := 0;
        bRouteOk  := FALSE;
        eErr      := 16#0005_046A;  // 读码失败拒收 / Read-fail reject
        xBusy     := FALSE;
    ELSIF bReadOk AND (LEN(sBarcode) > 0) THEN
        // 读码成功: 组态校验后路由 / Read ok: config check then route
        IF (uStationMod = 0) OR (uRouteCnt = 0) THEN
            uRouteSel := 0;         // 组态非法拒收 / Config illegal reject
            uSlotIdx  := 0;
            bRouteOk  := FALSE;
            eErr      := 16#0005_0468;
        ELSE
            // 取模索引: 条件减法实现, 不用取余运算（跨平台负数歧义禁令）
            // Modulo by conditional subtraction, no remainder operator
            uSlotCalc := uStationMod;       // 从花篮位号起算 / Start from station number
            uGuard    := 0;                 // 守卫计数清零 / Clear guard
            WHILE (uSlotCalc > uRouteCnt) AND (uGuard < 32) DO
                uSlotCalc := uSlotCalc - uRouteCnt;     // 减一轮分道数 / Subtract one route round
                uGuard    := uGuard + 1;                // 守卫计数防死循环 / Guard against dead loop
            END_WHILE
            uSlotIdx := uSlotCalc;      // 输出取模索引 1..分道数 / Output slot index
            // 路由选择: 升序取首个使能分道 / Route select: first enabled ascending
            uRouteSel := 0;
            FOR uZi := 1 TO 8 DO
                IF (uRouteSel = 0) AND abRouteEn[uZi] THEN
                    uRouteSel := INT_TO_USINT(uZi);     // 首个使能分道 / First enabled route
                END_IF
            END_FOR
            bRouteOk := TRUE;           // 路由成功 / Route accepted
            eErr     := 16#0005_0467;   // 正常码 / Normal code
        END_IF
        xBusy := FALSE;                 // 判定完成关窗 / Judgement done, close window
    END_IF
END_IF

END_FUNCTION_BLOCK
