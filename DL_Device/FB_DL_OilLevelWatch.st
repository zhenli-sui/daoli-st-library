(*
    FB_DL_OilLevelWatch —— 润滑 / 液压油油位连续监视（双阈值迟滞 + 确认延时 + NE107）
    ------------------------------------------------------------------
    组件名称  : FB_DL_OilLevelWatch
    分类      : DL_Device / LevelMonitoring
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴组织 —— T2-6 Rockwell AOI（矩阵行 166）：仅借鉴「设备级
                粗粒度监视 AOI」的公开功能形态（连续量监视 + 确认延时 +
                分级健康出口）；clean-room 声明 —— 零代码行复制，判据链 /
                迟滞口径 / 码位 100% 自有；非有限判据为 IEC 61131-3 标准语义
                （R79 双判）的道莅防御性实现。
    平台      : 纯 IEC 61131-3（TON / R_TRIG / LREAL 比较），CODESYS 3.5 /
                TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R72 构建轮 · 批 3 · 序号 9）
    ------------------------------------------------------------------
    功能说明  : 齿轮箱 / 液压单元油位巡检：欠油提前预警防干磨烧轴。
                单相监视（无顺序状态机 CASE，同族 FB_DL_AxisEncBatteryWatch
                口径家族一致）：
                ① 非有限液位闸：fLevelMm 非有限（NaN 自反判 + Inf 差值自反
                   判，R79）→ **直接故障锁存**（探头断线状态不明比欠油更
                   危险，R71 AxisEncBatteryWatch 口径家族一致），不等确认
                   延时；
                ② 组态域闸（R272 全枚举）：fLowWarnMm / fHystMm / fProbeMaxMm
                   非有限、fHystMm < 0（回差为负）、fLowWarnMm >= fProbeMaxMm
                   （阈值倒置）、fProbeMaxMm <= 0（量程非正）→ 组态锁存码
                   （根因优先归因，段 6 先于段 7）；
                ③ 双阈值迟滞判定：未预警相以进入线判（fLevelMm < fLowWarnMm），
                   已预警相以退出线判（fLevelMm >= fLowWarnMm + fHystMm），
                   防临界抖振；
                ④ TON 连续确认（断输入口径：液位回升出迟滞带 IN 即 FALSE，
                   计时清零重计）→ 预警锁存；
                ⑤ NE107 健康出口：欠油确认 → eMaintenanceReq；非有限 /
                   组态故障 → eFailure；正常 → eOk；失能 → eCheckFunction。
                锁存解除口径（R321 电平式声明）：bReset 上升沿为**唯一人工
                解除**，液位恢复越退出线为**条件恢复自动降级**双路——两路
                并存写死，禁恢复沿作唯一解除载体。预警锁存后自动降级判据 =
                液位 >= 退出线（迟滞带内保持预警，出带即自动解除）。
                满油探头饱和：fLevelMm > fProbeMaxMm → 信息级（满油合法
                工况，不拦截照判——判定方向与液位单调性一致，无危险侧偏差）。
                失能语义（R191 声明）：bEn = FALSE → bLowWarn / bError /
                nErrCode 出口清零、eHealth = eCheckFunction；_bFault /
                _bWarnLatch 锁存位**不被失能清除**（失能是操作态不是复位），
                须 bReset 上升沿解除——两语义分离。
    错误码    : 16#0003_0740 液位非有限（探头断线 / ADC 故障），直接锁存不等
                            确认延时 —— 故障级
                16#0003_0741 组态非法（阈值倒置 / 回差为负 / 阈值或量程非有限 /
                            量程非正 / 预警线不低量程上界），锁存至复位沿
                            —— 故障级
                16#0003_0742 液位越探头量程上界（探头饱和，满油合法工况）
                            —— 信息级，不置 bError（R45）
                加码反证句（R90）：0740（探头）与 0741（组态）成因互斥且调用
                方可自证（接线 vs 组态表），eHealth 出口同为 eFailure 但码位
                分流维修动作，输出组合不可互换观测，故各立一码；0742 由
                「液位在迟滞带上方 + 码位非零」唯一观测（正常满油不带码），
                不与既有输出组合重复。
    码位总账  : 16#0003_0740 用 ｜ 16#0003_0741 用 ｜ 16#0003_0742 用
    状态机    : N/A —— 单相监视，无顺序状态机，无自有 ENUM / CASE 可写；
                确认计时由 TON 实例自持（定时器状态而非顺序状态）；
                健康出口复用既有枚举 E_DL_Ne107Status（只引用）
    边界与披露: 一 TON（tonConfirm）与 R_TRIG（rtReset）每拍**无条件调用**
                   （规则 ⑦），IN 为段 7 计算出的显式条件；
                二 零全局变量、零 VAR_EXTERNAL、零物理地址；
                三 归属 Ownership：E_DL_Ne107Status 归属 I_DL_DeviceHealth.st
                   （全库唯一定义，R264），本件只引用不重声明；
                四 输入非有限 / 组态非法 → 直接锁存（不走迟滞判定集合，安全
                   侧赋值不引用本闸判定内的量，防自证循环，R127）；
                五 输出量纲：fLevelMm / fLowWarnMm / fHystMm / fProbeMaxMm 均
                   [mm]，本件不换算单位；
                六 分工互引：FB_DL_SiloLevelInterlock（料仓联锁）、
                   FB_DL_LevelSwitchVib（开关量检测）、FB_DL_HydrostaticLevelComp
                   （静压补偿换算）——本件只做模拟量油位趋势监视，不做联锁
                   与换算；
                七 依赖声明：仅 Standard.library（TON / R_TRIG / ABS），零
                   厂商方言。
    验收向量  : V1 液位 80 mm、预警线 100 mm、确认 2 s → 2 s 后 bLowWarn；
                V2 液位回升 130 mm（退出线 100 + 20）→ 自动降级解除；
                V3 液位回升 110 mm（迟滞带内）→ 预警保持（迟滞自证）；
                V4 fLevelMm = NaN → 0740 立即锁存（不等 2 s）；V5 fHystMm
                = −1 → 0741 锁存；V6 fLevelMm = 520（量程 500）→ 0742
                信息级照判；V7 bReset 上升沿 → 清锁存；V8 失能 → 出口清零、
                锁存保留。
                算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    修订记录  : 2026-11-23 v1.0.0 首次入库（R72 构建轮 · 批 3 · 序号 9）
*)
FUNCTION_BLOCK FB_DL_OilLevelWatch
VAR_INPUT
    fLevelMm    : LREAL;                   (* 油位连续值（引脚注入），[mm]，非有限即探头故障 / the oil level continuous value in mm *)
    fLowWarnMm  : LREAL := 100.0;          (* 低油位预警阈值（迟滞进入线），[mm] / the low oil warn threshold, the hysteresis enter line *)
    fHystMm     : LREAL := 20.0;           (* 迟滞回差（退出线 = 预警线 + 回差），[mm]，禁负 / the hysteresis band in mm, the exit line is warn plus band *)
    fProbeMaxMm : LREAL := 500.0;          (* 探头量程上界（饱和信息级判据），[mm]，禁非正 / the probe range upper bound in mm *)
    tConfirm    : TIME := T#2S;            (* 欠油确认延时，[ms] / the low oil confirmation delay *)
    bEn         : BOOL := TRUE;            (* 使能，[标志]，FALSE 出口清零、锁存保留 / the enable, FALSE clears the outlets, the latch kept *)
    bReset      : BOOL := FALSE;           (* 故障 / 预警复位，[标志]，上升沿唯一人工解除 / the reset, its rising edge is the only manual release *)
END_VAR
VAR_OUTPUT
    bLowWarn  : BOOL := FALSE;             (* 低油位预警锁存位（确认成立且未解除）[标志] / the low oil warn latched flag *)
    eHealth   : E_DL_Ne107Status;          (* NE107 健康出口（欠油 → eMaintenanceReq，故障 → eFailure）/ the NE 107 health outlet *)
    bValid    : BOOL := FALSE;             (* 出口可用标志，失能或锁存故障为 FALSE / the outlets usable *)
    bError    : BOOL := FALSE;             (* 故障标志，存在锁存故障时 TRUE / the fault flag *)
    nErrCode  : UDINT := 16#0000_0000;     (* 错误码，0 = 正常，锁存回放（R187）/ the error id, replayed from the latch *)
END_VAR
VAR
    _rtReset    : R_TRIG;                  (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonConfirm : TON;                     (* 欠油确认延时实例（无条件调用）/ the low oil confirmation timer *)
    _bFault     : BOOL := FALSE;           (* 故障锁存副本（探头 / 组态），仅复位沿解除 / the internal fault latch copy *)
    _nCodeLatch : UDINT := 0;              (* 锁存成因码，故障期回放 / the latched cause code *)
    _bWarnLatch : BOOL := FALSE;           (* 预警锁存副本（自动降级或复位沿解除）/ the warn latch copy *)
    _bCfgBad    : BOOL := FALSE;           (* 组态非法标志（逐拍重算，仅用于首次锁存）/ the config fault flag *)
    _bInBad     : BOOL := FALSE;           (* 液位非有限标志（逐拍重算）/ the input fault flag *)
    _bOutDom    : BOOL := FALSE;           (* 液位越量程上界标志（逐拍重算，信息级）/ the probe saturation flag *)
    _bRun       : BOOL := FALSE;           (* 运行许可 = 使能 且 无锁存故障 / the run permit *)
    _bLowCond   : BOOL := FALSE;           (* 欠油迟滞判定条件（含自保持，送 TON）/ the low oil hysteresis condition *)
END_VAR
VAR CONSTANT
    DL_OLW_CODE_PROBE : UDINT := 16#0003_0740; (* 液位非有限锁存码 [码] / the probe fault code *)
    DL_OLW_CODE_CFG   : UDINT := 16#0003_0741; (* 组态非法锁存码 [码] / the configuration fault code *)
    DL_OLW_CODE_SAT   : UDINT := 16#0003_0742; (* 探头饱和信息码 [码] / the probe saturation info code *)
    DL_OLW_ZERO       : UDINT := 0;            (* 无符号零哨兵 [码] / the unsigned zero sentinel *)
    DL_OLW_FZERO      : LREAL := 0.0;          (* 浮点零哨兵 [mm] / the float zero sentinel *)
END_VAR

// 段 1｜出口预置（统一出口预置，R256）/ segment 1, preset every outlet
bLowWarn := FALSE;                         // 预警出口预清零（映射段回填）/ preset the warn outlet false
eHealth  := E_DL_Ne107Status.eUnknown;     // 健康出口预置未知（首拍语义）/ preset the health outlet unknown
bValid   := FALSE;                         // 可用标志预清零 / preset the usable flag false
bError   := FALSE;                         // 故障标志预清零 / preset the fault flag false
nErrCode := DL_OLW_ZERO;                   // 码位预置无错 / preset the code zero
_bLowCond := FALSE;                        // 迟滞条件预清零 / preset the condition false

// 段 2｜复位沿无条件调用（规则 ⑦）/ segment 2, the unconditional reset edge refresh
_rtReset(CLK := bReset);                   // 每拍无条件刷新 / refreshed every scan

// 段 3｜锁存解除：复位沿唯一人工解除（作用域：清双锁存 + 清码，R311 声明）/ segment 3, the manual release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault := FALSE;                      // 清故障锁存（恒可达，R152 自证）/ clear the fault latch
    _bWarnLatch := FALSE;                  // 清预警锁存 / clear the warn latch
    _nCodeLatch := DL_OLW_ZERO;            // 清锁存码（可到达清除边）/ clear the latched code
END_IF

// 段 4｜组态域闸（R272 全枚举：fLowWarnMm / fHystMm / fProbeMaxMm 三引脚）/ segment 4, the configuration guard
_bCfgBad := (fLowWarnMm <> fLowWarnMm) OR ((fLowWarnMm - fLowWarnMm) <> DL_OLW_FZERO) // 预警线非有限 / the warn line non finite
         OR (fHystMm <> fHystMm) OR ((fHystMm - fHystMm) <> DL_OLW_FZERO)              // 回差非有限 / the hysteresis non finite
         OR (fProbeMaxMm <> fProbeMaxMm) OR ((fProbeMaxMm - fProbeMaxMm) <> DL_OLW_FZERO) // 量程非有限 / the range non finite
         OR (fHystMm < DL_OLW_FZERO)                                                   // 回差为负 / a negative hysteresis
         OR (fLowWarnMm >= fProbeMaxMm)                                                // 阈值倒置（预警线不低于量程上界）/ the threshold inversion
         OR (fProbeMaxMm <= DL_OLW_FZERO);                                             // 量程非正 / a non positive range

// 段 5｜输入守卫：液位非有限即危险（状态不明 > 欠油，直接锁存不等延时）/ segment 5, the input guard
_bInBad := (fLevelMm <> fLevelMm) OR ((fLevelMm - fLevelMm) <> DL_OLW_FZERO); // 液位非有限（R79 双判）/ the level non finite
_bOutDom := (fLevelMm > fProbeMaxMm);      // 液位越量程上界（探头饱和，信息级）/ the level over the range

// 段 6｜首次成因锁存（故障期内不重推断，回放锁存码，R189；组态根因优先）/ segment 6, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while not latched
    IF _bCfgBad THEN                       // 组态非法（根因优先归因）/ the config fault first
        _bFault := TRUE;                   // 置锁存 / latch
        _nCodeLatch := DL_OLW_CODE_CFG;    // 登记组态码 / register the config code
    ELSIF _bInBad THEN                     // 液位非有限（不等确认延时）/ the probe fault, no delay
        _bFault := TRUE;                   // 置锁存 / latch
        _nCodeLatch := DL_OLW_CODE_PROBE;  // 登记探头码 / register the probe code
    END_IF
END_IF

// 段 7｜运行许可与迟滞条件（分支内不调用任何定时器）/ segment 7, the run permit and the hysteresis condition
_bRun := bEn AND (NOT _bFault);            // 使能且无锁存故障 / enabled and not latched
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    IF _bWarnLatch THEN                    // 已预警相：以退出线判（迟滞防抖振）/ the latched phase, the exit line
        _bLowCond := fLevelMm < (fLowWarnMm + fHystMm); // 迟滞带内保持预警 / hold inside the band
    ELSE                                   // 未预警相：以进入线判 / the unlatched phase, the enter line
        _bLowCond := fLevelMm < fLowWarnMm; // 破进入线 / under the enter line
    END_IF
    IF _bLowCond AND _tonConfirm.Q THEN    // 破线经确认延时 / the condition confirmed
        _bWarnLatch := TRUE;               // 预警锁存 / latch the warn
    END_IF
    IF _bWarnLatch AND (NOT _bLowCond) THEN // 条件恢复自动降级（电平式双路之二，R321 声明；复位沿为人工路）/ the automatic level release
        _bWarnLatch := FALSE;              // 出迟滞带即自动解除（同拍生效）/ release over the exit line
    END_IF
ELSE                                       // 失能或锁存故障 / disabled or latched
    _bLowCond := FALSE;                    // 条件清零（TON 随之复位）/ clear the condition
END_IF

// 段 8｜确认定时器无条件调用（IN 为段 7 显式条件；断输入口径：出线即断计）/ segment 8, the unconditional confirmation timer
_tonConfirm(IN := _bRun AND _bLowCond, PT := tConfirm); // 欠油确认计时 / the confirmation timer

// 段 9｜出口映射（名实双出口同源，R191）/ segment 9, the outlet mapping
IF _bRun THEN                              // 运行许可成立 / the run permit holds
    bLowWarn := _bWarnLatch;               // 预警出口与锁存同源 / the warn outlet shares the latch
    bValid := TRUE;                        // 出口可用 / the outlets usable
    IF _bWarnLatch THEN                    // 预警确认成立 / the warn confirmed
        nErrCode := DL_OLW_ZERO;           // 预警本身不发码（欠油是正常工况分支非缺陷）/ the warn carries no code
        eHealth := E_DL_Ne107Status.eMaintenanceReq; // 欠油 → 需要维护 / maintenance required
    ELSE                                   // 无预警 / no warn
        eHealth := E_DL_Ne107Status.eOk;   // 正常 / ok
    END_IF
    IF _bOutDom AND (NOT _bWarnLatch) THEN // 运行中探头饱和且无更高优先级出口 / the saturation info
        nErrCode := DL_OLW_CODE_SAT;       // 信息级：探头饱和满油（不置 bError，R45）/ info level: the probe saturation
    END_IF
ELSIF (NOT bEn) THEN                       // 失能相（操作态优先于故障归因，同族口径）/ the disabled phase
    bLowWarn := FALSE;                     // 出口清零（锁存保留）/ the outlet cleared, the latch kept
    bError := FALSE;                       // 失能不是故障 / a disabled block is not a fault
    nErrCode := DL_OLW_ZERO;               // 失能不发码 / no code while disabled
    eHealth := E_DL_Ne107Status.eCheckFunction; // 失能 → 功能检查 / function check
ELSE                                       // 锁存故障相（失能优先级之上）/ the latched fault phase
    bLowWarn := FALSE;                     // 故障相预警出口清零（归并故障出口）/ the warn outlet cleared
    bError := TRUE;                        // 故障标志置位 / raise the fault flag
    nErrCode := _nCodeLatch;               // 回放锁存码 / replay the latched code
    eHealth := E_DL_Ne107Status.eFailure;  // 故障 → 失效（信号不可信）/ failure
END_IF
END_FUNCTION_BLOCK
