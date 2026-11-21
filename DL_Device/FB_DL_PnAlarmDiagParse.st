(*==============================================================================
 * 组件名称 (Component)  : FB_DL_PnAlarmDiagParse
 * 所属子库 (Sublibrary) : DL_Device
 * 前缀     (Prefix)     : FB_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版），
 *                         仅依赖标准函数 LEN / LEFT / CONCAT，零厂商方言、
 *                         零厂商专有库依赖
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 公开 PROFINET 告警分级语义（告警码到严重度/
 *                         描述/可重试性三出口）clean-room 借鉴，段表组织
 *                         参考本库 StatusWordSegDecoder 范式，
 *                         IEC 61131-3 标准语义的道莅防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : PROFINET 告警语义解析监视件。四元组（告警类别/
 *                         槽号/端口号/诊断码）一律引脚注入，不绑厂商系统
 *                         变量名。查表驱动输出三出口：严重度枚举、中文描述、
 *                         可重试性；未收录码兜底「未知-告警-不可重试」。
 *                         输出在告警到达沿或诊断码变化拍刷新，其余拍保持。
 * 码位     (Codes)      : 16#0003_00FC 信息级：入参非法（槽/端口越域或类别
 *                                      非法，早退，不置 bError）
 *                         16#0003_00FD 信息级：诊断码未收录（兜底出口）
 *                         16#0003_00FE~0100 保留未启用（仅监视件不置 bError，
 *                         码表与实现对齐，不虚声明）
 * 边界防错 (Boundary)   : 1 槽/端口 0 或超上限、告警类别 0 非法早退；
 *                         2 表驱动循环带 DL_GUARD_MAX 上限防失控；
 *                         3 字符串按 R37 定宽样板：拼接后超宽显式截断并
 *                           置 bTruncated；
 *                         4 纯监视件：全部码位信息级，不置任何故障标志；
 *                         5 无定时器/边沿实例（首扫标志驱动刷新策略）。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 8）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_DiagSev（归属本功能块，同文件发布，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_DiagSev :
(
    eInfo    := 0,     // 提示级：无需动作 / Info, no action required
    eWarning := 10,    // 警告级：可继续运行 / Warning, operation may continue
    eError   := 20,    // 错误级：功能受损 / Error, function impaired
    eFatal   := 30,    // 致命级：通信或功能中断 / Fatal, communication or function lost
    eUnknown := 99     // 未知级：无法判定 / Unknown, not classifiable
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_PnAlarmDiagParse
 * 调用约定: 每个扫描周期无条件调用一次；四元组引脚注入。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_PnAlarmDiagParse
VAR_INPUT
    uAlmType  : BYTE  := 16#01;         // 告警类别 [十六进制]，合法域 16#01..16#0F / Alarm class, valid 16#01..16#0F
    uSlot     : USINT := 1;             // 槽号 [个]，合法域 1..63 / Slot number, valid 1..63
    uPort     : USINT := 1;             // 端口号 [个]，合法域 1..8 / Port number, valid 1..8
    uDiagCode : WORD  := 16#0000;       // 诊断码 [十六进制] / Diagnostic code
    bNew      : BOOL  := FALSE;         // 告警到达通知沿 / Alarm arrival notification
END_VAR
VAR_OUTPUT
    eSev      : E_DL_DiagSev;           // 严重度出口 / Severity output
    sText     : STRING[80];             // 中文描述出口（定宽 80）/ Chinese description, fixed width 80
    bRetryable: BOOL;                   // 可重试性出口 / Retryability output
    bTruncated: BOOL;                   // 描述被截断标志（R37）/ Description truncated flag
    uErrorId  : UDINT;                  // 信息级码，0 = 无信息（段位码需 32 位载体）/ Info code, 0 = none, 32-bit carrier
END_VAR
VAR
    auCodes   : ARRAY[0..7] OF WORD := [16#0001, 16#0002, 16#0003, 16#0004, 16#0005, 16#0006, 16#0007, 16#0008];
                                        // 诊断码段表 / Diagnostic code segment table
    aeSev     : ARRAY[0..7] OF E_DL_DiagSev := [eFatal, eError, eError, eWarning, eFatal, eError, eInfo, eWarning];
                                        // 严重度并行表 / Parallel severity table
    asText    : ARRAY[0..7] OF STRING[32] := ['上游通信丢失', '从站参数错误', '端口链路断开', '诊断缓冲溢出',
                                              '地址配置冲突', '固件版本不匹配', '链路恢复就绪', '模块温度告警'];
                                        // 描述并行表 / Parallel description table
    abRetry   : ARRAY[0..7] OF BOOL := [TRUE, FALSE, TRUE, FALSE, FALSE, FALSE, TRUE, FALSE];
                                        // 可重试并行表 / Parallel retryability table
    bFirstScan: BOOL := TRUE;           // 首扫标志 / First-scan flag
    uPrevCode : WORD  := 16#FFFF;       // 上拍诊断码快照（16#FFFF 不入表作差异源）/ Previous code snapshot
    bRefresh  : BOOL;                   // 本拍刷新许可 / Refresh permit this scan
    i         : INT;                    // 查表循环索引 / Table search index
    nGuard    : INT;                    // 循环防失控计数器 / Loop guard counter
    nHit      : INT;                    // 命中下标，-1 = 未收录 / Hit index, -1 = not found
    sBuild    : STRING[80];             // 描述拼接暂存 / Description staging buffer
END_VAR
VAR CONSTANT
    DL_PNP_SLOT_MAX : USINT := 63;      // 槽号上限 [个] / Slot upper bound
    DL_PNP_PORT_MAX : USINT := 8;       // 端口号上限 [个] / Port upper bound
    DL_PNP_TYPE_LO  : BYTE  := 16#01;   // 类别合法域下限 / Class valid lower bound
    DL_PNP_TYPE_HI  : BYTE  := 16#0F;   // 类别合法域上限 / Class valid upper bound
    DL_PNP_ROWS     : INT   := 8;       // 段表行数 / Segment table row count
    DL_GUARD_MAX    : INT   := 16;      // 查表循环上限（行数一倍余）/ Search loop guard bound
    DL_PNP_PREFIX   : STRING[16] := 'PN-ALM '; // 描述统一前缀 / Uniform description prefix
END_VAR

// ---- 段 1｜刷新许可装配：到达沿、码变化、首扫三通道 ----------------------------
bRefresh := bNew OR bFirstScan OR (uDiagCode <> uPrevCode); // 任一通道许可刷新 / Any channel permits refresh
uPrevCode := uDiagCode;                                 // 更新码快照 / Update code snapshot
bFirstScan := FALSE;                                    // 清首扫标志 / Clear first-scan flag

// ---- 段 2｜非法入参早退（信息级，输出确定值）------------------------------------
IF (uSlot = 0) OR (uSlot > DL_PNP_SLOT_MAX) OR (uPort = 0) OR (uPort > DL_PNP_PORT_MAX)
   OR (uAlmType < DL_PNP_TYPE_LO) OR (uAlmType > DL_PNP_TYPE_HI) THEN
    eSev       := eUnknown;                            // 严重度未知 / Severity unknown
    sText      := 'IN-PARA-INVALID';                   // 入参非法描述 / Invalid parameter text
    bRetryable := FALSE;                                // 不可重试 / Not retryable
    bTruncated := FALSE;                                // 定宽内无截断 / No truncation
    uErrorId   := 16#0003_00FC;                         // 信息级：入参非法 / Info: invalid parameters
    RETURN;                                             // 早退出口 / Early exit
END_IF

// ---- 段 3｜查表驱动（带防失控上限），未刷新拍保持原输出 --------------------------
IF bRefresh THEN
    nHit := -1;                                         // 命中先置未收录 / Preset not found
    nGuard := 0;                                        // 计数器清零 / Clear guard counter
    FOR i := 0 TO (DL_PNP_ROWS - 1) DO
        nGuard := nGuard + 1;                           // 计数递增 / Increment guard
        IF (uDiagCode = auCodes[i]) OR (nGuard >= DL_GUARD_MAX) THEN
            IF uDiagCode = auCodes[i] THEN
                nHit := i;                              // 记录命中下标 / Record hit index
            END_IF
            EXIT;                                       // 单出循环防失控 / Single exit against runaway
        END_IF
    END_FOR
END_IF

// ---- 段 4｜三出口装配：命中行 / 未收录兜底 --------------------------------------
IF bRefresh THEN
    IF nHit >= 0 THEN
        eSev       := aeSev[nHit];                      // 严重度出口 / Severity output
        bRetryable := abRetry[nHit];                    // 可重试出口 / Retryability output
        sBuild     := CONCAT(DL_PNP_PREFIX, asText[nHit]); // 前缀拼接描述 / Prefix plus description
        IF LEN(sBuild) > 80 THEN
            sText := LEFT(sBuild, 80);                  // 超宽显式截断 / Explicit truncation
            bTruncated := TRUE;                         // 截断标志置位（R37）/ Truncated flag set
        ELSE
            sText := sBuild;                            // 定宽内直存 / Store within width
            bTruncated := FALSE;                        // 无截断 / No truncation
        END_IF
        uErrorId := 16#0000_0000;                        // 命中无码 / No code on hit
    ELSE
        eSev       := eWarning;                         // 未收录兜底：告警级 / Not found fallback: warning
        sText      := 'PN-ALM 未知告警';                // 兜底描述 / Fallback description
        bRetryable := FALSE;                            // 兜底不可重试 / Fallback not retryable
        bTruncated := FALSE;                            // 定宽内无截断 / No truncation
        uErrorId   := 16#0003_00FD;                     // 信息级：码未收录 / Info: code not indexed
    END_IF
END_IF
END_FUNCTION_BLOCK
