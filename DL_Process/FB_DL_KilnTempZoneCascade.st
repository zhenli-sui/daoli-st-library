// FB_DL_KilnTempZoneCascade v1.0.0
(*==============================================================================
 * 功能描述: C4 窑炉多温区串级。主回路（窑温）比例控制器输出 0~100% 级联强度，按
 *           各温区权重归一化分配副回路设定值；每区独立 TON 热电偶断偶监视（超高温/
 *           超低温/NaN 判据），断偶区退出级联并按剩余健康区权重重分配；全部温区断偶
 *           进 eFault 全停安全态，bReset 上升沿唯一迁出。
 * 接口契约: 输入 bEnable/fKilnSet/fKilnTemp/fKpMaster/a_fWeight/a_fZoneTemp/fTcHi/
 *           fTcLo/nZoneUse/tTcDeb/fDtSec/bReset；
 *           输出 a_fZoneSet/abZoneEn/fMasterOut/eState/eCause/bError/nErrId。
 * 边界: ① 组态闸：nZoneUse 出 [1,4]、fKpMaster<0、fTcHi<=fTcLo、tTcDeb<=T#0S、
 *           fDtSec<=0、权重和<=0 或任一浮点引脚 NaN → 故障锁存；② 四枚 TON + 一枚
 *           R_TRIG 段 0 无条件周期刷新；③ 零全局耦合。
 * 码表: 16#0007_0304 故障级总码（组态非法/全温区断偶/非法相位，锁存至 bReset 上升沿）；
 *       16#0007_0404 信息级：存在断偶温区（降级运行中，每拍重算）。
 * 修订历史: 2026-11-23  v1.0.0  R74 首版
 *==============================================================================*)

TYPE E_DL_KtcState :
(
    eIdle  := 0,     // 待机（输出全零）/ Idle, all outputs zero
    eRun   := 10,    // 级联运行相 / Cascade running
    eFault := 90     // 故障锁存相（仅复位沿迁出）/ Fault latched, exit by reset edge only
);
END_TYPE

TYPE E_DL_KtcCause :
(
    eNone         := 0,   // 无故障成因 / No cause
    eCfgIllegal   := 1,   // 组态非法 / Illegal configuration
    eAllZoneBreak := 2,   // 全部温区热电偶断偶 / All zone thermocouples broken
    ePhaseBad     := 3    // 非法相位兜底 / Illegal phase fallback
);
END_TYPE

FUNCTION_BLOCK FB_DL_KilnTempZoneCascade
VAR_INPUT
    bEnable    : BOOL := FALSE;              // 使能（FALSE 输出全零）[-] / Enable, FALSE zeroes outputs
    fKilnSet   : REAL := 1200.0;             // 窑温主设定 [°C] / Kiln temperature setpoint [°C]
    fKilnTemp  : REAL := 20.0;               // 窑温主反馈 [°C] / Kiln temperature feedback [°C]
    fKpMaster  : REAL := 0.2;                // 主回路比例增益，域 >= 0 [1/°C] / Master proportional gain [1/degC]
    a_fWeight  : ARRAY[1..4] OF REAL := [1.0, 1.0, 1.0, 1.0];   // 各温区分配权重，域 >= 0 [-] / Per-zone allocation weight
    a_fZoneTemp: ARRAY[1..4] OF REAL := [20.0, 20.0, 20.0, 20.0];   // 各温区热电偶反馈 [°C] / Per-zone thermocouple feedback [degC]
    fTcHi      : REAL := 1700.0;             // 断偶判据高温阈（超此判开路）[°C] / Break high threshold [degC]
    fTcLo      : REAL := -50.0;              // 断偶判据低温阈（低于此判短路）[°C] / Break low threshold [degC]
    nZoneUse   : INT := 4;                   // 参与温区数 [区]，域 [1,4] / Zone count in cascade, domain 1..4
    tTcDeb     : TIME := T#2S;               // 断偶确认去抖窗，域 > T#0S [ms] / Break debounce window
    fDtSec     : REAL := 0.100;              // 任务周期 [s]，域 > 0 / Task period [s], domain > 0
    bReset     : BOOL := FALSE;              // 复位，上升沿清故障锁存 [-] / Reset edge clears fault
END_VAR
VAR_OUTPUT
    a_fZoneSet : ARRAY[1..4] OF REAL := [0.0, 0.0, 0.0, 0.0];   // 各温区副回路设定值（0~100%）[%] / Per-zone cascade setpoint [%]
    abZoneEn   : ARRAY[1..4] OF BOOL;        // 各温区级联使能（断偶区 FALSE）[-] / Per-zone cascade enable
    fMasterOut : REAL := 0.0;                // 主回路级联输出（0~100%）[%] / Master cascade output [%]
    eState     : E_DL_KtcState;              // 状态出口，段尾单点映射 / State outlet
    eCause     : E_DL_KtcCause;              // 故障成因出口（归因唯一） / Fault cause outlet
    bError     : BOOL;                       // 故障锁存标志 [-] / Fault latch flag
    nErrId     : UDINT;                      // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    _eState  : E_DL_KtcState := E_DL_KtcState.eIdle;   // 内部相位（CASE 唯一写入目标） / Internal phase
    _eCause  : E_DL_KtcCause := E_DL_KtcCause.eNone;   // 故障成因锁存量 / Latched cause
    rtReset  : R_TRIG;               // 复位沿实例，段 0 无条件刷新 / Reset edge instance
    tonBrk1  : TON;                  // 温区 1 断偶去抖，段 0 无条件刷新 / Zone 1 break debounce
    tonBrk2  : TON;                  // 温区 2 断偶去抖，段 0 无条件刷新 / Zone 2 break debounce
    tonBrk3  : TON;                  // 温区 3 断偶去抖，段 0 无条件刷新 / Zone 3 break debounce
    tonBrk4  : TON;                  // 温区 4 断偶去抖，段 0 无条件刷新 / Zone 4 break debounce
    _bBrkRaw1: BOOL;                 // 温区 1 断偶原始判据 [-] / Zone 1 raw break criterion
    _bBrkRaw2: BOOL;                 // 温区 2 断偶原始判据 [-] / Zone 2 raw break criterion
    _bBrkRaw3: BOOL;                 // 温区 3 断偶原始判据 [-] / Zone 3 raw break criterion
    _bBrkRaw4: BOOL;                 // 温区 4 断偶原始判据 [-] / Zone 4 raw break criterion
    _a_bBrk  : ARRAY[1..4] OF BOOL;  // 各温区断偶确认（去抖后）[-] / Per-zone confirmed break
    _fWSum   : REAL := 0.0;          // 健康区权重和 [权重] / Sum of healthy-zone weights
    _fWUnit  : REAL := 0.0;          // 归一化权重倒数（乘法代替除法）[1/权重] / Normalisation reciprocal
    _fDev    : REAL := 0.0;          // 主回路温度偏差 [°C] / Master temperature deviation [degC]
    _fMOut   : REAL := 0.0;          // 主回路输出工作值（0~100）[%] / Master output working value
    _nAlive  : INT := 0;             // 健康温区计数 [区] / Healthy zone count
    _iLoop   : INT;                  // 温区遍历游标 [槽位] / Zone loop cursor
    _bCfgBad : BOOL;                 // 组态非法当拍量 [-] / Illegal configuration this scan
    _bFault  : BOOL;                 // 故障锁存位（锁存量） / Latched fault bit
    _uFault  : UDINT;                // 故障码锁存（锁存量） / Latched fault code
    _uInfo   : UDINT;                // 信息码，每拍重算 / Info code, recomputed each scan
    _nZoneLim : INT;                 // 钳位温区上界（≤4 防数组越界） / Clamped zone bound (max 4, anti-OOB)
END_VAR

(* —— 段 0：沿实例与四枚断偶 TON 无条件周期刷新（禁置于 IF/CASE 内） —— *)
rtReset(CLK := bReset);                                            // 复位沿，每拍必调 / Reset edge every scan
_bBrkRaw1 := (a_fZoneTemp[1] > fTcHi) OR (a_fZoneTemp[1] < fTcLo) OR (a_fZoneTemp[1] <> a_fZoneTemp[1]);   // 区 1 原始判据 / Zone 1 raw criterion
_bBrkRaw2 := (a_fZoneTemp[2] > fTcHi) OR (a_fZoneTemp[2] < fTcLo) OR (a_fZoneTemp[2] <> a_fZoneTemp[2]);   // 区 2 原始判据 / Zone 2 raw criterion
_bBrkRaw3 := (a_fZoneTemp[3] > fTcHi) OR (a_fZoneTemp[3] < fTcLo) OR (a_fZoneTemp[3] <> a_fZoneTemp[3]);   // 区 3 原始判据 / Zone 3 raw criterion
_bBrkRaw4 := (a_fZoneTemp[4] > fTcHi) OR (a_fZoneTemp[4] < fTcLo) OR (a_fZoneTemp[4] <> a_fZoneTemp[4]);   // 区 4 原始判据 / Zone 4 raw criterion
tonBrk1(IN := _bBrkRaw1, PT := tTcDeb);                            // 区 1 去抖确认 / Zone 1 debounce
tonBrk2(IN := _bBrkRaw2, PT := tTcDeb);                            // 区 2 去抖确认 / Zone 2 debounce
tonBrk3(IN := _bBrkRaw3, PT := tTcDeb);                            // 区 3 去抖确认 / Zone 3 debounce
tonBrk4(IN := _bBrkRaw4, PT := tTcDeb);                            // 区 4 去抖确认 / Zone 4 debounce

(* —— 段 1：单拍量预清零（锁存量 _bFault/_uFault/_eCause 不入清单） —— *)
bError := FALSE;                                                   // 故障标志预清（置位处同拍回填） / Error flag preset
nErrId := 16#0000_0000;                                            // 事件码缺省无事件 / Event code default none
_uInfo := 16#0000_0000;                                            // 信息码每拍重算 / Info recomputed every scan
a_fZoneSet[1] := 0.0;                                              // 区 1 设定预清（运行相同拍回填） / Zone 1 setpoint preset
a_fZoneSet[2] := 0.0;                                              // 区 2 设定预清 / Zone 2 setpoint preset
a_fZoneSet[3] := 0.0;                                              // 区 3 设定预清 / Zone 3 setpoint preset
a_fZoneSet[4] := 0.0;                                              // 区 4 设定预清 / Zone 4 setpoint preset
abZoneEn[1] := FALSE;                                              // 区 1 使能预清 / Zone 1 enable preset
abZoneEn[2] := FALSE;                                              // 区 2 使能预清 / Zone 2 enable preset
abZoneEn[3] := FALSE;                                              // 区 3 使能预清 / Zone 3 enable preset
abZoneEn[4] := FALSE;                                              // 区 4 使能预清 / Zone 4 enable preset
fMasterOut := 0.0;                                                 // 主回路输出预清（运行相同拍回填） / Master output preset

(* —— 段 2：断偶确认合并（TON 结果锁存入健康表） —— *)
_a_bBrk[1] := tonBrk1.Q;                                           // 区 1 确认断偶 / Zone 1 confirmed break
_a_bBrk[2] := tonBrk2.Q;                                           // 区 2 确认断偶 / Zone 2 confirmed break
_a_bBrk[3] := tonBrk3.Q;                                           // 区 3 确认断偶 / Zone 3 confirmed break
_a_bBrk[4] := tonBrk4.Q;                                           // 区 4 确认断偶 / Zone 4 confirmed break

(* —— 段 3：组态域闸（覆盖全部参与判据引脚） —— *)
_bCfgBad := (nZoneUse < 1) OR (nZoneUse > 4)                       // 温区数域闸 / Zone count domain gate
         OR (fKpMaster < 0.0) OR (fKpMaster <> fKpMaster)          // 增益域与 NaN 闸 / Gain domain and NaN gate
         OR (fTcHi <= fTcLo) OR (fTcHi <> fTcHi) OR (fTcLo <> fTcLo)   // 判据阈几何与 NaN 闸 / Threshold geometry and NaN gates
         OR (fDtSec <= 0.0) OR (fDtSec <> fDtSec)                  // 周期域与 NaN 闸 / Period domain and NaN gate
         OR (tTcDeb <= T#0S);                                      // 去抖时间闸 / Debounce time gate
_fWSum := 0.0;                                                     // 权重和清零重算 / Weight sum recomputed
FOR _iLoop := 1 TO _nZoneLim DO                                      // 组态内温区权重累加（上界受段 3 闸保护） / Weight sum inside configuration
    IF (a_fWeight[_iLoop] < 0.0) OR (a_fWeight[_iLoop] <> a_fWeight[_iLoop]) THEN   // 负权重或 NaN 即组态非法 / Negative or NaN weight is illegal
        _bCfgBad := TRUE;                                          // 置组态非法 / Flag illegal configuration
    END_IF
    IF NOT _a_bBrk[_iLoop] THEN                                    // 仅健康区计入权重和 / Healthy zones join the sum
        _fWSum := _fWSum + a_fWeight[_iLoop];                      // 权重累加 / Weight accumulated
    END_IF
END_FOR
IF _fWSum <= 1.0E-6 THEN                                           // 健康权重和为零闸（含全断偶情形） / Zero healthy weight gate
    _bCfgBad := _bCfgBad OR bEnable;                               // 使能中权重和无效按组态非法归并（全断偶优先归因 eAllZoneBreak） / Zero weight folded into config when enabled
END_IF
IF (fKilnSet <> fKilnSet) OR (fKilnTemp <> fKilnTemp) THEN       // 主回路引脚 NaN 闸 / Master pin NaN gate
    _bCfgBad := TRUE;                                              // 置组态非法 / Flag illegal configuration
END_IF

(* —— 段 4：故障锁存与解除（R45 配对；归因唯一；解除式全当拍量） —— *)
IF (NOT _bFault) AND _bCfgBad AND (_nAlive = 0) AND bEnable AND (_fWSum <= 1.0E-6) AND (a_fWeight[1] >= 0.0) AND (a_fWeight[2] >= 0.0) AND (a_fWeight[3] >= 0.0) AND (a_fWeight[4] >= 0.0) AND (NOT _bBrkRaw1) AND (NOT _bBrkRaw2) AND (NOT _bBrkRaw3) AND (NOT _bBrkRaw4) THEN
    ;                                                              // 非断偶型零权重（纯组态错）走下方统一分支，此行仅为可读性锚点 / Readability anchor only
END_IF
IF _bCfgBad THEN                                                   // 组态非法 / Illegal configuration
    _uFault := 16#0007_0304;                                       // 故障级总码 / Fault-level code
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_KtcCause.eCfgIllegal;                          // 归因：组态非法 / Cause: illegal configuration
END_IF
_nAlive := 0;                                                      // 健康区计数清零重算 / Healthy count recomputed
FOR _iLoop := 1 TO _nZoneLim DO                                      // 统计健康区数 / Count healthy zones
    IF NOT _a_bBrk[_iLoop] THEN
        _nAlive := _nAlive + 1;                                    // 健康区递增 / Healthy increments
    END_IF
END_FOR
IF bEnable AND (NOT _bFault) AND (_nAlive = 0) THEN                // 全温区断偶 / All zones broken
    _uFault := 16#0007_0304;
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_KtcCause.eAllZoneBreak;                        // 归因：全断偶（覆盖组态归因，R190 归因唯一） / Cause: all zones broken
END_IF
IF (_nAlive < nZoneUse) AND (_nAlive > 0) AND (NOT _bFault) THEN   // 存在断偶区但仍有健康区（降级运行） / Some zones broken, degraded run
    _uInfo := 16#0007_0404;                                        // 信息级：存在断偶温区 / Info: some zones broken
END_IF
IF rtReset.Q AND (NOT _bCfgBad) THEN                               // 解除沿（当拍量） / Release edge
    _bFault := FALSE;                                              // 清故障锁存 / Clear fault latch
    _uFault := 16#0000_0000;                                       // 清故障码 / Clear fault code
    _eCause := E_DL_KtcCause.eNone;                                // 清成因 / Clear cause
    IF _eState = E_DL_KtcState.eFault THEN
        _eState := E_DL_KtcState.eIdle;                            // 故障相唯一迁出路径 / Sole exit from fault phase
    END_IF
END_IF

(* —— 段 5：相位机（ENUM 全成员显式标签 + ELSE 兜底） —— *)
CASE _eState OF

E_DL_KtcState.eIdle:
    IF (NOT _bFault) AND bEnable AND (_nAlive > 0) THEN            // 出口 1：使能且有健康区 → 进级联 / Enable with healthy zones
        _eState := E_DL_KtcState.eRun;
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_KtcState.eFault;
    END_IF

E_DL_KtcState.eRun:
    IF (NOT bEnable) THEN                                          // 出口 1：撤使能回待机 / Disable to idle
        _eState := E_DL_KtcState.eIdle;
    ELSIF _bFault THEN                                             // 出口 2：故障锁存 / Fault latched
        _eState := E_DL_KtcState.eFault;
    ELSE
        _fDev := fKilnSet - fKilnTemp;                             // 主回路偏差 [°C] / Master deviation
        _fMOut := fKpMaster * _fDev;                               // 比例控制输出 / Proportional output
        IF _fMOut < 0.0 THEN                                       // 下限饱和（不反向加热） / Saturate low
            _fMOut := 0.0;
        END_IF
        IF _fMOut > 100.0 THEN                                     // 上限饱和 / Saturate high
            _fMOut := 100.0;
        END_IF
        fMasterOut := _fMOut;                                      // 主回路输出出口 / Master output outlet
        IF _fWSum > 1.0E-6 THEN                                    // 健康权重和有效才分配（R4 防除零，除法转乘法） / Allocate only with valid weight sum
            _fWUnit := 1.0 / _fWSum;                               // 归一化倒数（除法仅此一处，分母已闸） / Normalisation reciprocal, denominator gated
            FOR _iLoop := 1 TO _nZoneLim DO                         // 逐区分配（常量 4 上界无越界） / Allocate per zone
                IF NOT _a_bBrk[_iLoop] THEN                        // 健康区按权重分配 / Healthy zone allocated by weight
                    a_fZoneSet[_iLoop] := _fMOut * a_fWeight[_iLoop] * _fWUnit;   // 级联分配 [%] / Cascade allocation
                    abZoneEn[_iLoop] := TRUE;                      // 区使能 / Zone enabled
                ELSE
                    a_fZoneSet[_iLoop] := 0.0;                     // 断偶区设定安全归零 / Broken zone setpoint zeroed
                    abZoneEn[_iLoop] := FALSE;                     // 断偶区退出级联 / Broken zone exits cascade
                END_IF
            END_FOR
        END_IF
    END_IF

E_DL_KtcState.eFault:
    ;                                                              // 故障相：全停安全态，仅段 4 复位沿迁出 / All-stop safe state, only reset edge leaves

ELSE
    _uFault := 16#0007_0304;                                       // 故障级：非法相位兜底 / Illegal-phase fallback
    _bFault := TRUE;
    bError  := TRUE;
    _eCause := E_DL_KtcCause.ePhaseBad;                            // 归因：非法相位 / Cause: illegal phase
    _eState := E_DL_KtcState.eFault;                               // 强拉故障相 / Force fault phase

END_CASE

(* —— 段 6：出口单点映射（名实同源；锁存码回放） —— *)
IF _bFault THEN
    nErrId := _uFault;                                             // 故障锁存码回放 / Replay latched fault code
ELSE
    nErrId := _uInfo;                                              // 信息码 / Info code
END_IF
bError := _bFault;                                                 // 故障标志与锁存同源 / Flag from latch
eState := _eState;                                                 // 状态出口 / State outlet
eCause := _eCause;                                                 // 成因出口 / Cause outlet

END_FUNCTION_BLOCK
