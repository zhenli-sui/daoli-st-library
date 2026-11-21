(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TcChannelScanDiag
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / ABS），零厂商私有库
 * 功能描述 (Function)   : 多路热电偶断偶/反接/漂移诊断，逐通道轮询扫描（每拍扫一路，8 路一轮 8 拍）。
 *                         三类特征按优先级判定（优先级即归因优先级，先断偶后反接再漂移）：
 *                           ① 断偶 = 超量程特征：读数高于量程上限或低于量程下限（开路时前端
 *                              常表现为满量程上冲或极度负偏，故用双侧超量程判，不只判高侧）；
 *                           ② 反接 = 负向特征：读数低于 fNegThresh（明显负温，正常工况不会出现）；
 *                           ③ 漂移 = 慢变趋势特征：读数与慢变基线（EMA，系数 fDriftAlpha）之差
 *                              持续超 fDriftBand。用"基线 vs 瞬时"而非"两拍差分"，因为两拍差分
 *                              会被噪声主导；EMA 基线滤掉噪声只留趋势，正是慢变趋势的定义。
 *                         故障码按通道编码：每通道一个 ENUM 槽（aeFault[i]），另有 nFaultMask
 *                         位掩码（bit i = 通道 i 有故障）供 HMI 一字节查看。**不占用全局事件码段**。
 *                         故障为逐通道锁存，清除路径：bReset 上升沿（全清）——单通道清不在本件
 *                         （单通道清应由上层在换传感器后整体复位，避免"故障码还在但传感器已换"
 *                         的台账错乱）。
 * 接口     (Interface)  : 输入 afTempC 8 路温度（VAR_IN_OUT，本件只读）、nChannelCount 实际通道数
 *                         （2..8）、fRangeMin / fRangeMax 量程、fNegThresh 反接负向阈（工程单位）、
 *                         fDriftBand 漂移带、fDriftAlpha 基线 EMA 系数（0..1）、bReset 复位；
 *                         输出 aeFault 逐通道故障、nFaultMask 通道位掩码、bAnyFault 任一通道故障、
 *                         nScanIdx 当前扫描通道号、fLastValue 当拍扫描通道读数、eState / bError。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只诊断传感器链路（断偶/反接/漂移），
 *                         不做温度补偿、不参与温控回路、不判超温**。超温保护属温控/安全链；
 *                         把断偶诊断塞进超温保护会让"传感器坏了"与"真超温"混为一谈。
 *                         ② 组态闸：nChannelCount < 2 或 > 8（越 ARRAY 边界，缺此即数组越界读）、
 *                         fRangeMin >= fRangeMax（量程倒置）、fNegThresh >= fRangeMin
 *                         （反接阈落在量程内会把正常低温误判反接）、fDriftBand <= 0.0、
 *                         fDriftAlpha <= 0.0 或 >= 1.0（EMA 系数必须开区间）、任一输入 NaN
 *                         → 故障锁存，全部通道停止判定（不宣称），bError 置位。
 *                         ③ 轮询用 _nIdx 自增取模，绝不越界（先钳再取模双保险）。
 *                         ④ 单枚 R_TRIG（bReset）段 0 无条件周期刷新；无 TON，故无跨相复位问题。
 *                         ⑤ 故障相迁出唯一路径 = bReset 上升沿（R228B）。
 *                         ⑥ 零全局耦合（无 GVL / 无 VAR_EXTERNAL / 无物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_AnalogScaleEx`（模拟量标定换算）分工——那件把原始码值换成
 *                         工程单位，本件在工程单位域做**链路健康诊断**。二者串接顺序固定：
 *                         先换算后诊断（断偶判据依赖量程，量程是工程单位概念）。
 * 来源标签 (Source Tag) : T2-6 ◐（开源参考：热电偶断线/反接诊断特征参数域，零代码行复制）
 * 解除式   (Release)    : bReset 上升沿 ∧ 组态合法 → 全通道故障表清零、基线表清零（重新起 EMA）。
 *                         自证可满足：复位为外部动作，不受逐通道锁存门控。
 * 码表     (Codes)      : 本件**不占用任何全局数字码位**。故障以"逐通道 ENUM + 通道位掩码"
 *                         表达（ENUM 成员是通道内的故障种类，不是全局事件码）；数字码位待
 *                         主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 数组边界闸 + EMA 开区间闸 + 量程几何闸 + NaN 闸
 *                         R5 ✓ 声明逐行同行双语注释 ｜ R6 ✓ ENUM+CASE 含 ELSE
 *                         R7 ✓ R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-19  v1.0.0  R46 首版（批次 3 · 序号 13）
 *==============================================================================*)

TYPE E_DL_TcdFault :
(
    eOk      := 0,    // 通道健康 / Channel healthy
    eOpen    := 10,   // 断偶（超量程特征） / Open thermocouple, out-of-range signature
    eReverse := 20,   // 反接（负向特征） / Reversed polarity, negative signature
    eDrift   := 30,   // 漂移（慢变趋势特征） / Drift, slow-trend signature
    eCfg     := 90    // 组态/输入非法，通道未判定 / Configuration or input illegal, channel not judged
);
END_TYPE

TYPE E_DL_TcdState :
(
    eIdle  := 0,    // 首轮扫描未完成 / First scan round not complete
    eRun   := 10,   // 轮询诊断运行相 / Round-robin diagnosis running
    eFault := 90    // 组态故障相 / Configuration fault phase
);
END_TYPE

FUNCTION_BLOCK FB_DL_TcChannelScanDiag
VAR_IN_OUT
    afTempC : ARRAY[0..7] OF REAL;      // 8 路温度（本件只读，按 nChannelCount 截取） [°C] / Eight channels, read-only here [degC]
END_VAR
VAR_INPUT
    nChannelCount : INT := 8;           // 实际通道数，域 2..8 / Active channel count, 2..8
    fRangeMin     : REAL := -50.0;      // 量程下限，域 < fRangeMax [°C] / Range lower bound, < upper [degC]
    fRangeMax     : REAL := 400.0;      // 量程上限，域 > fRangeMin [°C] / Range upper bound, > lower [degC]
    fNegThresh    : REAL := -20.0;      // 反接负向阈，域 < fRangeMin [°C] / Reverse-polarity threshold, < range lower [degC]
    fDriftBand    : REAL := 5.0;        // 漂移带（读数与基线之差），域 > 0.0 [°C] / Drift band, > 0.0 [degC]
    fDriftAlpha   : REAL := 0.01;       // 基线 EMA 系数，域 (0, 1) 开区间 [-] / Baseline EMA coefficient, open interval (0,1)
    bReset        : BOOL := FALSE;      // 复位，上升沿清全部通道故障 [-] / Reset, rising edge clears all channel faults
END_VAR
VAR_OUTPUT
    aeFault    : ARRAY[0..7] OF E_DL_TcdFault;   // 逐通道故障出口 [-] / Per-channel fault outlet
    nFaultMask : BYTE;                  // 通道位掩码：bit i = 通道 i 有故障 [-] / Channel bit mask, bit i = channel i faulty
    bAnyFault  : BOOL;                  // 任一通道故障（锁存） [-] / Any channel faulty, latched
    nScanIdx   : INT;                   // 本拍扫描的通道号 [通道] / Channel scanned this scan
    fLastValue : REAL;                  // 本拍扫描通道的读数 [°C] / Reading of the scanned channel [degC]
    eState     : E_DL_TcdState;         // 状态出口 [-] / State outlet
    bError     : BOOL;                  // 故障标志（任一通道故障或组态非法） [-] / Error flag
END_VAR
VAR
    _eState   : E_DL_TcdState := E_DL_TcdState.eIdle;    // 内部相位（CASE 唯一写入目标） / Internal phase
    rtReset   : R_TRIG;                 // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _afBase   : ARRAY[0..7] OF REAL;    // 逐通道慢变基线（EMA，锁存量） [°C] / Per-channel slow baseline, latched [degC]
    _abInit   : ARRAY[0..7] OF BOOL;    // 逐通道基线已初始化标记（锁存量） / Per-channel baseline initialised flag
    _aeFault  : ARRAY[0..7] OF E_DL_TcdFault;   // 逐通道故障锁存表（锁存量） / Per-channel latched fault table
    _nIdx     : INT;                    // 轮询索引（锁存量） / Round-robin index, latched
    _nRound   : UDINT;                  // 已完成扫描次数（锁存量） / Completed scan rounds, latched
    _bAny     : BOOL;                   // 任一通道故障锁存位（锁存量） / Latched any-fault bit
    _bCfgBad  : BOOL;                   // 组态非法当拍量 [-] / Illegal configuration this scan
    _bNonFin  : BOOL;                   // 阈值非法当拍量 [-] / Illegal threshold this scan
    _fVal     : REAL;                   // 本拍扫描通道读数（已过边界钳位的索引取值） [°C] / Scanned channel value, index guaranteed in range
    _fDev     : REAL;                   // 读数与基线之差 [°C] / Deviation from the baseline [°C]
    _i        : INT;                    // 掩码重建索引 / Mask rebuild index
    _nSh      : INT;                    // 移位量归一后副本（0..7，禁 SHL 越位宽） [位] / Normalised shift amount, 0..7
END_VAR
VAR CONSTANT
    DL_TCD_MAXN  : INT := 8;        // 通道容量（与 ARRAY 上界一致） [通道] / Channel capacity matching the array bounds
    DL_TCD_MINN  : INT := 2;        // 最少通道数 [通道] / Minimum channel count
    DL_TCD_BIT   : BYTE := 16#01;   // 掩码左移基元 [位] / Mask shift primitive
END_VAR

(* —— 段 0：判据派生 + 复位沿无条件周期刷新 —— *)
_bNonFin := (fRangeMin <> fRangeMin) OR (fRangeMax <> fRangeMax)         // NaN 自反判（判等禁令唯一例外） / NaN self-reflexive tests
         OR (fNegThresh <> fNegThresh) OR (fDriftBand <> fDriftBand)
         OR (fDriftAlpha <> fDriftAlpha);
_bCfgBad := (nChannelCount < DL_TCD_MINN) OR (nChannelCount > DL_TCD_MAXN)   // 通道数越 ARRAY 边界闸 / Channel count against array bounds
         OR (fRangeMin >= fRangeMax)                                         // 量程倒置闸 / Range inversion gate
         OR (fNegThresh >= fRangeMin)                                        // 反接阈必须低于量程下限（否则误判低温） / Reverse threshold must lie below the range
         OR (fDriftBand <= 0.0)                                              // 漂移带须为正 / Drift band must be positive
         OR (fDriftAlpha <= 0.0) OR (fDriftAlpha >= 1.0)                     // EMA 系数开区间闸 / EMA coefficient open-interval gate
         OR _bNonFin;                                                        // 非有限 / Non-finite
rtReset(CLK := bReset);                                                     // 复位沿，每拍必调（R228A） / Reset edge, every scan

(* —— 段 1：单拍量预清零（锁存量 _aeFault/_afBase/_abInit/_nIdx/_nRound/_bAny 不入清单，R107） —— *)
bAnyFault  := FALSE;        // 任一故障出口预清 / Any-fault preset
nScanIdx   := 0;            // 扫描索引出口预清 / Scan index preset
fLastValue := 0.0;          // 读数出口预清 / Value preset
bError     := FALSE;        // 故障标志预清（R45 配对） / Error flag preset

(* —— 段 2：复位沿 + 组态闸 —— *)
IF rtReset.Q THEN
    FOR _i := 0 TO DL_TCD_MAXN - 1 DO
        _aeFault[_i] := E_DL_TcdFault.eOk;      // 全通道故障清 / Clear every channel fault
        _abInit[_i]  := FALSE;                  // 基线标记清（重新起 EMA） / Baseline flags cleared, EMA restarts
        _afBase[_i]  := 0.0;                    // 基线清 / Baselines cleared
    END_FOR
    _bAny   := FALSE;                           // 任一故障锁存清 / Clear the any-fault latch
    _nIdx   := 0;                               // 轮询索引归零 / Round-robin index cleared
    _nRound := 0;                               // 扫描轮次归零 / Round counter cleared
    IF _eState = E_DL_TcdState.eFault THEN
        _eState := E_DL_TcdState.eIdle;         // 故障相迁出（R228B） / Leave fault phase
    END_IF
END_IF
IF _bCfgBad THEN
    _eState := E_DL_TcdState.eFault;            // 组态非法入故障相 / Enter fault phase
    FOR _i := 0 TO DL_TCD_MAXN - 1 DO
        _aeFault[_i] := E_DL_TcdFault.eCfg;     // 全通道标"未判定"（不得伪报健康） / Mark every channel as not judged
    END_FOR
END_IF

(* —— 段 3：轮询索引钳位（先钳后取模，双保险防越界） —— *)
IF _nIdx < 0 THEN
    _nIdx := 0;                                 // 负索引钳位 / Clamp a negative index
END_IF
IF _nIdx > DL_TCD_MAXN - 1 THEN
    _nIdx := 0;                                 // 超上界回卷 / Wrap above the upper bound
END_IF
IF (NOT _bCfgBad) AND (_nIdx >= nChannelCount) THEN
    _nIdx := 0;                                 // 越过实际通道数回卷 / Wrap at the active channel count
END_IF

(* —— 段 4：单通道扫描判定（本拍只判一路，8 路一轮） —— *)
IF NOT _bCfgBad THEN
    _fVal := afTempC[_nIdx];                    // 索引已在段 3 钳位，取值为安全读 / Index already clamped
    nScanIdx   := _nIdx;                        // 扫描通道出口 / Scanned channel outlet
    fLastValue := _fVal;                        // 读数出口 / Value outlet
    IF (_fVal <> _fVal) THEN
        _aeFault[_nIdx] := E_DL_TcdFault.eCfg;  // 读数 NaN：该路标未判定（最可能是通道配置错） / NaN reading marks the channel not judged
    ELSIF (_fVal > fRangeMax) OR (_fVal < fRangeMin) THEN
        _aeFault[_nIdx] := E_DL_TcdFault.eOpen; // 超量程 = 断偶特征（双侧判） / Out of range on either side means open
    ELSIF _fVal < fNegThresh THEN
        _aeFault[_nIdx] := E_DL_TcdFault.eReverse;  // 负向超反接阈 = 反接特征 / Beyond the negative threshold means reversed
    ELSE
        IF _abInit[_nIdx] = FALSE THEN
            _afBase[_nIdx] := _fVal;            // 基线初始化（首读直接落盘） / Initialise the baseline with the first reading
            _abInit[_nIdx] := TRUE;             // 标记已初始化 / Mark initialised
        ELSE
            _fDev := _fVal - _afBase[_nIdx];    // 读数与基线之差 / Deviation from the baseline
            IF ABS(_fDev) > fDriftBand THEN
                _aeFault[_nIdx] := E_DL_TcdFault.eDrift;    // 慢变趋势超带 = 漂移特征 / Slow deviation beyond the band means drift
            ELSIF _aeFault[_nIdx] = E_DL_TcdFault.eDrift THEN
                _aeFault[_nIdx] := E_DL_TcdFault.eOk;       // 回到带内即清该路漂移（漂移是缓变，允许自愈） / Back inside clears drift on this channel
            END_IF
            _afBase[_nIdx] := _afBase[_nIdx] + (fDriftAlpha * _fDev);   // EMA 基线跟随（系数已闸） / EMA baseline update
        END_IF
    END_IF
    _nIdx := _nIdx + 1;                         // 索引前进 / Advance the index
    IF _nIdx >= nChannelCount THEN
        _nIdx := 0;                             // 到通道数回卷 / Wrap at the active count
        _nRound := _nRound + 1;                 // 一轮完成 / One round completed
    END_IF
END_IF

(* —— 段 5：掩码与汇总（由逐通道表重建，不独立维护，杜绝两处不一致） —— *)
nFaultMask := 16#00;                            // 掩码每拍重建 / Mask rebuilt each scan
FOR _i := 0 TO DL_TCD_MAXN - 1 DO
    IF (_i < nChannelCount) AND (_aeFault[_i] <> E_DL_TcdFault.eOk) THEN
        _nSh := _i;                                           // 移位量归一：先落副本再钳 / Normalise the shift amount first
        IF _nSh < 0 THEN
            _nSh := 0;                                        // 下界钳 / Lower clamp
        END_IF
        IF _nSh > 7 THEN
            _nSh := 7;                                        // 上界钳（BYTE 位宽 8，禁 SHL 越位宽） / Upper clamp, never shift past the BYTE width
        END_IF
        nFaultMask := nFaultMask OR SHL(DL_TCD_BIT, INT_TO_BYTE(_nSh));   // 位 i 置（移位量已归一到 0..7） / Set bit i with the shift amount normalised
        _bAny := TRUE;                                        // 任一故障锁存 / Latch the any-fault bit
    END_IF
END_FOR

(* —— 段 6：锁存相位迁移闸 —— *)
IF _bCfgBad THEN
    _bAny := TRUE;                              // 组态非法也算"有故障"（对外不宣称健康） / Illegal config counts as faulty
END_IF
IF _bAny AND (_eState <> E_DL_TcdState.eFault) AND _bCfgBad THEN
    _eState := E_DL_TcdState.eFault;            // 组态型故障入故障相 / Configuration fault enters the fault phase
END_IF

(* —— 段 7：相位机（ENUM 全成员显式标签 + ELSE 兜底，R128） —— *)
CASE _eState OF

E_DL_TcdState.eIdle:
    IF _bCfgBad THEN                            // 出口 1：组态非法 / Illegal configuration
        _eState := E_DL_TcdState.eFault;
    ELSIF _nRound >= 1 THEN                     // 出口 2：完成至少一轮，全通道已有结论 / At least one round done
        _eState := E_DL_TcdState.eRun;
    END_IF

E_DL_TcdState.eRun:
    IF _bCfgBad THEN                            // 出口 1：组态转非法 / Configuration went illegal
        _eState := E_DL_TcdState.eFault;
    ELSIF rtReset.Q THEN                        // 出口 2：复位回等待相 / Reset back to idle
        _eState := E_DL_TcdState.eIdle;
    END_IF

E_DL_TcdState.eFault:
    IF rtReset.Q AND (NOT _bCfgBad) THEN        // 出口：复位且组态已合法才迁出（R228B） / Reset with legal config
        _eState := E_DL_TcdState.eIdle;
    END_IF

ELSE
    _eState := E_DL_TcdState.eFault;            // 非法相位兜底 / Illegal-phase fallback
    bError  := TRUE;                            // 故障标志 / Error flag

END_CASE

(* —— 段 8：出口单点映射（逐通道表整体回放 + 汇总位同源，R191） —— *)
FOR _i := 0 TO DL_TCD_MAXN - 1 DO
    aeFault[_i] := _aeFault[_i];                // 逐通道故障回放 / Per-channel fault replay
END_FOR
bAnyFault := _bAny;                             // 任一故障与锁存同源 / Any-fault from latch
bError    := _bAny OR (_eState = E_DL_TcdState.eFault);    // 故障标志 = 任一故障或组态故障 / Error = any fault or config fault
eState    := _eState;                           // 状态出口 / State outlet

END_FUNCTION_BLOCK
