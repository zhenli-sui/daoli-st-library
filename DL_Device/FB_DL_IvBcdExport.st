(*==============================================================================
 * 组件名称 (Component)  : FB_DL_IvBcdExport
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商私有库
 * 功能描述 (Function)   : IV 测试仪 BCD 拨码设定导出。
 *                         把上位下发的十进制设定值（0..9999）拆成四位十进制数字，打包成 BCD 字，
 *                         经"导出脉冲 → 等回读 → 逐位比对"的握手闭环确认测试仪已正确接收；
 *                         回读不一致或超时即锁存故障，等人工复位后重导。
 *                         **面板互转语义（双向，写死）**：
 *                           正解：value → 四位数字 d1(个)…d4(千) → uBcd = d4·16#1000 + d3·16#0100 + d2·16#0010 + d1
 *                           反解：uBcd → value（用于回读通道是 BCD 字的机型，本件按整值比对不拆位）
 *                         两位以上的半字节合法性由"十进制拆分"结构性保证（每位恒 0..9），
 *                         故不存在"非 BCD 半字节"可导出；真正的越界风险在**设定值本身越域**，
 *                         故设 0..9999 域闸 + 越域拒导出（eRangeBad，信息级，不锁存）。
 *                         验收向量：
 *                           ① 设定 1234 → 数字 d1=4, d2=3, d3=2, d4=1；uBcd = 16#1234
 *                           ② 设定 0    → 数字全 0；uBcd = 16#0000（合法边界，不拒算）
 *                           ③ 设定 9999 → uBcd = 16#9999（上界，不溢出）
 *                           ④ 设定 10000 → 拒导出 + eRangeBad（域闸，信息级）
 *                           ⑤ 回读 = 16#1234 → bReadbackOk；回读 = 16#1235 → 锁存 eRbMismatch
 * 接口     (Interface)  : 入 iSetValue 设定值、bExport 导出沿、bReadbackValid 回读有效、
 *                         iReadbackBcd 回读 BCD 字、tReadbackTo 回读超时、bReset 复位沿；
 *                         出 uBcdPacked 打包 BCD 字、abDigits 四位数字（1..4 = 个/十/百/千）、
 *                         bExported 导出脉冲（单拍）、bReadbackOk 回读一致脉冲（单拍）、
 *                         bRbFailed 回读失败锁存、eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"设定值编码 + 导出握手"，不驱动拨码
 *                         继电器/光电隔离板、不解析 IV 测量曲线**（属测试仪通讯件与曲线件）；
 *                         ② **域闸**：iSetValue 越 0..9999 → 拒导出（信息级 eRangeBad，不锁存、
 *                         不改已导出值）；③ **移位量常量化**：打包移位量取常量 0/4/8/12，
 *                         恒小于 WORD 位宽 16，跨平台无未定义行为（R48/R295）；
 *                         ④ **回读超时 TON**：tonRb 段 0 无条件调用，IN 串 (NOT _bFault)，
 *                         故障期不累计，复位同拍不会立即重锁（R252）；
 *                         ⑤ **锁存解除式**：bRbFailed 与 eFault 仅由 bReset 上升沿解除
 *                         （R228B 唯一迁出），bReset 为外部引脚、恒可达；
 *                         ⑥ **握手单拍脉冲三律**：导出脉冲与回读成功脉冲均在 CASE 内用内部位
 *                         置位、段尾统一映射出口，禁同相内置位后同相撤位（R129）；
 *                         ⑦ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"设定值 BCD 导出与回读校验"。不接管：花篮标签打印联动
 *                         （属 FB_DL_CassetteBcdLabel）、纯数值 BCD 转换原子件（属 FC_DL_WordToBcd 族）、
 *                         IV 量测流程（属测试顺控件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P2（BCD 设定导出，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 域闸 + 常量移位 + 超时 TON + 单拍脉冲两段式 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ TON/R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 2 · 序号 10）
 *==============================================================================*)

TYPE E_DL_IbeState :
(
    eIdle    := 0,    // 待机相（可接受导出请求） / Idle, ready for an export request
    eWaitRead:= 10,   // 等回读相（握手窗口内） / Waiting for the read-back
    eFault   := 90    // 故障相（等复位） / Fault, awaiting reset
);
END_TYPE

TYPE E_DL_IbeCause :
(
    eNone       := 0,   // 无异常 / No anomaly
    eRangeBad   := 1,   // 设定值越 0..9999（信息级，拒导出） / Set point out of 0..9999, info level
    eRbMismatch := 2,   // 回读不一致（锁存，故障级） / Read-back mismatch, latched, fault level
    eRbTimeout  := 3,   // 回读超时（锁存，故障级） / Read-back timeout, latched, fault level
    eCfgIllegal := 4,   // 组态非法（超时非正） / Illegal configuration, non-positive timeout
    ePhaseBad   := 5    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_IvBcdExport
VAR_INPUT
    iSetValue     : INT := 0;              // 设定值，域 0..9999 [-] / Set point, domain 0..9999
    bExport       : BOOL := FALSE;         // 导出请求沿 [-] / Export request edge
    bReadbackValid: BOOL := FALSE;         // 回读有效（当拍电平） [-] / Read-back valid, level
    iReadbackBcd  : INT := 0;              // 回读 BCD 字（按整值比对） [BCD] / Read-back BCD word, compared as a whole
    tReadbackTo   : TIME := T#2S;          // 回读超时，域 > T#0S [ms] / Read-back timeout, > T#0S
    bReset        : BOOL := FALSE;         // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    uBcdPacked  : WORD := 16#0000;                       // 打包 BCD 字（千/百/十/个） [BCD] / Packed BCD word
    abDigits    : ARRAY[1..4] OF BYTE;                   // 四位十进制数字（1=个,2=十,3=百,4=千） [-] / Four decimal digits
    bExported   : BOOL := FALSE;                         // 导出脉冲（单拍） [-] / Export pulse, single scan
    bReadbackOk : BOOL := FALSE;                         // 回读一致脉冲（单拍） [-] / Read-back match pulse, single scan
    bRbFailed   : BOOL := FALSE;                         // 回读失败锁存（等复位） [-] / Read-back failure, latched
    eState      : E_DL_IbeState := E_DL_IbeState.eIdle;  // 相出口 [-] / Phase outlet
    eCause      : E_DL_IbeCause := E_DL_IbeCause.eNone;  // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError      : BOOL := FALSE;                         // 故障标志（仅故障级成因） [-] / Error flag, fault level only
END_VAR
VAR
    _eState   : E_DL_IbeState := E_DL_IbeState.eIdle;    // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_IbeCause := E_DL_IbeCause.eNone;    // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                           // 故障锁存位 / Latched fault bit
    _bRbFail  : BOOL := FALSE;                           // 回读失败锁存位 / Latched read-back failure
    _iWork    : INT := 0;                                // 十进制拆分工作值 [-] / Decimal split working value
    _uBcd     : WORD := 16#0000;                         // 打包工作值 [BCD] / Packing working value
    _iRbExp   : INT := 0;                                // 期望回读值（导出时的 BCD 整值） [BCD] / Expected read-back value
    _bExported: BOOL := FALSE;                           // 导出脉冲内部位（单拍） / Internal export pulse
    _bRbOk    : BOOL := FALSE;                           // 回读成功内部位（单拍） / Internal read-back OK pulse
    _bCfgBad  : BOOL := FALSE;                           // 组态非法当拍量 / Illegal configuration this scan
    tonRb     : TON;                                     // 回读超时实例，段 0 无条件调用 / Read-back timeout instance
    rtExport  : R_TRIG;                                  // 导出沿实例，段 0 无条件调用 / Export edge instance
    rtReset   : R_TRIG;                                  // 复位沿实例，段 0 无条件调用 / Reset edge instance
END_VAR
VAR CONSTANT
    DL_IBE_MAX  : INT := 9999;            // 设定值上限（四位十进制） [-] / Set-point upper bound
    DL_IBE_SH0  : WORD := 16#0000;        // 个位打包基准（占位常量，便于口径统一） [BCD] / Units packing base
    DL_IBE_SH4  : INT := 4;               // 十位左移量（恒 < 16，R48） [bit] / Tens shift, always below 16 bits
    DL_IBE_SH8  : INT := 8;               // 百位左移量（恒 < 16，R48） [bit] / Hundreds shift
    DL_IBE_SH12 : INT := 12;              // 千位左移量（恒 < 16，R48） [bit] / Thousands shift
    DL_IBE_MSK  : WORD := 16#000F;        // 半字节掩码（非事件码，头注释声明） [bit] / Nibble mask, not an event code
END_VAR

(* —— 段 0：组态闸 + TON 与两沿无条件周期刷新（R228A；IN 串故障否决，R252） —— *)
_bCfgBad := (tReadbackTo <= T#0S);                             // 回读超时须为正 / Timeout must be positive
rtExport(CLK := bExport);                                      // 导出沿 / Export edge
rtReset(CLK := bReset);                                        // 复位沿 / Reset edge
tonRb(IN := (_eState = E_DL_IbeState.eWaitRead) AND (NOT _bFault), PT := tReadbackTo);   // 回读超时（等回读相派生） / Read-back timeout

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bRbFail/_iRbExp 不入清单，R107） —— *)
_bExported := FALSE;                                           // 导出脉冲预清 / Export pulse preset
_bRbOk     := FALSE;                                           // 回读成功脉冲预清 / Read-back OK pulse preset
bError     := FALSE;                                           // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：组态闸（非法即锁存故障级） —— *)
IF _bCfgBad THEN
    _eCause := E_DL_IbeCause.eCfgIllegal;                       // 归因：组态非法 / Cause: illegal configuration
    _bFault := TRUE;                                            // 锁存 / Latch
    _eState := E_DL_IbeState.eFault;                            // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿：清故障与回读失败锁存，R228B） —— *)
IF rtReset.Q THEN
    _bFault  := FALSE;                                          // 清故障锁存 / Clear fault latch
    _bRbFail := FALSE;                                          // 清回读失败锁存 / Clear read-back failure latch
    _eCause  := E_DL_IbeCause.eNone;                            // 清成因 / Clear cause
    _eState  := E_DL_IbeState.eIdle;                            // 回待机相 / Back to idle
END_IF

(* —— 段 4：相迁移（导出 / 回读握手闭环） —— *)
IF (NOT _bFault) AND (NOT _bCfgBad) THEN
    CASE _eState OF

    E_DL_IbeState.eIdle:
        IF rtExport.Q THEN
            IF (iSetValue < 0) OR (iSetValue > DL_IBE_MAX) THEN
                _eCause := E_DL_IbeCause.eRangeBad;              // 域闸：越域拒导出（信息级，不锁存） / Out of range, info level
            ELSE
                (* 十进制拆分（每位恒 0..9，半字节合法由构造保证） *)
                _iWork := iSetValue;                             // 取设定值 / Take the set point
                abDigits[1] := INT_TO_BYTE(_iWork MOD 10);       // 个位 / Units
                _iWork := _iWork / 10;                           // 去掉个位 / Drop the units digit
                abDigits[2] := INT_TO_BYTE(_iWork MOD 10);       // 十位 / Tens
                _iWork := _iWork / 10;                           // 去掉十位 / Drop the tens digit
                abDigits[3] := INT_TO_BYTE(_iWork MOD 10);       // 百位 / Hundreds
                _iWork := _iWork / 10;                           // 去掉百位 / Drop the hundreds digit
                abDigits[4] := INT_TO_BYTE(_iWork MOD 10);       // 千位 / Thousands

                (* 打包 BCD：移位量为常量，跨平台安全（R48/R295） *)
                _uBcd := SHL(BYTE_TO_WORD(abDigits[4]), DL_IBE_SH12)
                      OR SHL(BYTE_TO_WORD(abDigits[3]), DL_IBE_SH8)
                      OR SHL(BYTE_TO_WORD(abDigits[2]), DL_IBE_SH4)
                      OR (BYTE_TO_WORD(abDigits[1]) AND DL_IBE_MSK);
                uBcdPacked := _uBcd;                             // 打包字出口 / Packed word outlet
                _iRbExp := WORD_TO_INT(_uBcd);                   // 期望回读值（整值比对） / Expected read-back
                _bExported := TRUE;                              // 导出脉冲（内部位，段 7 映射） / Internal export pulse
                _eState := E_DL_IbeState.eWaitRead;              // 进等回读相 / Enter the wait-read phase
            END_IF
        END_IF

    E_DL_IbeState.eWaitRead:
        IF bReadbackValid THEN
            IF iReadbackBcd = _iRbExp THEN
                _bRbOk := TRUE;                                  // 回读一致（内部位） / Read-back matches
                _eState := E_DL_IbeState.eIdle;                  // 回待机相 / Back to idle
            ELSE
                _bRbFail := TRUE;                                // 回读不一致：锁存 / Mismatch: latch
                _bFault  := TRUE;                                // 故障锁存 / Latch the fault
                _eCause  := E_DL_IbeCause.eRbMismatch;           // 归因：回读不一致 / Cause: read-back mismatch
                _eState  := E_DL_IbeState.eFault;                // 入故障相 / Enter fault phase
            END_IF
        ELSIF tonRb.Q THEN
            _bRbFail := TRUE;                                    // 回读超时：锁存 / Timeout: latch
            _bFault  := TRUE;                                    // 故障锁存 / Latch the fault
            _eCause  := E_DL_IbeCause.eRbTimeout;                // 归因：回读超时 / Cause: read-back timeout
            _eState  := E_DL_IbeState.eFault;                    // 入故障相 / Enter fault phase
        END_IF

    E_DL_IbeState.eFault:
        ;                                                        // 故障相：仅等复位沿 / Wait for the reset edge only

    ELSE
        _eCause := E_DL_IbeCause.ePhaseBad;                      // 归因：非法相位 / Cause: illegal phase
        _bFault := TRUE;                                         // 锁存 / Latch
        _eState := E_DL_IbeState.eFault;                         // 强拉故障相 / Force fault phase

    END_CASE
END_IF

(* —— 段 5：出口单点映射（名实双出口，R191） —— *)
bExported   := _bExported;                                       // 导出脉冲出口 / Export pulse outlet
bReadbackOk := _bRbOk;                                           // 回读成功脉冲出口 / Read-back OK outlet
bRbFailed   := _bRbFail;                                         // 回读失败出口 / Read-back failure outlet
eState      := _eState;                                          // 相出口 / Phase outlet
eCause      := _eCause;                                          // 成因出口 / Cause outlet
bError      := _bFault;                                          // 故障标志 / Error flag

END_FUNCTION_BLOCK
