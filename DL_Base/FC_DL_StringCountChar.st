(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringCountChar
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / LEFT / MID / FIND），零厂商私有库
 * 功能描述 (Function)   : 统计指定字符在字符串中的出现次数。典型用途：HMI 报文
 *                         分隔符计数（判断字段数 = 分隔符数 + 1）、协议帧结构预校验。
 *                         逐字符扫描，用 FIND(单字符, 实测单字符) = 1 做单字符等值判定
 *                         （纯 IEC 标准函数路径，不依赖平台 STRING 比较运算符方言；
 *                         单字符串 A 与 B 相等 ⇔ FIND(A,B)=1）。
 *                         填充字符取 sChar 首字符，故传入多字符串时按首字符计。
 * 接口     (Interface)  : 输入 sIn 被扫描字符串 [-]、sChar 目标字符（取首字符）[-]；
 *                         输出 uiCount 出现次数 [次]、uiLen 扫描字符数 [字符]、
 *                         eErrCode 错误码（E_DL_StrCountErr）；
 *                         返回值 = bValid 统计可信标志（TRUE = uiCount 可信）。
 * 边界     (Boundary)   : ① 属主边界：只统计单字符，不做多字符串（子串）计数、
 *                         不做分隔符拆分（拆分归 FC_DL_StringSplitPair）。
 *                         ② sChar 为空串 → 故障级 eEmptyChar，uiCount 哨兵 0。
 *                         ③ sIn 为空串 → 合法，uiCount=0、uiLen=0、eOk（空串零命中）。
 *                         ④ 扫描上界取 uiLen（<=255），循环严格有界，无越界读取。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringSplitPair` 分工：本件只计数不拆分；
 *                         与 `FC_DL_StringRemoveWhitespace` 分工：空白剔除归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + UINT +
 *                         本文件内定义 enum E_DL_StrCountErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 空字符域闸 + 扫描上界钳位 + 单字符等值判定 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 3）
 * 验收向量 (Acceptance) : ① sIn='A,B,C,D', sChar=',' → uiCount=3, uiLen=7, eOk, TRUE；
 *                         ② sIn='ABCD', sChar=',' → uiCount=0, uiLen=4, eOk, TRUE；
 *                         ③ sIn='', sChar=',' → uiCount=0, uiLen=0, eOk, TRUE；
 *                         ④ sChar='' → uiCount=0, 返回 FALSE, eEmptyChar；
 *                         ⑤ sIn=';;;', sChar=';' → uiCount=3。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrCountErr（字符计数错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrCountErr :
(
    eOk        := 0,   // 信息级：统计完成 / Info: counting completed
    eEmptyChar := 1    // 故障级：目标字符为空串，统计无意义 / Fault: target character empty, counting meaningless
);
END_TYPE

FUNCTION FC_DL_StringCountChar : BOOL
VAR_INPUT
    sIn   : STRING(255);   // 被扫描字符串 [-] / Scanned string
    sChar : STRING(255);   // 目标字符源（取首字符） [-] / Target character source, first char taken
END_VAR
VAR_OUTPUT
    uiCount : UINT;        // 出现次数 [次] / Occurrence count [times]
    uiLen   : UINT;        // 扫描字符数 [字符] / Scanned character count [chars]
    eErrCode: E_DL_StrCountErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _sOne   : STRING(255); // 归一后的单字符串 [-] / Normalized single character string
    _sCur   : STRING(255); // 当前扫描到的单字符 [-] / Current single character under scan
    _udLen  : UDINT;       // 输入字符数（LEN 原生宽度） [字符] / Input length in native width [chars]
    _udI    : UDINT;       // 扫描位置（1 基） [-] / Scan position, 1-based
    _uiHit  : UINT;        // 命中累加器 [次] / Hit accumulator [times]
END_VAR
VAR CONSTANT
    DL_SCC_LEN_MAX : UINT := 255;    // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SCC_START   : UDINT := 1;     // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
    DL_SCC_ONE_LEN : UDINT := 1;     // 单字符长度常量 [字符] / Single character length constant [chars]
    DL_SCC_HIT_ONE : UDINT := 1;     // FIND 命中首位的比较值 [-] / Compare value for first-position hit
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringCountChar := FALSE;                    // 返回值预置无效 / Return preset invalid
uiCount   := 0;                                    // 计数哨兵 0 / Count sentinel
uiLen     := 0;                                    // 长度哨兵 0 / Length sentinel
eErrCode  := E_DL_StrCountErr.eEmptyChar;          // 预置最严码 / Preset strictest code

(* —— 段 1：目标字符域闸（空串无统计意义） —— *)
IF LEN(sChar) = 0 THEN
    RETURN;                                        // 保持故障码与哨兵 / Keep fault code and sentinel
END_IF

(* —— 段 2：归一为目标单字符 —— *)
_sOne := LEFT(sChar, DL_SCC_ONE_LEN);               // 取首字符（1 基索引） / Take first character, 1-based

(* —— 段 3：实测长度并钳位（缓冲可表性反算） —— *)
_udLen := LEN(sIn);                                // 输入字符数 / Input length
IF _udLen > UINT_TO_UDINT(DL_SCC_LEN_MAX) THEN
    _udLen := UINT_TO_UDINT(DL_SCC_LEN_MAX);       // 超上限钳位，保证扫描有界 / Clamp to keep scan bounded
END_IF
uiLen := UDINT_TO_UINT(_udLen);                    // 输出扫描字符数 / Export scanned length

(* —— 段 4：空串早退（零命中，仍是成功结果） —— *)
IF _udLen = 0 THEN
    eErrCode := E_DL_StrCountErr.eOk;              // 信息级成功（零命中） / Info success, zero hits
    FC_DL_StringCountChar := TRUE;
    RETURN;
END_IF

(* —— 段 5：逐字符扫描（单字符等值判定：FIND(单字符, 实测) = 1） —— *)
_uiHit := 0;                                       // 累加器清零 / Clear accumulator
_udI   := DL_SCC_START;                            // 起算位置 1 / Start at position one
WHILE _udI <= _udLen DO
    _sCur := MID(sIn, DL_SCC_ONE_LEN, _udI);       // 取第 i 个字符（1 基） / Take i-th character, 1-based
    IF FIND(_sOne, _sCur) = DL_SCC_HIT_ONE THEN
        _uiHit := _uiHit + 1;                      // 命中累加 / Accumulate one hit
    END_IF
    _udI := _udI + 1;                              // 位置步进 / Advance position
END_WHILE

(* —— 段 6：结果复检（命中数不得超过扫描长度） —— *)
IF _uiHit > uiLen THEN
    uiCount  := 0;                                 // 复检失败回哨兵 / Recheck failed: sentinel
    eErrCode := E_DL_StrCountErr.eEmptyChar;       // 保持故障级（内部不一致不入正常出口） / Keep fault-level
    RETURN;
END_IF

uiCount  := _uiHit;                                // 导出命中数 / Export hit count
eErrCode := E_DL_StrCountErr.eOk;                  // 信息级成功 / Info success
FC_DL_StringCountChar := TRUE;                     // 统计可信 / Counting trustworthy

END_FUNCTION
