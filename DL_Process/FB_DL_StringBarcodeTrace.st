// =====================================================================
// FB_DL_StringBarcodeTrace.st
// 电池串条码绑定与工位路由（校验→拼接追溯键→查重→首绑定为准）
// Barcode binding and station routing FB
// 码位: 16#0005_0453 ~ 16#0005_0457 (本件独占 5 槽)
// 修改记录: R29 初版 (按 DISPATCH_R29 序 17)
// =====================================================================
FUNCTION_BLOCK FB_DL_StringBarcodeTrace
VAR_INPUT
    bEnable      : BOOL  := FALSE;    // 使能 / Enable
    bReset       : BOOL  := FALSE;    // 复位（含清重码计数）/ Reset
    bCodeValid   : BOOL  := FALSE;    // 扫码完成有效（脉冲）/ Code valid pulse
    sCode        : STRING(32) := '';  // 扫码内容，32 字符上限 / Scanned code
    sLotKey      : STRING(16) := '';  // 批次键（外部下发）/ Lot key
    uStationIdx  : USINT  := 1;       // 当前工位号 1~99 / Station index
    uStationCnt  : USINT  := 8;       // 工位总数 1~99 / Station count
    uLenMin      : USINT  := 8;       // 码最小长度 1~32 / Min length
    uLenMax      : USINT  := 24;      // 码最大长度 1~32 / Max length
    uDupMax      : USINT  := 3;       // 连续重码报警次数 1~20 / Duplicate alarm count
END_VAR
VAR_OUTPUT
    sBindingKey  : STRING(64);        // 追溯键 Lot|Station|Code / Binding key
    uRouteIdx    : USINT;             // 路由工位号 / Route index
    bRouteValid  : BOOL;              // 路由有效（可放行）/ Route valid
    bDuplicate   : BOOL;              // 重码（首绑定未被覆盖）/ Duplicate
    uDupCnt      : USINT;             // 连续重码计数 / Consecutive duplicate count
    eErr         : UDINT;             // 错误码 / Error code
END_VAR
VAR
    rtrigValid   : R_TRIG;            // 扫码有效沿检测（无条件刷新）/ Code valid edge detector
    aDupCode     : ARRAY[0..31] OF STRING(32);    // 重码环形记录表 / Duplicate ring records
    uDupHead     : USINT;             // 环形写指针 / Ring write pointer
    uDupFill     : USINT;             // 环形已存条数 / Ring filled count
    uIdx         : USINT;             // 查重循环下标 / Search loop index
    uLen         : USINT;             // 码长度 / Code length
    uChar        : USINT;             // 字符循环下标 / Char loop index
    sChar        : STRING(1);         // 单字符临时 / Single char temp
    bCharOK      : BOOL;              // 字符合法标记 / Char valid flag
    uLotLen      : USINT;             // 批次键长度 / Lot key length
    uStLen       : USINT;             // 工位号字符串长度 / Station string length
    uTotalLen    : USINT;             // 拼接结果总长（先算后拼）/ Total result length
    sStTmp       : STRING(8);         // 工位号字符串临时 / Station string temp
    bDupFound    : BOOL;              // 重码命中标记 / Duplicate found flag
    bLockLatch   : BOOL := FALSE;     // 连续重码故障锁存 / Consecutive dup fault latch
    xFirstScan   : BOOL  := TRUE;     // 首扫标记 / First-scan flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占，勿复用）:
//   16#0005_0453 信息 绑定成功、码唯一
//   16#0005_0454 故障 sLotKey 为空 / bCodeValid 时 sCode 为空串
//   16#0005_0455 故障 uStationIdx > uStationCnt / uStationCnt = 0 / uLenMin > uLenMax（组态错）
//   16#0005_0456 信息 码格式非法（长度/字符集不符）→ 拒收，bRouteValid=FALSE；拼接超限截断同登记
//   16#0005_0457 故障 bDuplicate 连续 uDupMax 次 → 锁存（uDupCnt ≥ uDupMax）
// ---------------------------------------------------------------------

// ---- 扫码沿检测（无条件刷新，R47 边沿纪律）/ Code valid edge, unconditional ----
rtrigValid(CLK := bCodeValid);  // 沿检测 / Edge detection

// ---- 组态错闸 / Configuration fault gate ----
IF (uStationCnt = 0) OR (uStationIdx > uStationCnt) OR (uLenMin > uLenMax)
   OR (uLenMin = 0) OR (uDupMax = 0) THEN
    bRouteValid := FALSE;       // 路由撤销 / Route invalid
    eErr := 16#0005_0455;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 首扫初始化（R16 首扫纪律）/ First-scan initialization ----
IF xFirstScan THEN
    bRouteValid := FALSE;       // 路由初始无效 / Route init invalid
    uRouteIdx := 0;             // 路由号清零 / Route cleared
    xFirstScan := FALSE;        // 清标记 / Clear flag
END_IF

// ---- 复位：清重码计数与重码表 / Reset: clear dup count and table ----
IF bReset THEN
    uDupCnt := 0;               // 计数清零 / Count cleared
    bDuplicate := FALSE;        // 重码复位 / Duplicate reset
    bLockLatch := FALSE;        // 锁存解除 / Latch released
    FOR uIdx := 0 TO 31 DO
        aDupCode[uIdx] := '';   // 重码表清空 / Table cleared
    END_FOR
    uDupHead := 0;              // 指针归零 / Pointer reset
    uDupFill := 0;              // 填充数清零 / Fill reset
END_IF

// ---- 使能撤销 / Disable ----
IF NOT bEnable THEN
    bRouteValid := FALSE;       // 路由撤销 / Route invalid
    bDuplicate := FALSE;        // 重码复位 / Duplicate reset
    eErr := 16#0005_0453;       // 信息级：空闲 / Info: idle
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 连续重码锁存路径 / Consecutive duplicate latch path ----
IF bLockLatch THEN
    bRouteValid := FALSE;       // 放行撤销 / Route invalid
    eErr := 16#0005_0457;       // 故障码回放 / Fault code replay
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 非沿拍维持原状 / Non-edge cycles hold state ----
IF NOT rtrigValid.Q THEN
    RETURN;                     // 绑定结果与路由保持 / Binding and route hold
END_IF

// ---- 批次键/码空闸（故障级）/ Empty lot or code gate ----
uLotLen := LEN(sLotKey);        // 批次键长度 / Lot length
uLen := LEN(sCode);             // 码长度 / Code length
IF (uLotLen = 0) OR (uLen = 0) THEN
    bRouteValid := FALSE;       // 路由撤销 / Route invalid
    eErr := 16#0005_0454;       // 故障码 / Fault code
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 长度校验（越界拒收信息级）/ Length validation ----
IF (uLen < uLenMin) OR (uLen > uLenMax) THEN
    bRouteValid := FALSE;       // 拒收 / Rejected
    eErr := 16#0005_0456;       // 信息级：格式非法 / Info: format invalid
    RETURN;                     // 本拍结束 / End of cycle
END_IF

// ---- 字符集校验：只允许数字与字母 / Charset validation: digits and letters only ----
bCharOK := TRUE;                // 先假设合法 / Assume valid
FOR uChar := 1 TO uLen DO
    sChar := MID(sCode, 1, uChar);      // 取单字符 / Extract char
    // 字典序判数字/大写/小写（纯 IEC 61131-3 字符串比较，不用非标准 ASCII 函数）
    // Lexicographic alnum check, pure IEC string comparison
    IF NOT (((sChar >= '0') AND (sChar <= '9'))
        OR ((sChar >= 'A') AND (sChar <= 'Z'))
        OR ((sChar >= 'a') AND (sChar <= 'z'))) THEN
        bCharOK := FALSE;       // 非数字字母 / Not alnum
    END_IF
END_FOR
IF NOT bCharOK THEN
    bRouteValid := FALSE;       // 拒收 / Rejected
    eErr := 16#0005_0456;       // 信息级：格式非法 / Info: format invalid
    RETURN;                     // uRouteIdx 不变 / Route holds
END_IF

// ---- 查重：环形表线性比对 / Duplicate search in ring table ----
bDupFound := FALSE;             // 命中复位 / Reset hit
FOR uIdx := 0 TO 31 DO
    IF (uIdx < uDupFill) AND (aDupCode[uIdx] = sCode) THEN
        bDupFound := TRUE;      // 命中 / Hit
    END_IF
END_FOR

IF bDupFound THEN
    // 重码：不覆盖首绑定，计数递增 / Duplicate: first binding kept, count up
    bDuplicate := TRUE;         // 重码标志 / Duplicate flag
    uDupCnt := uDupCnt + 1;     // 计数 / Count
    bRouteValid := FALSE;       // 本次不放行 / Not released
    IF uDupCnt >= uDupMax THEN
        bLockLatch := TRUE;     // 连续重码 → 锁存 / Latch on consecutive dups
        eErr := 16#0005_0457;   // 故障码 / Fault code
    ELSE
        eErr := 16#0005_0456;   // 信息级：重码拒收 / Info: duplicate rejected
    END_IF
    RETURN;                     // sBindingKey 保持首次值 / Binding key holds first value
END_IF

// ---- 拼接追溯键：先算后拼（上限 64，超限截 63 并置槽 4）/ Build key: compute length first ----
uStLen := 2;                    // 工位号最多两位数（1~99）/ Station digits max 2
uTotalLen := uLotLen + 1 + uStLen + 1 + uLen;   // Lot + | + St + | + Code / Total length
IF uTotalLen > 64 THEN
    // 超限：截 63 写入并登记（禁越界写）/ Over limit: truncate to 63
    sBindingKey := CONCAT(sLotKey, '|');
    sBindingKey := CONCAT(sBindingKey, USINT_TO_STRING(uStationIdx));
    sBindingKey := CONCAT(sBindingKey, '|');
    sBindingKey := CONCAT(sBindingKey, LEFT(sCode, 63 - uLotLen - 1 - uStLen - 1));   // 截断码 / Truncated code
    bRouteValid := FALSE;       // 键不完整不放行 / Incomplete key, no release
    eErr := 16#0005_0456;       // 信息级：超限截断 / Info: truncated
    RETURN;                     // 本拍结束 / End of cycle
END_IF

sBindingKey := CONCAT(sLotKey, '|');                    // Lot| / Lot|
sBindingKey := CONCAT(sBindingKey, USINT_TO_STRING(uStationIdx));   // +Station / +Station
sBindingKey := CONCAT(sBindingKey, '|');                // +| / +|
sBindingKey := CONCAT(sBindingKey, sCode);              // +Code / +Code

// ---- 首次绑定登记：入环形表（满覆盖最旧并置信息）/ First binding: register into ring ----
aDupCode[uDupHead] := sCode;    // 登记码 / Register code
uDupHead := uDupHead + 1;       // 指针前移 / Pointer advance
IF uDupHead > 31 THEN
    uDupHead := 0;              // 回绕 / Wrap
END_IF
IF uDupFill < 32 THEN
    uDupFill := uDupFill + 1;   // 填充 / Fill
ELSE
    // 表满覆盖最旧：信息级提示（不影响放行逻辑）/ Table full: overwrite oldest
    eErr := 16#0005_0456;       // 信息级 / Info
END_IF

// ---- 绑定成功 / Binding success ----
bDuplicate := FALSE;            // 重码复位 / Duplicate reset
uRouteIdx := uStationIdx;       // 路由号 = 当前工位 / Route = station
bRouteValid := TRUE;            // 放行 / Released
IF eErr <> 16#0005_0456 THEN
    eErr := 16#0005_0453;       // 信息级：绑定成功 / Info: bound
END_IF

END_FUNCTION_BLOCK
