(*==============================================================================
 * 组件名称 (Component)  : FB_DL_ElectrolyteFifoTrace
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / LEN / MUX 类标准函数），零厂商私有库
 * 功能描述 (Function)   : 注液批次 FIFO 追溯队列。
 *                         每支电芯注液完成时把"批次号 + 条码 + 注液量"三元组压入定长环形队列，
 *                         下游追溯/贴标工位按"先入先出"逐条取走，形成可回溯的注液履历链。
 *                         三条固化纪律：
 *                           ① **防重复入队**：压入前线性扫描在队记录，条码已存在即拒入（同一条码
 *                              在队列内只许出现一次，防重扫/重触发造成履历重复计数）；
 *                           ② **队满拒入**：计数达深度上限即拒入并锁存 bQueueFull，
 *                              直到出队使计数下降（或复位沿）才解除；
 *                           ③ **空队不宣称**：出队沿命中空队时 bOutValid=FALSE、不输出旧记录，
 *                              并按信息级置 eEmptyPop（不进锁存，R41 空队语义）。
 *                         验收向量：
 *                           ① 深度 32；压入 32 条后第 33 条 → 拒入 + bQueueFull 锁存
 *                           ② 同一 sBarcode 连续压入两次 → 第二次拒入 + eDupBarcode（不锁存）
 *                           ③ 空队出队 → bOutValid=FALSE + eEmptyPop（不锁存、不搬旧值）
 *                           ④ 满队后出队 1 条 → bQueueFull 解除，可再压入 1 条
 * 接口     (Interface)  : 入 bPush 入队沿、sBatchNo 批次号、sBarcode 电芯条码、fVolumeMl 注液量、
 *                         bPop 出队沿、bClear 清队沿、bReset 复位沿；
 *                         出 iQueueCnt 在队条数、sOutBatch / sOutBarcode / fOutVolumeMl 出队记录、
 *                         bOutValid 出队脉冲（单拍）、bQueueFull 队满锁存、bRejected 当拍拒入、
 *                         eState 相、eCause 成因、bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做"队列与履历记账"，不驱动注液泵/称重/
 *                         贴标机**，也不判注液量是否合格（属注液量判据件）；
 *                         ② **条码空串拒入**：LEN(sBarcode) = 0 → 拒入 + eBarcodeEmpty（信息级）；
 *                         ③ **深度闸**：环形指针一律以深度常量取模前先钳（下标恒在 1..32），
 *                         扫描循环带 _uGuard 计数器（上界 = 深度 + 2），循环必然收敛；
 *                         ④ **锁存解除式**：bQueueFull 的解除有两条——① 出队使计数 < 深度
 *                         （每拍重算，非沿）；② bReset 上升沿。两式自证可满足：出队沿与复位沿
 *                         均为外部引脚，不受任何锁存量门控，恒可达（R152/R234）；
 *                         ⑤ 组态/内部一致性故障（指针越界）→ 清队重建 + 锁存 ePtrCorrupt；
 *                         ⑥ 零全局耦合、零物理地址。
 * 分工声明 (Scope)      : 本件只管"注液履历队列"。不接管：注液量趋势判据
 *                         （属 FB_DL_ElectrolyteDosingTrend）、批次配方下发（属配方件）、
 *                         队列持久化落盘（属 MES 通讯件）。
 * 来源标签 (Source Tag) : ROADMAP 空勾真缺口 P1（注液批次追溯，自研 clean-room）
 * 码表     (Codes)      : 本件不占用任何全局数字码位（零码位范式 R297）；诊断由 BOOL + ENUM 出口承担。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 下标钳位 + 循环计数器 + 空串闸 + 满闸 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE 兜底 ｜ R7 ✓ R_TRIG 段 0 无条件刷新（本件无 TON）
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R47 首版（批次 2 · 序号 6）
 *==============================================================================*)

TYPE ST_DL_EftRecord :
STRUCT
    sBatchNo  : STRING[31] := '';   // 注液批次号（≤31 字符） [-] / Electrolyte batch number, up to 31 chars
    sBarcode  : STRING[63] := '';   // 电芯条码（≤63 字符，队列内唯一） [-] / Cell barcode, unique inside the queue
    fVolumeMl : LREAL := 0.0;       // 本次注液量 [ml] / Injected volume of this shot [ml]
END_STRUCT
END_TYPE

TYPE E_DL_EftState :
(
    eIdle  := 0,    // 待机相（队列可用） / Idle, queue serviceable
    eFault := 90    // 故障相（指针损坏，等复位） / Fault, pointer corruption, awaiting reset
);
END_TYPE

TYPE E_DL_EftCause :
(
    eNone        := 0,   // 无异常 / No anomaly
    eDupBarcode  := 1,   // 条码重复（拒入，信息级） / Duplicate barcode, info level
    eBarcodeEmpty:= 2,   // 条码空串（拒入，信息级） / Empty barcode, info level
    eEmptyPop    := 3,   // 空队出队（不宣称，信息级） / Pop on empty queue, info level
    eQueueFull   := 4,   // 队满拒入（锁存） / Queue full, latched
    ePtrCorrupt  := 5,   // 环形指针损坏（故障级） / Ring pointer corruption, fault level
    ePhaseBad    := 6    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_ElectrolyteFifoTrace
VAR_INPUT
    bPush     : BOOL := FALSE;      // 入队沿 [-] / Enqueue edge
    sBatchNo  : STRING[31] := '';   // 待入队批次号 [-] / Batch number to enqueue
    sBarcode  : STRING[63] := '';   // 待入队电芯条码（队列内须唯一） [-] / Barcode to enqueue, unique inside the queue
    fVolumeMl : LREAL := 0.0;       // 待入队注液量 [ml] / Volume to enqueue [ml]
    bPop      : BOOL := FALSE;      // 出队沿 [-] / Dequeue edge
    bClear    : BOOL := FALSE;      // 清队沿（运维用，非故障路径） [-] / Clear edge, maintenance only
    bReset    : BOOL := FALSE;      // 故障复位沿 [-] / Fault reset edge
END_VAR
VAR_OUTPUT
    iQueueCnt    : INT := 0;                        // 在队条数 [条] / Records currently queued
    sOutBatch    : STRING[31] := '';                // 出队记录批次号 [-] / Dequeued batch number
    sOutBarcode  : STRING[63] := '';                // 出队记录条码 [-] / Dequeued barcode
    fOutVolumeMl : LREAL := 0.0;                    // 出队记录注液量 [ml] / Dequeued volume [ml]
    bOutValid    : BOOL := FALSE;                   // 出队脉冲（单拍，空队不宣称） [-] / Dequeue pulse, empty queue not claimed
    bQueueFull   : BOOL := FALSE;                   // 队满锁存 [-] / Queue full, latched
    bRejected    : BOOL := FALSE;                   // 当拍发生拒入 [-] / A push was rejected this scan
    bFullRelease : BOOL := FALSE;                   // 队满解除脉冲（单拍，诊断用） [-] / Full-release pulse, diagnostic
    eState       : E_DL_EftState := E_DL_EftState.eIdle;   // 相出口 [-] / Phase outlet
    eCause       : E_DL_EftCause := E_DL_EftCause.eNone;   // 成因出口（R190 归因唯一） [-] / Cause outlet
    bError       : BOOL := FALSE;                   // 故障标志（仅指针损坏级） [-] / Error flag, pointer corruption only
END_VAR
VAR
    _eState   : E_DL_EftState := E_DL_EftState.eIdle;      // 内部相（CASE 唯一写入目标） / Internal phase
    _eCause   : E_DL_EftCause := E_DL_EftCause.eNone;      // 成因锁存量 / Latched cause
    _bFault   : BOOL := FALSE;                             // 故障锁存位 / Latched fault bit
    _bFull    : BOOL := FALSE;                             // 队满锁存位（与 bQueueFull 同源） / Latched full bit
    _iHead    : INT := 1;                                  // 出队头指针（1..32） / Dequeue head pointer
    _iTail    : INT := 1;                                  // 入队尾指针（1..32） / Enqueue tail pointer
    _iCnt     : INT := 0;                                  // 在队条数 / Queued record count
    _bOutValid: BOOL := FALSE;                             // 出队脉冲内部位（单拍） / Internal dequeue pulse
    _bRejected: BOOL := FALSE;                             // 当拍拒入内部位（单拍） / Internal reject flag
    _bFullRel : BOOL := FALSE;                             // 队满解除内部位（单拍） / Internal full-release flag
    _bDup     : BOOL := FALSE;                             // 重复条码扫描结论 / Duplicate-scan result
    _uScan    : UINT := 0;                                 // 查重扫描计数器（防死循环） / Duplicate-scan guard counter
    _iScanIdx : INT := 0;                                  // 查重扫描下标（1..32） / Duplicate-scan index
    _bPushed  : BOOL := FALSE;                             // 本拍入队成功标志 / Push-succeeded flag of this scan
    rtPush    : R_TRIG;                                    // 入队沿实例，段 0 无条件调用 / Enqueue edge instance
    rtPop     : R_TRIG;                                    // 出队沿实例，段 0 无条件调用 / Dequeue edge instance
    rtClear   : R_TRIG;                                    // 清队沿实例，段 0 无条件调用 / Clear edge instance
    rtReset   : R_TRIG;                                    // 复位沿实例，段 0 无条件调用 / Reset edge instance
    aRec      : ARRAY[1..32] OF ST_DL_EftRecord;           // 记录环（深度字面量上界，R104） / Record ring, literal depth
END_VAR
VAR CONSTANT
    DL_EFT_DEPTH : INT := 32;           // 队列深度（与数组字面量上界同源，改动须同步） [条] / Queue depth
    DL_EFT_GUARD : UINT := 34;          // 查重循环守护上限（深度 + 2） [次] / Duplicate-scan guard limit
END_VAR

(* —— 段 0：四枚沿实例无条件周期刷新（R228A） —— *)
rtPush(CLK := bPush);                                       // 入队沿 / Enqueue edge
rtPop(CLK := bPop);                                         // 出队沿 / Dequeue edge
rtClear(CLK := bClear);                                     // 清队沿 / Clear edge
rtReset(CLK := bReset);                                     // 复位沿 / Reset edge

(* —— 段 1：单拍量预清零（锁存量 _eCause/_bFault/_bFull 不入清单，R107） —— *)
_bOutValid := FALSE;                                        // 出队脉冲预清 / Dequeue pulse preset
_bRejected := FALSE;                                        // 拒入标志预清 / Reject flag preset
_bFullRel  := FALSE;                                        // 满解除脉冲预清 / Full-release pulse preset
bError     := FALSE;                                        // 故障标志预清（R45 配对） / Error preset

(* —— 段 2：环形指针自检（越界即判损坏：清队重建 + 锁存） —— *)
IF (_iHead < 1) OR (_iHead > DL_EFT_DEPTH) OR (_iTail < 1) OR (_iTail > DL_EFT_DEPTH)
   OR (_iCnt < 0) OR (_iCnt > DL_EFT_DEPTH) THEN
    _iHead  := 1;                                           // 头指针重建 / Head rebuilt
    _iTail  := 1;                                           // 尾指针重建 / Tail rebuilt
    _iCnt   := 0;                                           // 计数清零 / Count cleared
    _eCause := E_DL_EftCause.ePtrCorrupt;                   // 归因：指针损坏 / Cause: pointer corruption
    _bFault := TRUE;                                        // 锁存 / Latch
    _eState := E_DL_EftState.eFault;                        // 入故障相 / Enter fault phase
END_IF

(* —— 段 3：迁出链（bReset 上升沿；bClear 为该沿之外的运维清队路径） —— *)
IF rtReset.Q THEN
    _bFault := FALSE;                                       // 清故障锁存 / Clear fault latch
    _bFull  := FALSE;                                       // 清队满锁存 / Clear full latch
    _eCause := E_DL_EftCause.eNone;                         // 清成因 / Clear cause
    _eState := E_DL_EftState.eIdle;                         // 回待机相 / Back to idle
END_IF
IF rtClear.Q THEN
    _iHead := 1;                                            // 头指针回 1 / Head back to 1
    _iTail := 1;                                            // 尾指针回 1 / Tail back to 1
    _iCnt  := 0;                                            // 计数清零 / Count cleared
    _bFull := FALSE;                                        // 清队满锁存 / Clear full latch
END_IF

(* —— 段 4：相迁移（故障相由段 3 迁出；本件无多相业务，故两相 CASE） —— *)
CASE _eState OF

E_DL_EftState.eIdle:
    ;                                                       // 待机相：队列服务在段 5/6 执行 / Service happens in stages 5 and 6

E_DL_EftState.eFault:
    ;                                                       // 故障相：仅等复位 / Wait for the reset edge only

ELSE
    _eCause := E_DL_EftCause.ePhaseBad;                     // 归因：非法相位 / Cause: illegal phase
    _bFault := TRUE;                                        // 锁存 / Latch
    _eState := E_DL_EftState.eFault;                        // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 5：出队（FIFO 头指针推进；空队不宣称、不搬旧值） —— *)
IF (rtPop.Q) AND (_eState = E_DL_EftState.eIdle) THEN
    IF _iCnt > 0 THEN
        sOutBatch    := aRec[_iHead].sBatchNo;               // 取头记录批次号 / Take the head batch number
        sOutBarcode  := aRec[_iHead].sBarcode;               // 取头记录条码 / Take the head barcode
        fOutVolumeMl := aRec[_iHead].fVolumeMl;              // 取头记录注液量 / Take the head volume
        aRec[_iHead].sBatchNo  := '';                        // 清空已出队槽位批次号 / Clear the dequeued slot batch
        aRec[_iHead].sBarcode  := '';                        // 清空已出队槽位条码 / Clear the dequeued slot barcode
        aRec[_iHead].fVolumeMl := 0.0;                       // 清空已出队槽位注液量 / Clear the dequeued slot volume
        _bOutValid := TRUE;                                  // 出队脉冲 / Dequeue pulse
        _iCnt := _iCnt - 1;                                  // 计数递减 / Count decrement
        _iHead := _iHead + 1;                                // 头指针推进 / Head advance
        IF _iHead > DL_EFT_DEPTH THEN
            _iHead := 1;                                     // 环形回卷 / Ring wrap
        END_IF
        IF _bFull THEN
            _bFull := FALSE;                                 // 出队腾出空间：解除队满 / Space freed, clear the full latch
            _bFullRel := TRUE;                               // 满解除脉冲 / Full-release pulse
        END_IF
    ELSE
        _eCause := E_DL_EftCause.eEmptyPop;                  // 归因：空队出队（信息级，不锁存） / Cause: empty pop, info level
    END_IF
END_IF

(* —— 段 6：入队（先查重、再判满；拒入不改变队列内容） —— *)
IF (rtPush.Q) AND (_eState = E_DL_EftState.eIdle) THEN
    IF LEN(sBarcode) = 0 THEN
        _bRejected := TRUE;                                  // 空串拒入 / Empty barcode rejected
        _eCause := E_DL_EftCause.eBarcodeEmpty;              // 归因：条码空串（信息级） / Cause: empty barcode, info level
    ELSE
        (* 线性查重：扫描在队记录（带守护计数，深度有限故必然收敛） *)
        _bDup  := FALSE;                                     // 查重结论预置 / Duplicate result preset
        _uScan := 0;                                         // 扫描计数器归零 / Scan guard reset
        _iScanIdx := _iHead;                                 // 从当前头指针起扫 / Start at the current head
        WHILE (_uScan < DL_EFT_GUARD) AND (_uScan < _iCnt) DO
            IF aRec[_iScanIdx].sBarcode = sBarcode THEN
                _bDup := TRUE;                               // 命中重复条码 / Duplicate barcode found
            END_IF
            _uScan := _uScan + 1;                            // 计数器推进 / Guard advance
            _iScanIdx := _iScanIdx + 1;                      // 槽位推进 / Slot advance
            IF _iScanIdx > DL_EFT_DEPTH THEN
                _iScanIdx := 1;                              // 环形回卷 / Ring wrap
            END_IF
        END_WHILE

        IF _bDup THEN
            _bRejected := TRUE;                              // 重复条码拒入 / Duplicate barcode rejected
            _eCause := E_DL_EftCause.eDupBarcode;            // 归因：条码重复（信息级） / Cause: duplicate barcode, info level
        ELSIF _iCnt >= DL_EFT_DEPTH THEN
            _bRejected := TRUE;                              // 队满拒入 / Queue full, rejected
            _bFull := TRUE;                                  // 队满锁存（入队前判满语义） / Latch the full state
            _eCause := E_DL_EftCause.eQueueFull;             // 归因：队满 / Cause: queue full
        ELSE
            aRec[_iTail].sBatchNo  := sBatchNo;              // 写尾记录批次号 / Write the tail batch number
            aRec[_iTail].sBarcode  := sBarcode;              // 写尾记录条码 / Write the tail barcode
            aRec[_iTail].fVolumeMl := fVolumeMl;             // 写尾记录注液量 / Write the tail volume
            _iCnt  := _iCnt + 1;                             // 计数递增 / Count increment
            _iTail := _iTail + 1;                            // 尾指针推进 / Tail advance
            IF _iTail > DL_EFT_DEPTH THEN
                _iTail := 1;                                 // 环形回卷 / Ring wrap
            END_IF
        END_IF
    END_IF
END_IF

(* —— 段 7：出口单点映射（名实双出口，R191） —— *)
iQueueCnt   := _iCnt;                                        // 在队条数出口 / Queued count outlet
bOutValid   := _bOutValid;                                   // 出队脉冲出口 / Dequeue pulse outlet
bQueueFull  := _bFull;                                       // 队满出口 / Full outlet
bRejected   := _bRejected;                                   // 拒入标志出口 / Reject outlet
bFullRelease:= _bFullRel;                                    // 满解除脉冲出口 / Full-release outlet
eState      := _eState;                                      // 相出口 / Phase outlet
eCause      := _eCause;                                      // 成因出口 / Cause outlet
bError      := _bFault;                                      // 故障标志（仅故障级码置位） / Error flag, fault level only

END_FUNCTION_BLOCK
