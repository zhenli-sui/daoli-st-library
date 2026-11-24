(*
  ==================================================================
  组件名 Component  : FB_DL_VfdPrechargeSeq
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_0728 / 0729 / 072A / 072B / 072C（故障级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 中
  功能   Purpose    : 直流母线预充电回路时序监视：接触器反馈窗 + 电压上升斜率 +
                      总时限三闸（预充电阻过热、接触器卡阻、整流缺相的启动期保护）。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方
                      代码行）；预充电时序与斜率判据取自公开电力电子上电时序工程
                      口径（分类与公式借鉴，零代码复制），滤波、闸门、迟滞与码位
                      100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符与 TON 语义；预充电回路
                      公开上电时序工程定义
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / CASE / 四则），三平台通用
  依赖   Depends    : 仅 Standard.library（TON / R_TRIG 属标准件）
  分工声明 Split     : FB_DL_RailPowerSequence（多轨分级上电时序，DL_Base）/
                      FB_DL_VfdDcBusRipple（运行期母线监视）/ FB_DL_VfdGeneric
                      （变频器通用抽象）互引；本件为启动期预充回路专用时序（R216）。
  归属 Ownership     : E_DL_PrechargePhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 组态闸结构早退（族② 判据）：fUdNom ≤ 0 / fUdTargetPct
                         越域 (0, 100] / fSlopeMinPctS ≤ 0 / tFbWindow ≤ 0 /
                         tPrechargeMax ≤ 0 / 任一非有限 → 组态码 0728 + 三件套 +
                         RETURN（除法段不可达，R1 教训出厂即正确）；
                      二 状态机 ENUM + CASE 必带 ELSE（非法态兜底落 eFault + 锁存
                         0728，禁静默）；本拍合法事件优先于超时迁移（R275 同拍
                         竞态：CASE 分支先消化反馈 / 电压 / 撤令事件，再消化
                         超时；撤令判据为 eWaitFb / eRamp 分支首个 ELSIF，
                         R64 v1.0.1 上移）；
                      三 失败锁存 bPrechargeFault + _bFaultLatch：反馈超窗 /
                         斜率低于下限持续宽限期（常量）/ 总时限到——任一触发；
                         锁存解除式（可达自证，R152）：bResetCmd 上升沿清锁存回
                         eIdle（bResetCmd 输入引脚恒可达，本件无「置位即永久」路径）；
                      四 斜率口径（代理阈值三句声明，R95）：斜率 = 移动窗
                         Δ(电压%) ÷ Δt，窗常量 T#500MS 与换算常量 0.5 秒配比
                         一致（同拍双窗声明 R100：tPrechargeMax > tFbWindow 为
                         交付默认配比，调用方改参须维持）；采样周期由窗常量代理，
                         覆盖 T#500MS 整数倍周期任务；不覆盖的极慢任务区间由
                         tonTotal 总时限闸兜底；
                      五 fUdMeas 非有限 → 故障级码 072C + bError（运行期测点坏），
                         该拍跳过斜率判据（不误判卡阻），状态机继续运行；测点坏
                         期间宽限计时同步挂起（tonSlopeLow 串 NOT _bMeasBad，
                         判据挂起 ≠ 计时挂起，恢复后计时清零续算，R64 v1.0.1）；
                      六 bKmCmd 撤回且未锁存 → 回 eIdle（bPrechargeDone 复位）；
                         eDone 相指令撤回 → 亦回 eIdle（监视件不锁完成态）；
                      七 bEnable = FALSE 的语义写死（FB33-4 声明行）：强制 eIdle +
                         双出口复位（不 faults，使能断开 ≠ 预充故障）；
                      八 TON / R_TRIG 段 0 无条件刷新（禁入分支，R7）；监视类 TON
                         IN 串故障锁存门控（FB50-1）；错峰窗 TON 自复位
                         （IN := NOT tonSlopeWin.Q，R188）；
                      九 首拍 _bInit 全量初始化；无全局、无外部变量、无物理地址。
  错误码 Codes      :
    16#0003_0728【故障级】组态非法（限值域外 / 非有限）或非法状态拦截（ELSE 兜底）
    16#0003_0729【故障级】接触器反馈超窗（tFbWindow 内未见 bKmFb）
    16#0003_072A【故障级】电压斜率持续低于下限（fSlopeMinPctS，疑似卡阻）
    16#0003_072B【故障级】预充总时限到（tPrechargeMax）
    16#0003_072C【故障级】母线电压测点非有限（该拍跳过斜率判据，不误判卡阻）
  码位反证 Note     :
    0729 / 072A / 072B 三码不可合并：反馈超窗查接触器与辅助触点、斜率不足查预充电
    阻与整流、总时限到查整段上电流程，处置人与 bPrechargeFault 相位均不同（Ramp 相
    才可能 072A，WaitFb 相才可能 0729），但 bPrechargeFault 单布尔无法区分，按 R90
    分立；0728 组态族（含 ELSE 非法态拦截，出口同形：锁存 + 早退，R90 不另立）；
    072C 与三闸码分立：测点坏期间斜率判据挂起，三闸码此时不可达，码值即相位诊断。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 正常预充：指令 → 反馈在窗内 → 斜率达标 → 电压达 90% → eDone、bPrechargeDone
    V2 反馈超 tFbWindow → 锁存故障 0729；V3 斜率持续低于限（卡阻）→ 锁存 072A
    V4 总时限到 → 锁存 072B；V5 fUdNom = 0 → 组态早退（族② 回归向量）
    V6 故障态 bResetCmd 上升沿 → 解锁回 eIdle（锁存解除可达向量）
    V7 完成后指令撤回 → 回 eIdle；V8 fUdTargetPct = 101 → 组态早退
    V9 非法枚举态（强改 eState）→ ELSE 兜底落 eFault + 0728
  修订记录 Revision  :
    2026-11-21  v1.0.0  R63 首版（批 4 · 序号 13）
    2026-11-21  v1.0.1  R64 返修 R63-D1/D2：tonSlopeLow 宽限计时串 NOT _bMeasBad
                        （测点坏期间宽限计时同步挂起）；NOT bKmCmd 撤令判据上移
                        至 eWaitFb / eRamp 分支首个 ELSIF（消除同拍竞态假锁存
                        0729 / 072B / 072A）；头注释边界二 / 边界五同步
  ==================================================================
*)
TYPE E_DL_PrechargePhase :
(
    eIdle   := 0,  // 待机：等接触器指令 / idle, waiting for the contactor command
    eWaitFb := 10, // 等反馈：指令后等接触器辅助反馈，TON 反馈窗计时 / waiting for the auxiliary feedback with the window timer
    eRamp   := 20, // 斜率监视：电压上升斜率与总时限双闸 / the ramp phase with the slope and the total time gates
    eDone   := 30, // 完成：电压达目标百分比（指令撤回即退出，不锁完成态）/ done, the voltage reached the target, the phase exits with the command
    eFault  := 40  // 锁存故障：任一闸触发，复位沿解除 / a latched fault released by the reset edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_VfdPrechargeSeq
VAR_INPUT
    bEnable       : BOOL := TRUE;   // 使能，FALSE 时强制 eIdle + 双出口复位（边界七）/ the enable, false forces the idle and resets both outlets
    bKmCmd        : BOOL := FALSE;  // 预充接触器指令 [-] / the precharge contactor command
    bKmFb         : BOOL := FALSE;  // 接触器辅助反馈 [-] / the contactor auxiliary feedback
    fUdMeas       : LREAL := 0.0;   // 母线电压实测 [伏]，必须有限 / the measured bus voltage, must be finite
    fUdNom        : LREAL := 540.0; // 额定母线电压 [伏]，须 > 0（除子与基准）/ the nominal bus voltage, must be positive
    fUdTargetPct  : LREAL := 90.0;  // 预充完成阈值 [%] 相对额定，域 (0, 100] / the completion threshold relative to the nominal
    fSlopeMinPctS : LREAL := 5.0;   // 最小电压上升斜率 [%/秒]，须 > 0 / the minimum voltage slope in percent per second
    bResetCmd     : BOOL := FALSE;  // 故障复位电平，上升沿清锁存回 eIdle（边界三解除式）/ the fault reset level, its rising edge releases the latch to idle
    tFbWindow     : TIME := T#2S;   // 反馈确认窗 [毫秒] / the feedback confirmation window
    tPrechargeMax : TIME := T#15S;  // 预充总时限 [毫秒] / the precharge total time limit
END_VAR
VAR_OUTPUT
    bPrechargeDone  : BOOL := FALSE;          // 预充完成（eDone 相电平派生）[-] / the precharge done derived from the done phase
    bPrechargeFault : BOOL := FALSE;          // 预充故障（锁存）[-] / the latched precharge fault
    eState          : E_DL_PrechargePhase;    // 状态机出口 [状态] / the state machine outlet
    bValid          : BOOL := FALSE;          // 判据可用 [-] / the criteria are usable
    eErr            : UDINT := 16#0000_0000;  // 错误码，0 = 正常 / the error code, zero is ok
    bError          : BOOL := FALSE;          // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;  // 首拍初始化标志（R310 / FB50-2）/ the first scan flag
    _eState     : E_DL_PrechargePhase := E_DL_PrechargePhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch: BOOL := FALSE;  // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _uLatch     : UDINT := 16#0000_0000; // 故障码锁存 [码]（复位沿清除，FB33-1）/ the latched fault code cleared by the reset edge
    _fPctNow    : LREAL := 0.0;   // 本拍电压百分比 [％] / the voltage percentage of this scan
    _fPctSnap   : LREAL := 0.0;   // 斜率窗快照电压百分比 [%] / the window snapshot percentage
    _fSlopeNow  : LREAL := 0.0;   // 本拍斜率 [%/秒] / the slope of this scan
    _bSlopeLow  : BOOL := FALSE;  // 斜率低于下限状态（窗际保持）/ the slope below floor state
    _bMeasBad   : BOOL := FALSE;  // 电压测点坏标记（逐拍重算）/ the measurement broken flag
    _bCfgBad    : BOOL := FALSE;  // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bFinNom    : BOOL := FALSE;  // 额定电压有限闸结果（逐拍重算）/ the nominal finiteness gate result
    _bFinTgt    : BOOL := FALSE;  // 目标阈值有限闸结果（逐拍重算）/ the target finiteness gate result
    _bFinSlope  : BOOL := FALSE;  // 斜率限值有限闸结果（逐拍重算）/ the slope limit finiteness gate result
    _bFinMeas   : BOOL := FALSE;  // 电压测点有限闸结果（逐拍重算）/ the measurement finiteness gate result
    rtReset     : R_TRIG;         // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance
    tonFb       : TON;            // 反馈窗定时器，段 0 无条件刷新 / the feedback window timer
    tonSlopeWin : TON;            // 斜率采样错峰窗（自复位，R188）/ the self resetting slope sampling window
    tonSlopeLow : TON;            // 斜率宽限计时器，段 0 无条件刷新 / the slope grace timer
    tonTotal    : TON;            // 总时限定时器，段 0 无条件刷新 / the total time timer
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_VPS_PCT     : LREAL := 100.0;  // 百分比换算系数 [%] / the percentage scaling factor
    DL_VPS_WINSEC  : LREAL := 0.5;    // 斜率窗时长换算 [秒]，与 T#500MS 配比一致（手工同步，R100）/ the window duration of half a second aligned with the timer
    DL_VPS_ZEROR   : LREAL := 0.0;    // 实数零常量 [伏] / the real zero constant
    DL_VPS_TIME0   : TIME := T#0S;    // 时间零常量 [毫秒] / the time zero constant
    DL_VPS_SLOPEWIN: TIME := T#500MS; // 斜率采样错峰窗 [毫秒]（常量提级）/ the slope sampling window lifted out of the body
    DL_VPS_SLOPEGRACE: TIME := T#1S;  // 斜率宽限期 [毫秒]（常量提级）/ the slope grace period lifted out of the body
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；监视 TON 串故障锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtReset(CLK := bResetCmd); // 复位沿 / the reset edge
tonFb(IN := (_eState = E_DL_PrechargePhase.eWaitFb) AND (NOT _bFaultLatch), PT := tFbWindow); // 反馈窗计时（串锁存门控防复位同拍重锁）/ the feedback window with the latch gate
tonSlopeWin(IN := (NOT tonSlopeWin.Q) AND (_eState = E_DL_PrechargePhase.eRamp) AND (NOT _bFaultLatch), PT := DL_VPS_SLOPEWIN); // 斜率采样错峰窗：自复位驱动（R188，禁外部沿清零）/ the self resetting slope window
tonSlopeLow(IN := (_eState = E_DL_PrechargePhase.eRamp) AND _bSlopeLow AND (NOT _bMeasBad) AND (NOT _bFaultLatch), PT := DL_VPS_SLOPEGRACE); // 斜率宽限计时（串测点坏闸：判据挂起 ≠ 计时挂起，测点恢复后计时清零续算，R64-D1）/ the slope grace timer with the latch gate
tonTotal(IN := ((_eState = E_DL_PrechargePhase.eWaitFb) OR (_eState = E_DL_PrechargePhase.eRamp)) AND (NOT _bFaultLatch), PT := tPrechargeMax); // 总时限计时（串锁存门控）/ the total time timer with the latch gate

// 段 1｜首拍初始化与复位沿作用域（R310 / R311）/ segment 1, the first scan init and the reset edge scope
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eState := E_DL_PrechargePhase.eIdle; // 状态显式落空闲 / place the state to idle
    _bFaultLatch := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _uLatch := 16#0000_0000; // 故障码锁存显式清零 / clear the latched code explicitly
    _fPctSnap := DL_VPS_ZEROR; // 斜率快照显式清零 [%] / clear the snapshot explicitly
    _bSlopeLow := FALSE; // 斜率低限态显式清零 / clear the slope state explicitly
END_IF
IF rtReset.Q THEN // 复位沿（作用域声明：清锁存 + 迁相位 + 清斜率态，R311）/ the reset edge with the declared scope
    _bFaultLatch := FALSE; // 清故障锁存（唯一解除路径，边界三自证可达）/ clear the fault latch, the only release path
    _uLatch := 16#0000_0000; // 清故障码锁存 / clear the latched code
    _eState := E_DL_PrechargePhase.eIdle; // 迁回空闲 / back to idle
    _bSlopeLow := FALSE; // 清斜率低限态 / clear the slope state
    _fPctSnap := _fPctNow; // 斜率快照对齐本拍（防复位后旧快照误判）/ align the snapshot to this scan
END_IF

// 段 2｜组态域闸结构早退（边界一，族② 判据：全部限值逐个点名，R272）/ segment 2, the structural early exit on an illegal configuration
_bFinNom := (fUdNom = fUdNom) AND ((fUdNom - fUdNom) = (fUdNom - fUdNom)); // 额定电压有限 / the nominal is finite
_bFinTgt := (fUdTargetPct = fUdTargetPct) AND ((fUdTargetPct - fUdTargetPct) = (fUdTargetPct - fUdTargetPct)); // 目标阈值有限 / the target is finite
_bFinSlope := (fSlopeMinPctS = fSlopeMinPctS) AND ((fSlopeMinPctS - fSlopeMinPctS) = (fSlopeMinPctS - fSlopeMinPctS)); // 斜率限值有限 / the slope limit is finite
_bCfgBad := (NOT _bFinNom) OR (fUdNom <= DL_VPS_ZEROR)
         OR (NOT _bFinTgt) OR (fUdTargetPct <= DL_VPS_ZEROR) OR (fUdTargetPct > DL_VPS_PCT)
         OR (NOT _bFinSlope) OR (fSlopeMinPctS <= DL_VPS_ZEROR)
         OR (tFbWindow <= DL_VPS_TIME0) OR (tPrechargeMax <= DL_VPS_TIME0); // 组态非法 / an illegal configuration
IF _bCfgBad THEN // 组态非法：结构早退（出口三件套 + RETURN，除法段不可达）/ an illegal configuration exits structurally
    eState := _eState; // 状态照实出口（冻结）/ export the state as is
    bPrechargeDone := FALSE; // 完成位复位 / the done bit resets
    bPrechargeFault := _bFaultLatch; // 故障锁存照实回放 / replay the latch
    bValid := FALSE; // 判据不可用 / the criteria are not usable
    eErr := 16#0003_0728; // 故障级：组态非法 / fault grade, an illegal configuration
    bError := TRUE; // 同拍置故障标志（R45 配对）/ raise the fault flag on the same scan
    RETURN; // 结构早退 / the structural early exit
END_IF

// 段 3｜失能分支：强制 eIdle + 双出口复位，不 faults（边界七声明行）/ segment 3, the disabled branch
IF NOT bEnable THEN // 失能 / disabled
    _eState := E_DL_PrechargePhase.eIdle; // 强制空闲 / force the idle
    _bFaultLatch := FALSE; // 锁存复位（使能断开 ≠ 预充故障）/ clear the latch
    _uLatch := 16#0000_0000; // 码锁存复位 / clear the code
    _bSlopeLow := FALSE; // 斜率态复位 / clear the slope state
    eState := _eState; // 状态出口 / the state outlet
    bPrechargeDone := FALSE; // 完成位复位 / the done bit resets
    bPrechargeFault := FALSE; // 故障位复位 / the fault bit resets
    bValid := FALSE; // 失能即不可用 / the criteria are not usable while disabled
    bError := FALSE; // 失能不是故障 / a disabled device is not a fault
    eErr := 16#0000_0000; // 失能不发码 / no code is emitted while disabled
    RETURN; // 早退 / early return
END_IF

// 段 4｜电压测点闸与百分比换算（除子 fUdNom > 0 已由段 2 证明）/ segment 4, the measurement gate and the percentage
_bFinMeas := (fUdMeas = fUdMeas) AND ((fUdMeas - fUdMeas) = (fUdMeas - fUdMeas)); // 电压测点有限 / the measurement is finite
_bMeasBad := NOT _bFinMeas; // 测点坏标记（逐拍重算）/ the broken flag recomputed
IF _bFinMeas THEN // 测点有限才换算 / the conversion runs only on a finite sample
    _fPctNow := (fUdMeas / fUdNom) * DL_VPS_PCT; // 电压百分比 [%]，除子已证 > 0 / the percentage with the proven divisor
END_IF

// 段 5｜斜率计算（错峰窗到拍采样；测点坏拍跳过，边界四五）/ segment 5, the slope sampling at the window tick
IF (_eState = E_DL_PrechargePhase.eRamp) AND (NOT _bMeasBad) AND (NOT _bFaultLatch) THEN // Ramp 相且测点好才采样 / the sampling runs only in the ramp with a good point
    IF tonSlopeWin.Q THEN // 错峰窗到拍（自复位 TON 输出）/ the window tick
        _fSlopeNow := (_fPctNow - _fPctSnap) / DL_VPS_WINSEC; // 斜率 = Δ(电压%)/Δt [%/秒]，除子为常量 0.5 / the slope with the constant divisor
        _fPctSnap := _fPctNow; // 快照推进 [%] / advance the snapshot
        _bSlopeLow := _fSlopeNow < fSlopeMinPctS; // 斜率低限态更新（窗际保持，宽限计时器累计）/ update the slope state kept across windows
    END_IF
END_IF

// 段 6｜主状态机（ENUM + CASE，ELSE 兜底；本拍事件优先于超时迁移，R275；安全相迁移带全量闸位复检，R274）/ segment 6, the main machine
CASE _eState OF
    E_DL_PrechargePhase.eIdle: // 空闲相 / the idle phase
        IF bKmCmd AND (NOT _bFaultLatch) AND (NOT _bCfgBad) THEN // 指令电平 + 全量闸位复检（R274）/ the command with the full gate recheck
            _fPctSnap := _fPctNow; // 斜率快照对齐起步拍（防旧快照误判）/ align the snapshot to the start
            _bSlopeLow := FALSE; // 斜率态复位 / clear the slope state
            _eState := E_DL_PrechargePhase.eWaitFb; // 迁入等反馈相 / enter the wait phase
        END_IF
    E_DL_PrechargePhase.eWaitFb: // 等反馈相 / the wait phase
        IF bKmFb THEN // 事件优先：反馈已到（R275 本拍合法事件先消化）/ the feedback arrived, the event goes first
            _eState := E_DL_PrechargePhase.eRamp; // 迁入斜率监视相 / enter the ramp phase
        ELSIF NOT bKmCmd THEN // 撤令事件优先段首位（R64-D2：先于 tonTotal / tonFb 超时命中，消除同拍竞态假锁存 072B / 0729）/ the withdrawal is the first eligible event before the timeouts
            _eState := E_DL_PrechargePhase.eIdle; // 回空闲 / back to idle
        ELSIF tonTotal.Q THEN // 总时限到（反馈窗内同时受总闸保护）/ the total time expired
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0003_072B; // 故障级：总时限到 / fault grade, the total time expired
            bError := TRUE; // 同拍置故障标志（R45 配对，段 8 故障分支沿用）/ raise the fault flag on the same scan
        ELSIF tonFb.Q THEN // 反馈超窗 / the feedback window expired
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0003_0729; // 故障级：反馈超窗 / fault grade, the feedback window expired
            bError := TRUE; // 同拍置故障标志（R45 配对，段 8 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_PrechargePhase.eRamp: // 斜率监视相 / the ramp phase
        IF _fPctNow >= fUdTargetPct THEN // 事件优先：电压达目标（R275）/ the target reached, the event goes first
            _eState := E_DL_PrechargePhase.eDone; // 迁入完成相 / enter the done phase
        ELSIF NOT bKmCmd THEN // 撤令事件优先段首位（R64-D2：先于 tonTotal / tonSlopeLow 超时命中，消除同拍竞态假锁存 072B / 072A）/ the withdrawal is the first eligible event before the timeouts
            _eState := E_DL_PrechargePhase.eIdle; // 回空闲 / back to idle
        ELSIF tonTotal.Q THEN // 总时限到 / the total time expired
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0003_072B; // 故障级：总时限到 / fault grade, the total time expired
            bError := TRUE; // 同拍置故障标志（R45 配对，段 8 故障分支沿用）/ raise the fault flag on the same scan
        ELSIF tonSlopeLow.Q THEN // 斜率低于下限持续宽限期（卡阻判据）/ the slope stayed below the floor through the grace
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _uLatch := 16#0003_072A; // 故障级：斜率持续不足 / fault grade, the slope stayed insufficient
            bError := TRUE; // 同拍置故障标志（R45 配对，段 8 故障分支沿用）/ raise the fault flag on the same scan
        END_IF
    E_DL_PrechargePhase.eDone: // 完成相（监视件不锁完成态，边界六）/ the done phase
        IF NOT bKmCmd THEN // 指令撤回即退出 / the phase exits with the command
            _eState := E_DL_PrechargePhase.eIdle; // 回空闲（bPrechargeDone 随相复位）/ back to idle
        END_IF
    E_DL_PrechargePhase.eFault: // 锁存故障相（驻留，解除由段 1 复位沿承担）/ the fault phase dwelling, the release belongs to the reset edge
        ; // 驻留语义由注释表达（禁自赋值死语句，R261）/ the dwell is expressed by this comment without a dead statement
    ELSE // 非法枚举值拦截（边界二：落故障相并锁存，禁静默）/ the illegal enumeration guard
        _bFaultLatch := TRUE; // 锁存故障 / latch the fault
        _uLatch := 16#0003_0728; // 故障级：非法状态拦截（归入组态族一码，出口同形，R90）/ fault grade, the illegal state in the configuration family
        bError := TRUE; // 同拍置故障标志（R45 配对，段 8 故障分支沿用）/ raise the fault flag on the same scan
        _eState := E_DL_PrechargePhase.eFault; // 落故障相 / force the fault phase
END_CASE

// 段 7｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 7, the latch to phase gate
IF _bFaultLatch AND (_eState <> E_DL_PrechargePhase.eFault) THEN // 已锁存但不在故障相 / latched outside the fault phase
    _eState := E_DL_PrechargePhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 8｜统一出口（名实双出口同源，R191）/ segment 8, the unified outlet
eState := _eState; // 状态出口 / the state outlet
bPrechargeDone := (_eState = E_DL_PrechargePhase.eDone); // 完成位与状态同源派生（eDone 相电平）/ the done bit derived from the state
bPrechargeFault := _bFaultLatch; // 故障位与锁存同源 / the fault bit from the latch
bValid := (NOT _bFaultLatch) AND (NOT _bMeasBad); // 判据可用（无锁存故障且测点好）/ usable without a latch or a broken point
IF _bFaultLatch THEN // 故障锁存回放优先（不在故障相按当下输入重新推断，R152）/ the latched fault replays first
    bValid := FALSE; // 故障相不可用 / not usable in the fault phase
    bError := TRUE; // 故障位置位（R45 配对）/ raise the fault bit
    eErr := _uLatch; // 锁存码回放 / replay the latched code
ELSIF _bMeasBad THEN // 测点坏（故障级 072C，该拍斜率判据已跳过不误判卡阻，边界五）/ the point is broken
    bError := TRUE; // 故障位置位（R45 配对）/ raise the fault bit
    eErr := 16#0003_072C; // 故障级：电压测点非有限 / fault grade, the voltage point is not finite
ELSE // 无事件 / no event
    bError := FALSE; // 无故障 / no fault
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
