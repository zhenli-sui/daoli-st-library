(*
  ============================================================
  组件名 : FC_DL_BinLabelCheckSum
  分类   : DL_Process
  功能   : 货位标号校验和计算，按长度与分隔符数量生成模 36 校验位并校验格式合法性
  复杂度 : C1
  版本   : 1.0.0
  作者   : 道莅工业代码库工厂 / R81
  日期   : 2026-11-24
  开源溯源 : clean-room（no upstream）—— 依据公开工程公式自研，未复制任何上游实现
  红线自检 : R1 无GVL/R2 无物理地址/R3 纯IEC/R4 防除零/R5 双语注释
  接口说明 :
      简化口径：不作 ASCII 码位转换，仅统计长度、连字符数量与空格数量参与校验和，
      以避免依赖各平台私有 STRING 转数值函数。这是本组件的既定设计口径，非降级实现。
      校验和 = 长度 + 连字符数*3 + 空格数*7；校验位 = 校验和 MOD 36。
      格式合法 = 长度落在 4~32 之间，且至少含 1 位数字，且连字符与空格各不超过 4 个。
      字符扫描用标准 FIND/DELETE 迭代，并设扫描次数上限，杜绝异常串导致的死循环。
  ============================================================
*)
FUNCTION FC_DL_BinLabelCheckSum : BOOL
VAR_INPUT
    bEnable : BOOL;         // 使能：TRUE 时计算 / Enable: TRUE to compute
    bErr    : BOOL;         // 外部故障：TRUE 时立即退出并置结果无效 / External fault: TRUE aborts with invalid result
    sLabel  : STRING[32];   // 待校验的货位标号文本 [文本] / label text to be verified [text]
END_VAR
VAR_OUTPUT
    iSum       : INT;  // 校验和整数 [无量纲计数] / checksum integer [dimensionless count]
    iChkDigit  : INT;  // 校验位，校验和对 36 取模 [0~35] / check digit, checksum modulo 36 [0 to 35]
    iLabelLen  : INT;  // 标号实际长度 [字符] / actual label length [character]
    bFormatOk  : BOOL; // 格式合法：TRUE 表示长度与字符构成符合约定 / format legal, TRUE when length and characters match the rule
    bValid     : BOOL; // 输出有效：TRUE 表示结果可用 / Output valid
END_VAR
VAR CONSTANT
    DL_LEN_MIN  : INT := 4;  // 标号最小长度 [字符] / minimum label length [character]
    DL_LEN_MAX  : INT := 32; // 标号最大长度 [字符] / maximum label length [character]
    DL_MOD_BASE : INT := 36; // 校验位取模基数 [无量纲] / modulus base of the check digit [dimensionless]
    DL_SCAN_MAX : INT := 64; // 单类字符扫描次数上限，防死循环 [次] / scan iteration limit per character class [time]
    DL_SEP_MAX  : INT := 4;  // 分隔符允许的最多出现次数 [次] / maximum allowed separator occurrences [time]
    DL_W_LEN    : INT := 1;  // 长度项权重 [无量纲] / weight of the length term [dimensionless]
    DL_W_DASH   : INT := 3;  // 连字符项权重 [无量纲] / weight of the hyphen term [dimensionless]
    DL_W_SPACE  : INT := 7;  // 空格项权重 [无量纲] / weight of the space term [dimensionless]
END_VAR
VAR
    _sTmp      : STRING[32]; // 扫描用工作副本 [文本] / working copy used for scanning [text]
    _iPos      : INT := 0;   // 最近一次查找命中位置，0 表示未命中 [字符位序] / last match position, zero means no match [character index]
    _iDash     : INT := 0;   // 连字符出现次数 [次] / number of hyphen occurrences [time]
    _iSpace    : INT := 0;   // 空格出现次数 [次] / number of space occurrences [time]
    _iGuard    : INT := 0;   // 扫描次数看门狗计数 [次] / watchdog counter of scan iterations [time]
    _bHasDigit : BOOL := FALSE; // 至少含一位数字的判定结果 / verdict of containing at least one digit
END_VAR

    // 段 1｜出口预置
    iSum := 0;
    iChkDigit := 0;
    iLabelLen := 0;
    bFormatOk := FALSE;
    bValid := FALSE;
    // 段 2｜使能闸与外部故障闸
    IF NOT bEnable THEN
        RETURN;
    END_IF;
    IF bErr THEN
        RETURN;
    END_IF;
    // 段 3｜长度闸
    iLabelLen := LEN(sLabel);
    IF iLabelLen < DL_LEN_MIN THEN
        RETURN;
    END_IF;
    IF iLabelLen > DL_LEN_MAX THEN
        RETURN;
    END_IF;
    // 段 4｜统计连字符数量：逐次定位后删除该字符，直至不再命中
    _sTmp := sLabel;
    _iDash := 0;
    _iGuard := 0;
    _iPos := FIND(_sTmp, '-');
    WHILE _iPos > 0 DO
        _iDash := _iDash + 1;
        _sTmp := DELETE(_sTmp, _iPos, 1);
        _iGuard := _iGuard + 1;
        IF _iGuard > DL_SCAN_MAX THEN
            EXIT;
        END_IF;
        _iPos := FIND(_sTmp, '-');
    END_WHILE;
    // 段 5｜统计空格数量
    _sTmp := sLabel;
    _iSpace := 0;
    _iGuard := 0;
    _iPos := FIND(_sTmp, ' ');
    WHILE _iPos > 0 DO
        _iSpace := _iSpace + 1;
        _sTmp := DELETE(_sTmp, _iPos, 1);
        _iGuard := _iGuard + 1;
        IF _iGuard > DL_SCAN_MAX THEN
            EXIT;
        END_IF;
        _iPos := FIND(_sTmp, ' ');
    END_WHILE;
    // 段 6｜数字存在性：逐字符常量查找，命中任一即为真
    _bHasDigit := (FIND(sLabel, '0') > 0) OR (FIND(sLabel, '1') > 0) OR (FIND(sLabel, '2') > 0) OR (FIND(sLabel, '3') > 0) OR (FIND(sLabel, '4') > 0) OR (FIND(sLabel, '5') > 0) OR (FIND(sLabel, '6') > 0) OR (FIND(sLabel, '7') > 0) OR (FIND(sLabel, '8') > 0) OR (FIND(sLabel, '9') > 0);
    // 段 7｜校验和与校验位
    iSum := iLabelLen * DL_W_LEN + _iDash * DL_W_DASH + _iSpace * DL_W_SPACE;
    IF iSum < 0 THEN
        iSum := 0;
    END_IF;
    iChkDigit := iSum MOD DL_MOD_BASE;
    // 段 8｜格式合法性
    IF _bHasDigit AND (_iDash <= DL_SEP_MAX) AND (_iSpace <= DL_SEP_MAX) THEN
        bFormatOk := TRUE;
    ELSE
        bFormatOk := FALSE;
    END_IF;
    bValid := TRUE;
    FC_DL_BinLabelCheckSum := bValid;
END_FUNCTION
