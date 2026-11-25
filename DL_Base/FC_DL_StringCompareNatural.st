(*==============================================================================
 * 组件名称 (Component)  : FC_DL_StringCompareNatural
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 IEC 61131-3 标准字符串九函数（LEN / MID / LEFT / CONCAT / DELETE / FIND），零厂商私有库
 * 功能描述 (Function)   : 自然序比较（Human sort / natural sort）。规则：
 *                           · 双方同位置均为数字时，各自提取完整数字段，按「数值」比较
 *                             （去前导零后先比位数、同位数再逐位比较），故 A2 < A10；
 *                           · 其余位置按单字符序数比较，序数由排序字符集常量
 *                             DL_SCN_ORDER 的 FIND 位置给出（集合外字符序数记 0，排最前）；
 *                           · 公共前缀耗尽后，剩余字符多者更大（A < AB）。
 *                         全程用 FIND(集合, 单字符) 取序数，不依赖平台字符串比较运算符或
 *                         字符码强转方言（R3 纯标准函数路径）。
 * 接口     (Interface)  : 输入 sInA 左串、sInB 右串 [-]；
 *                         输出 iResult 比较结果（-1 左小 / 0 相等 / 1 左大）[-]、
 *                         bEqual 是否相等、eErrCode 错误码（E_DL_StrNatErr）；
 *                         返回值 = bValid 比较可信标志（TRUE = iResult 可信）。
 * 边界     (Boundary)   : ① 属主边界：只做比较，不做排序（排序归调用方的数组管理）、
 *                         不做大小写折叠（'A' 与 'a' 序数不同，A 在前）。
 *                         ② 数字段归一：去前导零后 '007' 与 '7' 相等（数值 7），
 *                         故 "A007" = "A7"（iResult=0）；长度差由去零后的位数决定。
 *                         ③ 序数集合只含 0-9 / A-Z / a-z；标点与空格序数记 0（同序则继续后移，
 *                         不判等、不报错），排序稳定性由调用方的稳定排序保证。
 *                         ④ 长度均钳位至 255（缓冲可表性），双向扫描严格有界。
 *                         ⑤ 内层数字段提取循环亦以上界 _udLenA/_udLenB 收口，无越界。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FC_DL_StringReverse` 分工：位序重排归那件、序比较归本件；
 *                         与 `FC_DL_StringIsNumeric` 分工：整串数值判定归那件。
 * 来源标签 (Source Tag) : 原创实现（无外部代码引入）
 * 码表     (Codes)      : 本件不占用全局数字码位；出口为 BOOL + INT + BOOL +
 *                         本文件内定义 enum E_DL_StrNatErr（全库唯一）。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 双层循环上界收口 + 去前导零守恒 + 序数集合法（无字符码强转） ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 N/A（纯函数无状态机） ｜ R7 N/A（无实例调用）
 * 修订历史 (Revision)   : 2026-11-23  v1.0.0  R77 首版（批次 B2 · 序号 9）
 * 验收向量 (Acceptance) : ① sInA='A2', sInB='A10' → iResult=-1（数字段 2 < 10）, bEqual=FALSE, eOk；
 *                         ② sInA='A2', sInB='A2' → iResult=0, bEqual=TRUE；
 *                         ③ sInA='A007', sInB='A7' → 去零后数值相同 → iResult=0, bEqual=TRUE；
 *                         ④ sInA='A', sInB='AB' → 公共前缀耗尽，右串剩余 → iResult=-1；
 *                         ⑤ sInA='B1', sInB='A99' → 首字符序数 B > A → iResult=1；
 *                         ⑥ sInA='', sInB='' → iResult=0, bEqual=TRUE, eOk。
 *==============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_StrNatErr（自然序比较错误码，归属 DL_Base，与本件同文件，全库唯一属主）
 *----------------------------------------------------------------------------*)
TYPE E_DL_StrNatErr :
(
    eOk      := 0,   // 信息级：比较完成，结果可信 / Info: comparison completed, result trustworthy
    eClampLen:= 1    // 信息级：输入超缓冲上限已按 255 字符比较 / Info: inputs clamped to 255 chars for comparison
);
END_TYPE

FUNCTION FC_DL_StringCompareNatural : BOOL
VAR_INPUT
    sInA : STRING(255);   // 左串 [-] / Left string
    sInB : STRING(255);   // 右串 [-] / Right string
END_VAR
VAR_OUTPUT
    iResult : INT;        // 比较结果：-1 左小 / 0 相等 / 1 左大 [-] / Compare result: -1 less, 0 equal, 1 greater
    bEqual  : BOOL;       // 是否相等（iResult=0） [-] / Whether equal, iResult equals zero
    eErrCode: E_DL_StrNatErr; // 错误码出口 [-] / Error code outlet
END_VAR
VAR
    _udLenA  : UDINT;       // 左串生效长度 [字符] / Effective left length [chars]
    _udLenB  : UDINT;       // 右串生效长度 [字符] / Effective right length [chars]
    _udA     : UDINT;       // 左串游标（1 基） [-] / Left cursor, 1-based
    _udB     : UDINT;       // 右串游标（1 基） [-] / Right cursor, 1-based
    _udKa    : UDINT;       // 数字段内位序 [-] / Bit index inside digit run
    _udRunA  : UDINT;       // 左数字段长度 [字符] / Left digit run length [chars]
    _udRunB  : UDINT;       // 右数字段长度 [字符] / Right digit run length [chars]
    _rkA     : UDINT;       // 左字符序数（0 = 集合外） [-] / Left character rank, 0 means outside set
    _rkB     : UDINT;       // 右字符序数（0 = 集合外） [-] / Right character rank, 0 means outside set
    _sChA    : STRING(255); // 左串当前单字符 [-] / Current left character
    _sChB    : STRING(255); // 右串当前单字符 [-] / Current right character
    _sRunA   : STRING(255); // 左数字段（已去前导零） [-] / Left digit run, leading zeros stripped
    _sRunB   : STRING(255); // 右数字段（已去前导零） [-] / Right digit run, leading zeros stripped
    _iRes    : INT;         // 比较结果内部累加 [-] / Internal compare result
END_VAR
VAR CONSTANT
    DL_SCN_SET_DIGIT : STRING(255) := '0123456789';   // 数字字符集 [-] / Digit character set
    DL_SCN_SET_ZERO  : STRING(255) := '0';            // 零字符集（去前导零用） [-] / Zero character set for leading-zero strip
    DL_SCN_ORDER     : STRING(255) := '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'; // 序数字符集 [-] / Rank character set
    DL_SCN_LEN_MAX   : UINT := 255;                   // 缓冲上限（STRING(255) 契约） [字符] / Buffer ceiling [chars]
    DL_SCN_START     : UDINT := 1;                    // 字符串起始位置（IEC 1 基） [-] / String start position, 1-based
    DL_SCN_ONE_LEN   : UDINT := 1;                    // 单字符长度常量 [字符] / Single character length constant
    DL_SCN_HIT_ONE   : UDINT := 1;                    // FIND 首位命中的比较值 [-] / Compare value for first-position hit
END_VAR

(* —— 段 0：出口预置安全值 —— *)
FC_DL_StringCompareNatural := FALSE;               // 返回值预置不可信 / Return preset untrustworthy
iResult  := 0;                                     // 比较结果哨兵：相等 / Result sentinel: equal
bEqual   := FALSE;                                 // 相等标志预置否 / Equality flag preset false
eErrCode := E_DL_StrNatErr.eClampLen;              // 预置最严码（本件仅信息级码） / Preset strictest code

(* —— 段 1：长度实测与上域钳位（双向扫描严格有界） —— *)
_udLenA := LEN(sInA);                              // 左串字符数 / Left length
_udLenB := LEN(sInB);                              // 右串字符数 / Right length
IF (_udLenA > UINT_TO_UDINT(DL_SCN_LEN_MAX)) OR (_udLenB > UINT_TO_UDINT(DL_SCN_LEN_MAX)) THEN
    eErrCode := E_DL_StrNatErr.eClampLen;          // 信息级钳位码 / Info clamp code
ELSE
    eErrCode := E_DL_StrNatErr.eOk;                // 信息级成功预置 / Info success preset
END_IF
IF _udLenA > UINT_TO_UDINT(DL_SCN_LEN_MAX) THEN
    _udLenA := UINT_TO_UDINT(DL_SCN_LEN_MAX);      // 左串钳位 / Left clamped
END_IF
IF _udLenB > UINT_TO_UDINT(DL_SCN_LEN_MAX) THEN
    _udLenB := UINT_TO_UDINT(DL_SCN_LEN_MAX);      // 右串钳位 / Right clamped
END_IF

(* —— 段 2：游标与结果预清零（不含保持量，逐次比较独立） —— *)
_udA  := DL_SCN_START;
_udB  := DL_SCN_START;
_iRes := 0;

(* —— 段 3：主扫描（双游标均在界内且尚未分出胜负） —— *)
WHILE (_udA <= _udLenA) AND (_udB <= _udLenB) AND (_iRes = 0) DO
    _sChA := MID(sInA, DL_SCN_ONE_LEN, _udA);      // 取左串当前字符 / Take left current character
    _sChB := MID(sInB, DL_SCN_ONE_LEN, _udB);      // 取右串当前字符 / Take right current character

    IF (FIND(DL_SCN_SET_DIGIT, _sChA) > 0) AND (FIND(DL_SCN_SET_DIGIT, _sChB) > 0) THEN
        (* —— 段 3a：双方均为数字 → 提取完整数字段按数值比较 —— *)
        _sRunA := '';                              // 左数字段清空 / Clear left run
        WHILE (_udA <= _udLenA) AND (FIND(DL_SCN_SET_DIGIT, MID(sInA, DL_SCN_ONE_LEN, _udA)) > 0) DO
            _sRunA := CONCAT(_sRunA, MID(sInA, DL_SCN_ONE_LEN, _udA));   // 逐位累积左数字段 / Accumulate left digit
            _udA   := _udA + 1;                    // 游标越过该位 / Cursor passes this digit
        END_WHILE
        _sRunB := '';                              // 右数字段清空 / Clear right run
        WHILE (_udB <= _udLenB) AND (FIND(DL_SCN_SET_DIGIT, MID(sInB, DL_SCN_ONE_LEN, _udB)) > 0) DO
            _sRunB := CONCAT(_sRunB, MID(sInB, DL_SCN_ONE_LEN, _udB));   // 逐位累积右数字段 / Accumulate right digit
            _udB   := _udB + 1;
        END_WHILE

        (* 去前导零：保留至少一位（"000" 归一为 "0"） *)
        WHILE (LEN(_sRunA) > DL_SCN_ONE_LEN) AND (FIND(DL_SCN_SET_ZERO, LEFT(_sRunA, DL_SCN_ONE_LEN)) = DL_SCN_HIT_ONE) DO
            _sRunA := DELETE(_sRunA, DL_SCN_ONE_LEN, DL_SCN_START);      // 删首零 / Delete leading zero
        END_WHILE
        WHILE (LEN(_sRunB) > DL_SCN_ONE_LEN) AND (FIND(DL_SCN_SET_ZERO, LEFT(_sRunB, DL_SCN_ONE_LEN)) = DL_SCN_HIT_ONE) DO
            _sRunB := DELETE(_sRunB, DL_SCN_ONE_LEN, DL_SCN_START);      // 删首零 / Delete leading zero
        END_WHILE

        _udRunA := LEN(_sRunA);                    // 左段位数 / Left digit count
        _udRunB := LEN(_sRunB);                    // 右段位数 / Right digit count
        IF _udRunA < _udRunB THEN
            _iRes := -1;                           // 位数少者数值小 / Fewer digits is smaller
        ELSIF _udRunA > _udRunB THEN
            _iRes := 1;                            // 位数多者数值大 / More digits is greater
        ELSE
            _udKa := DL_SCN_START;                 // 同位数逐位比较 / Same digit count: compare per digit
            WHILE (_udKa <= _udRunA) AND (_iRes = 0) DO
                _rkA := FIND(DL_SCN_SET_DIGIT, MID(_sRunA, DL_SCN_ONE_LEN, _udKa));  // 左位序数 / Left digit rank
                _rkB := FIND(DL_SCN_SET_DIGIT, MID(_sRunB, DL_SCN_ONE_LEN, _udKa));  // 右位序数 / Right digit rank
                IF _rkA < _rkB THEN
                    _iRes := -1;                   // 左位小 / Left digit smaller
                ELSIF _rkA > _rkB THEN
                    _iRes := 1;                    // 左位大 / Left digit greater
                END_IF
                _udKa := _udKa + 1;                // 位序步进 / Advance digit index
            END_WHILE
        END_IF
    ELSE
        (* —— 段 3b：非数字段 → 按字符序数比较 —— *)
        _rkA := FIND(DL_SCN_ORDER, _sChA);         // 左字符序数（集合外 = 0） / Left rank, outside set is zero
        _rkB := FIND(DL_SCN_ORDER, _sChB);         // 右字符序数（集合外 = 0） / Right rank, outside set is zero
        IF _rkA < _rkB THEN
            _iRes := -1;                           // 左字符序数小 / Left character rank smaller
        ELSIF _rkA > _rkB THEN
            _iRes := 1;                            // 左字符序数大 / Left character rank greater
        END_IF
        _udA := _udA + 1;                          // 双游标同步步进 / Advance both cursors
        _udB := _udB + 1;
    END_IF
END_WHILE

(* —— 段 4：公共前缀耗尽后的长度裁决（剩余字符多者更大） —— *)
IF _iRes = 0 THEN
    IF _udA <= _udLenA THEN
        _iRes := 1;                                // 左串有剩余 → 左大 / Left has remainder: greater
    ELSIF _udB <= _udLenB THEN
        _iRes := -1;                               // 右串有剩余 → 左小 / Right has remainder: less
    ELSE
        _iRes := 0;                                // 同时耗尽 → 相等 / Both exhausted: equal
    END_IF
END_IF

(* —— 段 5：导出结果与相等标志 —— *)
iResult := _iRes;                                  // 导出比较结果 / Export compare result
bEqual  := (_iRes = 0);                            // 相等标志 / Equality flag
FC_DL_StringCompareNatural := TRUE;                // 比较可信 / Comparison trustworthy

END_FUNCTION
