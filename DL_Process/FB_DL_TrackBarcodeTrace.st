//==============================================================================
// 功能块：FB_DL_TrackBarcodeTrace ｜ 中文名称：托盘条码路由追溯
// 所属子库：DL_Process ｜ 版本：v1.0.0 ｜ 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 功能描述：托盘条码扫码路由——触发沿进扫码态，扫码枪以「bScanDone +
//           sBarcode」契约回读（R49 字符串纪律：超限截断判定在钳长
//           之前）；判据：前缀 A 匹配 → A 道、前缀 B 匹配 → B 道、
//           空码或双前缀均不匹配 → 拒收道；扫码超时（触发后超时窗满
//           bScanDone 未到）→ 故障。追溯码（sTraceCode）随路由结果
//           锁存输出，供上位追溯链消费。触发到判定的握手为单次有效
//           （bScanDone 需在触发后、超时窗内到，迟到作废）。
// 开源溯源 (Origin)：道莅原创实现（参考产线追溯与分道路由工程惯例 分类与参数域）
// 单位表：时间[ms] / 字符串长度[字符] / 道别[—]
// 错误码表：16#0005_01F6 信息级（路由判定完成：分道结果当拍有效，不置
//           bError）/ 16#0005_01F7 信息级（空码或无匹配按拒收路由降级
//           提示，不置 bError）/ 16#0005_0336 故障级（扫码超时：超时窗
//           满 bScanDone 未到，锁存，置 bError——该场景不可由 0337 的
//           组态类判据观测，属扫码枪握手独立域）/ 16#0005_0337 故障级
//           （组态非法：两前缀均为空字符串，判据无定义，置 bError）/
//           16#0005_0338 故障级兜底（状态机落 ELSE，置 bError）
// 状态机：E_DL_BarcodeRouteState（四态：eIdle=0 / eScanning=10 /
//           eRouted=20 / eFault=99），CASE 含 ELSE 兜底，ELSE 置 0338
//           并清路由输出
// 边界行为：① 组态非法（双前缀均空）→ 故障态锁存，bReset 复位；②
//           扫码态新触发沿不重置（单次握手，防连击）；③ 空码/无匹配
//           → 拒收道 + 信息 01F7 降级可观测；④ 迟到的 bScanDone（超时
//           后）作废不判（防陈旧数据误路由）；⑤ 未触发/故障态路由输出
//           清零并 bValid := FALSE；⑥ eRouted 等触发撤销回空闲（同拍
//           重启防抖，R39 范式）。
// 修订历史：v1.0.0 2026-11-17 首版（R24 派单 · ROADMAP P0 §469）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_BarcodeRouteState（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 扫码路由相位，每个成员在 CASE 中有且仅有一个标签。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_BarcodeRouteState :
(
    eIdle     := 0,   // 空闲：等触发沿 / Idle, awaiting trigger edge
    eScanning := 10,  // 扫码：等握手或超时 / Scanning, awaiting handshake or timeout
    eRouted   := 20,  // 已路由：结果锁存，等触发撤销 / Routed, result latched, awaiting trigger drop
    eFault    := 99   // 故障：超时/组态/非法状态 / Fault, timeout, config or illegal state
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举: E_DL_LaneRoute（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 分道判定结果。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_LaneRoute :
(
    eNone    := 0,   // 无判定：未路由 / None, not routed
    eLaneA   := 1,   // A 道：前缀 A 匹配 / Lane A, prefix A matched
    eLaneB   := 2,   // B 道：前缀 B 匹配 / Lane B, prefix B matched
    eReject  := 3    // 拒收道：空码或无匹配 / Reject lane, empty or unmatched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TrackBarcodeTrace
VAR_INPUT
    bTrigger      : BOOL;                   // 触发扫码 [—]，上升沿生效 / Trigger scan, rising edge
    bReset        : BOOL;                   // 故障复位 [—]，上升沿清故障态 / Fault reset, rising edge clears the fault state
    sBarcode      : STRING(32);             // 扫码枪回读码 [字符]，超 32 字符截断（截断判定先于钳长，R49） / Scanner barcode [chars], truncated beyond 32
    bScanDone     : BOOL;                   // 扫码完成握手 [—]（单次有效） / Scan-done handshake, single-shot
    sRoutePrefixA : STRING(8) := 'A';       // A 道前缀 [字符]，两前缀不得均空 / Lane A prefix [chars]
    sRoutePrefixB : STRING(8) := 'B';       // B 道前缀 [字符] / Lane B prefix [chars]
    tScanTimeout  : TIME  := T#2S;          // 扫码超时窗 [ms]，须 > 0 / Scan timeout window [ms]
END_VAR
VAR_OUTPUT
    eRoute     : E_DL_LaneRoute;            // 分道判定 [—] / Lane verdict
    bLaneA     : BOOL;                      // A 道输出 [—] / Lane A output
    bLaneB     : BOOL;                      // B 道输出 [—] / Lane B output
    bReject    : BOOL;                      // 拒收道输出 [—] / Reject lane output
    sTraceCode : STRING(32);                // 追溯码 [字符]（路由结果锁存随行） / Trace code [chars], latched with the verdict
    eState     : E_DL_BarcodeRouteState;    // 相位出口 [—] / Phase outlet
    eErr       : UDINT;                     // 错误码，0 = 无错，码位 16#0005_01F6 起信息级、16#0005_0336 起故障级（分带见错误码表） / Error code, 0 = no error, band info/fault per the code table
    bError     : BOOL;                      // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid     : BOOL;                      // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    fbTimeout : TON;                        // 扫码超时计时（每拍无条件刷新）[ms] / Scan timeout timer, refreshed unconditionally
    fbTrig    : R_TRIG;                     // 触发沿检测（待机/故障分支同样无条件刷新） / Trigger edge detector, refreshed unconditionally
    _eState   : E_DL_BarcodeRouteState := E_DL_BarcodeRouteState.eIdle; // 当前相位 / Current phase
    _bCfgBad  : BOOL;                       // 组态非法锁存 / Illegal config latch
    _eVerdict : E_DL_LaneRoute := E_DL_LaneRoute.eNone; // 判定暂存 / Verdict staging
    _sCapture : STRING(32);                 // 捕获码暂存 [字符] / Captured barcode staging [chars]
    _bInfoRoute: BOOL;                      // 判定完成信息当拍标志 / Verdict info flag of this scan
    _bInfoRej : BOOL;                       // 拒收降级信息当拍标志 / Reject-degrade info flag of this scan
    _bIllegal : BOOL;                       // 非法状态标志 / Illegal state flag
    _bInit    : BOOL := FALSE;              // 首扫标志，初值 FALSE 取非判定 / First-scan flag, tested negated
    _nLen     : INT;                        // 回读码长度 [字符] / Barcode length [chars]
END_VAR
VAR CONSTANT
    DL_TBT_STR_MAX : INT := 32;             // 追溯码容量上限 [字符] / Trace-code capacity [chars]
    DL_TBT_ZERO    : INT := 0;              // 零值常量，避免裸字面量 [字符] / Zero constant, avoids a bare literal [chars]
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜每拍预置：路由输出先清（安全侧），单拍标志预清零
 *      Route outputs cleared fail-safe first, one-shot flags pre-cleared
 *-----------------------------------------------------------------------------*)
eRoute   := E_DL_LaneRoute.eNone;        // 分道判定先清 / Verdict cleared first
bLaneA   := FALSE;                       // A 道先清 / Lane A cleared first
bLaneB   := FALSE;                       // B 道先清 / Lane B cleared first
bReject  := FALSE;                       // 拒收道先清 / Reject cleared first
sTraceCode := '';                        // 追溯码先清（路由态在段 5 重置） / Trace code cleared first
eErr   := 16#0000_0000;                  // 错误码每拍重算 / Error code recomputed
bError := FALSE;                         // 故障标志每拍重算 / Fault flag recomputed
bValid := FALSE;                         // 可用标志每拍重算 / Usable flag recomputed
_bInfoRoute := FALSE;                    // 判定信息预清零 / Verdict info pre-cleared
_bInfoRej   := FALSE;                    // 拒收信息预清零 / Reject info pre-cleared
_bIllegal   := FALSE;                    // 非法状态预清零 / Illegal flag pre-cleared

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化
 *      First-scan initialisation
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _eState  := E_DL_BarcodeRouteState.eIdle; // 相位空闲起步 / Phase starts idle
    _bCfgBad := FALSE;                   // 组态锁存清零 / Config latch cleared
    _bInit   := TRUE;                    // 首扫只做一次 / The first scan runs once
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜组态闸 + 沿/超时无条件刷新（R40：CASE 之外每拍必调）
 *      Config gate plus unconditional refresh per R40
 *-----------------------------------------------------------------------------*)
fbTrig(CLK := bTrigger);                 // 触发沿检测 / Trigger edge detection
fbTimeout(IN := (_eState = E_DL_BarcodeRouteState.eScanning), PT := tScanTimeout); // 扫码超时窗 / Scan timeout window
IF (LEN(sRoutePrefixA) = DL_TBT_ZERO) AND (LEN(sRoutePrefixB) = DL_TBT_ZERO) THEN
    _bCfgBad := TRUE;                    // 双前缀均空：判据无定义锁存（0337） / Both prefixes empty, criteria undefined
END_IF
IF bReset THEN
    _bCfgBad := FALSE;                   // 复位清组态锁存 / Reset clears the config latch
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜相位机（CASE 含 ELSE 兜底；状态改写只出现在分支判据内，R39）
 *      Phase machine with ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE _eState OF

    E_DL_BarcodeRouteState.eIdle:          // 空闲：触发沿且组态合法进扫码
        IF fbTrig.Q AND (NOT _bCfgBad) THEN
            _eState := E_DL_BarcodeRouteState.eScanning; // 进扫码 / To scanning
        ELSIF fbTrig.Q AND _bCfgBad THEN
            _eState := E_DL_BarcodeRouteState.eFault; // 组态非法进故障 / Illegal config to fault
        END_IF

    E_DL_BarcodeRouteState.eScanning:      // 扫码：握手判定或超时
        IF _bCfgBad THEN
            _eState := E_DL_BarcodeRouteState.eFault; // 组态漂移转故障 / Config drift, fault
        ELSIF fbTimeout.Q THEN
            _eState := E_DL_BarcodeRouteState.eFault; // 超时进故障（迟到的握手作废） / Timeout to fault, late handshake void
        ELSIF bScanDone THEN
            _nLen := LEN(sBarcode);        // 回读码长度 [字符] / Barcode length
            IF _nLen = DL_TBT_ZERO THEN
                _eVerdict := E_DL_LaneRoute.eReject; // 空码拒收（R49：判定在钳长前） / Empty barcode, reject
                _bInfoRej := TRUE;         // 拒收降级提示（信息级） / Reject-degrade notice, info
            ELSE
                IF _nLen > DL_TBT_STR_MAX THEN
                    _nLen := DL_TBT_STR_MAX; // 超限先置截断判定再钳长（本件容量即 32，防御路径） / Truncation verdict before the clamp per R49
                    _bInfoRej := TRUE;     // 截断归拒收降级提示（信息级） / Truncation folded into the degrade notice
                END_IF
                _sCapture := LEFT(sBarcode, _nLen); // 钳长后捕获 / Captured after the clamp
                IF (LEN(sRoutePrefixA) > DL_TBT_ZERO)
                   AND (LEFT(_sCapture, LEN(sRoutePrefixA)) = sRoutePrefixA) THEN
                    _eVerdict := E_DL_LaneRoute.eLaneA; // 前缀 A 匹配 → A 道 / Prefix A matched
                ELSIF (LEN(sRoutePrefixB) > DL_TBT_ZERO)
                   AND (LEFT(_sCapture, LEN(sRoutePrefixB)) = sRoutePrefixB) THEN
                    _eVerdict := E_DL_LaneRoute.eLaneB; // 前缀 B 匹配 → B 道 / Prefix B matched
                ELSE
                    _eVerdict := E_DL_LaneRoute.eReject; // 无匹配拒收 / No match, reject
                    _bInfoRej := TRUE;     // 拒收降级提示（信息级） / Reject-degrade notice, info
                END_IF
            END_IF
            _eState := E_DL_BarcodeRouteState.eRouted; // 进路由态锁存 / To routed, latched
        END_IF

    E_DL_BarcodeRouteState.eRouted:        // 已路由：等触发撤销回空闲（同拍重启防抖）
        IF NOT bTrigger THEN
            _eVerdict := E_DL_LaneRoute.eNone; // 判定复位 / Verdict reset
            _eState := E_DL_BarcodeRouteState.eIdle; // 回空闲 / Back to idle
        END_IF

    E_DL_BarcodeRouteState.eFault:         // 故障：复位沿且原因消失回空闲
        IF bReset AND (NOT _bCfgBad) THEN
            _eState := E_DL_BarcodeRouteState.eIdle; // 回空闲 / Back to idle
        END_IF

    ELSE                                   // 非法状态兜底（R21：CASE 必带 ELSE）
        _bIllegal := TRUE;                 // 标记非法状态 / Flag the illegal state
        _eVerdict := E_DL_LaneRoute.eNone; // 判定复位 / Verdict reset
        _eState := E_DL_BarcodeRouteState.eFault; // 回故障态 / Back to fault
END_CASE

(*------------------------------------------------------------------------------
 * 段 5｜路由出口（eRouted 态单源赋值；互斥由 IF/ELSE 结构性成立）
 *      Route outlet, single-source in the routed phase
 *-----------------------------------------------------------------------------*)
CASE _eVerdict OF
    E_DL_LaneRoute.eLaneA:                 // A 道 / Lane A
        bLaneA := TRUE;                    // A 道输出 / Lane A output
    E_DL_LaneRoute.eLaneB:                 // B 道 / Lane B
        bLaneB := TRUE;                    // B 道输出 / Lane B output
    E_DL_LaneRoute.eReject:                // 拒收道 / Reject lane
        bReject := TRUE;                   // 拒收道输出 / Reject output
    ELSE                                   // 无判定：输出全清 / No verdict, all clear
        _eVerdict := _eVerdict;            // 保持预置清零（判定维持空档，显式自持）/ Stays cleared (explicit self-hold)
END_CASE
IF _eState = E_DL_BarcodeRouteState.eRouted THEN
    eRoute := _eVerdict;                   // 判定出口（路由态） / Verdict outlet in the routed phase
    IF _eVerdict <> E_DL_LaneRoute.eNone THEN
        sTraceCode := _sCapture;           // 追溯码随行（仅有效判定） / Trace code attached to a valid verdict
        _bInfoRoute := TRUE;               // 判定完成信息（信息级） / Verdict-done info
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜码位出口与放行（故障级码 3 行内置 bError，R45/R101 配对）
 *      Code outlet and release, fault codes paired with bError
 *-----------------------------------------------------------------------------*)
IF _bIllegal THEN
    eErr   := 16#0005_0338;                // 故障级：状态机兜底 / Fault: state machine fallback
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bCfgBad THEN
    eErr   := 16#0005_0337;                // 故障级：组态非法（双前缀均空） / Fault: illegal configuration
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF (_eState = E_DL_BarcodeRouteState.eFault) AND (NOT _bCfgBad) THEN
    eErr   := 16#0005_0336;                // 故障级：扫码超时 / Fault: scan timeout
    bError := TRUE;                        // 置故障标志 / Raise the fault flag
ELSIF _bInfoRej THEN
    eErr := 16#0005_01F7;                  // 信息级：空码/无匹配/截断按拒收降级 / Info: reject-degrade notice
ELSIF _bInfoRoute THEN
    eErr := 16#0005_01F6;                  // 信息级：路由判定完成 / Info: verdict done
END_IF

bValid := (NOT bError) AND (_eState = E_DL_BarcodeRouteState.eRouted); // 仅路由态放行 / Usable only in the routed phase
eState := _eState;                       // 相位出口 / Phase outlet
END_FUNCTION_BLOCK
