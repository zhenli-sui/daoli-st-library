(*
  FB_DL_CartonErectVacMonitor  —  纸箱成型吸盘真空建立时长与老化漂移监视 / Carton erector vacuum build-time and ageing monitor
  分类 Category : DL_Device
  码位 Code     : 16#03_2_10
  版本 Version  : 1.0.0
  来源 Source   : t2-1-lgf-measurement — IEC 61131-3 标准语义的道莅防御性实现
  溯源 Origin   : LGF 测量类文档公开语义借鉴（基线/漂移/样本中值），clean-room 实现，未复制源码行
  功能 Function : 1) 每次取料（bPickStart 上升沿）启动一次真空建立计时，真空度（负压绝对值）达 fVacTargetKpa
                     即记录本次建立时长 fBuildTimeMs；超 tBuildMax 未达则置 bBuildTimeout；
                  2) 建立时长入环形样本缓冲（长度 DL_BASE_MAX），基线 fBaselineMs 取**中值**（抗野值）；
                  3) 当前时长相对基线的漂移 fDriftPct 超 fDriftWarnPct 且连续 nWarnCycles 次 → bAgingWarn（吸盘老化）；
                  4) 样本数 < DL_MIN_SAMPLES 时不出漂移结论：bAgingWarn := FALSE、fDriftPct := 0（R191 显式声明）。
  边界 Boundary : ① fVacTargetKpa <= 0 判组态错 0210（建立判据门限为 0 会让"建立"恒成立）；
                      tBuildMax <= 0 / fDriftWarnPct <= 0 / nWarnCycles < 1 同判组态错；
                  ② nBaselineSamples > DL_BASE_MAX 时钳制到 DL_BASE_MAX 并置信息级 0110（不静默截断）；
                  ③ 建立时长为 0（同拍达成，或计时分辨率不足）走下限保护：分母用 MAX(基线, 1 ms)，
                     基线未建立（= 0）时 fDriftPct 直接置 0，绝不产生 inf/NaN；
                  ④ bBuildTimeout 为保持型（故障级 0220），清除路径 = rtReset.Q 或「下一次取料建立成功」；
                  ⑤ bAgingWarn 为维护级告警（信息级 0130，**不置 bError**）：漂移回落至门限内即自行释放；
                  ⑥ 注入件故障（iVac.bFault）时本件照常计时但置信息级 0140 并抑制漂移结论（数据不可信，
                     不得把注入件故障记成吸盘老化，R190 归因唯一）。
  依赖 Depends  : I_DL_VacuumGenerator（DL_Device 既有契约，注入不实例化）；
                  仅 Standard.library（TON / R_TRIG / ABS / MIN / MAX）
  同拍双窗配比  : tBuildMax（单次建立上限）与心跳窗 DL_HEART_WINDOW 不同源；配比约束
                  tBuildMax >= DL_HEART_WINDOW，保证建立过程中至少一次判活（R100）

  码表 Error codes（本件格 03_2_10，子码步进 +0x10）:
    16#0003_0210 故障级：组态非法（真空目标 <= 0 / 建立上限 <= 0 / 漂移门限 <= 0 / 预警次数 < 1）
    16#0003_0220 故障级：真空建立超时（tBuildMax 内未达 fVacTargetKpa，保持型）
    16#0003_0230 故障级：状态机落 ELSE 兜底（非法相位 ID）
    16#0003_0110 信息级：nBaselineSamples 超数组上限已钳制（不置 bError）
    16#0003_0120 信息级：样本数不足，本拍不出漂移结论（不置 bError）
    16#0003_0130 信息级：吸盘老化预警已成立（维护级，不置 bError）
    16#0003_0140 信息级：注入件故障，漂移结论抑制（不置 bError）

  修订历史 Revision :
    2026-11-18  v1.0.0  R37 首版
*)

TYPE E_DL_VacBuildState :
(
    eIdle    := 0,   // 空闲：等取料触发 / Idle, waiting for a pick trigger
    eBuilding := 10, // 建立中：本次真空建立计时进行中 / Building, timing the present evacuation
    eMeasured := 20, // 已测量：本次入样本缓冲，等下一次 / Measured, the sample is buffered
    eFault   := 90   // 故障：组态非法或建立超时锁定 / Fault, illegal configuration or a latched build timeout
);
END_TYPE

FUNCTION_BLOCK FB_DL_CartonErectVacMonitor
VAR_INPUT
    bEnable        : BOOL := FALSE;             // 总使能，FALSE 时不启动计时 / Master enable, low level stops timing
    bReset         : BOOL := FALSE;             // 复位，上升沿清故障锁存 / Reset, rising edge clears the latch
    bPickStart     : BOOL := FALSE;             // 取料起始触发（上升沿受理）/ Pick trigger, rising edge
    fVacTargetKpa  : REAL := 60.0;              // 真空目标（负压绝对值）[kPa]，域 > 0 / Vacuum target magnitude [kPa]
    tBuildMax      : TIME := T#1500MS;          // 单次建立时长上限 [ms]，域 > 0 / Maximum build time [ms]
    nBaselineSamples : INT := 9;                // 基线样本数 [个]，域 3~DL_BASE_MAX / Baseline sample count
    fDriftWarnPct  : REAL := 30.0;              // 漂移预警门限 [%]，域 > 0 / Drift warning threshold [%]
    nWarnCycles    : INT := 3;                  // 连续超门限次数 [次]，域 >= 1 / Consecutive exceed cycles
END_VAR
VAR_OUTPUT
    fBuildTimeMs   : REAL;                      // 本次建立时长 [ms] / Build time of the present pick [ms]
    fBaselineMs    : REAL;                      // 基线建立时长（样本中值）[ms] / Baseline build time, the sample median [ms]
    fDriftPct      : REAL;                      // 相对基线漂移 [%]，已限幅 / Drift against the baseline [%], clamped
    bAgingWarn     : BOOL;                      // 吸盘老化预警（维护级）/ Suction-cup ageing warning
    bBuildTimeout  : BOOL;                      // 建立超时（保持型）/ Build timeout, held
    nSampleCount   : INT;                       // 当前有效样本数 [个] / Number of valid samples
    bValid         : BOOL;                      // 判据可用标志 / Criteria usable
    bError         : BOOL;                      // 故障标志，派生自锁存 / Fault flag derived from the latch
    nErrId         : UDINT;                     // 事件码，0 = 无事件 / Event code, 0 = no event
    eStateOut      : E_DL_VacBuildState;        // 状态出口，段尾单点映射 / State outlet, mapped at the tail
END_VAR
VAR_IN_OUT
    iVac           : I_DL_VacuumGenerator;      // 真空发生器接口引用（注入，不实例化）/ Vacuum generator reference, injected
END_VAR
VAR
    tonBuild     : TON;                         // 单次建立计时，每拍无条件调用 / Build timer, called unconditionally
    tonHeart     : TON;                         // 周期心跳窗，自复位 / Periodic heartbeat window, self-resetting
    rtReset      : R_TRIG;                      // 复位上升沿 / Reset rising edge
    rtPick       : R_TRIG;                      // 取料上升沿 / Pick rising edge
    _eState      : E_DL_VacBuildState := E_DL_VacBuildState.eIdle;  // 内部相位（CASE 唯一写入目标）/ Internal phase
    _uFault      : UDINT;                       // 故障码锁存 / Latched fault code
    _uInfo       : UDINT;                       // 信息码，每拍重算 / Information code, recomputed per scan
    _bFault      : BOOL;                        // 故障锁存位 / Latched fault bit
    _bCfgBad     : BOOL;                        // 组态非法聚合 / Configuration invalid aggregate
    _bTimeout    : BOOL;                        // 建立超时保持量 / Held timeout value
    _bAging      : BOOL;                        // 老化预警保持量 / Held ageing warning
    _bInjectFault : BOOL;                       // 注入件故障 / Injected component fault
    _bVacReached : BOOL;                        // 真空已达目标 / Vacuum reached the target
    _bSampleNew  : BOOL;                        // 本次已入样本（单拍）/ A sample was buffered this scan
    _bBuildBrk   : BOOL := TRUE;                // 建立计时断输入一拍 / One-scan build break
    _bHeartBrk   : BOOL := TRUE;                // 心跳窗断输入一拍 / One-scan heartbeat break
    _nBaseUse    : INT;                         // 生效基线样本数，已钳制 [个] / Effective baseline sample count
    _nFill       : INT;                         // 已填样本数 [个] / Filled samples
    _nWriteIdx   : INT;                         // 环形写指针 [索引] / Ring write index
    _nWarnCnt    : INT;                         // 连续超门限计数 [次] / Consecutive exceed counter
    _nSortIdx    : INT;                         // 排序循环索引 [索引] / Sorting loop index
    _fSample     : ARRAY[0..15] OF REAL;        // 样本缓冲（建立时长）[ms] / Sample buffer [ms]
    _fMed        : REAL;                        // 中值 [ms] / Median [ms]
    _fBase       : REAL;                        // 基线保持量 [ms] / Held baseline [ms]
    _fDrift      : REAL;                        // 漂移保持量 [%] / Held drift [%]
    _fDevDen     : REAL;                        // 漂移分母（下限保护）[ms] / Drift denominator with a floor [ms]
    _fSortKey    : REAL;                        // 排序临时量（保留字，未参与秩计数法）[ms] / Sorting scratch reserved
    _nJ          : INT;                         // 内层循环索引 [索引] / Inner loop index
    _nRank       : INT;                         // 秩计数（严格小于本点的样本数）[个] / Rank counter
END_VAR
VAR CONSTANT
    DL_BASE_MAX   : INT := 16;          // 样本缓冲声明长度 [个] / Declared sample buffer length
    DL_MIN_SAMPLES : INT := 3;          // 出漂移结论的最少样本数 [个] / Minimum samples before a verdict
    DL_MS_FLOOR   : REAL := 1.0;        // 时长下限保护 [ms] / Duration floor to avoid division by zero
    DL_DRIFT_CLAMP_PCT : REAL := 500.0; // 漂移限幅 [%] / Drift clamp [%]
    DL_VAC_LIM_KPA : REAL := 200.0;     // 真空有限性上限 [kPa] / Vacuum magnitude ceiling [kPa]
    DL_HEART_WINDOW : TIME := T#2S;     // 心跳观察窗 [ms]，自复位节拍 / Heartbeat window, self-resetting
END_VAR

(* —— 段 0：定时器与边缘检测无条件周期刷新（R182：调用语句不得置于 IF / CASE 内） —— *)
rtReset(CLK := bReset);                                          // 复位上升沿，每拍必调
rtPick(CLK := bPickStart);                                       // 取料上升沿，每拍必调
tonHeart(IN := (NOT tonHeart.Q) AND (NOT _bHeartBrk), PT := DL_HEART_WINDOW);  // 心跳窗自复位
_bHeartBrk := FALSE;                                             // 断输入拍在调用后自清
tonBuild(IN := (_eState = E_DL_VacBuildState.eBuilding) AND (NOT _bBuildBrk), PT := tBuildMax);  // 建立计时
_bBuildBrk := FALSE;                                             // 断输入拍在调用后自清

(* —— 段 1：单拍量预清零（样本 / 基线 / 计数不入清单，R187①） —— *)
_uInfo      := 16#0000_0000;   // 信息码每拍重算
bError      := FALSE;          // 故障出口每拍重算，段 7 由锁存派生
bValid      := FALSE;          // 可用标志缺省 FALSE
_bCfgBad    := FALSE;          // 组态非法预清零
_bSampleNew := FALSE;          // 入样本单拍标志预清零
_bVacReached := FALSE;         // 真空达标判据预清零

(* —— 段 2：复位沿清锁存与保持量（R188 双路径） —— *)
IF rtReset.Q THEN
    _bFault   := FALSE;            // 复位沿清锁存位
    _uFault   := 16#0000_0000;     // 复位沿清锁存码
    _bTimeout := FALSE;            // 清建立超时保持量
    _bAging   := FALSE;            // 清老化预警保持量
    _nWarnCnt := 0;                // 清连续超门限计数
END_IF
IF (_uFault = 16#0003_0220) AND (NOT _bTimeout) THEN
    _uFault := 16#0000_0000;       // 按码专清：超时保持量已释放 → 对应码清除
    _bFault := FALSE;              // 锁存位同步清
END_IF

(* —— 段 3：组态域闸（覆盖全部参与换算的引脚，R151） —— *)
IF (fVacTargetKpa <> fVacTargetKpa) OR (fVacTargetKpa <= 0.0) OR (fVacTargetKpa > DL_VAC_LIM_KPA) THEN
    _bCfgBad := TRUE;              // 真空目标非法（建立判据门限）
END_IF
IF TIME_TO_DINT(tBuildMax) <= 0 THEN
    _bCfgBad := TRUE;              // 建立上限非法
END_IF
IF (fDriftWarnPct <> fDriftWarnPct) OR (fDriftWarnPct <= 0.0) THEN
    _bCfgBad := TRUE;              // 漂移门限非法
END_IF
IF nWarnCycles < 1 THEN
    _bCfgBad := TRUE;              // 连续次数门限非法
END_IF
_nBaseUse := nBaselineSamples;     // 生效样本数初值
IF _nBaseUse > DL_BASE_MAX THEN
    _nBaseUse := DL_BASE_MAX;      // 上限钳制（不静默截断，置信息码 0110）
    _uInfo := 16#0003_0110;        // 信息级：样本数超缓冲上限已钳制
END_IF
IF _nBaseUse < DL_MIN_SAMPLES THEN
    _nBaseUse := DL_MIN_SAMPLES;   // 下限钳制：低于 3 无中值意义
    _uInfo := 16#0003_0110;        // 信息级：样本数过小已抬升至最小可用值
END_IF
IF _bCfgBad THEN
    _uFault := 16#0003_0210;       // 故障级：组态非法
    _bFault := TRUE;               // 锁存位置位（复位沿可清）
    bError  := TRUE;               // 故障标志置位（R45 配对）
    _eState := E_DL_VacBuildState.eFault;  // 进故障相
END_IF

(* —— 段 4：真空反馈判据与注入件故障归因 —— *)
_bInjectFault := iVac.bFault;                                  // 注入件故障（不参与老化归因）
_bVacReached := ABS(iVac.fPressure) >= fVacTargetKpa;          // 真空达标（负压绝对值，分母无）
IF ABS(iVac.fPressure) > DL_VAC_LIM_KPA THEN
    _bCfgBad := TRUE;                                          // 真空反馈非有限/超上界：判据不可信
    _uFault := 16#0003_0210;                                   // 故障级：输入异常归入组态/输入异常码
    _bFault := TRUE;                                           // 锁存
    bError  := TRUE;                                           // 故障标志置位（R45 配对）
    _eState := E_DL_VacBuildState.eFault;                      // 进故障相
    _bVacReached := FALSE;                                     // 坏值不得当作达标
END_IF

(* —— 段 5：相位机（只做迁移与样本入缓冲；出口在段 8） —— *)
CASE _eState OF

E_DL_VacBuildState.eIdle:
    IF rtPick.Q AND bEnable AND (NOT _bFault) AND (NOT _bCfgBad) THEN
        _eState := E_DL_VacBuildState.eBuilding;          // 取料触发：进建立相
        _bBuildBrk := TRUE;                               // 建立计时从零
    END_IF

E_DL_VacBuildState.eBuilding:
    IF (NOT bEnable) THEN
        _eState := E_DL_VacBuildState.eIdle;              // 失能：放弃本次测量
    ELSIF _bVacReached THEN
        fBuildTimeMs := TIME_TO_REAL(tonBuild.ET);        // 本次建立时长 [ms]
        IF fBuildTimeMs < DL_MS_FLOOR THEN
            fBuildTimeMs := DL_MS_FLOOR;                  // 下限保护（同拍达成时不出现 0 时长）
        END_IF
        _fSample[_nWriteIdx] := fBuildTimeMs;             // 入环形样本缓冲
        _nWriteIdx := (_nWriteIdx + 1) MOD DL_BASE_MAX;   // 写指针推进（移位量已归一）
        IF _nFill < DL_BASE_MAX THEN
            _nFill := _nFill + 1;                         // 已填样本数饱和到缓冲长度
        END_IF
        _bSampleNew := TRUE;                              // 本拍已入样本（单拍）
        _bTimeout := FALSE;                               // 建立成功：超时保持量释放（按码专清的另一条边）
        _eState := E_DL_VacBuildState.eMeasured;          // 进已测量相
    ELSIF tonBuild.Q THEN
        _bTimeout := TRUE;                                // 建立超时保持量
        _uFault := 16#0003_0220;                          // 故障级：真空建立超时
        _bFault := TRUE;                                  // 锁存
        bError  := TRUE;                                  // 故障标志置位（R45 配对）
        _eState := E_DL_VacBuildState.eFault;             // 进故障相
    END_IF

E_DL_VacBuildState.eMeasured:
    IF (NOT bEnable) THEN
        _eState := E_DL_VacBuildState.eIdle;              // 失能：回空闲
    ELSIF rtPick.Q THEN
        _eState := E_DL_VacBuildState.eBuilding;          // 下一次取料：直接进建立相
        _bBuildBrk := TRUE;                               // 建立计时从零
    ELSE
        _eState := E_DL_VacBuildState.eIdle;              // 本次已完成：回空闲等待
    END_IF

E_DL_VacBuildState.eFault:
    IF (NOT _bFault) AND (NOT _bCfgBad) AND bEnable THEN
        _eState := E_DL_VacBuildState.eIdle;              // 锁存已清且组态合法：回空闲
    END_IF

ELSE
    _uFault := 16#0003_0230;                              // 故障级：相位 ID 越界（枚举兜底）
    _bFault := TRUE;                                      // 锁存
    bError  := TRUE;                                      // 故障标志置位（R45 配对）
    _eState := E_DL_VacBuildState.eFault;                 // 强制回故障相
END_CASE

(* —— 段 6：基线与漂移估计（中值抗野值；样本不足不出结论） —— *)
IF _bSampleNew AND (_nFill >= DL_MIN_SAMPLES) THEN
    (* 中值用秩计数法：对每点统计「严格小于它的样本数」，秩等于 nFill/2 者即中值。
       两层循环上界均由 _nFill 钳制（<= DL_BASE_MAX），无越界、无浮点相等比较 *)
    _fMed := _fSample[0];                                  // 中值初值（_nFill >= 3 已由外条件保证）
    FOR _nSortIdx := 0 TO (_nFill - 1) DO
        _nRank := 0;                                       // 本点秩计数清零
        FOR _nJ := 0 TO (_nFill - 1) DO
            IF _fSample[_nJ] < _fSample[_nSortIdx] THEN
                _nRank := _nRank + 1;                      // 严格小于本点的样本数
            END_IF
        END_FOR
        IF _nRank = (_nFill / 2) THEN
            _fMed := _fSample[_nSortIdx];                  // 秩等于半数的点即中值
        END_IF
    END_FOR
    _fBase := _fMed;                                       // 基线更新为中值 [ms]
    _fDevDen := MAX(_fBase, DL_MS_FLOOR);                  // 分母下限保护 [ms]
    _fDrift := (fBuildTimeMs - _fBase) / _fDevDen * 100.0; // 漂移 [%]（分母已证 >= 1 ms）
    IF _fDrift > DL_DRIFT_CLAMP_PCT THEN
        _fDrift := DL_DRIFT_CLAMP_PCT;                     // 上行限幅
    END_IF
    IF _fDrift < -DL_DRIFT_CLAMP_PCT THEN
        _fDrift := -DL_DRIFT_CLAMP_PCT;                    // 下行限幅
    END_IF
    IF _bInjectFault THEN
        _uInfo := 16#0003_0140;                            // 信息级：注入件故障，漂移结论抑制
        _nWarnCnt := 0;                                    // 抑制期不计连续次数
    ELSIF _fDrift > fDriftWarnPct THEN
        _nWarnCnt := _nWarnCnt + 1;                        // 连续超门限计数
        IF _nWarnCnt >= nWarnCycles THEN
            _bAging := TRUE;                               // 老化预警成立（维护级）
            _uInfo := 16#0003_0130;                        // 信息级：吸盘老化预警
        END_IF
    ELSE
        _nWarnCnt := 0;                                    // 未超门限：连续计数归零
        _bAging := FALSE;                                  // 漂移回落到门限内即自行释放（维护级可逆）
    END_IF
ELSIF _nFill < DL_MIN_SAMPLES THEN
    _uInfo := 16#0003_0120;                                // 信息级：样本不足，本拍不出漂移结论
    _fDrift := 0.0;                                        // 无基线：漂移置 0（不产生 inf/NaN）
    _bAging := FALSE;                                      // 无结论：不置老化预警
END_IF

(* —— 段 7：故障码优先级链（每个 bError 置位源在此均有码，R45 配对） —— *)
IF _bCfgBad THEN
    _uFault := 16#0003_0210;                               // 组态非法优先上报
    _bFault := TRUE;
    bError  := TRUE;
END_IF

(* —— 段 8：出口单点映射（名实同源；锁存码回放，禁同拍抹除） —— *)
fBaselineMs   := _fBase;                                   // 基线出口 [ms]
fDriftPct     := _fDrift;                                  // 漂移出口 [%]
bAgingWarn    := _bAging AND (NOT _bInjectFault);          // 老化预警出口（注入件故障期抑制）
bBuildTimeout := _bTimeout;                                // 建立超时出口（保持型）
nSampleCount  := _nFill;                                   // 有效样本数出口
eStateOut     := _eState;                                  // 状态出口
IF _bFault THEN
    nErrId := _uFault;                                     // 故障锁存码回放（不在故障相按当下输入重推）
    bError := TRUE;                                        // 故障出口派生自锁存
ELSE
    nErrId := _uInfo;                                      // 信息码
END_IF
bValid := bEnable AND (NOT _bFault) AND (NOT _bCfgBad);    // 判据可用

END_FUNCTION_BLOCK
