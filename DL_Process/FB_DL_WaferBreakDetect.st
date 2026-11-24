(*
  FB_DL_WaferBreakDetect  —  电池片隐裂/碎片在线判据 / Wafer crack-break online detection
  分类 Category : DL_Process
  码位 Code     : 16#06_0_BB
  段位说明      : R38 W7 预留 B6~BF 本轮正式启用，BA 格由 TankLevelStrapping 启用，本件启用 BB 格
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — 视觉位 + 峰值捕获双判据聚合分级待挖项
  溯源 Origin   : clean-room 实现，未复制任何源码行
  功能 Function : 1) 视觉结果位判据：FC_DL_BitFieldExtract 从视觉结果字提取碎片位/隐裂位
                  （每片在位沿采样一次，单件瞬时判定）；
                  2) 突发峰值判据：FB_DL_PeakDetector 捕获贴合力信号突发峰值
                  （fPeakThreshN 阈值事件），批内突发异常口径；
                  3) 双判据聚合分级（批内累计口径，非单件越限）：
                  eOk / eWatch / eSuspect / eReject 四级，分级每拍重算；
                  4) 批次管理：bBatchStart 沿清累计，达 uBatchSize 置 bBatchDone。
  边界 Boundary : ① 判据取「批内突发异常」：单件碎片只计件数，分级看批内率，禁单件直接判级；
                  ② 位偏移域闸 0..31（DWORD 字长）；峰值阈值/批量域非法判组态错锁存；
                  ③ 力信号非有限：峰值件内部保持上次有效值（件内防御），本件置信息级码；
                  ④ 无状态机相（聚合型 FB）：分级 CASE 为计算型分类，含 ELSE 兜底；
                  ⑤ R228-B 达标声明：eFault 迁出 = rtReset.Q（输入引脚，恒可达），逐字写于此。
  依赖 Depends  : FC_DL_BitFieldExtract（函数调用，引脚按 registry 实名）；
                  FB_DL_PeakDetector / FB_DL_SignalStatistics（实例化，引脚按 registry 实名）
  码表 Error codes（本件格 06_0_BB，子码步进 +0x100）:
    16#0006_01BB 信息级：批次完成（bBatchDone 置位拍）
    16#0006_02BB 故障级：组态非法（位偏移/阈值/批量域非法），锁存至复位
    16#0006_03BB 信息级：批次分级为拒收（eReject 拍）
    16#0006_04BB 信息级：当前片碎片判定命中
    16#0006_05BB 信息级：突发峰值捕获（批内异常事件）
    16#0006_06BB 信息级：当前片隐裂判定命中
    16#0006_07BB 故障级：保留码，本件无 CASE 主状态机，仅作后续维护者新增分支时的防御式默认码
    16#0006_08BB 故障级：状态机落 ELSE 兜底（分级 CASE 非法分支，防御口径）

  修订历史 Revision :
    2026-11-19  v1.0.0  R39 首版（批次 4 · 序号 19）
*)

TYPE E_DL_WaferGrade :
(
    eOk      := 0,    // 正常：批内无异常累计 / OK, no batch anomalies
    eWatch   := 10,   // 关注：峰值接近阈值（0.8 倍口径）/ Watch, peak near threshold
    eSuspect := 20,   // 可疑：批内有碎片/隐裂/突发累计 / Suspect, batch anomalies present
    eReject  := 30    // 拒收：碎片或突发计数达上限 / Reject, break or burst count at limit
);
END_TYPE

FUNCTION_BLOCK FB_DL_WaferBreakDetect
VAR_INPUT
    uVisionWord   : DWORD := 16#0;      // 视觉结果字（位打包）/ Vision result word, bit-packed
    nBreakBitOff  : INT  := 4;          // 碎片位偏移 [bit]，域 0..31 / Break bit offset
    nCrackBitOff  : INT  := 5;          // 隐裂位偏移 [bit]，域 0..31 / Crack bit offset
    fForceN       : REAL := 0.0;        // 贴合力信号 [N]（突发峰值判据源）/ Lamination force signal
    fPeakThreshN  : REAL := 20.0;       // 突发峰值阈值 [N]，域 > 0 / Burst peak threshold
    bWaferPresent : BOOL := FALSE;      // 当前片在位脉冲（每片一沿）[-] / Wafer present pulse, one edge per piece
    bBatchStart   : BOOL := FALSE;      // 批次启动沿（清批内累计）[-] / Batch start edge, clears batch counters
    uBatchSize    : UDINT := 1000;      // 批量 [片]，域 > 0 / Batch size
    uBreakCntMax  : UDINT := 3;         // 碎片拒收上限 [片]，域 > 0 / Break reject limit
    uBurstCntMax  : UDINT := 5;         // 突发拒收上限 [次]，域 > 0 / Burst reject limit
    bReset        : BOOL := FALSE;      // 故障复位，上升沿生效 / Fault reset, rising edge
END_VAR
VAR_OUTPUT
    bWaferBreak  : BOOL;                // 当前片碎片判定（在位沿采样）[-] / Current-piece break verdict
    bWaferCrack  : BOOL;                // 当前片隐裂判定 [-] / Current-piece crack verdict
    bBurstEvt    : BOOL;                // 突发峰值事件（电平，峰值超阈期间）[-] / Burst event, level while over threshold
    eGrade       : E_DL_WaferGrade;     // 批内分级出口（每拍重算）/ Batch grade outlet, recomputed each scan
    uBreakCnt    : UDINT;               // 批内碎片累计 [片] / Batch break count
    uCrackCnt    : UDINT;               // 批内隐裂累计 [片] / Batch crack count
    uBurstCnt    : UDINT;               // 批内突发累计 [次] / Batch burst count
    uPieceCnt    : UDINT;               // 批内已检片数 [片] / Pieces inspected in batch
    fPeakForceN  : REAL;                // 当前峰值保持值 [N]（峰值件出口）/ Current held peak force
    bBatchDone   : BOOL;                // 批次完成（达批量）[-] / Batch done flag
    bError       : BOOL;                // 故障锁存，仅故障级码置位，bReset 清除 [-] / Fault latch
    uErrorId     : UDINT;               // 事件码，0 = 无事件（故障级锁存回放）/ Event code
END_VAR
VAR
    fbPeak      : FB_DL_PeakDetector;   // 突发峰值捕获实例（主体首部无条件刷新）/ Burst peak detector instance
    fbStat      : FB_DL_SignalStatistics;   // 力信号统计窗实例（主体首部无条件刷新）/ Force statistics window instance
    rtWafer     : R_TRIG;               // 在位脉冲上升沿 / Wafer present rising edge
    rtBatch     : R_TRIG;               // 批次启动上升沿 / Batch start rising edge
    rtReset     : R_TRIG;               // 故障复位上升沿 / Fault reset rising edge
    _uFieldBrk  : DWORD;                // 碎片位提取结果 / Break bit extraction result
    _uMaskBrk   : DWORD;                // 碎片位掩码（件出口）/ Break bit mask
    _nActWBrk   : INT;                  // 碎片位实际宽度 / Break bit actual width
    _uErrBrk    : UDINT;                // 碎片位提取错误码 / Break extraction error
    _bValBrk    : BOOL;                 // 碎片位提取有效 / Break extraction valid
    _uFieldCrk  : DWORD;                // 隐裂位提取结果 / Crack bit extraction result
    _uMaskCrk   : DWORD;                // 隐裂位掩码 / Crack bit mask
    _nActWCrk   : INT;                  // 隐裂位实际宽度 / Crack bit actual width
    _uErrCrk    : UDINT;                // 隐裂位提取错误码 / Crack extraction error
    _bValCrk    : BOOL;                 // 隐裂位提取有效 / Crack extraction valid
    _bBurstLatch: BOOL;                 // 当前片突发锁存（片内保持，沿采样时消费）/ Per-piece burst latch
    _eGradeInt  : E_DL_WaferGrade := E_DL_WaferGrade.eOk;   // 分级内部量（CASE 唯一写入目标）/ Internal grade, sole CASE target
    _uInfo      : UDINT;                // 信息码，每拍重算 / Info code
    _uFault     : UDINT;                // 故障码锁存寄存 / Latched fault code register
    _bFault     : BOOL;                 // 故障锁存位 / Latched fault bit
    _bCfgBad    : BOOL;                 // 组态非法聚合 / Configuration invalid aggregate
END_VAR
VAR CONSTANT
    DL_WBD_INF_CAP   : REAL := 1.0E15;     // 非有限值筛查幅值上限 / Non-finite screening cap
    DL_WBD_BIT_MAX   : INT  := 31;         // 位偏移上限 [bit]（DWORD 字长）/ Bit offset upper bound
    DL_WBD_CNT_MAX   : UDINT := 16#FFFF_FFFE;  // 计数饱和上限 / Counter saturation bound
    DL_WBD_WATCH_RAT : REAL := 0.8;        // 关注级阈值比（峰值/阈值）[无量纲] / Watch-grade threshold ratio
END_VAR

(* —— 段 0：边沿与依赖件实例无条件周期刷新（R182：调用语句不得置于 IF/CASE 内） —— *)
rtWafer(CLK := bWaferPresent);                          // 在位沿刷新，每拍必调
rtBatch(CLK := bBatchStart);                            // 批次沿刷新，每拍必调
rtReset(CLK := bReset);                                 // 复位沿刷新，每拍必调
fbPeak(bEnable := TRUE,                                 // 峰值捕获恒使能
       bReset := rtWafer.Q,                             // 每片在位沿复位峰值（片口径）
       fSignal := fForceN,                              // 贴合力信号
       tSample := T#10MS,                               // 采样周期（标准口径）
       fDecayRate := 0.0,                               // 不衰减（片内保持口径）
       bDetectValley := FALSE,                          // 只测峰
       fThreshold := MAX(fPeakThreshN, 1.0E-6),         // 突发阈值（下限防零阈常报）
       bThresholdEnable := TRUE);                       // 阈值事件使能
fbStat(fIn := fForceN,                                  // 力信号统计窗（诊断随行）
       bSample := TRUE,                                 // 每拍采样
       nWindow := 32,                                   // 窗长（标准口径）
       bClear := rtBatch.Q);                            // 批次沿清窗

(* —— 段 1：单拍量预清零（锁存量 _uFault/_bFault/_uBreakCntInt 等累计量不入清单，R187①） —— *)
_uInfo := 16#0000_0000;             // 信息码每拍重算
_bCfgBad := FALSE;                  // 组态非法预清零
bWaferBreak := FALSE;               // 当前片判定缺省 FALSE（沿采样段单点置位）
bWaferCrack := FALSE;               // 当前片判定缺省 FALSE
bBatchDone := FALSE;                // 批完成缺省 FALSE（计数段单点置位）
uErrorId := 16#0000_0000;           // 事件码缺省无事件

(* —— 段 2：组态域闸（覆盖全部参与判据换算的引脚，R151） —— *)
IF (nBreakBitOff < 0) OR (nBreakBitOff > DL_WBD_BIT_MAX)
   OR (nCrackBitOff < 0) OR (nCrackBitOff > DL_WBD_BIT_MAX) THEN
    _bCfgBad := TRUE;               // 位偏移域非法
END_IF
IF (fPeakThreshN <= 0.0) OR (ABS(fPeakThreshN) > DL_WBD_INF_CAP)
   OR (fForceN <> fForceN) OR (ABS(fForceN) > DL_WBD_INF_CAP) OR ((fForceN - fForceN) <> 0.0) THEN
    _bCfgBad := TRUE;               // 阈值/力信号域非法
END_IF
IF (uBatchSize = 0) OR (uBreakCntMax = 0) OR (uBurstCntMax = 0) THEN
    _bCfgBad := TRUE;               // 批量/上限域非法
END_IF

(* —— 段 3：故障锁存与迁出沿（R228-B：rtReset.Q 恒可达） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0006_02BB;        // 故障级：组态非法（仅首次进入时写入）
    _bFault := TRUE;
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN
    _bFault := FALSE;               // 清故障锁存位（组态恢复合法为前提）
    _uFault := 16#0000_0000;
END_IF

(* —— 段 4：批次启动沿（清批内累计） —— *)
IF rtBatch.Q THEN
    uBreakCnt := 0;                 // 碎片累计清零
    uCrackCnt := 0;                 // 隐裂累计清零
    uBurstCnt := 0;                 // 突发累计清零
    uPieceCnt := 0;                 // 片数清零
    bBatchDone := FALSE;            // 批完成标志复位（沿拍清除）
END_IF

(* —— 段 5：突发峰值判据（峰值件出口镜像 + 批内突发锁存） —— *)
fPeakForceN := fbPeak.fPeak;        // 峰值保持值镜像
bBurstEvt := fbPeak.bOverThreshold; // 超阈电平镜像（每拍重算）
IF bBurstEvt AND (NOT _bBurstLatch) THEN
    _bBurstLatch := TRUE;           // 片内突发锁存（防同一突发重复计数）
    uBurstCnt := uBurstCnt + 1;     // 批内突发累计
    IF uBurstCnt >= DL_WBD_CNT_MAX THEN
        uBurstCnt := DL_WBD_CNT_MAX;    // 计数饱和防回绕
    END_IF
    _uInfo := 16#0006_05BB;         // 信息级：突发峰值捕获
END_IF
IF rtWafer.Q THEN
    _bBurstLatch := FALSE;          // 片沿：突发锁存复位（下一片重新捕获）
END_IF

(* —— 段 6：视觉位判据（在位沿采样一次；位段提取原子 ×2） —— *)
IF rtWafer.Q AND (NOT _bFault) THEN
    FC_DL_BitFieldExtract(uSource := uVisionWord,       // 视觉结果字
                          nOffset := nBreakBitOff,      // 碎片位偏移
                          nWidth := 1,                  // 单位提取
                          uField => _uFieldBrk,         // 提取结果
                          uMask => _uMaskBrk,           // 掩码
                          nActualW => _nActWBrk,        // 实际宽度
                          uErrorId => _uErrBrk,         // 错误码
                          bValid => _bValBrk);          // 有效标志
    FC_DL_BitFieldExtract(uSource := uVisionWord,       // 视觉结果字
                          nOffset := nCrackBitOff,      // 隐裂位偏移
                          nWidth := 1,                  // 单位提取
                          uField => _uFieldCrk,         // 提取结果
                          uMask => _uMaskCrk,           // 掩码
                          nActualW => _nActWCrk,        // 实际宽度
                          uErrorId => _uErrCrk,         // 错误码
                          bValid => _bValCrk);          // 有效标志
    IF _bValBrk AND (_uFieldBrk > 0) THEN
        bWaferBreak := TRUE;        // 当前片碎片判定命中
        uBreakCnt := uBreakCnt + 1; // 批内碎片累计
        IF uBreakCnt >= DL_WBD_CNT_MAX THEN
            uBreakCnt := DL_WBD_CNT_MAX;
        END_IF
        _uInfo := 16#0006_04BB;     // 信息级：碎片命中
    END_IF
    IF _bValCrk AND (_uFieldCrk > 0) THEN
        bWaferCrack := TRUE;        // 当前片隐裂判定命中
        uCrackCnt := uCrackCnt + 1; // 批内隐裂累计
        IF uCrackCnt >= DL_WBD_CNT_MAX THEN
            uCrackCnt := DL_WBD_CNT_MAX;
        END_IF
        _uInfo := 16#0006_06BB;     // 信息级：隐裂命中
    END_IF
    uPieceCnt := uPieceCnt + 1;     // 已检片数
    IF uPieceCnt >= DL_WBD_CNT_MAX THEN
        uPieceCnt := DL_WBD_CNT_MAX;
    END_IF
END_IF

(* —— 段 7：分级 CASE（计算型分类，含 ELSE 兜底） —— *)
IF (NOT _bFault) AND (uPieceCnt > 0) THEN
    CASE _eGradeInt OF
    E_DL_WaferGrade.eOk:
        IF (uBreakCnt >= uBreakCntMax) OR (uBurstCnt >= uBurstCntMax) THEN
            _eGradeInt := E_DL_WaferGrade.eReject;      // 达拒收上限：进拒收级
        ELSIF (uBreakCnt > 0) OR (uCrackCnt > 0) OR (uBurstCnt > 0) THEN
            _eGradeInt := E_DL_WaferGrade.eSuspect;     // 有异常累计：进可疑级
        ELSIF fPeakForceN >= fPeakThreshN * DL_WBD_WATCH_RAT THEN
            _eGradeInt := E_DL_WaferGrade.eWatch;       // 峰值近阈：进关注级
        END_IF
    E_DL_WaferGrade.eWatch:
        IF (uBreakCnt >= uBreakCntMax) OR (uBurstCnt >= uBurstCntMax) THEN
            _eGradeInt := E_DL_WaferGrade.eReject;      // 达拒收上限：进拒收级
        ELSIF (uBreakCnt > 0) OR (uCrackCnt > 0) OR (uBurstCnt > 0) THEN
            _eGradeInt := E_DL_WaferGrade.eSuspect;     // 有异常累计：进可疑级
        ELSIF fPeakForceN < fPeakThreshN * DL_WBD_WATCH_RAT THEN
            _eGradeInt := E_DL_WaferGrade.eOk;          // 峰值回落：回正常级
        END_IF
    E_DL_WaferGrade.eSuspect:
        IF (uBreakCnt >= uBreakCntMax) OR (uBurstCnt >= uBurstCntMax) THEN
            _eGradeInt := E_DL_WaferGrade.eReject;      // 达拒收上限：进拒收级
        END_IF
    E_DL_WaferGrade.eReject:
        IF rtBatch.Q THEN
            _eGradeInt := E_DL_WaferGrade.eOk;          // 新批次：回正常级（段 4 清累计后自然满足）
        END_IF
    ELSE
        _uFault := 16#0006_08BB;    // 故障级：非法分级 ID 兜底
        _bFault := TRUE;
        _eGradeInt := E_DL_WaferGrade.eReject;      // 防御口径：回拒收级
    END_CASE
    IF _eGradeInt = E_DL_WaferGrade.eReject THEN
        _uInfo := 16#0006_03BB;     // 信息级：分级拒收（覆盖命中码，分级状态优先）
    END_IF
END_IF

(* —— 段 8：批次完成（达批量置位，新批次沿清除） —— *)
IF (NOT _bFault) AND (uPieceCnt >= uBatchSize) THEN
    bBatchDone := TRUE;             // 批完成标志
    _uInfo := 16#0006_01BB;         // 信息级：批次完成（覆盖分级码，完成事件优先）
END_IF

(* —— 段 9：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
eGrade := _eGradeInt;               // 分级出口镜像
IF _bFault THEN
    uErrorId := _uFault;            // 故障锁存码回放
    bError := TRUE;
    bBatchDone := FALSE;            // 故障态批完成强制 FALSE（安全侧）
ELSE
    uErrorId := _uInfo;             // 信息码
    bError := FALSE;
END_IF

END_FUNCTION_BLOCK
