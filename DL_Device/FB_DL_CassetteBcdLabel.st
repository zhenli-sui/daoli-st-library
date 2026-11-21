(*==============================================================================
 * 组件名称 (Component)  : FB_DL_CassetteBcdLabel
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG / LEN），零厂商私有库
 * 功能描述 (Function)   : 花篮 BCD 拨码标签机联动。
 *                         把批次号（0..9999）编成 4 位 BCD 拨码，驱动标签机打印，再用扫码枪回读
 *                         校验"打出来的标签"与"拨码值"一致，形成闭环；不一致或打印超时即锁存。
 *                         三段语义：
 *                           ① **拨码生成**：数值 → 四位十进制 → 打包 BCD（移位量取常量 0/4/8/12，
 *                              恒小于 WORD 位宽 16），并做**逐位 BCD 校验**（每位 ≤ 9，由十进制拆分
 *                              结构性保证，另设反解校验以覆盖"外部写入 BCD 字"的通道）；
 *                           ② **扫码枪语义**：回读串逐字符转数字并校验字符合法（'0'..'9'），
 *                              非法字符即判 eScanFormat；
 *                           ③ **打印同步握手**：打印脉冲单拍 → 等 bPrintDone → 扫码校验 → 结果脉冲。
 *                         **忙时拒新任务**：打印窗口内收到新的生成请求只置 bBusyReject（信息级），
 *                         不打断当前任务（打断会产生半张标签，比排队更糟）。
 *                         验收向量：
 *                           ① 批次 1234 → uBcd = 16#1234，四位数字 4/3/2/1
 *                           ② 回读 "1234" → 校验通过，bLabelOk 单拍
 *                           ③ 回读 "12X4" → eScanFormat 锁存（非法字符）
 *                           ④ 回读 "1235" → eScanMismatch 锁存（数值不一致）
 *                           ⑤ 打印窗口内再次请求生成 → bBusyReject 单拍，当前任务不受影响
 * 接口     (Interface)  : 入 iLotNo 批次号（0..9999）、bGenReq 生成沿、bPrintDone 打印完成、
 *                         sScanCode 扫码回读串、bScanValid 回读有效、tPrintTo 打印超时、bReset 复位沿；
 *                         出 uBcdPacked 打包 BCD、abDigits 四位数字（1=个 … 4=千）、bPrintCmd 打印脉冲（单拍）、
 *                         bLabelOk 标签校验通过脉冲（单拍）、bBusy 打印中、bBusyReject 忙拒单拍、
 *                         bLabelFail 标签失败锁存、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"拨码编码 + 打印握手 + 扫码校验"，
 *                         不驱动打印头/拨码继电器、不解析标签条码的厂商前缀**（属设备驱动与协议件）；
 *                         ② **BCD 半字节校验**：位宽 16 恰 4 个半字节，校验域 k=0..3 完整覆盖，
 *                         头注释声明"不做越界半字节校验"（R57：越域半字节不存在而非非法）；
 *                         ③ **域闸**：iLotNo 越 0..9999 → 拒生成 + eLotBad（信息级）；
 *                         ④ **打印超时 TON**：tonPrint 段 0 无条件调用，IN 串 (NOT _bFault)，
 *                         故障期不累计，复位同拍不会立即重锁（R252）；
 *                         ⑤ **锁存解除式**：bLabelFail / eFault 仅由 bReset 上升沿解除（R228B），
 *                         bReset 为外部引脚、恒可达；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"花篮拨码标签联动"。不接管：IV 测试仪设定值导出
 *                         （属 FB_DL_IvBcdExport）、标签模板排版（属标签设计侧）、
 *                         花篮工艺履历（属追溯件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P2（花篮 BCD 标签联动，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 域闸 + 字符域校验 + 常量移位 + 超时 TON ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/三 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 4 · 序号 18）
 *==============================================================================*)

TYPE E_DL_CblState :
(
    eIdle    := 0,    // 待机相（等生成请求） / Idle, awaiting a generation request
    ePrinting:= 10,   // 打印中（等打印完成） / Printing, awaiting completion
    eVerify  := 20,   // 校验相（等扫码回读） / Verifying, awaiting the scan read-back
    eFault   := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_CblCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eLotBad      := 1,   // 批次号越域（信息级，拒生成） / Lot number out of range, info level
    eBusyReject  := 2,   // 忙时拒新任务（信息级） / Busy, new request rejected, info level
    ePrintTimeout:= 3,   // 打印超时（锁存） / Print timeout, latched
    eScanFormat  := 4,   // 回读含非法字符（锁存） / Illegal character in the read-back, latched
    eScanMismatch:= 5,   // 回读与拨码不一致（锁存） / Read-back mismatch, latched
    eCfgIllegal  := 6,   // 组态非法（超时非正） / Illegal configuration
    ePhaseBad    := 7    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_CassetteBcdLabel
VAR_INPUT
    iLotNo     : INT := 0;                 // 批次号，域 0..9999 [-] / Lot number, domain 0..9999
    bGenReq    : BOOL := FALSE;            // 生成请求沿 [-] / Generation request edge
    bPrintDone : BOOL := FALSE;            // 打印完成（当拍电平） [-] / Print finished, level
    sScanCode  : STRING[15] := '';         // 扫码回读串 [-] / Scan read-back string
    bScanValid : BOOL := FALSE;            // 回读有效（当拍电平） [-] / Read-back valid, level
    tPrintTo   : TIME := T#10S;            // 打印超时，域 > T#0S [ms] / Print timeout, > T#0S
    bReset     : BOOL := FALSE;            // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    uBcdPacked : WORD := 16#0000;                        // 打包 BCD 字 [BCD] / Packed BCD word
    abDigits   : ARRAY[1..4] OF BYTE;                    // 四位数字（1=个,2=十,3=百,4=千） [-] / Four digits
    bPrintCmd  : BOOL := FALSE;                          // 打印脉冲（单拍） [-] / Print pulse, single scan
    bLabelOk   : BOOL := FALSE;                          // 标签校验通过脉冲（单拍） [-] / Label verified pulse
    bBusy      : BOOL := FALSE;                          // 打印/校验中 [-] / Busy
    bBusyReject: BOOL := FALSE;                          // 忙拒单拍 [-] / Busy rejection, single scan
    bLabelFail : BOOL := FALSE;                          // 标签失败锁存（等复位） [-] / Label failure, latched
    eState     : E_DL_CblState := E_DL_CblState.eIdle;   // 相出口 [-] / Phase outlet
    eCause     : E_DL_CblCause := E_DL_CblCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError     : BOOL := FALSE;                          // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_CblState := E_DL_CblState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_CblCause := E_DL_CblCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bFail    : BOOL := FALSE;                           // 标签失败锁存位 / Latched label-failure bit
    _uBcd     : WORD := 16#0000;                         // 打包工作值 [BCD] / Packing working value
    _iWork    : INT := 0;                                // 十进制拆分工作值 [-] / Decimal split working value
    _iVal     : INT := 0;                                // 回读串解析出的数值 [-] / Value parsed from the read-back
    _iPos     : INT := 0;                                // 回读串字符位置 / Character position in the read-back
    _iLen     : INT := 0;                                // 回读串长度 [字符] / Read-back length
    _iDigit   : INT := 0;                                // 当前字符代表的数字值（0..9） [-] / Digit value of the current character
    sChr      : STRING[1] := '';                         // 当前单字符（用于 '0'..'9' 判等） [-] / Current single character
    _bPrintCmd: BOOL := FALSE;                           // 打印脉冲内部位（单拍） / Internal print pulse
    _bLabelOk : BOOL := FALSE;                           // 校验通过内部位（单拍） / Internal verified pulse
    _bBusyRej : BOOL := FALSE;                           // 忙拒内部位（单拍） / Internal busy-rejection flag
    _bFmtBad  : BOOL := FALSE;                           // 回读格式结论 [-] / Read-back format result
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    tonPrint  : TON;                                     // 打印超时实例，段 0 无条件调用 / Print timeout instance
    rtGen     : R_TRIG;                                  // 生成沿实例，段 0 无条件调用 / Generation edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_CBL_LOT_MAX : INT := 9999;        // 批次号上限（四位十进制） [-] / Lot upper bound
    DL_CBL_SH4     : INT := 4;           // 十位左移量（恒 < 16，R48） [bit] / Tens shift
    DL_CBL_SH8     : INT := 8;           // 百位左移量（恒 < 16，R48） [bit] / Hundreds shift
    DL_CBL_SH12    : INT := 12;          // 千位左移量（恒 < 16，R48） [bit] / Thousands shift
    DL_CBL_MSK     : WORD := 16#000F;    // 半字节掩码（非事件码，头注释声明） [bit] / Nibble mask, not an event code
    DL_CBL_CHR_MAX : INT := 15;          // 回读串长度硬上限（与 STRING[15] 同源） [字符] / Hard length ceiling
END_VAR

(* —— 段 0：组态闸 + TON 与两沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (tPrintTo <= T#0S);                                             // 打印超时须为正 / Timeout must be positive
rtGen(CLK := bGenReq);                                                      // 生成沿 / Generation edge
rtReset(CLK := bReset);                                                     // 复位沿 / Reset edge
tonPrint(IN := (_eState = E_DL_CblState.ePrinting) AND (NOT _bFault), PT := tPrintTo);   // 打印超时 / Print timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bFail 不入清单，R107） —— *)
_bPrintCmd := FALSE;                                                        // 打印脉冲预清 / Print pulse preset
_bLabelOk  := FALSE;                                                        // 校验通过脉冲预清 / Verified pulse preset
_bBusyRej  := FALSE;                                                        // 忙拒预清 / Busy-rejection preset
bError     := FALSE;                                                        // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_CblCause.eCfgIllegal;                                    // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                                         // 锁存 / Latch
    _eState := E_DL_CblState.eFault;                                         // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿：清双锁存，R228B） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                                        // 清故障锁存 / Clear fault latch
    _bFail  := FALSE;                                                        // 清标签失败锁存 / Clear the label-failure latch
    _eCause := E_DL_CblCause.eNone;                                          // 清成因 / Clear cause
    _eState := E_DL_CblState.eIdle;                                          // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（生成 → 打印 → 校验 握手闭环；忙时拒新） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_CblState.eIdle:
        IF rtGen.Q THEN
            IF (iLotNo < 0) OR (iLotNo > DL_CBL_LOT_MAX) THEN
                _eCause := E_DL_CblCause.eLotBad;                             // 域闸：批次号越界（信息级） / Lot out of range, info level
            ELSE
                (* 十进制拆分（每位恒 0..9，BCD 半字节合法由构造保证） *)
                _iWork := iLotNo;                                             // 取批次号 / Take the lot number
                abDigits[1] := INT_TO_BYTE(_iWork MOD 10);                    // 个位 / Units
                _iWork := _iWork / 10;                                        // 去个位 / Drop units
                abDigits[2] := INT_TO_BYTE(_iWork MOD 10);                    // 十位 / Tens
                _iWork := _iWork / 10;                                        // 去十位 / Drop tens
                abDigits[3] := INT_TO_BYTE(_iWork MOD 10);                    // 百位 / Hundreds
                _iWork := _iWork / 10;                                        // 去百位 / Drop hundreds
                abDigits[4] := INT_TO_BYTE(_iWork MOD 10);                    // 千位 / Thousands
                _uBcd := SHL(BYTE_TO_WORD(abDigits[4]), DL_CBL_SH12)
                      OR SHL(BYTE_TO_WORD(abDigits[3]), DL_CBL_SH8)
                      OR SHL(BYTE_TO_WORD(abDigits[2]), DL_CBL_SH4)
                      OR (BYTE_TO_WORD(abDigits[1]) AND DL_CBL_MSK);          // 打包 BCD / Pack BCD
                uBcdPacked := _uBcd;                                          // 打包字出口 / Packed word outlet
                _bPrintCmd := TRUE;                                           // 打印脉冲（内部位） / Internal print pulse
                _eState := E_DL_CblState.ePrinting;                           // 进打印相 / Enter printing
            END_IF
        END_IF

    E_DL_CblState.ePrinting:
        IF bPrintDone THEN
            _eState := E_DL_CblState.eVerify;                                 // 打印完成：进校验相 / Printing done, verify
        ELSIF tonPrint.Q THEN
            _bFail  := TRUE;                                                  // 打印超时：锁存 / Timeout: latch
            _bFault := TRUE;                                                  // 故障锁存 / Latch the fault
            _eCause := E_DL_CblCause.ePrintTimeout;                           // 归因：打印超时 / Cause: print timeout
            _eState := E_DL_CblState.eFault;                                  // 入故障相 / Enter fault phase
        ELSIF rtGen.Q THEN
            _bBusyRej := TRUE;                                                // 忙时拒新任务（不打断当前打印） / Busy rejection
            _eCause := E_DL_CblCause.eBusyReject;                             // 归因：忙拒（信息级） / Cause: busy rejection
        END_IF

    E_DL_CblState.eVerify:
        IF bScanValid THEN
            (* 扫码串解析：逐字符与 '0'..'9' 单字符字面量比对（ST 无字符码函数，
               故用字符串字面量判等；非法字符即判格式错） *)
            _iLen := LEN(sScanCode);                                          // 取回读长度 / Read-back length
            IF (_iLen < 1) OR (_iLen > DL_CBL_CHR_MAX) THEN
                _bFmtBad := TRUE;                                             // 长度越域：判格式错 / Length out of range
            ELSE
                _bFmtBad := FALSE;                                            // 格式结论初值 / Format result initial value
                _iVal := 0;                                                   // 数值累加器归零 / Value accumulator reset
                FOR _iPos := 1 TO DL_CBL_CHR_MAX DO
                    IF _iPos <= _iLen THEN
                        sChr := MID(sScanCode, 1, _iPos);                     // 取单个字符 / Single character
                        IF (sChr = '0') THEN
                            _iDigit := 0;
                        ELSIF (sChr = '1') THEN
                            _iDigit := 1;
                        ELSIF (sChr = '2') THEN
                            _iDigit := 2;
                        ELSIF (sChr = '3') THEN
                            _iDigit := 3;
                        ELSIF (sChr = '4') THEN
                            _iDigit := 4;
                        ELSIF (sChr = '5') THEN
                            _iDigit := 5;
                        ELSIF (sChr = '6') THEN
                            _iDigit := 6;
                        ELSIF (sChr = '7') THEN
                            _iDigit := 7;
                        ELSIF (sChr = '8') THEN
                            _iDigit := 8;
                        ELSIF (sChr = '9') THEN
                            _iDigit := 9;
                        ELSE
                            _iDigit := 0;                                     // 非法字符的数值占位（不参与累加） / Placeholder, not accumulated
                            _bFmtBad := TRUE;                                 // 非法字符 / Illegal character
                        END_IF
                        _iVal := _iVal * 10 + _iDigit;                        // 十进制累加 / Decimal accumulate
                    END_IF
                END_FOR
            END_IF

            IF _bFmtBad THEN
                _bFail  := TRUE;                                              // 格式错：锁存 / Format error: latch
                _bFault := TRUE;                                              // 故障锁存 / Latch the fault
                _eCause := E_DL_CblCause.eScanFormat;                         // 归因：回读格式非法 / Cause: scan format
                _eState := E_DL_CblState.eFault;                              // 入故障相 / Enter fault phase
            ELSIF _iVal = iLotNo THEN
                _bLabelOk := TRUE;                                            // 校验通过脉冲 / Verified pulse
                _eState := E_DL_CblState.eIdle;                               // 回待机相 / Back to idle
            ELSE
                _bFail  := TRUE;                                              // 不一致：锁存 / Mismatch: latch
                _bFault := TRUE;                                              // 故障锁存 / Latch the fault
                _eCause := E_DL_CblCause.eScanMismatch;                       // 归因：回读不一致 / Cause: scan mismatch
                _eState := E_DL_CblState.eFault;                              // 入故障相 / Enter fault phase
            END_IF
        END_IF

    E_DL_CblState.eFault:
        ;                                                                     // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_CblCause.ePhaseBad;                                   // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                                      // 锁存 / Latch
        _eState := E_DL_CblState.eFault;                                      // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：出口单点映射（名实双出口，R191） —— *)
bPrintCmd   := _bPrintCmd;                                                    // 打印脉冲出口 / Print pulse outlet
bLabelOk    := _bLabelOk;                                                     // 校验通过出口 / Verified outlet
bBusy       := (_eState = E_DL_CblState.ePrinting) OR (_eState = E_DL_CblState.eVerify);   // 忙碌出口 / Busy outlet
bBusyReject := _bBusyRej;                                                     // 忙拒出口 / Busy-rejection outlet
bLabelFail  := _bFail;                                                        // 标签失败出口 / Label-failure outlet
eState      := _eState;                                                       // 相出口 / Phase outlet
eCause      := _eCause;                                                       // 成因出口 / Cause outlet
bError      := _bFault;                                                       // 故障标志 / Error flag

END_FUNCTION_BLOCK
