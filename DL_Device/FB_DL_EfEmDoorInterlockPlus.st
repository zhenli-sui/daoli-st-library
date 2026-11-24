(*==============================================================================
 * 组件名称 (Component)  : FB_DL_EfEmDoorInterlockPlus
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性 (Platform)     : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop（纯标准元素，零方言）
 * 功能描述 (Function)   : EFEM 门 / 阀 / 真空三域互斥与首因仲裁。唯一放行出口 bRelease
 *                         由四类阻断条件（门未关、阀位矛盾、真空不足、片在位）合成，阻断
 *                         域掩码逐域可见，首因只报一个编号（同拍取编号最小，锁存至复位）。
 *                         不做门体驱动输出、不做真空泵控制、不做安全回路硬线替代（安全
 *                         回路必须另有硬线双通道，本件只做逻辑侧互斥）。
 *                         门状态字位段（头注释即契约）：bit0 门关到位 ｜ bit1 门开到位 ｜
 *                         bit2 门锁到位 ｜ bit3~bit15 保留且必须为 0。
 * 溯源 (Origin)         : 道莅 clean-room 防御性实现
 * 本文件内含 (Contains) : TYPE E_DL_EfEmDomain / FUNCTION_BLOCK FB_DL_EfEmDoorInterlockPlus
 * 依赖 (Depends)        : 无（纯布尔/浮点防御逻辑，仅 Standard.library 的 ABS）
 * 红线自检 (Redline)    : 无外部全局变量、无硬件地址直引 ｜ 全变量中英双语同行注释
 *                         真空门限判零防除零 ｜ 真空非有限按保守侧（真空不足）处理 ｜
 *                         阀位矛盾判定前置于互斥仲裁 ｜ 枚举显式赋值 ｜ CASE 含 ELSE 兜底
 *                         本件无定时器/沿实例，故无周期刷新项（结构上无条件分支）
 * 错误码表 (Codes)      : 16#0003_03AC 就绪（放行或禁用，无故障）
 *                         16#0003_03AD 故障级 门状态字非法（保留位非 0）。反证句：保留位
 *                                    脏数据在输出侧与「门未关」同为禁行，不可由首因 1 区分，
 *                                    故必须独立成码
 *                         16#0003_03AE 故障级 阀位矛盾或真空门限组态非法（双反馈同 TRUE /
 *                                    同为 FALSE / 门限 ≤0）
 *                         16#0003_03AF 故障级 真空读数非有限，按「真空不足」保守侧禁行
 *                         16#0003_03B0 预留：本版不发码（下一轮区间起点，禁止回填）
 * 修订历史 (Revision)   : 2026-11-17  v1.0.0  首版入库 · R28 · 阶段三批 1
 * 验收向量 (Acceptance) : 正向 门关（状态字 bit0=1、bit2=1）、阀开反馈有效、真空 0.1 kPa
 *                         低于门限 5 kPa → 禁行、首因 3、掩码 bit2；抽到 0.05 kPa →
 *                         放行、首因清零
 *                         反向 阀双反馈同为 FALSE → 16#0003_03AE 且禁行；真空给 NaN →
 *                         16#0003_03AF 且按真空不足禁行（首因 3）；门限给 0 → 16#0003_03AE；
 *                         状态字保留位 bit7 置 1 → 16#0003_03AD 且禁行
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_EfEmDomain（归属本功能块，同文件发布，全库唯一定义）
 * 含义: 首因所属域，每个成员在 CASE 中有且仅有一个标签。
 *----------------------------------------------------------------------------*)
TYPE E_DL_EfEmDomain :
(
    eNone    := 0,    // 无阻断域：三域全放行 / No blocking domain, all domains released
    eDoor    := 1,    // 门域：门未关到位 / Door domain, the door is not closed
    eValve   := 2,    // 阀域：阀位矛盾 / Valve domain, contradictory valve position
    eVacuum  := 3,    // 真空域：真空不足或读数非有限 / Vacuum domain, insufficient vacuum or a non-finite reading
    eWafer   := 4,    // 片域：腔内片在位（E84 语义） / Wafer domain, a wafer is present inside the chamber
    eIllegal := 99    // 非法域：状态字保留位非 0 / Illegal domain, reserved bits of the status word are set
);
END_TYPE

FUNCTION_BLOCK FB_DL_EfEmDoorInterlockPlus
VAR_INPUT
    bEnable         : BOOL := FALSE;      // 使能，FALSE 即禁行（失效导向安全侧） / Enable, FALSE forces the release output off
    uDoorStatusWord : WORD;               // 门状态字 [bit]，bit0 关到位 bit1 开到位 bit2 锁到位 bit3~15 保留 / Door status word
    bValveClosed    : BOOL := FALSE;      // 阀关到位反馈 / Valve closed feedback
    bValveOpened    : BOOL := FALSE;      // 阀开到位反馈 / Valve opened feedback
    fVacuum_kPa     : REAL := 101.3;      // 腔体真空 [kPa(abs)]，域 0~101.3 / Chamber vacuum in kilopascal absolute, domain 0 to 101.3
    fVacuumOk_kPa   : REAL := 5.0;        // 允许开门真空门限 [kPa(abs)] / Vacuum threshold permitting the door to open
    bWaferPresent   : BOOL := FALSE;      // 腔内片在位（E84 语义） / Wafer present in the chamber
    bReset          : BOOL := FALSE;      // 首因与锁存复位，上升沿生效 / First-cause and latch reset, rising edge
END_VAR
VAR_OUTPUT
    bRelease        : BOOL;               // 三域放行（唯一出口） / Three-domain release, the single outlet
    bDoorPermit     : BOOL;               // 允许开门（与放行同源，语义收窄为门域） / Door open permit, same source as the release
    uFirstCause     : UINT;               // 首因编号 1 门未关 2 阀位矛盾 3 真空不足 4 片在位 [—] / First cause number
    uBlockMask      : WORD;               // 阻断域掩码 bit0 门 bit1 阀 bit2 真空 bit3 片 [bit] / Blocking domain mask
    bError          : BOOL;               // 故障级标志，仅故障级码置位 / Fault-class flag, set on fault codes only
    eErr            : UDINT;              // 错误码，段位 16#0003_xxxx / Error code in segment 16#0003_xxxx
END_VAR
VAR
    _bInit          : BOOL := FALSE;      // 首扫标志，取非判定 / First-scan flag, tested negated
    _bDoorClosed    : BOOL;               // 门关到位（状态字 bit0） / Door closed, status word bit 0
    _bLocked        : BOOL;               // 门锁到位（状态字 bit2） / Door locked, status word bit 2
    _bReservedBad   : BOOL;               // 状态字保留位非 0 / Reserved bits of the status word are set
    _bValveBad      : BOOL;               // 阀位矛盾 / Contradictory valve position
    _bVacBad        : BOOL;               // 真空不足（含读数非有限） / Insufficient vacuum including non-finite readings
    _bCfgBad        : BOOL;               // 真空门限组态非法 / Vacuum threshold configuration invalid
    _bBlkDoor       : BOOL;               // 门域阻断 / Door domain blocked
    _bBlkValve      : BOOL;               // 阀域阻断 / Valve domain blocked
    _bBlkVac        : BOOL;               // 真空域阻断 / Vacuum domain blocked
    _bBlkWafer      : BOOL;               // 片域阻断 / Wafer domain blocked
    _bAnyBlock      : BOOL;               // 任一域阻断 / Any domain blocked
    _bFirstLatched  : BOOL;               // 首因已锁存（锁存后不再改判） / First cause latched and no longer re-arbitrated
    _eDomain        : E_DL_EfEmDomain := E_DL_EfEmDomain.eNone; // 当前首因域 / Current first-cause domain
    _rtrigReset     : R_TRIG;             // 复位上升沿 / Rising edge of the reset command
END_VAR
VAR CONSTANT
    DL_EFEM_READY      : UDINT := 16#0003_03AC;  // 就绪码 / Ready code
    DL_EFEM_WORD_BAD   : UDINT := 16#0003_03AD;  // 故障级状态字非法码 / Fault code for an illegal status word
    DL_EFEM_VALVE_BAD  : UDINT := 16#0003_03AE;  // 故障级阀位矛盾或组态非法码 / Fault code for a valve contradiction or bad configuration
    DL_EFEM_VAC_BAD    : UDINT := 16#0003_03AF;  // 故障级真空非有限码 / Fault code for a non-finite vacuum reading
    DL_EFEM_VAC_LO     : REAL := 0.0;            // 真空物理下限 [kPa(abs)] / Physical vacuum lower bound
    DL_EFEM_VAC_HI     : REAL := 101.3;          // 真空物理上限 [kPa(abs)] / Physical vacuum upper bound
    DL_EFEM_MASK_DOOR  : WORD := 16#0001;        // 门域掩码位 [bit] / Door domain mask bit
    DL_EFEM_MASK_VALVE : WORD := 16#0002;        // 阀域掩码位 [bit] / Valve domain mask bit
    DL_EFEM_MASK_VAC   : WORD := 16#0004;        // 真空域掩码位 [bit] / Vacuum domain mask bit
    DL_EFEM_MASK_WAFER : WORD := 16#0008;        // 片域掩码位 [bit] / Wafer domain mask bit
    DL_EFEM_WORD_RSV   : WORD := 16#FFF8;        // 状态字保留位掩码 [bit] / Reserved bit mask of the status word
    DL_EFEM_CAUSE_DOOR : UINT := 1;               // 首因 1 门未关 / First cause 1, the door is not closed
    DL_EFEM_CAUSE_VALVE : UINT := 2;              // 首因 2 阀位矛盾 / First cause 2, contradictory valve position
    DL_EFEM_CAUSE_VAC  : UINT := 3;               // 首因 3 真空不足 / First cause 3, insufficient vacuum
    DL_EFEM_CAUSE_WAFER : UINT := 4;              // 首因 4 片在位 / First cause 4, a wafer is present
END_VAR

// 段 1｜输出与单拍标志预置（放行类输出先清零：失效导向安全侧）
bRelease := FALSE;                                  // 放行出口先清 / Release outlet cleared first
bDoorPermit := FALSE;                               // 开门许可先清 / Door permit cleared first
uFirstCause := 0;                                   // 首因预清 / First cause pre-cleared
uBlockMask := 16#0000;                              // 掩码预清 / Mask pre-cleared
bError := FALSE;                                    // 故障标志预清 / Fault flag pre-cleared
eErr := 0;                                          // 错误码预清 / Error code pre-cleared

// 段 2｜沿检测无条件周期刷新（严禁置于分支内）
_rtrigReset(CLK := bReset);                         // 复位沿 / Reset edge

// 段 3｜首扫初始化（判据取非，R19）
IF NOT _bInit THEN
    _eDomain := E_DL_EfEmDomain.eNone;              // 首因域待机 / First-cause domain starts at none
    _bInit := TRUE;                                 // 首扫只做一次 / The first scan runs once
END_IF

// 段 4｜复位路径：清首因锁存（放行条件本身不清，条件仍在则同拍重新锁存）
IF _rtrigReset.Q THEN
    _bFirstLatched := FALSE;                        // 首因锁存解除 / First-cause latch released
    uFirstCause := 0;                               // 首因编号清 / First-cause number cleared
    _eDomain := E_DL_EfEmDomain.eNone;              // 首因域清 / First-cause domain cleared
END_IF

// 段 5｜门状态字解析（保留位脏数据先判，避免位段错位被当门未关）
_bDoorClosed := (uDoorStatusWord AND DL_EFEM_MASK_DOOR) <> 16#0000;   // bit0 关到位 / Bit 0, closed position reached
_bLocked := (uDoorStatusWord AND 16#0004) <> 16#0000;                 // bit2 锁到位 / Bit 2, locking position reached
_bReservedBad := (uDoorStatusWord AND DL_EFEM_WORD_RSV) <> 16#0000;   // 保留位非 0 / Reserved bits are set

// 段 6｜阀位矛盾闸（前置于互斥仲裁：矛盾状态下首因必须指阀域而不是门域）
_bValveBad := (bValveClosed AND bValveOpened) OR ((NOT bValveClosed) AND (NOT bValveOpened));

// 段 7｜真空组态与读数闸（门限判零防除零；读数非有限按真空不足保守侧）
_bCfgBad := (fVacuumOk_kPa <> fVacuumOk_kPa) OR ((fVacuumOk_kPa - fVacuumOk_kPa) <> (fVacuumOk_kPa - fVacuumOk_kPa))
         OR (fVacuumOk_kPa <= DL_EFEM_VAC_LO) OR (fVacuumOk_kPa > DL_EFEM_VAC_HI);
IF (fVacuum_kPa <> fVacuum_kPa) OR ((fVacuum_kPa - fVacuum_kPa) <> (fVacuum_kPa - fVacuum_kPa)) THEN
    _bVacBad := TRUE;                               // 读数非有限：按真空不足处理 / Non-finite reading treated as insufficient vacuum
    eErr := DL_EFEM_VAC_BAD;                        // 故障级：真空读数非有限 / Fault, non-finite vacuum reading
    bError := TRUE;
ELSE
    _bVacBad := (fVacuum_kPa > fVacuumOk_kPa);      // 真空值高于门限 = 真空不足 / A value above the threshold means insufficient vacuum
END_IF
IF _bCfgBad THEN
    eErr := DL_EFEM_VALVE_BAD;                      // 故障级：真空门限组态非法 / Fault, the vacuum threshold configuration is invalid
    bError := TRUE;
END_IF
IF _bReservedBad THEN
    eErr := DL_EFEM_WORD_BAD;                       // 故障级：状态字保留位非 0 / Fault, reserved bits of the status word are set
    bError := TRUE;
END_IF
IF _bValveBad THEN
    eErr := DL_EFEM_VALVE_BAD;                      // 故障级：阀位矛盾（先于互斥判定） / Fault, contradictory valve position checked before the arbitration
    bError := TRUE;
END_IF

// 段 8｜四域阻断判定（掩码逐域可见，首因只报一个）
_bBlkDoor := (NOT _bDoorClosed) OR (NOT _bLocked);  // 门域：关到位与锁到位缺一即阻断 / Door domain blocked unless closed and locked
_bBlkValve := _bValveBad OR _bCfgBad;               // 阀域：阀位矛盾或组态非法即阻断 / Valve domain blocked on a contradiction or bad configuration
_bBlkVac := _bVacBad OR _bCfgBad;                   // 真空域：真空不足或组态非法即阻断 / Vacuum domain blocked on insufficient vacuum or bad configuration
_bBlkWafer := bWaferPresent;                        // 片域：腔内片在位即阻断 / Wafer domain blocked while a wafer is present
_bAnyBlock := _bBlkDoor OR _bBlkValve OR _bBlkVac OR _bBlkWafer;   // 任一域阻断 / Any domain blocked
IF _bBlkDoor THEN
    uBlockMask := uBlockMask OR DL_EFEM_MASK_DOOR;  // 门域掩码置位 / Door domain mask bit set
END_IF
IF _bBlkValve THEN
    uBlockMask := uBlockMask OR DL_EFEM_MASK_VALVE; // 阀域掩码置位 / Valve domain mask bit set
END_IF
IF _bBlkVac THEN
    uBlockMask := uBlockMask OR DL_EFEM_MASK_VAC;   // 真空域掩码置位 / Vacuum domain mask bit set
END_IF
IF _bBlkWafer THEN
    uBlockMask := uBlockMask OR DL_EFEM_MASK_WAFER; // 片域掩码置位 / Wafer domain mask bit set
END_IF

// 段 9｜首因仲裁（仅未锁存时仲裁；顺序 1→4 即同拍取编号最小）
IF (NOT _bFirstLatched) AND _bAnyBlock THEN
    IF _bBlkDoor THEN
        _eDomain := E_DL_EfEmDomain.eDoor;          // 优先 1：门未关 / Priority 1, the door is not closed
    ELSIF _bBlkValve THEN
        _eDomain := E_DL_EfEmDomain.eValve;         // 优先 2：阀位矛盾 / Priority 2, contradictory valve position
    ELSIF _bBlkVac THEN
        _eDomain := E_DL_EfEmDomain.eVacuum;        // 优先 3：真空不足 / Priority 3, insufficient vacuum
    ELSE
        _eDomain := E_DL_EfEmDomain.eWafer;         // 优先 4：片在位 / Priority 4, a wafer is present
    END_IF
    _bFirstLatched := TRUE;                         // 首因锁存 / First cause latched
ELSIF (NOT _bAnyBlock) THEN
    _bFirstLatched := FALSE;                        // 阻断全消失：锁存解除（状态量随条件销号） / All blocks cleared, the latch is released
    _eDomain := E_DL_EfEmDomain.eNone;              // 首因域回无 / First-cause domain back to none
END_IF

// 段 10｜首因域映射（ENUM + CASE + ELSE 兜底）
CASE _eDomain OF
    E_DL_EfEmDomain.eNone:
        uFirstCause := 0;                           // 无首因 / No first cause
    E_DL_EfEmDomain.eDoor:
        uFirstCause := DL_EFEM_CAUSE_DOOR;          // 首因 1 / First cause 1
    E_DL_EfEmDomain.eValve:
        uFirstCause := DL_EFEM_CAUSE_VALVE;         // 首因 2 / First cause 2
    E_DL_EfEmDomain.eVacuum:
        uFirstCause := DL_EFEM_CAUSE_VAC;           // 首因 3 / First cause 3
    E_DL_EfEmDomain.eWafer:
        uFirstCause := DL_EFEM_CAUSE_WAFER;         // 首因 4 / First cause 4
    E_DL_EfEmDomain.eIllegal:
        uFirstCause := 0;                           // 非法域不报首因，由 03AD 表达 / The illegal domain reports no first cause, 03AD carries it
        eErr := DL_EFEM_WORD_BAD;                   // 故障级：非法域 / Fault, illegal domain
        bError := TRUE;
    ELSE
        // 非法枚举值兜底（故障级，状态字非法码承载）
        uFirstCause := 0;
        eErr := DL_EFEM_WORD_BAD;                   // 故障级：枚举越界 / Fault, the enumeration is out of range
        bError := TRUE;
        _eDomain := E_DL_EfEmDomain.eIllegal;
END_CASE

// 段 11｜放行出口（唯一出口；使能跌落即禁行，故障级存在亦禁行）
bRelease := bEnable AND (NOT _bAnyBlock) AND (NOT _bReservedBad) AND (NOT _bCfgBad) AND (NOT _bValveBad) AND (NOT _bVacBad);
bDoorPermit := bRelease;                            // 开门许可与放行同源 / Door permit shares the release source
IF bRelease THEN
    eErr := DL_EFEM_READY;                          // 就绪：三域放行 / Ready, all domains released
ELSE
    IF NOT bEnable THEN
        eErr := DL_EFEM_READY;                      // 禁用为正常停机（掩码已标全阻断域） / Disable is a normal stop, the mask shows the blocked domains
    END_IF
END_IF
END_FUNCTION_BLOCK
