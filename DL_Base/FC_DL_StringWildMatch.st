// ==============================================================================
// 组件名 Component  : FC_DL_StringWildMatch
// 分类   Category   : DL_Base
// 前缀   Naming     : FC_DL_ ｜ b/n/c/s 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity : 中
// 功能   Purpose    : 通配符匹配：'*' 匹配任意长度（含空），'?' 匹配单个
//                      字符，其余字符直比。迭代双指针算法（无递归），记录
//                      最后一次 '*' 位置用于失配回溯；连续 '*' 允许并按折叠
//                      语义天然处理（重复推进模式指针即可）。大小写可选
//                      （bCaseSense 默认敏感，由调用方传参决定，无默认折叠）。
// 开源溯源 Origin    : 道莅原创（通配匹配双指针回溯为公开经典算法语义，
//                      本实现 clean-room，未复制任何源码行）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6.4 WHILE / FOR 遍历语义；
//                      单 '*' 回溯双指针公开算法定义（借定义，不抄实现）
// 平台   Platform   : 纯 IEC 61131-3（WHILE / FOR / LEN / MID / FIND），三平台通用
// 依赖   Depends    : 无（零委托、零库件；LEN / MID / FIND 为 IEC 标准函数）
// 分工声明 Split     : FC_DL_StringEditDistance（编辑距离量化）与本件互引；
//                      本件判定模式命中与否，彼件量化差异度，互补不重叠（R216）。
// 归属 Ownership     : 本件无 TYPE 声明；全部引脚为 IEC 标准原生类型。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 长度一次锁存：STRING(64) 声明容量即上限，实测长度触 64 上界即视为
//      调用方侧可能已截断 → bValid = FALSE 拒绝判定（保守拒绝，不输出
//      存疑匹配结果）；
//   二 无递归：双指针 + 单星回溯点（nStarP / nStarT），每次回溯 nStarT
//      单调递增且 nT 归位 nStarT，全程终止有证；WHILE 带计数护栏
//      nGuard（上界 4096，远大于最坏 2*(64+64) 指针步数），护栏命中强制
//      失配退出（结构性不可达兜底，不静默死循环）；
//   三 尾部模式核查：文本耗尽后剩余模式必须全为 '*' 才命中（FOR 扫描），
//      防止 "a*b" 类模式对短文本误报命中；
//   四 大小写折叠只用 FIND 定位 + MID 取字（域内恒命中），域外字符不折叠
//      直比；'?' 不参与折叠（单字符任意匹配语义优先）；
//   五 空串口径：空模式只命中空文本（尾部核查自然覆盖）；空文本对 '*'
//      结尾模式命中；
//   六 纯函数：无记忆量、无定时器、无边沿实例，每调用重算；
//   七 无除法；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0001_0742【信息级】任一串长度触 64 声明上限视为可能截断
//                （bValid = FALSE 拒绝判定，bMatch 置 FALSE）
//   注：本件引脚契约按任务定稿无独立 eErr 出口，故障语义经出口组合表达；
//   护栏命中与 bValid 通道无关（结构性不可达兜底，仅强制 bMatch = FALSE）。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 "a*c" / "abbbc" → TRUE；V2 "a?c" / "abc" → TRUE；V3 "a?c" / "abbc" → FALSE
//   V4 "**" 折叠连续星 / 任意串 → TRUE；V5 "a*" / "" → TRUE；V6 "" / "" → TRUE
//   V7 "a*b" / "abbc" → FALSE（尾部核查）；V8 64 字符串 → bValid = FALSE
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 1 · 序号 2）
// ==============================================================================
FUNCTION FC_DL_StringWildMatch : BOOL
VAR_INPUT
    sPat       : STRING(64);   // 模式串 [字符]，'*' 任意长度 / '?' 单字符 / the pattern string
    sTxt       : STRING(64);   // 文本串 [字符] / the text string
    bCaseSense : BOOL := TRUE; // 大小写敏感开关，默认敏感 [-] / case sensitivity switch, sensitive by default
END_VAR
VAR_OUTPUT
    bMatch : BOOL;             // 匹配结果 [-]，TRUE = 命中 / the match result, true means hit
    bValid : BOOL;             // 结果可用 [-]，任一串触 64 上限（可能截断）为 FALSE / the validity flag, false when possibly truncated
END_VAR
VAR
    nPatLen : INT;             // 锁存的模式串长度 [字符] / the latched pattern length
    nTxtLen : INT;             // 锁存的文本串长度 [字符] / the latched text length
    nP      : INT;             // 模式指针 [字符位序]，1 起 / the pattern pointer, one based
    nT      : INT;             // 文本指针 [字符位序]，1 起 / the text pointer, one based
    nStarP  : INT;             // 最后一次 '*' 的模式位序 [字符位序]，0 = 无 / the last star pattern position, zero means none
    nStarT  : INT;             // 该 '*' 已吞噬到的文本位序 [字符位序] / the text position consumed by that star
    nGuard  : INT;             // 循环护栏计数 [次] / the loop guard counter
    nK      : INT;             // 尾部模式扫描索引 [字符位序] / the trailing pattern scan index
    nPos    : INT;             // 码表定位 [索引]，1 起 / the table position, one based
    cP      : STRING(1);       // 模式当前字符 [字符] / the current pattern char
    cT      : STRING(1);       // 文本当前字符 [字符] / the current text char
    cPf     : STRING(1);       // 折叠后模式字符 [字符] / the case folded pattern char
    cTf     : STRING(1);       // 折叠后文本字符 [字符] / the case folded text char
    bRest   : BOOL;            // 剩余模式含非星字符标志 [-] / the flag that the rest contains a non star char
END_VAR
VAR CONSTANT
    DL_SWM_NMAX : INT := 64;   // 串长上限 [字符]，与形参声明一致 / the string cap aligned with the declarations
    DL_SWM_ONE  : INT := 1;    // 整型一常量 [字符] / the integer one constant
    DL_SWM_GMAX : INT := 4096; // 护栏计数上界 [次]，远大于最坏指针步数 256 / the guard bound far above the worst case
END_VAR

// 段 1｜返回值与全部出口预置（R45 四段式第一段）/ segment 1, the preset of the return and all outlets
FC_DL_StringWildMatch := FALSE; // 返回值预置假 / preset the return false
bMatch := FALSE;                // 匹配结果预置不命中 / preset the match false
bValid := FALSE;                // 有效标志预置假（段 2 按触界复核）/ preset the validity false

// 段 2｜长度一次锁存 + 触界截断闸（边界一）/ segment 2, latch lengths with the truncation gate
nPatLen := LEN(sPat);           // 模式串长度 [字符] / the pattern length
nTxtLen := LEN(sTxt);           // 文本串长度 [字符] / the text length
IF nPatLen < 0 THEN             // 防御性异常长度（结构性不可达）/ a defensive anomalous length
    nPatLen := 0;               // 异常返回值钳零 / clamp the anomalous value to zero
END_IF
IF nTxtLen < 0 THEN             // 防御性异常长度（结构性不可达）/ a defensive anomalous length
    nTxtLen := 0;               // 异常返回值钳零 / clamp the anomalous value to zero
END_IF
IF (nPatLen >= DL_SWM_NMAX) OR (nTxtLen >= DL_SWM_NMAX) THEN // 任一串触声明上限 / either string at the declared cap
    bMatch := FALSE;            // 可能截断，拒绝输出存疑匹配 / possibly truncated, refuse the doubtful match
    RETURN;                     // 早退（信息级 0742 通道即 bValid = FALSE）/ early return
END_IF
bValid := TRUE;                 // 触界闸通过，判定可用 / the gate passed, the verdict usable

// 段 3｜双指针主循环（边界二：单星回溯 + 护栏，无递归）/ segment 3, the two pointer main loop with the single star backtrack
nP := DL_SWM_ONE;               // 模式指针起始 [字符位序] / the pattern pointer start
nT := DL_SWM_ONE;               // 文本指针起始 [字符位序] / the text pointer start
nStarP := 0;                    // 回溯星位序清零（0 = 无）/ clear the star position
nStarT := 0;                    // 回溯星吞噬位清零 / clear the star consumed position
bMatch := TRUE;                 // 乐观预置，失配即断 / preset optimistic, break on mismatch
nGuard := 0;                    // 护栏清零 / reset the guard
WHILE nT <= nTxtLen DO          // 文本耗尽即出循环转尾部核查 / exit when the text is exhausted
    nGuard := nGuard + DL_SWM_ONE; // 护栏计数推进 / advance the guard
    IF nGuard > DL_SWM_GMAX THEN   // 护栏命中（结构性不可达兜底，边界二）/ the guard tripped, structurally unreachable
        bMatch := FALSE;           // 强制失配退出，禁死循环 / force the mismatch, no hang
        EXIT;                      // 断主循环 / break the main loop
    END_IF
    IF nP <= nPatLen THEN          // 模式未耗尽 / the pattern not exhausted
        cP := MID(sPat, DL_SWM_ONE, nP); // 取模式当前字符 / take the current pattern char
        cT := MID(sTxt, DL_SWM_ONE, nT); // 取文本当前字符 / take the current text char
        IF cP = '*' THEN           // 通配星：登记回溯点后推进模式指针（连续星折叠语义天然成立）/ a star, register the backtrack point
            nStarP := nP;          // 登记星位序 / register the star position
            nStarT := nT;          // 登记当前文本位序 / register the text position
            nP := nP + DL_SWM_ONE; // 模式指针推进 / advance the pattern pointer
        ELSE                       // 非星字符 / a non star char
            cPf := cP;             // 折叠暂存默认原值 / the folded staging defaults to the original
            cTf := cT;             // 折叠暂存默认原值 / the folded staging defaults to the original
            IF NOT bCaseSense THEN // 大小写不敏感才折叠（边界四）/ fold only when insensitive
                IF (cP >= 'A') AND (cP <= 'Z') THEN // 模式字符在大写域内 / the pattern char in the uppercase domain
                    nPos := FIND('ABCDEFGHIJKLMNOPQRSTUVWXYZ', cP); // 大写码表定位（域内恒命中）/ locate in the uppercase table
                    cPf := MID('abcdefghijklmnopqrstuvwxyz', DL_SWM_ONE, nPos); // 同位取小写 / the same position lowercase
                END_IF
                IF (cT >= 'A') AND (cT <= 'Z') THEN // 文本字符在大写域内 / the text char in the uppercase domain
                    nPos := FIND('ABCDEFGHIJKLMNOPQRSTUVWXYZ', cT); // 大写码表定位 / locate in the uppercase table
                    cTf := MID('abcdefghijklmnopqrstuvwxyz', DL_SWM_ONE, nPos); // 同位取小写 / the same position lowercase
                END_IF
            END_IF
            IF (cP = '?') OR (cPf = cTf) THEN // 问号单字符任意匹配或折叠后相等 / a question mark or the folded equality
                nP := nP + DL_SWM_ONE; // 双指针同步推进 / advance both pointers
                nT := nT + DL_SWM_ONE; // 双指针同步推进 / advance both pointers
            ELSIF nStarP > 0 THEN  // 失配但有回溯星：星多吞一个字符后重试 / a mismatch with a star, let the star swallow one more
                nStarT := nStarT + DL_SWM_ONE; // 星吞噬位递增 / advance the swallowed position
                nT := nStarT;      // 文本指针归位到星吞噬位 / reset the text pointer
                nP := nStarP + DL_SWM_ONE; // 模式指针归位到星后一位 / reset the pattern pointer
            ELSE                   // 失配且无回溯星 / a mismatch without any star
                bMatch := FALSE;   // 判定不命中 / the verdict is a miss
                EXIT;              // 断主循环 / break the main loop
            END_IF
        END_IF
    ELSIF nStarP > 0 THEN          // 模式已耗尽但有回溯星：星继续吞噬 / the pattern exhausted, the star swallows on
        nStarT := nStarT + DL_SWM_ONE; // 星吞噬位递增 / advance the swallowed position
        nT := nStarT;              // 文本指针归位 / reset the text pointer
        nP := nStarP + DL_SWM_ONE; // 模式指针归位 / reset the pattern pointer
    ELSE                           // 模式与文本均无余量且无星 / nothing left without a star
        bMatch := FALSE;           // 判定不命中 / the verdict is a miss
        EXIT;                      // 断主循环 / break the main loop
    END_IF
END_WHILE

// 段 4｜尾部模式核查（边界三：剩余模式必须全为 '*'）/ segment 4, the trailing pattern check
IF bMatch THEN                  // 主循环未失配才核查 / check only without a mismatch
    bRest := FALSE;             // 非星残留标志预置假 / preset the non star rest flag false
    FOR nK := nP TO nPatLen DO  // 剩余模式有界扫描 / the bounded scan of the rest
        IF MID(sPat, DL_SWM_ONE, nK) <> '*' THEN // 发现非星字符 / a non star char found
            bRest := TRUE;      // 置残留标志 / raise the rest flag
        END_IF
    END_FOR
    IF bRest THEN               // 剩余模式含非星字符 / the rest contains a non star char
        bMatch := FALSE;        // 判定不命中（防 "a*b" 对短文本误报）/ the verdict is a miss
    END_IF
END_IF

// 段 5｜出口装配 / segment 5, the outlet assembly
FC_DL_StringWildMatch := bValid; // 返回判定可用性 / return the verdict usability
END_FUNCTION
