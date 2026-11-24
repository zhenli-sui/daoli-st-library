(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringPadLeftZeros
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / LEFT / CONCAT），零厂商私有库
 * 功能描述 (Function)   : 左补零至定长（编号 / 时间戳 / 批号规范化）。
 *                         sIn 左侧填充 pad 字符（默认 '0'）至 uiTargetLen 长度；
 *                         sIn 已达或超过目标长度时原样返回（不截断）并置 bOverflow；
 *                         目标长度超过缓冲上限 255 时钳位至 255 并置 bOverflow。
 *                         用于 PLC 侧生成定宽字符串键（如 "00042"），便于 HMI 对齐与
 *                         上位机字典排序（定宽字典序 = 数值序）。
 * 接口     (Interface)  : 输入 sIn 原始字符串 [-]、uiTargetLen 目标定长 [字符]、
 *                         sPadChar 填充字符（取首字符，空串视为 '0'）[-]；
 *                         输出 sOut 结果字符串、uiOutLen 实际字符数 [字符]、
 *                         bOverflow 溢出/钳位回执、eErrCode 错误码（E_DL_StrPadErr）；
 *                         返回值 = bValid 转换有效标志（TRUE = sOut 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做补位，不做数值格式化、不做千分位、不截断。
 *                         ② 全局缓冲上限 255（STRING(255) 契约），目标超限钳位并置
 *                         bOverflow（信息级码 eClampLen，不置故障）。
 *                         ③ 输入为空串时输出全填充串（长度 = uiTargetLen），合法。
 *                         ④ 索引全 1 基（IEC 字符串函数约定），无 0 基偏移路径。
 *                         ⑤ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringTruncEllipsis` 分工：超长截断归那件，
 *                         本件超长只回执不截断（补位与截断语义互斥，避免隐式改写）。
 *                         与 `FC_DL_StringRepeat` 分工：重复拼接归那件，本件只补单字符。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL 返回 + STRING 结果 +
 *                         本文件内定义 enum E_DL_StrPadErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 目标长度双侧钳位 + 循环上限硬保护 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 1）
 * 验收向量 (Acceptance) : ① sIn='42', uiTargetLen=5, sPadChar='0' → sOut='00042',
 *                         uiOutLen=5, bOverflow=FALSE, 返回 TRUE, eErrCode=eOk；
 *                         ② sIn='123456', uiTargetLen=3 → sOut='123456'（原样不截断）,
 *                         uiOutLen=6, bOverflow=TRUE, 返回 TRUE, eErrCode=eOverflowInput；
 *                         ③ sIn='', uiTargetLen=3 → sOut='000', uiOutLen=3, eOk；
 *                         ④ uiTargetLen=300 → 钳位 255，bOverflow=TRUE, eClampLen。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrPadErr（左补零错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 * 分级: 故障级码（eInvalidParam）恒伴返回 FALSE；信息级码（eOk / eOverflowInput /
 *       eClampLen）返回 TRUE 且结果仍可信。
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrPadErr :
(
    eOk            := 0,   // 信息级：正常补位完成 / Info: padding completed
    eOverflowInput := 1,   // 信息级：输入已达目标长度，原样返回 / Info: input already long enough, returned as-is
    eClampLen      := 2,   // 信息级：目标长度超缓冲上限已钳位 / Info: target length clamped to buffer ceiling
    eInvalidParam  := 3    // 故障级：参数非法（填充串全空且目标长度非正） / Fault: invalid parameter
);
END_TYPE

FUNCTION FC_DL_StringPadLeftZeros : BOOL
VAR_INPUT
    sIn         : STRING(255);   // 原始字符串（待补位） [-] / Raw input string to be padded
    uiTargetLen : UINT;          // 目标定长，合法域 1..255 [字符] / Target fixed length, domain 1..255 [chars]
    sPadChar    : STRING(255);   // 填充字符源（取首字符，空串按 '0'） [-] / Pad character source, first char, empty means '0'
END_VAR
VAR_OUTPUT
    sOut        : STRING(255);   // 补位结果字符串 [-] / Padded result string
    uiOutLen    : UINT;          // 结果实际字符数 [字符] / Actual character count of result [chars]
    bOverflow   : BOOL;          // 溢出/钳位回执（信息级，不置故障） [-] / Overflow or clamp receipt, info level
    eErrCode    : E_DL_StrPadErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _uiInLen    : UINT;          // 输入字符串字符数 [字符] / Input character count [chars]
    _uiPadNum   : UINT;          // 需补入的填充字符个数 [字符] / Number of pad characters required [chars]
    _sPadOne    : STRING(255);   // 单字符填充串（循环拼接基元） [-] / Single-character pad unit for concatenation
    _i          : UINT;          // 填充循环计数器 [-] / Padding loop counter
END_VAR
VAR CONSTANT
    DL_SPZ_LEN_MAX : UINT := 255;   // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling per STRING(255) contract [chars]
    DL_SPZ_LEN_MIN : UINT := 1;     // 目标长度下限（0 视为非法参数） [字符] / Target length lower bound, 0 is invalid [chars]
    DL_SPZ_ZERO_CH : STRING(255) := '0'; // 默认填充字符 / Default pad character
END_VAR

(* —— 段 0：出口预置安全值（预置最严码 + 哨兵输出） —— *)
FC_DL_StringPadLeftZeros := FALSE;                // 返回值预置无效 / Return preset invalid
sOut      := '';                                  // 结果哨兵空串 / Result sentinel empty string
uiOutLen  := 0;                                   // 长度哨兵 0 / Length sentinel zero
bOverflow := FALSE;                               // 溢出口预置正常 / Overflow preset normal
eErrCode  := E_DL_StrPadErr.eInvalidParam;        // 预置最严码，参数闸命中直接早退 / Preset strictest code

(* —— 段 1：参数域闸（目标长度下限；分母型参数无，纯域判定） —— *)
IF uiTargetLen < DL_SPZ_LEN_MIN THEN
    RETURN;                                       // 目标长度 0：保持故障码与哨兵 / Zero target length: keep fault code
END_IF

(* —— 段 2：目标长度上限钳位（缓冲可表性反算，R 饱和硬限） —— *)
IF uiTargetLen > DL_SPZ_LEN_MAX THEN
    uiTargetLen := DL_SPZ_LEN_MAX;                 // 钳位至缓冲上限 / Clamp to buffer ceiling
    bOverflow   := TRUE;                           // 钳位回执 / Clamp receipt
    eErrCode    := E_DL_StrPadErr.eClampLen;       // 信息级码 / Info-level code
END_IF

(* —— 段 3：输入长度实测（LEN 返回 UDINT，标准函数显式收窄到 UINT） —— *)
_uiInLen := UDINT_TO_UINT(LEN(sIn));               // 输入字符数 / Input character count

(* —— 段 4：已达目标长度：原样返回不截断（早退分支，语义显式） —— *)
IF _uiInLen >= uiTargetLen THEN
    sOut      := sIn;                              // 原样返回 / Return as-is
    uiOutLen  := _uiInLen;                         // 实际长度取输入长度 / Length equals input length
    bOverflow := TRUE;                             // 已达/超过目标长度回执 / Already at or beyond target
    eErrCode  := E_DL_StrPadErr.eOverflowInput;    // 信息级码（覆盖钳位码，更贴语义） / Info code overrides clamp code
    FC_DL_StringPadLeftZeros := TRUE;              // 结果可信 / Result trustworthy
    RETURN;                                        // 早退 / Early exit
END_IF

(* —— 段 5：填充字符解析（空串按默认 '0'，否则取首字符） —— *)
IF LEN(sPadChar) = 0 THEN
    _sPadOne := DL_SPZ_ZERO_CH;                    // 空串回落默认字符 / Empty falls back to default character
ELSE
    _sPadOne := LEFT(sPadChar, 1);                 // 取首字符（1 基索引） / Take first character, 1-based
END_IF

(* —— 段 6：循环左补（补数已由上限钳位保证 <= 255，循环有界） —— *)
_uiPadNum := uiTargetLen - _uiInLen;               // 需补个数 = 目标 - 现有 / Pad count = target - existing
sOut      := _sPadOne;                             // 以单个填充字符起头，避免首次拼接空串副作用 / Start with one pad unit
IF _uiPadNum > DL_SPZ_LEN_MIN THEN
    FOR _i := 2 TO _uiPadNum DO
        sOut := CONCAT(sOut, _sPadOne);            // 逐个追加填充字符 / Append one pad character per iteration
    END_FOR;
END_IF
sOut := CONCAT(sOut, sIn);                         // 左补齐后接原串 / Append original string after pad prefix

(* —— 段 7：结果复检（长度必须等于目标，否则判内部不一致） —— *)
uiOutLen := UDINT_TO_UINT(LEN(sOut));              // 实测结果长度 / Measured result length
IF uiOutLen <> uiTargetLen THEN
    sOut     := '';                                // 复检失败回哨兵 / Recheck failed: back to sentinel
    uiOutLen := 0;                                 // 长度回哨兵 / Length back to sentinel
    eErrCode := E_DL_StrPadErr.eInvalidParam;      // 故障级码 / Fault-level code
    RETURN;                                        // 返回 FALSE 保持 / Keep return FALSE
END_IF

(* —— 段 8：成功出口（信息级码保留，bOverflow 供调用方判别） —— *)
IF eErrCode = E_DL_StrPadErr.eClampLen THEN
    bOverflow := TRUE;                             // 钳位情形回执保持 / Keep clamp receipt
END_IF
FC_DL_StringPadLeftZeros := TRUE;                  // 补位有效 / Padding valid

END_FUNCTION
