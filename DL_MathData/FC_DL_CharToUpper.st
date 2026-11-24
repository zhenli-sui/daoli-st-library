(*==============================================================================
 * 组件名称 : FC_DL_CharToUpper ｜ 子库 : DL_MathData ｜ v1.0.0 ｜ 2026-11-23
 * 平台     : CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert（纯 IEC，无厂商库）
 * 功能简介 : 小写英文字母转大写（'a'..'z' → 'A'..'Z'），其余字符原样返回。
 *            无字符算术库函数可用，故以 26 项等值映射（每行两项）实现，
 *            语义与 ASCII 减 32 完全一致。
 * 契约     : 返回转换后的单字符；输入 sChar 单字符；空串原样返回；
 *            纯函数无状态、同输入同输出。
 * 开源溯源 : 来源 fisothemes/TwinCAT-Dynamic-String-Kit
 *            https://github.com/fisothemes/TwinCAT-Dynamic-String-Kit / MIT
 *            借鉴点：字符分类/变换谓词语义，实现为本库 clean-room 重写。
 * 依赖     : 无 DL_ 内部依赖（本批自足实现）
 * 红线自检 : R1 零全局 R2 零%I/%Q R3 纯IEC R4 空串原样返回无越界
 *            R5 双语注释 R6 N/A（无状态机） R7 N/A（无定时器实例）
 * 修订历史 : 2026-11-23 R78-B1 字符分类族模板派生首版
 *============================================================================*)
FUNCTION FC_DL_CharToUpper : STRING(1)
VAR_INPUT
    sChar : STRING(1);      // 待转换单字符 / Single character to convert
END_VAR
IF sChar = 'a' THEN FC_DL_CharToUpper := 'A'; ELSIF sChar = 'b' THEN FC_DL_CharToUpper := 'B';        // a→A b→B a/b to upper
ELSIF sChar = 'c' THEN FC_DL_CharToUpper := 'C'; ELSIF sChar = 'd' THEN FC_DL_CharToUpper := 'D';     // c→C d→D c/d to upper
ELSIF sChar = 'e' THEN FC_DL_CharToUpper := 'E'; ELSIF sChar = 'f' THEN FC_DL_CharToUpper := 'F';     // e→E f→F e/f to upper
ELSIF sChar = 'g' THEN FC_DL_CharToUpper := 'G'; ELSIF sChar = 'h' THEN FC_DL_CharToUpper := 'H';     // g→G h→H g/h to upper
ELSIF sChar = 'i' THEN FC_DL_CharToUpper := 'I'; ELSIF sChar = 'j' THEN FC_DL_CharToUpper := 'J';     // i→I j→J i/j to upper
ELSIF sChar = 'k' THEN FC_DL_CharToUpper := 'K'; ELSIF sChar = 'l' THEN FC_DL_CharToUpper := 'L';     // k→K l→L k/l to upper
ELSIF sChar = 'm' THEN FC_DL_CharToUpper := 'M'; ELSIF sChar = 'n' THEN FC_DL_CharToUpper := 'N';     // m→M n→N m/n to upper
ELSIF sChar = 'o' THEN FC_DL_CharToUpper := 'O'; ELSIF sChar = 'p' THEN FC_DL_CharToUpper := 'P';     // o→O p→P o/p to upper
ELSIF sChar = 'q' THEN FC_DL_CharToUpper := 'Q'; ELSIF sChar = 'r' THEN FC_DL_CharToUpper := 'R';     // q→Q r→R q/r to upper
ELSIF sChar = 's' THEN FC_DL_CharToUpper := 'S'; ELSIF sChar = 't' THEN FC_DL_CharToUpper := 'T';     // s→S t→T s/t to upper
ELSIF sChar = 'u' THEN FC_DL_CharToUpper := 'U'; ELSIF sChar = 'v' THEN FC_DL_CharToUpper := 'V';     // u→U v→V u/v to upper
ELSIF sChar = 'w' THEN FC_DL_CharToUpper := 'W'; ELSIF sChar = 'x' THEN FC_DL_CharToUpper := 'X';     // w→W x→X w/x to upper
ELSIF sChar = 'y' THEN FC_DL_CharToUpper := 'Y'; ELSIF sChar = 'z' THEN FC_DL_CharToUpper := 'Z';     // y→Y z→Z y/z to upper
ELSE
    FC_DL_CharToUpper := sChar;     // 非小写字母（含空串/大写/符号）原样返回 / Non-lowercase returned unchanged
END_IF
END_FUNCTION
