(*
  FB_DL_WaferCountPreset  —  晶圆计数预置饱和（预置计满 + 花篮位模计数） / Wafer preset count with saturation and cassette-slot modulo counting
  分类 Category : DL_Process
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-counter — 计数族深化（与 WaferCountAxis/WaferCountYield 分工：那两件管计数轴/良率统计，本件管预置饱和与模计数）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 预置计数：bCntPulse 上升沿递增 uCount，达 uPreset 置 bPresetDone
                  并停计；计满后仍来沿 → 0380 溢出饱和锁存（防静默丢片）；
                  2) 花篮位模计数：bSlotPulse 沿按 uCassSlots 取模递增 uCassMod，
                  回零拍发信息级 04A8；模基数域闸 uCassSlots > 0；
                  3) 脉冲宽度监视：计数沿后高电平持续超 tMinPulse → 0381 锁存
                  （同拍重触发漏计风险，归因独立）；
                  4) 相位机：eIdle → eCount → eFull → eFault；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 组态闸：uPreset = 0 或 uCassSlots = 0 或 tMinPulse <= 0
                  → 037F 锁存，ELSE 兜底归并 037F（码表声明）；
                  ② 模计数用 MOD 内建，模基数 > 0 已由域闸保证，无除零路径；
                  ③ 计数沿 R_TRIG 与宽度监视 TON 均无条件周期刷新；
                  ④ 无 GVL 依赖：纯引脚输入输出，无外部变量引用，无物理 IO 地址。
  依赖 Depends  : Standard.library（TON / R_TRIG）
  码表 Error codes（Process 段 0005，窗口 037F~0381 / 04A7~04A9）:
    16#0005_037F 故障级：组态非法（预置/模基数/最小脉宽域非法）或相位落 ELSE 兜底（归并声明），锁存至 bReset
    16#0005_0380 故障级：预置计满后计数沿溢出锁存，锁存至 bReset
    16#0005_0381 故障级：计数脉冲宽度异常锁存（高电平持续超 tMinPulse），锁存至 bReset
    16#0005_04A7 信息级：预置计满沿（进 eFull）
    16#0005_04A8 信息级：花篮模计数回零沿
    16#0005_04A9 信息级：计数复位完成沿
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 2 · 序号 1）
*)

TYPE E_DL_WcpState :
(
    eIdle   := 0,    // 未使能：不计数 / Idle, not counting
    eCount  := 10,   // 计数中：沿递增 / Counting, edge increments
    eFull   := 20,   // 计满：预置达成停计 / Full, preset reached
    eFault  := 90    // 故障：溢出或脉宽锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_WaferCountPreset
VAR_INPUT
    bCntPulse    : BOOL := FALSE;     // 晶圆计数脉冲 [-] / Wafer count pulse
    bSlotPulse   : BOOL := FALSE;     // 花篮槽位脉冲 [-] / Cassette slot pulse
    uPreset      : UDINT := 25;       // 预置计数值 [片]，域 > 0 / Preset count value
    uCassSlots   : UDINT := 25;       // 花篮模计数基数 [槽]，域 > 0 / Cassette modulo base
    tMinPulse    : TIME := T#5MS;     // 最小合法脉宽 [ms]，域 > 0 / Minimum legal pulse width
    bCntEn       : BOOL := FALSE;     // 计数使能（电平）[-] / Count enable, level
    bCntRst      : BOOL := FALSE;     // 计数复位指令，上升沿清计数 [-] / Count reset command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_WcpState;     // 状态出口，段尾单点映射 / State outlet
    uCount       : UDINT;             // 晶圆计数 [片] / Wafer count
    bPresetDone  : BOOL;              // 预置达成标志（eFull 相电平）[-] / Preset-done flag
    uCassMod     : UDINT;             // 花篮模计数值 [槽] / Cassette modulo count
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    tonPulseW    : TON;               // 脉冲宽度监视（电平式），无条件刷新 / Pulse width watch timer
    rtCntPulse   : R_TRIG;            // 计数脉冲沿实例，无条件刷新 / Count pulse edge instance
    rtSlotPulse  : R_TRIG;            // 槽位脉冲沿实例，无条件刷新 / Slot pulse edge instance
    rtCntRst     : R_TRIG;            // 计数复位沿实例，无条件刷新 / Count reset edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_WcpState := E_DL_WcpState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码，每拍重算 / Transient info code
END_VAR

(* —— 段 0：定时器与沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtCntPulse(CLK := bCntPulse);                            // 计数脉冲沿（每拍必调）
rtSlotPulse(CLK := bSlotPulse);                          // 槽位脉冲沿（每拍必调）
rtCntRst(CLK := bCntRst);                                // 计数复位沿（每拍必调）
rtReset(CLK := bReset);                                  // 复位沿（每拍必调）
tonPulseW(IN := bCntPulse, PT := tMinPulse);             // 脉宽监视（电平式，脉冲撤销自动断 IN）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault 不入清单，禁同拍抹除） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
bPresetDone := FALSE;               // 预置达成标志缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸 + 计数复位（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
END_IF
IF (uPreset = 0) OR (uCassSlots = 0) OR (TIME_TO_DINT(tMinPulse) <= 0) THEN
    _uFault := 16#0005_037F;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF
IF rtCntRst.Q THEN                  // 计数复位沿（当拍量）
    uCount := 16#0000_0000;         // 计数清零
    uCassMod := 16#0000_0000;       // 模计数清零
    _uInfo := 16#0005_04A9;         // 信息级：计数复位完成沿
END_IF

(* —— 段 3：溢出与脉宽锁存（判据当拍量/电平式窗） —— *)
IF (NOT _bFault) AND tonPulseW.Q THEN
    _uFault := 16#0005_0381;        // 故障级：脉宽异常（同拍重触发漏计风险）
    _bFault := TRUE;
END_IF
IF (NOT _bFault) AND (_eState = E_DL_WcpState.eFull) AND rtCntPulse.Q THEN
    _uFault := 16#0005_0380;        // 故障级：计满后计数沿溢出
    _bFault := TRUE;
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bCntPulse = 当拍量；NOT bCntEn = 当拍量。
     均不含锁存量（_bFault/_uFault），解除边真实可达（脉冲撤销 + 撤使能 + 复位沿）。 —— *)
IF rtReset.Q AND (NOT bCntPulse) AND (NOT bCntEn) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    IF _eState = E_DL_WcpState.eFault THEN
        _eState := E_DL_WcpState.eIdle;     // 故障相迁出：回未使能
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_WcpState.eIdle:
    IF bCntEn AND (NOT _bFault) THEN
        _eState := E_DL_WcpState.eCount;    // 使能：进计数相
    END_IF

E_DL_WcpState.eCount:
    IF rtCntPulse.Q THEN                    // 计数沿（当拍量）
        IF uCount < uPreset THEN
            uCount := uCount + 1;           // 计数递增（先比后加，防跨预置）
        END_IF
        IF uCount >= uPreset THEN
            _uInfo := 16#0005_04A7;         // 信息级：预置计满沿
            _eState := E_DL_WcpState.eFull; // 进计满相
        END_IF
    END_IF

E_DL_WcpState.eFull:
    bPresetDone := TRUE;                    // 预置达成标志（相电平）
    IF rtCntPulse.Q THEN
        _uFault := 16#0005_0380;            // 故障级：计满后溢出（段 3 同判据冗余收敛，单点归因）
        _bFault := TRUE;
    END_IF
    IF NOT bCntEn THEN
        _eState := E_DL_WcpState.eIdle;     // 撤使能：回未使能相
    END_IF

E_DL_WcpState.eFault:
    ;                                       // 故障相：等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_037F;                // 故障级：非法相位兜底（归并组态码，码表声明）
    _bFault := TRUE;
    _eState := E_DL_WcpState.eFault;        // 强制回故障相

END_CASE

(* —— 段 5b：花篮模计数（独立于相位机；模回零沿当拍检出） —— *)
IF (_eState = E_DL_WcpState.eCount) AND rtSlotPulse.Q THEN
    uCassMod := (uCassMod + 1) MOD uCassSlots;  // 模计数（模基数域闸 > 0，无除零）
    IF uCassMod = 0 THEN                        // 回零拍（模运算整型判等合规）
        _uInfo := 16#0005_04A8;                 // 信息级：花篮模回零沿
    END_IF
END_IF

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bPresetDone := FALSE;           // 故障相预置达成出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
