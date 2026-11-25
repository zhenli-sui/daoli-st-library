(*
  Name: FB_DL_AirCompressorMasterSeq
  Category: DL_Process
  Version: 1.0.0
  Round: R90 / 2026-11-25
  开源溯源：clean-room 自研（族 压缩空气系统能效，ST 开源生态实测 0 命中，无外部代码引入）
  功能：1) 两机空压站群控：主用机常开承担基载，压力跌破加载点且单机不够时投入辅机（双机运行），
           压力回到卸载点以上则退出辅机，回到单机主用相，形成带迟滞的两级容量控制。
        2) 主备轮换：主用相由轮换定时器 tonRot 计时（PT = tRotateH），到点后比较两机累计运行小时，
           把小时较少的一台设为主用，实现运行小时均衡；定时器自复位（IN := 运行相 AND NOT Q），
           不依赖外部沿清零。
        3) 故障切换：主用机故障立即由备机接管（相位在主用相之间直接迁移，不落故障相）；
           仅在两台同时故障或组态非法时才进故障相并锁存码值。辅机故障则退回单机主用相。
        4) 加载/卸载由带回差的锁存量给出：压力 <= 加载点置加载锁存，>= 卸载点清加载锁存，
           带内保持，防止在压力带内高频加减载。
  边界条件：1) 非有限值闸：压力、目标、回差、扫描周期四路实值入参统一过
           NOT(x > -DL_BIG AND x < DL_BIG)，同时拦 NaN 与 Inf；命中即判组态非法并进故障相，
           绝不把 NaN 送进压力比较（NaN 比较恒假会让加载判据静默失效，R19）。
        2) 组态零闸：fTargetBar 必须 > DL_EPS；fHystBar 必须 >= DL_HYST_MIN 且 <= fTargetBar
           （回差为 0 或越界会使加载点 >= 卸载点，压力带反号或退化为单点，必然频繁启停）；
           ABS(fCycleS) > DL_EPS 才允许累计运行小时（R21：斜率/积分类算法必须把周期时间作为入参
           并做零闸，不许假设固定扫描周期）。
        3) 压力带钳制：fTargetBar 钳 0 ~ DL_P_MAX(40 bar)、fHystBar 钳 0 ~ DL_P_MAX，
           加载点再钳到 >= 0，卸载点钳到 <= DL_P_MAX，防组态越界把压力带推到量程外。
        4) 饱和钳制：累计运行小时钳 0 ~ DL_H_MAX(200000 h)，防长年运行溢出。
        5) 相超时说明：eAcmLead1/eAcmLead2 两相的「超时」由轮换定时器 tonRot 承担（到点即轮换，
           该定时器本身就是主用相的时限监视）；eAcmAssist1/eAcmAssist2 两相由 tonAssist 监视
           （投入辅机后 DL_ASSIST_MAX 内压力仍未恢复 → 气量不足，判故障）；
           eAcmIdle 与 eAcmFault 为稳态相等候相，不设超时（设了会周期性误报）。
        6) 状态机兜底：CASE 全态覆盖 + ELSE 强制回故障相；故障解除路径为
           (NOT xAuto) AND (NOT xFault1) AND (NOT xFault2)，可达。
        7) FB 主体不使用 RETURN，统一单出口（跨平台可移植性）。
  量纲自证：fLoadBar = bar − bar/2 = bar；fUnloadBar = bar + bar/2 = bar；
           运行小时 = (s) / (s/h) = h，与 fHours1/fHours2 同量纲；
           tonRot/tonAssist 的 PT 为 [TIME]，与 TON 同量纲；本件无跨量纲相加。
  码表 Error codes（本件格 0090_04xx，故障级一律 3 行内置 _uFault/_bFault/_eState）:
    16#0090_0401 信息级：自动未投入（不置故障位）
    16#0090_0402 故障级：两台空压机同时故障
    16#0090_0403 故障级：辅机投入后压力长时间未恢复（气量不足）
    16#0090_0404 故障级：组态非法（目标压力/回差/扫描周期越界或非有限）
    16#0090_0405 故障级：状态机落 ELSE 兜底（非法相位 ID）

  修订历史 Revision :
    2026-11-25  v1.0.0  R90 首版
*)

TYPE E_DL_AcmState :
(
    eAcmIdle    := 0,    // 待机：自动未投入 / Idle, automatic mode not engaged
    eAcmLead1   := 10,   // 1 号主用，2 号停机 / Unit 1 lead, unit 2 stopped
    eAcmLead2   := 20,   // 2 号主用，1 号停机 / Unit 2 lead, unit 1 stopped
    eAcmAssist1 := 30,   // 1 号为主 + 2 号辅，双机运行 / Unit 1 lead with unit 2 assisting
    eAcmAssist2 := 40,   // 2 号为主 + 1 号辅，双机运行 / Unit 2 lead with unit 1 assisting
    eAcmFault   := 90    // 故障：锁存待解除 / Fault, latched awaiting release
);
END_TYPE

FUNCTION_BLOCK FB_DL_AirCompressorMasterSeq
VAR_INPUT
    xAuto        : BOOL;    // 自动投入指令 [bool] / Automatic mode command [bool]
    xFault1      : BOOL;    // 1 号机故障汇总 [bool] / Unit 1 fault aggregate [bool]
    xFault2      : BOOL;    // 2 号机故障汇总 [bool] / Unit 2 fault aggregate [bool]
    fPressureBar : REAL;    // 母管压力实测 [bar] / Header pressure measurement [bar]
    fTargetBar   : REAL;    // 目标压力（压力带中心）[bar] / Target pressure, band centre [bar]
    fHystBar     : REAL;    // 加载/卸载回差带宽 [bar] / Load-unload hysteresis band [bar]
    tRotateH     : TIME;    // 主备轮换周期 [TIME] / Lead rotation period [TIME]
    fCycleS      : REAL;    // 扫描周期 [s] / Scan cycle time [s]
END_VAR
VAR_OUTPUT
    xRun1        : BOOL;    // 1 号机运行指令 [bool] / Unit 1 run command [bool]
    xRun2        : BOOL;    // 2 号机运行指令 [bool] / Unit 2 run command [bool]
    xLoad1       : BOOL;    // 1 号机加载指令 [bool] / Unit 1 load command [bool]
    xLoad2       : BOOL;    // 2 号机加载指令 [bool] / Unit 2 load command [bool]
    fLoadBar     : REAL;    // 加载压力点 [bar] / Load pressure point [bar]
    fUnloadBar   : REAL;    // 卸载压力点 [bar] / Unload pressure point [bar]
    fHours1      : REAL;    // 1 号机累计运行小时 [h] / Unit 1 accumulated running hours [h]
    fHours2      : REAL;    // 2 号机累计运行小时 [h] / Unit 2 accumulated running hours [h]
    eState       : E_DL_AcmState;   // 状态出口，段尾单点映射 / State outlet, single-point mapped
    nErrId       : UDINT;   // 事件码，0 = 无事件 / Event code, 0 = none
END_VAR
VAR
    tonRot       : TON;     // 主用相轮换定时器，自复位 [TIME] / Lead rotation timer, self-resetting
    tonAssist    : TON;     // 辅机投入恢复监视定时器 [TIME] / Assist recovery supervision timer
    _eState      : E_DL_AcmState := E_DL_AcmState.eAcmIdle;   // 内部相位（CASE 唯一写入目标）
    _eStatePrev  : E_DL_AcmState := E_DL_AcmState.eAcmIdle;   // 上一拍相位快照（周期末更新）
    _fTargetClamp: REAL;    // 钳制后的目标压力 [bar] / Clamped target pressure [bar]
    _fHystClamp  : REAL;    // 钳制后的回差带宽 [bar] / Clamped hysteresis band [bar]
    _fLoadPtBar  : REAL;    // 加载压力点 [bar] / Load pressure point [bar]
    _fUnloadPtBar: REAL;    // 卸载压力点 [bar] / Unload pressure point [bar]
    _bNeedAssist : BOOL;    // 需投入辅机（压力跌破加载点）[bool] / Assist required flag [bool]
    _bRecovered  : BOOL;    // 压力已回到卸载点以上 [bool] / Pressure recovered flag [bool]
    _bLeadRunning: BOOL;    // 主用相运行中（轮换定时器激励源）[bool] / Lead phase running flag [bool]
    _bRun1       : BOOL;    // 1 号机运行内部量 [bool] / Unit 1 run internal [bool]
    _bRun2       : BOOL;    // 2 号机运行内部量 [bool] / Unit 2 run internal [bool]
    _bLoadLat1   : BOOL;    // 1 号机加载锁存（迟滞承载）[bool] / Unit 1 load latch [bool]
    _bLoadLat2   : BOOL;    // 2 号机加载锁存（迟滞承载）[bool] / Unit 2 load latch [bool]
    _fHours1     : REAL;    // 1 号机累计运行小时内部量 [h] / Unit 1 hours internal [h]
    _fHours2     : REAL;    // 2 号机累计运行小时内部量 [h] / Unit 2 hours internal [h]
    _bCfgBad     : BOOL;    // 组态非法聚合 [bool] / Configuration invalid aggregate [bool]
    _bFault      : BOOL;    // 故障锁存位 [bool] / Latched fault flag [bool]
    _uInfo       : UDINT;   // 信息码，每拍重算 / Info code, recomputed every cycle
    _uFault      : UDINT;   // 故障码锁存 / Latched fault code
END_VAR
VAR CONSTANT
    DL_EPS       : REAL := 1.0E-9;      // 组态零闸阈值 [-] / Configuration zero gate threshold [-]
    DL_BIG       : REAL := 1.0E12;      // 非有限值闸量级上限 [-] / Finiteness gate magnitude [-]
    DL_P_MAX     : REAL := 40.0;        // 压力量程上限 [bar] / Pressure range ceiling [bar]
    DL_HYST_MIN  : REAL := 0.05;        // 回差带宽下限 [bar] / Hysteresis lower bound [bar]
    DL_TWO       : REAL := 2.0;         // 半带宽除数（对称展开）[-] / Half-band divisor [-]
    DL_S_PER_H   : REAL := 3600.0;      // h → s 换算因子 [s/h] / Hour to second factor [s/h]
    DL_H_MAX     : REAL := 200000.0;    // 累计运行小时饱和上限 [h] / Running hours saturation ceiling [h]
    DL_ASSIST_MAX: TIME := T#30M;       // 辅机投入后压力恢复监视窗 [TIME] / Assist recovery window [TIME]
END_VAR

(* —— 段 0：单拍量预清零（锁存量 _uFault/_bFault/_bLoadLat*/_fHours*/_eStatePrev 不入清单，R187①） —— *)
_uInfo := 16#0090_0401;                     // 缺省信息：自动未投入（进自动后由各相覆盖）
nErrId := 16#0000_0000;                     // 事件码缺省无事件 / Event code defaults to none

(* —— 段 1：非有限值闸（R19：NaN 比较恒假会让加载判据静默失效，必须前置拦截） —— *)
_bCfgBad := NOT (fPressureBar > -DL_BIG AND fPressureBar < DL_BIG)
            OR NOT (fTargetBar > -DL_BIG AND fTargetBar < DL_BIG)
            OR NOT (fHystBar > -DL_BIG AND fHystBar < DL_BIG)
            OR NOT (fCycleS > -DL_BIG AND fCycleS < DL_BIG);

(* —— 段 2：组态零闸（R4/R21：回差退化、目标为零、周期为零均判组态非法） —— *)
_bCfgBad := _bCfgBad
            OR (fTargetBar <= DL_EPS)                         // 目标压力必须为正
            OR (fTargetBar > DL_P_MAX)                        // 目标压力不越量程
            OR (fHystBar < DL_HYST_MIN)                       // 回差不得低于下限（防频繁启停）
            OR (fHystBar > fTargetBar)                        // 回差不得大于目标压力（否则加载点为负）
            OR (ABS(fCycleS) <= DL_EPS);                      // 扫描周期零闸

(* —— 段 3：压力带解算（R22 方向自核：加载在下、卸载在上，各偏半个回差） —— *)
_fTargetClamp := LIMIT(0.0, fTargetBar, DL_P_MAX);            // 目标压力钳 0..40 [bar]
_fHystClamp := LIMIT(0.0, fHystBar, DL_P_MAX);                // 回差钳 0..40 [bar]
_fLoadPtBar := LIMIT(0.0, _fTargetClamp - _fHystClamp / DL_TWO, DL_P_MAX);      // 加载点 [bar]
_fUnloadPtBar := LIMIT(0.0, _fTargetClamp + _fHystClamp / DL_TWO, DL_P_MAX);    // 卸载点 [bar]

(* —— 段 4：判据量（压力越低越需辅机，回到卸载点以上即判恢复） —— *)
_bNeedAssist := (NOT _bCfgBad) AND (fPressureBar <= _fLoadPtBar);      // 跌破加载点
_bRecovered := (NOT _bCfgBad) AND (fPressureBar >= _fUnloadPtBar);     // 回到卸载点以上

(* —— 段 5：定时器无条件周期刷新（R7 + R188：轮换定时器自复位，不靠外部沿） —— *)
_bLeadRunning := (_eState = E_DL_AcmState.eAcmLead1) OR (_eState = E_DL_AcmState.eAcmLead2);
tonRot(IN := _bLeadRunning AND (NOT tonRot.Q), PT := tRotateH);        // 主用相轮换计时，自复位
tonAssist(IN := (_eState = E_DL_AcmState.eAcmAssist1) OR (_eState = E_DL_AcmState.eAcmAssist2),
          PT := DL_ASSIST_MAX);                                        // 辅机恢复监视窗

(* —— 段 6：全局故障拦截（优先级最高；已锁存则不再改写码值，禁同拍抹除） —— *)
IF _bCfgBad AND (NOT _bFault) THEN
    _uFault := 16#0090_0404;                // 故障级：组态非法
    _bFault := TRUE;                        // 锁存（3 行内置，R45 配对）
    _eState := E_DL_AcmState.eAcmFault;
END_IF
IF xFault1 AND xFault2 AND (NOT _bFault) THEN
    _uFault := 16#0090_0402;                // 故障级：两机同时故障
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_AcmState.eAcmFault;
END_IF

(* —— 段 7：相位机（只做迁移；出口在段 9 单点映射） —— *)
CASE _eState OF

E_DL_AcmState.eAcmIdle:
    IF NOT xAuto THEN
        _uInfo := 16#0090_0401;             // 信息级：自动未投入
    ELSIF _fHours1 <= _fHours2 THEN
        _eState := E_DL_AcmState.eAcmLead1; // 小时较少者为主用（均衡起点）
    ELSE
        _eState := E_DL_AcmState.eAcmLead2;
    END_IF

E_DL_AcmState.eAcmLead1:
    IF NOT xAuto THEN
        _eState := E_DL_AcmState.eAcmIdle;  // 撤自动：回待机
    ELSIF xFault1 THEN
        _eState := E_DL_AcmState.eAcmLead2; // 主用故障：备机接管（不落故障相）
    ELSIF _bNeedAssist THEN
        _eState := E_DL_AcmState.eAcmAssist1;   // 单机不足：投入辅机
    ELSIF tonRot.Q AND (_fHours2 < _fHours1) THEN
        _eState := E_DL_AcmState.eAcmLead2; // 轮换到点且 2 号小时更少：换主用
    END_IF

E_DL_AcmState.eAcmLead2:
    IF NOT xAuto THEN
        _eState := E_DL_AcmState.eAcmIdle;
    ELSIF xFault2 THEN
        _eState := E_DL_AcmState.eAcmLead1; // 主用故障：备机接管
    ELSIF _bNeedAssist THEN
        _eState := E_DL_AcmState.eAcmAssist2;
    ELSIF tonRot.Q AND (_fHours1 < _fHours2) THEN
        _eState := E_DL_AcmState.eAcmLead1; // 轮换到点且 1 号小时更少：换主用
    END_IF

E_DL_AcmState.eAcmAssist1:
    IF NOT xAuto THEN
        _eState := E_DL_AcmState.eAcmIdle;
    ELSIF xFault1 THEN
        _eState := E_DL_AcmState.eAcmLead2; // 主机故障：辅机转主用
    ELSIF xFault2 THEN
        _eState := E_DL_AcmState.eAcmLead1; // 辅机故障：退回单机主用
    ELSIF _bRecovered THEN
        _eState := E_DL_AcmState.eAcmLead1; // 本拍合法事件（压力恢复）优先于超时迁移（R275）
    ELSIF tonAssist.Q THEN
        _uFault := 16#0090_0403;            // 故障级：气量不足，双机仍不能恢复压力
        _bFault := TRUE;
        _eState := E_DL_AcmState.eAcmFault;
    END_IF

E_DL_AcmState.eAcmAssist2:
    IF NOT xAuto THEN
        _eState := E_DL_AcmState.eAcmIdle;
    ELSIF xFault2 THEN
        _eState := E_DL_AcmState.eAcmLead1; // 主机故障：辅机转主用
    ELSIF xFault1 THEN
        _eState := E_DL_AcmState.eAcmLead2; // 辅机故障：退回单机主用
    ELSIF _bRecovered THEN
        _eState := E_DL_AcmState.eAcmLead2; // 本拍合法事件优先于超时迁移
    ELSIF tonAssist.Q THEN
        _uFault := 16#0090_0403;            // 故障级：气量不足
        _bFault := TRUE;
        _eState := E_DL_AcmState.eAcmFault;
    END_IF

E_DL_AcmState.eAcmFault:
    IF (NOT xAuto) AND (NOT xFault1) AND (NOT xFault2) AND (NOT _bCfgBad) THEN
        _bFault := FALSE;                   // 解除路径：撤自动 + 两机故障消失 + 组态恢复（可达）
        _uFault := 16#0000_0000;            // 清锁存码
        _eState := E_DL_AcmState.eAcmIdle;  // 回待机
    END_IF

ELSE
    _uFault := 16#0090_0405;                // 故障级：非法相位 ID 兜底
    _bFault := TRUE;                        // 锁存
    _eState := E_DL_AcmState.eAcmFault;     // 强制回故障相

END_CASE

(* —— 段 8：后置段（R23：运行派生、加载锁存、小时累计一律在迁移判断之后） —— *)
_bRun1 := ((_eState = E_DL_AcmState.eAcmLead1) OR (_eState = E_DL_AcmState.eAcmAssist1)
           OR (_eState = E_DL_AcmState.eAcmAssist2)) AND (NOT _bFault) AND (NOT xFault1);
_bRun2 := ((_eState = E_DL_AcmState.eAcmLead2) OR (_eState = E_DL_AcmState.eAcmAssist1)
           OR (_eState = E_DL_AcmState.eAcmAssist2)) AND (NOT _bFault) AND (NOT xFault2);

(* 加载锁存：跌破加载点置位，回到卸载点以上复位，带内保持（迟滞防频繁加减载） *)
IF NOT _bRun1 THEN
    _bLoadLat1 := FALSE;                    // 停机即清加载锁存
ELSIF fPressureBar <= _fLoadPtBar THEN
    _bLoadLat1 := TRUE;                     // 跌破加载点：加载
ELSIF fPressureBar >= _fUnloadPtBar THEN
    _bLoadLat1 := FALSE;                    // 回到卸载点以上：卸载
END_IF
IF NOT _bRun2 THEN
    _bLoadLat2 := FALSE;                    // 停机即清加载锁存
ELSIF fPressureBar <= _fLoadPtBar THEN
    _bLoadLat2 := TRUE;                     // 跌破加载点：加载
ELSIF fPressureBar >= _fUnloadPtBar THEN
    _bLoadLat2 := FALSE;                    // 回到卸载点以上：卸载
END_IF

(* 运行小时累计（R21：周期时间已做零闸，段 2 已判 ABS(fCycleS) > DL_EPS 才允许进入本段） *)
IF _bRun1 AND (ABS(fCycleS) > DL_EPS) THEN
    _fHours1 := MIN(DL_H_MAX, _fHours1 + fCycleS / DL_S_PER_H);    // s / (s/h) = h
END_IF
IF _bRun2 AND (ABS(fCycleS) > DL_EPS) THEN
    _fHours2 := MIN(DL_H_MAX, _fHours2 + fCycleS / DL_S_PER_H);    // s / (s/h) = h
END_IF

_eStatePrev := _eState;                     // 快照统一在周期末尾更新（R23）

(* —— 段 9：出口单点映射（名实同源；运行/加载由状态与锁存导出，不在多分支各写一遍） —— *)
xRun1 := _bRun1;                            // 1 号机运行出口
xRun2 := _bRun2;                            // 2 号机运行出口
xLoad1 := _bRun1 AND _bLoadLat1;            // 1 号机加载出口（停机必不加载）
xLoad2 := _bRun2 AND _bLoadLat2;            // 2 号机加载出口
IF _bCfgBad THEN
    fLoadBar := 0.0;                        // 组态非法：压力带出口闸断为字面量，禁 NaN 外泄
    fUnloadBar := 0.0;                      // 同上
ELSIF _bFault THEN
    fLoadBar := _fLoadPtBar;                // 故障锁存但组态仍有效：回放上拍解算值
    fUnloadBar := _fUnloadPtBar;            // 同上
ELSE
    fLoadBar := _fLoadPtBar;                // 加载压力点出口 [bar]
    fUnloadBar := _fUnloadPtBar;            // 卸载压力点出口 [bar]
END_IF
fHours1 := _fHours1;                        // 1 号机运行小时出口 [h]
fHours2 := _fHours2;                        // 2 号机运行小时出口 [h]
eState := _eState;                          // 状态出口单点映射
IF _bFault THEN
    nErrId := _uFault;                      // 故障锁存码回放（不在故障相按当下输入重推断）
ELSE
    nErrId := _uInfo;                       // 信息码
END_IF

END_FUNCTION_BLOCK
