// ==============================================================================
// 组件名 Component  : FC_DL_StringEditDistance
// 分类   Category   : DL_Base
// 前缀   Naming     : FC_DL_ ｜ b/n/f/c/s 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity : 中
// 功能   Purpose    : 两串编辑距离（Levenshtein，插入 / 删除 / 替换各记 1）：
//                      滚动单行动态规划，上一行整型数组暂存（空间 O(64)）；
//                      空串处理：一方为空返回另一方长度，双空返回 0；
//                      大小写可选（bCaseSense 默认敏感）。纯 ST 手写 DP，
//                      不调平台专有函数。
// 开源溯源 Origin    : 道莅原创（编辑距离为公开经典算法定义，本实现
//                      clean-room，未复制任何源码行）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.4 FOR 遍历与数组语义；
//                      Levenshtein 距离公开算法定义（借定义，不抄实现）
// 平台   Platform   : 纯 IEC 61131-3（FOR / 数组 / LEN / MID / FIND），三平台通用
// 依赖   Depends    : 无（零委托、零库件；LEN / MID / FIND 为 IEC 标准函数）
// 分工声明 Split     : FC_DL_StringWildMatch（通配匹配）与本件互引；本件量化
//                      两串差异度，彼件判定模式命中，语义互补不重叠（R216）。
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 长度一次锁存：LEN 各取一次；STRING(64) 声明容量即上限，实测长度触
//      64 上界即视为调用方侧可能已截断 → bTooLong 置位（信息语义，距离仍
//      按现内容计算，bValid 不受影响）；
//   二 DP 行数组 aPrev[0..64] 全容量恒等预置为行 0；nLenB <= 64 已证，
//      aPrev 下标 [0, nLenB] 不越界；内层左邻取 aPrev[nJ-1]（nJ >= 1 已证
//      下标 >= 0）；
//   三 大小写折叠只用 FIND 定位 + MID 取字（域内字符恒命中，nPos 在
//      1..26 内），域外字符不折叠直比；
//   四 空串口径：nLenA = 0 时外层整段跳过，行 0 恒等即为结果行，
//      nDist = nLenB（等价另一方长度），双空 → 0，无需特判分支；
//   五 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   六 无除法；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0740【信息级】任一串长度触 64 声明上限，可能已被调用方截断
//                （bTooLong = TRUE，bValid 保持 TRUE，距离按现内容给出）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，故障语义经出口组合表达；
//   bValid = FALSE 无可达路径（本件恒可用，防御性异常长度已钳零吸收）。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 kitten / sitting → 3
//   V2 空串 / abc → 3；V3 双空 → 0
//   V4 bCaseSense = FALSE 时 abc / ABC → 0
//   V5 64 字符串 → bTooLong = TRUE 且 bValid = TRUE、距离可用
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 1 · 序号 1）
// ==============================================================================
FUNCTION FC_DL_StringEditDistance : BOOL
VAR_INPUT
    sA         : STRING(64);       // 串 A [字符] / string A [chars]
    sB         : STRING(64);       // 串 B [字符] / string B [chars]
    bCaseSense : BOOL := TRUE;     // 大小写敏感开关，默认敏感 [-] / case sensitivity switch, sensitive by default
END_VAR
VAR_OUTPUT
    nDist    : INT;                // 编辑距离 [次]，插入 / 删除 / 替换各记 1 / the edit distance in operations
    bValid   : BOOL;               // 结果可用标志 [-]，本件恒 TRUE / the result usable flag, always true here
    bTooLong : BOOL;               // 触 64 上限提示 [-]（信息级 0740）/ the at-cap flag, informational
END_VAR
VAR
    aPrev   : ARRAY[0..64] OF INT; // DP 上一行整型数组 [次]，行 0 恒等预置 / the previous DP row, row zero preset to identity
    nLenA   : INT;                 // 锁存的串 A 长度 [字符] / the latched length of string A
    nLenB   : INT;                 // 锁存的串 B 长度 [字符] / the latched length of string B
    nI      : INT;                 // 外层行索引（串 A 方向）[字符] / the outer row index along string A
    nJ      : INT;                 // 内层列索引（串 B 方向）[字符] / the inner column index along string B
    nDiag   : INT;                 // 对角缓存 dp[i-1][j-1] [次] / the diagonal staging value
    nUp     : INT;                 // 上邻缓存 dp[i-1][j] [次] / the upper neighbor staging value
    nBest   : INT;                 // 当前三选一最小值 [次] / the current minimum of the three candidates
    cA      : STRING(1);           // 串 A 当前字符 [字符] / the current char of string A
    cB      : STRING(1);           // 串 B 当前字符 [字符] / the current char of string B
    cAf     : STRING(1);           // 折叠后串 A 字符 [字符] / the case folded char of string A
    cBf     : STRING(1);           // 折叠后串 B 字符 [字符] / the case folded char of string B
    nPos    : INT;                 // 码表定位 [索引]，1 起 / the table position, one based
    bEq     : BOOL;                // 当前字符对相等标志 [-] / the equality flag of the char pair
END_VAR
VAR CONSTANT
    DL_SED_NMAX : INT := 64;       // 串长上限 [字符]，与形参声明一致 / the string cap aligned with the declarations
    DL_SED_ONE  : INT := 1;        // 整型一常量 [字符] / the integer one constant
END_VAR

// 段 1｜返回值与全部出口预置（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_StringEditDistance := FALSE; // 返回值预置假 / preset the return false
nDist    := 0;                     // 距离预置零 [次] / preset the distance zero
bValid   := TRUE;                  // 有效标志预置真（本件恒可用）/ preset valid, always usable
bTooLong := FALSE;                 // 触界提示预置假 / preset the cap flag false

// 段 2｜长度一次锁存 + 触界提示（边界一）/ segment 2, latch the lengths once with the cap flag
nLenA := LEN(sA);                  // 串 A 长度 [字符] / the length of string A
nLenB := LEN(sB);                  // 串 B 长度 [字符] / the length of string B
IF nLenA < 0 THEN                  // 防御性异常长度（结构性不可达）/ a defensive anomalous length
    nLenA := 0;                    // 异常返回值钳零 / clamp the anomalous value to zero
END_IF
IF nLenB < 0 THEN                  // 防御性异常长度（结构性不可达）/ a defensive anomalous length
    nLenB := 0;                    // 异常返回值钳零 / clamp the anomalous value to zero
END_IF
IF (nLenA >= DL_SED_NMAX) OR (nLenB >= DL_SED_NMAX) THEN // 任一串触声明上限 / either string at the declared cap
    bTooLong := TRUE;              // 触上限提示（信息级 0740，可能已截断）/ the at-cap flag raised
END_IF

// 段 3｜DP 行 0 恒等预置（边界二）/ segment 3, the DP row zero identity preset
FOR nJ := 0 TO DL_SED_NMAX DO      // 全容量有界遍历 / the full capacity bounded traversal
    aPrev[nJ] := nJ;               // 行 0：dp[0][j] = j [次] / row zero, dp[0][j] equals j
END_FOR

// 段 4｜滚动单行 DP 主循环（边界四：nLenA = 0 时整段跳过即空串口径）/ segment 4, the rolling single row DP
FOR nI := 1 TO nLenA DO            // 串 A 方向逐行 / row by row along string A
    nDiag := aPrev[0];             // 对角缓存 dp[i-1][0]（覆盖前先存）/ stage the diagonal before the overwrite
    aPrev[0] := nI;                // 首列 dp[i][0] = i [次] / the first column
    FOR nJ := 1 TO nLenB DO        // 串 B 方向逐列 / column by column along string B
        nUp := aPrev[nJ];          // 上邻 dp[i-1][j] 暂存 [次] / stage the upper neighbor
        cA := MID(sA, DL_SED_ONE, nI); // 取串 A 当前字符 / take the current char of string A
        cB := MID(sB, DL_SED_ONE, nJ); // 取串 B 当前字符 / take the current char of string B
        cAf := cA;                 // 折叠暂存默认原值 / the folded staging defaults to the original
        cBf := cB;                 // 折叠暂存默认原值 / the folded staging defaults to the original
        IF NOT bCaseSense THEN     // 大小写不敏感才折叠（边界三）/ fold only when insensitive
            IF (cA >= 'A') AND (cA <= 'Z') THEN // 串 A 字符在大写域内 / the char of A in the uppercase domain
                nPos := FIND('ABCDEFGHIJKLMNOPQRSTUVWXYZ', cA); // 大写码表定位（域内恒命中 1..26）/ locate in the uppercase table
                cAf := MID('abcdefghijklmnopqrstuvwxyz', DL_SED_ONE, nPos); // 同位取小写 / the same position lowercase
            END_IF
            IF (cB >= 'A') AND (cB <= 'Z') THEN // 串 B 字符在大写域内 / the char of B in the uppercase domain
                nPos := FIND('ABCDEFGHIJKLMNOPQRSTUVWXYZ', cB); // 大写码表定位 / locate in the uppercase table
                cBf := MID('abcdefghijklmnopqrstuvwxyz', DL_SED_ONE, nPos); // 同位取小写 / the same position lowercase
            END_IF
        END_IF
        bEq := (cAf = cBf);        // 折叠后比对（边界三）/ the folded compare
        IF bEq THEN                // 字符相等 / the chars equal
            nBest := nDiag;        // 取对角（零代价）[次] / take the diagonal, zero cost
        ELSE                       // 字符不等 / the chars differ
            nBest := nDiag + DL_SED_ONE;          // 替换代价 [次] / the substitution cost
            IF (nUp + DL_SED_ONE) < nBest THEN    // 删除代价更小 / the deletion cost is smaller
                nBest := nUp + DL_SED_ONE;        // 取删除代价 [次] / take the deletion cost
            END_IF
            IF (aPrev[nJ - 1] + DL_SED_ONE) < nBest THEN // 插入代价更小（左邻已为本行新值）/ the insertion cost is smaller
                nBest := aPrev[nJ - 1] + DL_SED_ONE;     // 取插入代价 [次] / take the insertion cost
            END_IF
        END_IF
        nDiag := nUp;              // 对角推进（先存后写，滚动关键序）/ advance the diagonal before the overwrite
        aPrev[nJ] := nBest;        // 写当前行当前列 [次]（下标 nJ <= 64 已证）/ write the current cell
    END_FOR
END_FOR

// 段 5｜出口装配（边界四：空串口径由行 0 恒等自然成立）/ segment 5, the outlet assembly
nDist := aPrev[nLenB];             // 距离出口 [次]（nLenB = 0 时取 aPrev[0]）/ the distance outlet
FC_DL_StringEditDistance := TRUE;  // 返回成功 / return success
END_FUNCTION
