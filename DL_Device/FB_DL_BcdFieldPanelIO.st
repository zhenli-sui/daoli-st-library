(*
  FB_DL_BcdFieldPanelIO  —  面板 BCD 拨码阵列采集/输出 / BCD thumbwheel field panel IO assembly
  分类 Category : DL_Device
  码位 Code     : 16#03_2_17
  段位说明      : 03_2 段低半字节 00~0F 已满（05 为历史空穴留存），R38 已进位 12/13 段，
                  本轮续用 1x 段，本件启用 17 格（R192）
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-converter — BCD 转换族的设备级阵列组装待挖项
  溯源 Origin   : clean-room 实现，未复制任何源码行
                  （与 FC_DL_BcdToWord / FC_DL_WordToBcd 分工：那两件是单路原子，本件是设备级阵列 IO 组装）
  功能 Function : 1) 4 位十进制拨码（16 位输入阵列）逐位消抖（FB_DL_SignalDebounce ×16）；
                  2) 消抖后按 4 bit/位组装 BCD 字 → FC_DL_BcdToWord 逐位解码 → 设定值 uSetValue；
                  3) 位码非法（半字节 > 9）持续 tInvalidTo → 故障级锁存（接线/拨码故障），bReset 解除；
                  4) 稳定值变化沿 bNewValue 单拍脉冲（内部锁存 + 单拍收口，禁同拍抹除）；
                  5) 输出路径：uDisplayVal 经 FC_DL_WordToBcd 回 BCD 字供面板灯显。
  边界 Boundary : ① 16 只消抖实例在主体首部 FOR 循环内无条件刷新（每拍必调，等效无条件域）；
                  ② 位序约定：abDigBits 下标 0 = 个位 BCD bit0，下标 4k..4k+3 = 第 k 位十进制位；
                  ③ tDebounce = T#0S 时消抖直通（消抖件原生语义，透传不钳制）；
                  ④ 组态域闸：tInvalidTo 非正按 1s 兜底（防非法组态令故障永不锁存）；
                  ⑤ 无状态机 CASE 主相（采集型 FB）：故障经锁存位承载，无跨相 TON 复用问题。
  依赖 Depends  : FB_DL_SignalDebounce（实例化 ×16）/ FC_DL_BcdToWord / FC_DL_WordToBcd（函数调用）
  码表 Error codes（本件格 03_2_17，子码步进 +0x100）:
    16#0003_0117 信息级：稳定设定值变化沿已捕获（bNewValue 拍）
    16#0003_0217 故障级：位码非法持续超 tInvalidTo（半字节 > 9，接线/拨码故障），锁存至复位
    16#0003_0317 信息级：回显 BCD 编码饱和（uDisplayVal > 9999，WordToBcd 溢出口径透传）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 2 · 序号 9）
*)

FUNCTION_BLOCK FB_DL_BcdFieldPanelIO
VAR_INPUT
    abDigBits  : ARRAY[0..15] OF BOOL;    // 拨码原始位输入阵列，下标 0 = 个位 bit0 / Raw digit bit inputs, index 0 = units bit0
    tDebounce  : TIME := T#20MS;          // 逐位消抖延时 [ms]，T#0S = 直通 / Per-bit debounce delay
    tInvalidTo : TIME := T#1S;            // 位码非法持续判据 [ms]，域 > 0（非法组态按 1s 兜底）/ Invalid-code persistence time
    uDisplayVal: UINT := 0;               // 面板回显十进制值 [0..9999]，越限走饱和路径 / Display value for the panel echo
    bReset     : BOOL := FALSE;           // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    uSetValue  : UINT;                    // 稳定设定值 [0..9999]（逐位解码合成）/ Stable setpoint value
    bSetValid  : BOOL;                    // 设定值有效（无非法半字节）/ Setpoint validity flag
    anDigVal   : ARRAY[0..3] OF UINT;     // 逐位十进制值 [0..9]（故障位为垃圾值，以 bSetValid 为准）/ Per-digit decimal values
    uBcdEcho   : WORD;                    // 回显 BCD 码字（每半字节一位十进制）/ Echo BCD word for panel lamps
    bNewValue  : BOOL;                    // 稳定设定值变化沿，单拍脉冲 [-] / Stable value change edge, single-cycle pulse
    bError     : BOOL;                    // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch, cleared by reset
    uErrorId   : UDINT;                   // 事件码，0 = 无事件（故障级锁存回放）/ Event code, fault codes latched
END_VAR
VAR
    afbDeb     : ARRAY[0..15] OF FB_DL_SignalDebounce;  // 逐位消抖实例阵列，主体首部无条件刷新 / Per-bit debounce instances
    tonInvalid : TON;                     // 位码非法持续计时（单用途，无跨相复用）/ Invalid-code persistence timer
    rtReset    : R_TRIG;                  // 复位上升沿 / Reset rising edge
    i0         : INT;                     // 位遍历索引 [0..15]，移位量同域严格非负 / Bit loop index, also the shift amount
    _uStable   : WORD;                    // 消抖后稳定 BCD 字 / Debounced stable BCD word
    _uStablePrv: WORD;                    // 上拍稳定 BCD 字（变化沿基准）/ Previous stable BCD word, edge basis
    _bNibBad   : BOOL;                    // 本拍存在非法半字节 / Invalid nibble present this cycle
    _bInit     : BOOL := FALSE;           // 首扫标志，初值 FALSE，判据 NOT bInit（R19 范式）/ First-scan flag
    _bNewLatch : BOOL;                    // 变化沿内部锁存（单拍收口源）/ Change-edge internal latch
    _uEchoErr  : UDINT;                   // WordToBcd 回显错误码透传 / WordToBcd echo error passthrough
    _uDigErr0  : UDINT;                   // 个位 BcdToWord 错误码透传 / Units-digit decode error passthrough
    _uDigErr1  : UDINT;                   // 十位 BcdToWord 错误码透传 / Tens-digit decode error passthrough
    _uDigErr2  : UDINT;                   // 百位 BcdToWord 错误码透传 / Hundreds-digit decode error passthrough
    _uDigErr3  : UDINT;                   // 千位 BcdToWord 错误码透传 / Thousands-digit decode error passthrough
    _uInfo     : UDINT;                   // 本拍信息码，每拍重算 / Transient info code this cycle
    _uFault    : UDINT;                   // 故障码锁存寄存 / Latched fault code register
    _bFault    : BOOL;                    // 故障锁存位 / Latched fault bit
END_VAR
VAR CONSTANT
    DL_BFP_DIG_MASK : WORD := 16#000F;    // 半字节提取掩码（低 4 位）/ Nibble extraction mask
    DL_BFP_INVALID_TO_FBK : TIME := T#1S; // 非法持续判据兜底值 [ms] / Persistence-time fallback value
END_VAR

(* —— 段 0：定时器与边沿实例无条件周期刷新（R7 红线；消抖阵列在 FOR 内每拍全量刷新） —— *)
rtReset(CLK := bReset);                                         // 复位沿刷新，每拍必调
FOR i0 := 0 TO 15 DO                                            // 消抖阵列每拍全量刷新（等效无条件域）
    afbDeb[i0](bRawInput := abDigBits[i0],                      // 原始位输入
               tRiseDelay := tDebounce,                         // 上升确认延时（组态透传）
               tFallDelay := tDebounce,                         // 下降确认延时（组态透传）
               bEnable := TRUE);                                // 消抖恒使能
END_FOR
tonInvalid(IN := _bNibBad, PT := MAX(tInvalidTo, DL_BFP_INVALID_TO_FBK));   // 非法持续计时（单用途，组态兜底）

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_bNewLatch/_uStablePrv 不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bNibBad := FALSE;                  // 非法半字节标志预清零
_bNewLatch := FALSE;                // 变化沿锁存预清零（组装段单点置位）
bNewValue := FALSE;                 // 变化沿出口单拍（统一出口映射）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：稳定 BCD 字组装（消抖后位 → 半字节拼接；移位量 = 下标，0..15 严格域内） —— *)
FOR i0 := 0 TO 15 DO
    IF afbDeb[i0].bStable THEN
        _uStable := _uStable OR SHL(WORD#1, i0);    // 置位（移位量归一：下标即移位量，非负）
    ELSE
        _uStable := _uStable AND NOT SHL(WORD#1, i0);   // 清位（移位量同域）
    END_IF
END_FOR

(* —— 段 3：首扫初始化（R19 唯一合法范式） —— *)
IF NOT _bInit THEN
    _uStablePrv := _uStable;        // 首扫：变化沿基准同步为当前稳定字
    _bInit := TRUE;
END_IF

(* —— 段 4：逐位 BCD 解码（FC_DL_BcdToWord 原子 ×4；非法半字节聚合） —— *)
FC_DL_BcdToWord(uBcd := _uStable AND 16#000F, uErrorId => _uDigErr0);   // 个位解码
FC_DL_BcdToWord(uBcd := SHR(_uStable, 4) AND 16#000F, uErrorId => _uDigErr1);   // 十位解码（SHR 正向移位，量归一）
FC_DL_BcdToWord(uBcd := SHR(_uStable, 8) AND 16#000F, uErrorId => _uDigErr2);   // 百位解码
FC_DL_BcdToWord(uBcd := SHR(_uStable, 12) AND 16#000F, uErrorId => _uDigErr3);  // 千位解码
IF (_uDigErr0 <> 0) OR (_uDigErr1 <> 0) OR (_uDigErr2 <> 0) OR (_uDigErr3 <> 0) THEN
    _bNibBad := TRUE;               // 本拍存在非法半字节（任一位 > 9）
END_IF
anDigVal[0] := FC_DL_BcdToWord(uBcd := _uStable AND 16#000F);           // 个位值（错误路径返回 0，安全侧）
anDigVal[1] := FC_DL_BcdToWord(uBcd := SHR(_uStable, 4) AND 16#000F);   // 十位值
anDigVal[2] := FC_DL_BcdToWord(uBcd := SHR(_uStable, 8) AND 16#000F);   // 百位值
anDigVal[3] := FC_DL_BcdToWord(uBcd := SHR(_uStable, 12) AND 16#000F);  // 千位值
uSetValue := anDigVal[0] + anDigVal[1] * 10 + anDigVal[2] * 100 + anDigVal[3] * 1000;   // 十进制合成

(* —— 段 5：故障锁存（非法持续到点才锁存，瞬时切换不误报） —— *)
IF tonInvalid.Q THEN
    _uFault := 16#0003_0217;        // 故障级：位码非法持续超限
    _bFault := TRUE;
END_IF
IF rtReset.Q THEN
    _bFault := FALSE;               // 清故障锁存位（唯一解除路径：bReset 上升沿）
    _uFault := 16#0000_0000;
END_IF

(* —— 段 6：有效性出口与变化沿（内部锁存 → 统一出口单拍，两段式收口） —— *)
bSetValid := NOT _bNibBad;          // 有效性 = 本拍无非法半字节（瞬时口径）
IF (NOT _bNibBad) AND (_uStable <> _uStablePrv) THEN
    _bNewLatch := TRUE;             // 稳定字变化：内部锁存置位（段 1 已预清零，同拍不抹）
    _uInfo := 16#0003_0117;         // 信息级：变化沿已捕获
END_IF
_uStablePrv := _uStable;            // 变化沿基准更新（段尾单点）
bNewValue := _bNewLatch;            // 出口 = 内部锁存（置位同拍不被抹）

(* —— 段 7：回显 BCD 编码（FC_DL_WordToBcd 原子，越限饱和码透传） —— *)
uBcdEcho := FC_DL_WordToBcd(uVal := uDisplayVal, uErrorId => _uEchoErr);
IF _uEchoErr <> 0 THEN
    _uInfo := 16#0003_0317;         // 信息级：回显饱和（覆盖变化沿码，回显状态优先）
END_IF

(* —— 段 8：事件码单点回放（故障锁存优先） —— *)
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
