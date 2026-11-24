(*==============================================================================
 * 组件名称 : FC_DL_CharIsSpace ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 判定 STRING(1) 单字符是否为空白字符（空格 16#20 或水平制表符
 *            Tab 16#09），Tab 用 IEC 标准字符串转义 '$T' 表示，不用库函数。
 * 契约     : 返回 TRUE = 空格或 Tab；输入 sChar 单字符，空串恒 FALSE；
 *            纯函数无状态、同输入同输出。
 * 开源溯源 : 来源 fisothemes/TwinCAT-Dynamic-String-Kit
 *            https://github.com/fisothemes/TwinCAT-Dynamic-String-Kit / MIT
 *            借鉴点：字符分类谓词语义，实现为本库 clean-room 重写。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC（'$T' 为 IEC 标准转义）
 *            R4 空串防御（恒 FALSE） R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 字符分类族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_CharIsSpace : BOOL
VAR_INPUT
    sChar : STRING(1);      // 待判定单字符（空串恒 FALSE） / Single character to test (empty = FALSE)
END_VAR
IF (sChar = ' ') OR (sChar = '$T') THEN
    FC_DL_CharIsSpace := TRUE;      // 空格或 Tab 命中 / Space or tab hit
ELSE
    FC_DL_CharIsSpace := FALSE;     // 空串或其他字符 / Empty string or other character
END_IF
END_FUNCTION
