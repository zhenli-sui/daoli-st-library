(*
  FB_DL_CassetteMapVerify  —  花篮片位映射比对校验（Mapping 序列解析 + 错片定位） / Cassette slot-map verify with first-error slot location
  分类 Category : DL_Process
  版本 Version  : 1.0.1
  兼容性 Platform: CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert（仅 Standard.library）
  来源 Source   : roadmap-semi-p2 — 半导体花篮 Mapping 缺口件（与 WaferCassetteSlot 槽位监视分工：那件管槽位实时态，本件管映射比对校验）
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 8 槽映射比对：bVerifyCmd 沿承载，wErrMap := wExpMap XOR
                  wActMap（异或位图逐槽比对），wErrMap = 16#0000 → 校验通过
                  （信息级 04B9）；非零 → 0391 映射失配锁存 + 首错槽位定位
                  （nFirstErrSlot 取最低错位槽号，信息级 04BB）；
                  2) 组态闸：wExpMap = 16#0000（空花篮无校验意义）→ 0392 锁存；
                  3) 相位机：eIdle → eDone（比对完成稳态）→ eFault；错片定位
                  只在失配沿承载一次，锁存期不重扫（禁按当下输入重推断）；
                  4) 信息级三码：校验通过 / 失配检出 / 首错定位（沿置位，复位沿
                  清除——v1.0.1 按信息码复位沿清除范式收敛，原单拍沿改锁存）；
                  5) 解除式全当拍量（R240 落地），逐 BOOL 标注见段 4。
  边界 Boundary : ① 槽位掩码 SHL(WORD#1, 0..7)，移位量域 < 16 结构性安全（R48）；
                  ② wActMap 信任来源为槽位传感器组态（头注释声明信任边界）；
                  ③ 失配锁存码由锁存回放，不随后续 wActMap 漂移（R152 回放纪律）；
                  ④ 零全局耦合：无全局变量表依赖、无外部变量声明、无物理 IO 地址。
  依赖 Depends  : Standard.library（R_TRIG）
  码表 Error codes（Process 段 0005，窗口 0391~0393 / 04B9~04BB）:
    16#0005_0391 故障级：映射失配锁存（首错槽号入 nFirstErrSlot），锁存至 bReset
    16#0005_0392 故障级：组态非法（期望图 16#0000 空花篮无效），锁存至 bReset
    16#0005_0393 故障级：相位落 ELSE 兜底，锁存至 bReset
    16#0005_04B9 信息级：校验通过（沿置位，复位沿清除）
    16#0005_04BA 信息级：失配检出（沿置位，复位沿清除）
    16#0005_04BB 信息级：首错槽位定位（nFirstErrSlot 写定拍置位，复位沿清除）
  修订历史 Revision :
    2026-11-19  v1.0.0  R42 首版（批次 3 · 序号 2）
    2026-11-19  v1.0.1  R44 P0 返修（R43 挂账 3 条）：①信息码复位沿清除范式——
                        原实现 _uInfo 每拍重算致 04B9/04BA/04BB 单拍即逝且 HMI 不可
                        采样，借用 FB_DL_DeviceParamVerify v1.0.1 修法改为锁存至
                        bReset 上升沿清除（段 1 预清零撤销、两处解除沿补清）；
                        ②锁存解除式可达自证复核——rtReset.Q 输入引脚当拍量恒可达，
                        维持原解除式不动；③R228A 补查——rtVerify/rtReset 段 0 无条件
                        刷新在位、本件无 TON 实例，补查通过零改动；无关逻辑零改动。
*)

TYPE E_DL_CmvState :
(
    eIdle   := 0,    // 空闲：等校验指令 / Idle, waiting verify command
    eDone   := 10,   // 完成：比对稳态（通过） / Done, verified steady
    eFault  := 90    // 故障：失配或组态锁定 / Fault, latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_CassetteMapVerify
VAR_INPUT
    wExpMap      : WORD := 16#00FF;   // 期望映射位图，位 n = 槽 n 有片 [-] / Expected slot map bitmap
    wActMap      : WORD := 16#00FF;   // 实际映射位图（槽位传感器组态）[-] / Actual slot map bitmap
    bVerifyCmd   : BOOL := FALSE;     // 校验指令，上升沿承载比对 [-] / Verify command edge
    bReset       : BOOL := FALSE;     // 复位，上升沿清故障锁存 / Reset edge clears fault latch
END_VAR
VAR_OUTPUT
    eState       : E_DL_CmvState;     // 状态出口，段尾单点映射 / State outlet
    wErrMap      : WORD;              // 失配位图镜像（异或结果，锁存快照）/ Mismatch bitmap snapshot
    nFirstErrSlot: DINT;              // 首错槽号 [0..7]，-1 = 无首错 / First error slot index
    bMatch       : BOOL;              // 比对通过标志（eDone 相电平）[-] / Match flag
    bError       : BOOL;              // 故障锁存标志 / Fault latch flag
    nErrId       : UDINT;             // 事件码，0 = 无事件 / Event code
END_VAR
VAR
    rtVerify     : R_TRIG;            // 校验指令沿实例，无条件刷新 / Verify edge instance
    rtReset      : R_TRIG;            // 复位沿实例，无条件刷新 / Reset edge instance
    _eState      : E_DL_CmvState := E_DL_CmvState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _nIdx        : DINT;              // 阵列循环索引 [-] / Array loop index
    _bFirstFound : BOOL;              // 首错槽已定位标志（锁存量）/ First-error located flag
    _bFault      : BOOL;              // 故障锁存位（锁存量）/ Latched fault bit
    _uFault      : UDINT;             // 故障码锁存（锁存量）/ Latched fault code
    _uInfo       : UDINT;             // 信息码锁存（沿置位，复位沿清除） / Latched info code
END_VAR

(* —— 段 0：沿实例无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtVerify(CLK := bVerifyCmd);         // 校验沿（每拍必调）
rtReset(CLK := bReset);              // 复位沿（每拍必调）

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_bFirstFound/_uInfo/wErrMap 不入清单，
     禁同拍抹除；信息码 v1.0.1 起为锁存量，仅复位沿清除） —— *)
bMatch := FALSE;                    // 通过标志缺省 FALSE
nErrId := 16#0000_0000;             // 事件码缺省无事件

(* —— 段 2：复位沿 + 组态域闸（判据当拍量） —— *)
IF rtReset.Q THEN                   // rtReset.Q = 当拍量
    _bFault := FALSE;               // 清故障锁存位
    _uFault := 16#0000_0000;        // 清故障锁存码
    _uInfo := 16#0000_0000;         // 清信息码锁存（v1.0.1：信息码复位沿清除范式）
    _bFirstFound := FALSE;          // 首错定位标志清零
    nFirstErrSlot := -1;            // 首错槽号恢复哨兵
    wErrMap := 16#0000;             // 失配位图清零
END_IF
IF wExpMap = 16#0000 THEN           // 期望图域闸（空花篮无效，WORD 判等合规）
    _uFault := 16#0005_0392;        // 故障级：组态非法
    _bFault := TRUE;                // 故障标志与码位配对（R45）
END_IF

(* —— 段 3：校验沿承载比对（判据当拍量沿；失配沿单次定位，锁存期不重扫） —— *)
IF rtVerify.Q AND (NOT _bFault) THEN
    wErrMap := wExpMap XOR wActMap; // 异或位图比对（16 位掩码域结构性安全）
    IF wErrMap = 16#0000 THEN
        _uInfo := 16#0005_04B9;     // 信息级：校验通过沿
        _eState := E_DL_CmvState.eDone;     // 进完成稳态相
    ELSE
        _uInfo := 16#0005_04BA;     // 信息级：失配检出沿
        FOR _nIdx := 0 TO 7 DO      // 首错槽定位（自低向高首个错位）
            IF (NOT _bFirstFound) AND ((wErrMap AND SHL(WORD#1, UINT(_nIdx))) <> WORD#0) THEN
                nFirstErrSlot := _nIdx;             // 首错槽号写定（锁存量，仅此处写）
                _bFirstFound := TRUE;               // 定位标志
                _uInfo := 16#0005_04BB;             // 信息级：首错定位沿（覆盖失配沿，后到优先声明）
            END_IF
        END_FOR
        _uFault := 16#0005_0391;    // 故障级：映射失配锁存
        _bFault := TRUE;
        _eState := E_DL_CmvState.eFault;    // 进故障相
    END_IF
END_IF

(* —— 段 4：故障解除式（R240 落地，逐 BOOL 标注）：
     rtReset.Q = 当拍量；NOT bVerifyCmd = 当拍量；wExpMap ≠ 0 为保持量（组态），
     组态修正后配合复位沿当拍量解除，可达。 —— *)
IF rtReset.Q AND (NOT bVerifyCmd) THEN
    _bFault := FALSE;               // 清故障锁存位（锁存量，仅此当拍量解除沿可清）
    _uFault := 16#0000_0000;        // 清故障锁存码（锁存量，仅本当拍量解除沿可清）
    _uInfo := 16#0000_0000;         // 清信息码锁存（v1.0.1：信息码复位沿清除范式）
    _bFirstFound := FALSE;          // 首错定位标志清零（锁存量）
    nFirstErrSlot := -1;            // 首错槽号恢复哨兵
    IF _eState = E_DL_CmvState.eFault THEN
        _eState := E_DL_CmvState.eIdle;     // 故障相迁出：回空闲
    END_IF
END_IF

(* —— 段 5：相位机（CASE 全覆盖 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_CmvState.eIdle:
    ;                               // 空闲：等校验沿（段 3 承载迁出）

E_DL_CmvState.eDone:
    bMatch := TRUE;                 // 通过标志（相电平）
    IF NOT bVerifyCmd THEN          // 校验指令撤销：回空闲（比对结果随相清除）
        _eState := E_DL_CmvState.eIdle;
    END_IF

E_DL_CmvState.eFault:
    ;                               // 故障相：失配锁存回放，等解除沿（段 4 承载迁出）

ELSE
    _uFault := 16#0005_0393;        // 故障级：非法相位兜底
    _bFault := TRUE;
    _eState := E_DL_CmvState.eFault;    // 强制回故障相

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
IF _bFault THEN
    nErrId := _uFault;              // 故障锁存码回放
    bMatch := FALSE;                // 故障相通过出口强制 FALSE（安全侧）
ELSE
    nErrId := _uInfo;               // 信息码
END_IF
bError := _bFault;                  // 故障标志与锁存位同源
eState := _eState;                  // 状态出口单点映射

END_FUNCTION_BLOCK
