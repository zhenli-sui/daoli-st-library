(*==============================================================================
 * 组件名称 (Component)  : FB_DL_WaferCassetteSlot
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : 花篮 25 槽占用双向计数与满/空判据。进片沿 +1、出片沿 −1，同拍
 *                         双沿按「物理不可能，必是抖动或逻辑错」双丢弃并报码；两个沿的净
 *                         额一次性施加，占用计数只有一处写入点；占用为 0 时的出片不借位到
 *                         25（借位会把满篮误判为空篮），锁存计数矛盾；位图按先低槽后高槽
 *                         顺序填充（顺序装片假设），出片清最低置位位。不做槽位光学检测、
 *                         不做花篮身份识别。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_CassetteState / FUNCTION_BLOCK FB_DL_WaferCassetteSlot
 * 依赖 (Depends)        : 无（仅 Standard.library 的 SHL / SHR 与位运算）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         槽数钳位 1~25 且写位图前判槽号 ｜ 占用计数单点写入（净额合并）
 *                         双沿沿实例无条件周期刷新 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底
 * 错误码表 (Codes)      : 16#0003_03B6 就绪（计数正常，含满/空稳态）
 *                         16#0003_03B7 故障级 清空请求在使能期被拒（清空须先失能）
 *                         16#0003_03B8 信息级 槽数 >25 已钳制（不置故障级标志）
 *                         16#0003_03B9 故障级 同拍进出双沿或满篮进片（请求双丢弃）
 *                         16#0003_03BA 故障级 空篮出片，锁存计数矛盾（不借位到 25）。
 *                                    本件 5 槽全用、无预留槽，已登记待裁定
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 3
 * 验收向量 (Acceptance) : 正向 25 槽连续进满 → 占用 25、bFull、位图 16#01FF_FFFF；再出
 *                         1 片 → 占用 24、bFull=FALSE、16#0003_03B6
 *                         反向 空篮出片 → bCounterMismatch、占用保持 0、16#0003_03BA；
 *                         同拍进出双沿 → 16#0003_03B9 且双丢弃；槽数给 30 → 钳 25 +
 *                         16#0003_03B8（信息级）；使能期清空请求 → 16#0003_03B7 且不清
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_CassetteState（归属本功能块，同文件发布，全库唯一定义）
 *----------------------------------------------------------------------------*)
TYPE E_DL_CassetteState :
(
    eEmpty := 0,    // 空篮：占用 0 / Empty cassette, no occupied slot
    ePart  := 10,   // 部分占用：0 < 占用 < 槽数 / Partially occupied
    eFull  := 20,   // 满篮：占用 = 槽数 / Full cassette
    eFault := 99    // 故障：计数矛盾锁存 / Fault, the counter contradiction is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_WaferCassetteSlot
VAR_INPUT
    bEnable      : BOOL := FALSE;         // 使能，FALSE 锁存位图（计数冻结） / Enable, FALSE freezes the slot map
    bLoadPulse   : BOOL := FALSE;         // 进片 +1，上升沿 / Load pulse, rising edge adds one
    bUnloadPulse : BOOL := FALSE;         // 出片 −1，上升沿 / Unload pulse, rising edge subtracts one
    bClear       : BOOL := FALSE;         // 清空（换花篮），须 bEnable=FALSE / Clear for a cassette change, requires bEnable FALSE
    uSlotCount   : UINT := 25;            // 槽数 [个]，域 1~25 / Slot count, domain 1 to 25
END_VAR
VAR_OUTPUT
    uOccupied    : UINT;                  // 占用槽数 [个] / Occupied slot count
    uEmptySlot   : UINT;                  // 空槽数 [个] / Empty slot count
    bFull        : BOOL;                  // 满篮判据 / Full criterion
    bEmpty       : BOOL;                  // 空篮判据 / Empty criterion
    uSlotMask    : DWORD;                 // 占用位图 bit0=第 1 槽 … bit24=第 25 槽 [bit]（25 位须 32 位容器，规格 WORD 无法表达） / Occupancy map, 25 bits need a 32-bit container
    bCounterMismatch : BOOL;              // 计数矛盾已锁存 / Counter contradiction latched
    eErr         : UDINT;                 // 错误码，段位 16#0003_xxxx / Error code in segment 16#0003_xxxx
END_VAR
VAR
    _eState      : E_DL_CassetteState := E_DL_CassetteState.eEmpty; // 占用状态 / Occupancy state
    _bInit       : BOOL := FALSE;         // 首扫标志，取非判定 / First-scan flag, tested negated
    _bMismatch   : BOOL := FALSE;         // 矛盾锁存状态量 / Contradiction latch state quantity
    _nNet        : INT;                   // 本拍净额（+进 −出） / Net delta of this scan
    _uSlotEff    : UINT := 25;            // 生效槽数（钳制后） / Effective slot count after clamping
    _uwOccupied  : UINT;                  // 占用内部唯一写点 / The single internal write point of the occupancy
    _rtrigLoad   : R_TRIG;                // 进片上升沿 / Rising edge of the load pulse
    _rtrigUnload : R_TRIG;                // 出片上升沿 / Rising edge of the unload pulse
END_VAR
VAR CONSTANT
    DL_CS_READY   : UDINT := 16#0003_03B6;  // 就绪码 / Ready code
    DL_CS_CLEAR_REJ : UDINT := 16#0003_03B7; // 故障级清空被拒码 / Fault code for a rejected clear request
    DL_CS_SLOT_CLAMP : UDINT := 16#0003_03B8; // 信息级槽数钳制码 / Info code for a clamped slot count
    DL_CS_BOTH    : UDINT := 16#0003_03B9;  // 故障级双沿或满篮进片码 / Fault code for double edges or a load on a full cassette
    DL_CS_UNDER   : UDINT := 16#0003_03BA;  // 故障级空篮出片码 / Fault code for an unload on an empty cassette
    DL_CS_SLOT_MAX : UINT := 25;            // 槽数上限 [个] / Slot count upper bound
    DL_CS_FULL_MASK : DWORD := 16#01FF_FFFF; // 25 槽满位图 [bit] / Full map of 25 slots
    DL_CS_BIT0      : DWORD := 16#0000_0001; // 位图零号位常量 [bit] / Bit zero constant of the map
END_VAR

// 段 1｜输出与单拍标志预置
eErr := 0;                                          // 错误码预清 / Error code pre-cleared
_nNet := 0;                                         // 净额预清 / Net delta pre-cleared

// 段 2｜双沿沿实例无条件周期刷新（R24：严禁置于分支内）
_rtrigLoad(CLK := bLoadPulse);                      // 进片沿 / Load edge
_rtrigUnload(CLK := bUnloadPulse);                  // 出片沿 / Unload edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _uwOccupied := 0;                               // 占用起点 0 [个] / Occupancy starts at zero
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜槽数钳制（>25 钳制并报信息级；<1 钳制到 1）
IF uSlotCount > DL_CS_SLOT_MAX THEN
    _uSlotEff := DL_CS_SLOT_MAX;                    // 槽数上限钳制 [个] / Slot count clamped to the upper bound
    eErr := DL_CS_SLOT_CLAMP;                       // 信息级：槽数已钳制 / Info, the slot count was clamped
ELSIF uSlotCount < 1 THEN
    _uSlotEff := 1;                                 // 槽数下限钳制 [个] / Slot count clamped to the lower bound
    eErr := DL_CS_SLOT_CLAMP;                       // 信息级：槽数已钳制 / Info, the slot count was clamped
ELSE
    _uSlotEff := uSlotCount;                        // 采用组态槽数 [个] / Use the configured slot count
END_IF

// 段 5｜清空请求（须失能；使能期请求被拒并报码）
IF bClear THEN
    IF bEnable THEN
        eErr := DL_CS_CLEAR_REJ;                    // 故障级：使能期清空被拒 / Fault, a clear request while enabled is rejected
    ELSE
        _uwOccupied := 0;                           // 清空占用 [个] / Occupancy cleared
        _bMismatch := FALSE;                        // 矛盾锁存解除 / Contradiction latch released
        _eState := E_DL_CassetteState.eEmpty;       // 状态回空篮 / State back to empty
    END_IF
END_IF

// 段 6｜双向沿合并为净额（同拍双沿：物理不可能，双丢弃并报码）
IF _rtrigLoad.Q AND _rtrigUnload.Q THEN
    _nNet := 0;                                     // 双沿丢弃 / Both edges discarded
    eErr := DL_CS_BOTH;                             // 故障级：同拍双沿 / Fault, both edges in the same scan
ELSIF _rtrigLoad.Q THEN
    _nNet := 1;                                     // 进片 +1 / Load adds one
ELSIF _rtrigUnload.Q THEN
    _nNet := -1;                                    // 出片 −1 / Unload subtracts one
ELSE
    _nNet := 0;                                     // 无沿 / No edge
END_IF

// 段 7｜净额一次性施加（占用唯一写点；越界一律拒绝，不借位）
IF bEnable AND (NOT _bMismatch) THEN
    IF _nNet > 0 THEN
        IF _uwOccupied >= _uSlotEff THEN
            eErr := DL_CS_BOTH;                     // 故障级：满篮进片 / Fault, a load on a full cassette
        ELSE
            _uwOccupied := _uwOccupied + 1;         // 占用 +1（唯一写点）[个] / Occupancy incremented, the single write point
        END_IF
    ELSIF _nNet < 0 THEN
        IF _uwOccupied = 0 THEN
            _bMismatch := TRUE;                     // 空篮出片：锁存矛盾，不借位到 25 / Unload on an empty cassette, the contradiction is latched
            _eState := E_DL_CassetteState.eFault;
            eErr := DL_CS_UNDER;                    // 故障级：空篮出片 / Fault, an unload on an empty cassette
        ELSE
            _uwOccupied := _uwOccupied - 1;         // 占用 −1（唯一写点）[个] / Occupancy decremented, the single write point
        END_IF
    END_IF
END_IF

// 段 8｜位图维护（先低槽后高槽顺序填充；出片清最低置位位；写前判槽号 ≤ 槽数）
IF (NOT _bMismatch) AND (_uwOccupied > 0) THEN
    IF _uwOccupied >= DL_CS_SLOT_MAX THEN
        uSlotMask := DL_CS_FULL_MASK;               // 满 25 槽：满位图 [bit] / All 25 slots, the full map
    ELSE
        uSlotMask := SHL(DL_CS_BIT0, UINT_TO_UDINT(_uwOccupied)) - DL_CS_BIT0;   // 低 _uwOccupied 槽全置位 [bit] / The lowest occupied slots are set
    END_IF
ELSE
    uSlotMask := 16#0000_0000;                      // 空篮或矛盾锁存：位图清 / Empty or latched mismatch, the map is cleared
END_IF

// 段 9｜出口判据（占用/空槽/满/空）
uOccupied := _uwOccupied;                           // 占用出口 [个] / Occupancy output
IF _uwOccupied >= _uSlotEff THEN
    uEmptySlot := 0;                                // 满篮：空槽 0 [个] / Full, no empty slot
ELSE
    uEmptySlot := _uSlotEff - _uwOccupied;          // 空槽数 [个] / Empty slot count
END_IF
bFull := (_uwOccupied >= _uSlotEff);                // 满篮判据 / Full criterion
bEmpty := (_uwOccupied = 0);                        // 空篮判据 / Empty criterion
bCounterMismatch := _bMismatch;                     // 矛盾锁存出口 / Contradiction latch output

// 段 10｜占用状态映射（ENUM + CASE + ELSE 兜底）
CASE _eState OF
    E_DL_CassetteState.eEmpty:
        IF _uwOccupied > 0 THEN
            IF _uwOccupied >= _uSlotEff THEN
                _eState := E_DL_CassetteState.eFull;    // 直接满篮 / Straight to full
            ELSE
                _eState := E_DL_CassetteState.ePart;    // 部分占用 / Partially occupied
            END_IF
        END_IF
    E_DL_CassetteState.ePart:
        IF _uwOccupied = 0 THEN
            _eState := E_DL_CassetteState.eEmpty;       // 回空篮 / Back to empty
        ELSIF _uwOccupied >= _uSlotEff THEN
            _eState := E_DL_CassetteState.eFull;        // 转满篮 / To full
        END_IF
    E_DL_CassetteState.eFull:
        IF _uwOccupied = 0 THEN
            _eState := E_DL_CassetteState.eEmpty;       // 全出完回空篮 / Back to empty after unloading all
        ELSIF _uwOccupied < _uSlotEff THEN
            _eState := E_DL_CassetteState.ePart;        // 转部分占用 / To partially occupied
        END_IF
    E_DL_CassetteState.eFault:
        IF NOT _bMismatch THEN
            _eState := E_DL_CassetteState.eEmpty;       // 清空解除后回空篮 / Back to empty after the clear
        END_IF
    ELSE
        // 非法状态兜底：按矛盾锁存处理（安全侧）
        _bMismatch := TRUE;
        _eState := E_DL_CassetteState.eFault;
        eErr := DL_CS_UNDER;                            // 故障级：非法状态 / Fault, illegal state
END_CASE
IF eErr = 0 THEN
    eErr := DL_CS_READY;                                // 无事件回就绪码 / Ready code when nothing else applies
END_IF
END_FUNCTION_BLOCK
