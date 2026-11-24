(*
  ==================================================================
  组件名 Component  : FB_DL_RailPowerSequence
  分类   Category   : DL_Base
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  复杂度 Complexity  : 中
  版本   Version    : 1.0.3
  功能   Purpose    : 多路供电轨按序上电/断电（延时可配、断电逆序、步进超时锁存）。
  来源   Source     : self-std（供电时序公开工程语义自研）
  平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / CASE），三平台通用
  分工声明 Split     : 与 FB_DL_LaserWeldPowerSeq（工艺专用属主）分工——后者绑定
                      激光焊接工艺流；本件为通用时序原子，不绑工艺、不判负载
                      特性（R216 双向互引）。
  作者   Author     : 道莅代码库 · PLC 编程专家（R61）
  归属 Ownership     : E_DL_RailPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 uRailCount = 0 或 > 8 判组态非法故障码，不进时序
                         （边界五；R239 显式分支，禁比较算子隐式分流）；
                      二 断电逆序强制：断电步序 = 上电步序倒序（结构写死）；
                      三 步进超时按「单轨」计时（v1.0.2 修 D2）：tonStep.IN 串入逐拍派生
                         的本轨待响应量 _bRailPending（eRampUp 取 NOT abRailFb[_nStep]、
                         eRampDn 取 abRailFb[_nStep]），本轨一响应即自动复位，不再整段
                         连续计时；锁存独立码 + 解除式可达自证：故障相由复位沿迁回空闲
                         并清锁存（bReset 输入引脚恒可达，R152 自证）；
                      三A 上电推进判据「沿 OR 电平」双路（v1.0.3 修 R62-D4 中）：eRampUp
                         推进条件 = rtFb.Q（反馈上升沿）OR abRailFb[_nStep]（电平已就位
                         直过）——「反馈预闭合」处置口径：若轨在上一步计时期间或起步拍
                         前反馈电平已提前闭合（边沿被上一步消费 / 起步拍无沿），单轨超时
                         门控（_bRailPending = FALSE）与推进判据（仅沿）同源失效会静默
                         挂死；电平直过支路消除该挂死路径。断电相完成判据本为电平式
                         （NOT abRailFb[_nStep]），无此问题；
                      七 空轨断电早退（v1.0.2 修 D1）：_nCnt = 0 时收到断电沿不迁移、
                         不置 bDone、仅发信息级 0655，防伪造「完成单拍」；原负下标
                         钳位语句保留为二重防御，不再是唯一防线；
                      四 状态机 ENUM + CASE，ELSE 拦非法态；TON/R_TRIG 段 0
                         无条件刷新（禁入分支，R7）；TON IN 串故障锁存门控
                         （FB50-1）；
                      五 使能失电语义为「弃用本轮时序」（回空闲，不锁存不出
                         单拍）——R191 声明行；
                      六 无全局、无外部变量、无物理地址。
  错误码   Codes    :
    16#0001_0642【故障级】供电轨数组态非法（=0 或 >8），锁存至复位沿
    16#0001_0643【故障级】步进反馈超时（tStepTimeout 内未见该轨反馈），锁存至复位沿
    16#0001_0655【信息级】空轨断电请求已忽略（_nCnt 为 0 时无可断轨，不迁移不置 bDone）
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 3 轨、反馈逐轨到位 → uOnCount=3、bDone 单拍
    V2 第 2 轨反馈不至 → 码 0643、eFault、锁存待复位
    V3 uRailCount=0 → 码 0642、不进时序
    V4 空轨断电（abRailFb 全 FALSE、bOffCmd 上升沿）→ bDone 全拍 FALSE、
       eState 保持 eIdle、eErr=0655（v1.0.2 回归向量）
    V5 3 轨、每轨反馈延时 0.8×tStepTimeout → 全序列成功、无 0643；
       单轨延时 1.2× → 该轨锁 0643（v1.0.2 单轨超时回归向量）
    V6 轨 2 反馈预闭合（在轨 1 计时期间电平提前拉高，无沿）→ 轨 2 仍被推进、
       不锁 0643（v1.0.3 沿 OR 电平双路回归向量）
  修订记录 Revision  :
    2026-11-21  v1.0.0  R61 首版（批 3 · 序号 9）
    2026-11-21  v1.0.1  R61 终审 D1 就地修（安全侧）：空轨断电起步 _nStep<0 钳位、堵 abRailFb[-1] 越界读（R333 安全侧例外，正常路径行为零变更）
    2026-11-21  v1.0.2  R62-D1/D2 返修：①eIdle/eStable 的 rtOff 分支加 _nCnt=0 空轨早退（不迁移、不置 bDone、仅信息码 0655），原钳位降为二重防御；②新增 _bRailPending 串入 tonStep.IN 实现单轨超时；③段 0 rtFb 刷新条件扩到 eRampUp 或 eRampDn
    2026-11-21  v1.0.3  R63 返修 R4（R62-D4 中）：eRampUp 推进判据改「沿 OR 电平」双路（rtFb.Q OR abRailFb[_nStep]），反馈预闭合轨电平直过，消除单轨超时门控与推进判据同源静默挂死；头注释补「反馈预闭合」处置口径与向量 V6
  ==================================================================
*)
TYPE E_DL_RailPhase :
(
    eIdle    := 0,  // 空闲：等上电/断电命令沿 / idle, waiting for the power command edges
    eRampUp  := 10, // 上电步进：正向逐轨 / the power up stepping forward rail by rail
    eStable  := 20, // 稳定：全轨已上 / stable, all rails powered
    eRampDn  := 30  // 断电步进：逆向逐轨（边界二）/ the power down stepping in the reverse order
);
END_TYPE

FUNCTION_BLOCK FB_DL_RailPowerSequence
VAR_INPUT
    bOnCmd       : BOOL := FALSE; // 上电命令电平，上升沿发起正向时序 / the power on command level
    bOffCmd      : BOOL := FALSE; // 断电命令电平，上升沿发起逆向时序 / the power off command level
    bReset       : BOOL := FALSE; // 故障复位电平，上升沿清锁存回空闲 / the fault reset level
    uRailCount   : UDINT := 3;    // 供电轨数 [路]，合法域 1..8 / the rail count, legal from one to eight
    tStepTimeout : TIME := T#5S;  // 单轨步进超时 [毫秒] / the per rail step timeout
END_VAR
VAR_IN_OUT
    abRailFb  : ARRAY[0..7] OF BOOL; // 各轨反馈电平 [路反馈]，只读 / the rail feedback levels, read only
    atOnDelay : ARRAY[0..7] OF TIME; // 各轨上电前延时 [毫秒]，可配 / the per rail pre power delay, configurable
END_VAR
VAR_OUTPUT
    uOnCnt  : UDINT := 0;              // 已上电轨数 [路] / the powered rail count
    bDone   : BOOL := FALSE;           // 本轮时序完成单拍脉冲 [-] / the round done one shot pulse
    eState  : E_DL_RailPhase;          // 主状态机当前态 [状态] / the current state
    bError  : BOOL := FALSE;           // 故障锁存位（与锁存同源，R191）/ the fault bit from the latch
    eErr    : UDINT := 16#0000_0000;   // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit   : BOOL := FALSE;                          // 首拍初始化标志（R310）/ the first scan flag
    _eState  : E_DL_RailPhase := E_DL_RailPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bDone   : BOOL := FALSE;                          // 完成单拍内部位，段 1 预清段 5 映射 / the internal done bit
    _bFault  : BOOL := FALSE;                          // 故障锁存副本（仅复位沿清除）/ the fault latch copy
    _nStep   : DINT  := 0;                             // 当前步进轨索引 [下标] / the current step rail index
    _nCnt    : UDINT := 0;                             // 已完成轨数副本 [路] / the completed rail count copy
    _nUse    : DINT  := 0;                             // 钳位后的轨数 [路] / the clamped rail count
    _bCfgBad : BOOL  := FALSE;                         // 组态非法标记（逐拍重算）/ the configuration fault flag
    _bStepGo : BOOL  := FALSE;                         // 步进计时使能（驻留派生）[-] / the step timing enable derived from the dwell
    _bRailPending : BOOL := FALSE;                     // 本轨待响应量（逐拍派生：上电取未反馈、断电取仍反馈）[-] / the pending rail of this step, derived every scan
    _bEmptyOff : BOOL := FALSE;                        // 空轨断电早退标记（逐拍重算，信息级 0655）/ the empty bank off request flag, recomputed every scan
    rtOn     : R_TRIG;  // 上电命令沿实例，段 0 无条件刷新 / the on command edge instance
    rtOff    : R_TRIG;  // 断电命令沿实例，段 0 无条件刷新 / the off command edge instance
    rtReset  : R_TRIG;  // 复位沿实例，段 0 无条件刷新 / the reset edge instance
    rtFb     : R_TRIG;  // 步进轨反馈沿实例，段 0 无条件刷新 / the step rail feedback edge instance
    tonStep  : TON;     // 步进超时计时器，段 0 无条件刷新 / the step timeout timer
END_VAR
VAR CONSTANT
    DL_RPS_RMAX : DINT := 8; // 供电轨容量上界 [路]，与数组容量一致 / the rail capacity aligned with the array
END_VAR

// 段 0｜定时器与沿检测无条件周期刷新（禁入分支，R7；TON IN 串故障锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtOn(CLK := bOnCmd); // 上电沿 / the on edge
rtOff(CLK := bOffCmd); // 断电沿 / the off edge
rtReset(CLK := bReset); // 复位沿 / the reset edge
IF (_eState = E_DL_RailPhase.eRampUp) OR (_eState = E_DL_RailPhase.eRampDn) THEN // 两相步进相均刷当前轨反馈（v1.0.2 扩相，防断电相恒刷 0 号轨）/ both stepping phases watch the current rail
    rtFb(CLK := abRailFb[_nStep]); // 当前步进轨反馈沿 / the current step rail feedback edge
ELSE // 非步进相：非步进相固定刷新 0 号轨（保持无条件调用形态）/ the other phases refresh on the rail zero slot
    rtFb(CLK := abRailFb[0]); // 固定下标刷新 / the fixed index refresh
END_IF
_bStepGo := (_eState = E_DL_RailPhase.eRampUp) OR (_eState = E_DL_RailPhase.eRampDn); // 步进相驻留派生 / the dwell derived enable
// 单轨待响应量：只由「本相 + 本轨反馈」派生，本轨一响应即落 FALSE 使 TON 自动复位（v1.0.2 修 D2）/ the per rail pending, the timer resets by itself once this rail responds
IF _eState = E_DL_RailPhase.eRampUp THEN // 上电相：本轨尚未反馈即待响应 / the ramp up phase waits for the feedback to appear
    _bRailPending := NOT abRailFb[_nStep]; // 未反馈为待响应 / pending while the feedback is still absent
ELSIF _eState = E_DL_RailPhase.eRampDn THEN // 断电相：本轨仍反馈即待响应 / the ramp down phase waits for the feedback to vanish
    _bRailPending := abRailFb[_nStep]; // 仍反馈为待响应 / pending while the feedback is still present
ELSE // 其余相无单轨待响应语义 / no per rail pending outside the stepping phases
    _bRailPending := FALSE; // 非步进相清待响应 / clear the pending outside the stepping phases
END_IF
tonStep(IN := _bStepGo AND (NOT _bFault) AND _bRailPending, PT := tStepTimeout); // 单轨超时（串故障锁存门控 + 本轨待响应，FB50-1）/ the per rail timeout with the latch gate and the rail pending

// 段 1｜首拍初始化与单拍标志预清（FB32-1；R256）/ segment 1, the first scan init and the preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _nStep := 0; // 步进索引显式清零 / clear the step index explicitly
    _nCnt := 0; // 完成轨数显式清零 / clear the completed count explicitly
    _eState := E_DL_RailPhase.eIdle; // 状态显式落空闲 / place the state to idle
END_IF
IF rtReset.Q THEN // 复位沿（作用域：清锁存 + 迁相位 + 清步进量，R311）/ the reset edge with the declared scope
    _bFault := FALSE; // 清故障锁存 / clear the fault latch
    _nStep := 0; // 清步进索引 / clear the step index
    _nCnt := 0; // 清完成轨数 / clear the completed count
    _eState := E_DL_RailPhase.eIdle; // 迁回空闲 / back to idle
END_IF
_bDone := FALSE; // 完成单拍预清零 / preset the done pulse false
_bCfgBad := FALSE; // 组态标记预清零 / preset the configuration flag false
_bEmptyOff := FALSE; // 空轨早退标记预清零（单拍信息位，段 5 映射 0655）/ preset the empty bank flag false

// 段 2｜组态域闸（轨数合法域 1..8，边界一）/ segment 2, the rail count gate
_nUse := UDINT_TO_DINT(uRailCount); // 轨数升位接管（超 DINT 域转负即被下界捕获）/ take the rail count widened, an overflow lands below the floor
IF (_nUse < 1) OR (_nUse > DL_RPS_RMAX) THEN // 轨数越域 / the rail count out of the domain
    _bCfgBad := TRUE; // 置组态非法标记 / raise the configuration flag
    _bFault := TRUE; // 锁存故障（0642，段 5 回放）/ latch the fault
END_IF
IF _nUse < 1 THEN // 下界钳位（防越界索引）/ the floor clamp for the index safety
    _nUse := 1; // 钳到一 / clamp to one
END_IF
IF _nUse > DL_RPS_RMAX THEN // 上界钳位 / the ceiling clamp
    _nUse := DL_RPS_RMAX; // 钳到容量 / clamp to the capacity
END_IF

// 段 3｜主状态机（ENUM + CASE，ELSE 拦非法态；安全相迁移带全量闸位复检，R274）/ segment 3, the main machine
CASE _eState OF
    E_DL_RailPhase.eIdle: // 空闲相 / the idle phase
        IF rtOn.Q AND (NOT _bFault) AND (NOT _bCfgBad) THEN // 上电沿 + 全量闸位复检（R274）/ the on edge with the full gate recheck
            _nStep := 0; // 从 0 号轨正向起步 / start forward from the rail zero
            _nCnt := 0; // 完成轨数归零 / reset the completed count
            _eState := E_DL_RailPhase.eRampUp; // 迁入上电步进相 / enter the ramp up phase
        ELSIF rtOff.Q AND (NOT _bFault) AND (NOT _bCfgBad) THEN // 断电沿 + 全量闸位复检 / the off edge with the recheck
            IF _nCnt = 0 THEN // 空轨早退（v1.0.2 修 D1）：无已上电轨则无从逆序断电 / the empty bank early exit, no powered rail to cut
                _bEmptyOff := TRUE; // 仅置信息级标记，不迁移、不置 bDone / raise the informational flag only, no migration and no done pulse
            ELSE // 有已上电轨：正常逆序起步 / a powered bank, start the reverse sequence
                _nStep := UDINT_TO_DINT(_nCnt) - 1; // 从已完成末轨逆向起步（断电逆序，边界二）/ start reverse from the last powered rail
                IF _nStep < 0 THEN // 二重防御：空轨已在上面早退，本钳位不再是唯一防线（R61-D1 保留）/ a second line of defence, no longer the only guard
                    _nStep := 0; // 钳到 0 号轨，防 abRailFb[-1] 越界读 / clamp to the rail zero against the negative index read
                END_IF
                _eState := E_DL_RailPhase.eRampDn; // 迁入断电步进相 / enter the ramp down phase
            END_IF
        END_IF
    E_DL_RailPhase.eRampUp: // 上电步进相 / the ramp up phase
        IF rtFb.Q OR abRailFb[_nStep] THEN // 推进判据「沿 OR 电平」双路（v1.0.3 修 R62-D4）：沿到或电平已预闭合均直过，防超时门控与推进判据同源静默挂死 / the advance criterion in the edge OR level dual path, a pre closed feedback passes by level so the timeout gate and the advance criterion cannot fail together in silence
            _nCnt := _nCnt + 1; // 完成轨数推进 / advance the completed count
            _nStep := _nStep + 1; // 步进索引推进 / advance the step index
            IF _nStep >= _nUse THEN // 全轨完成 / all rails done
                _bDone := TRUE; // 置完成单拍 / raise the done pulse
                _eState := E_DL_RailPhase.eStable; // 迁入稳定相 / enter the stable phase
            END_IF
        ELSIF tonStep.Q THEN // 步进超时（边界三）/ the step timeout
            _bFault := TRUE; // 锁存超时故障（0643）/ latch the timeout fault
        ELSIF _bFault THEN // 前置条件消失出口 / the prerequisite gone exit
            _eState := E_DL_RailPhase.eIdle; // 迁回空闲（锁存迁移由段 4 收口）/ back to idle
        END_IF
    E_DL_RailPhase.eStable: // 稳定相 / the stable phase
        IF rtOff.Q AND (NOT _bFault) THEN // 断电沿 + 闸位复检 / the off edge with the recheck
            IF _nCnt = 0 THEN // 空轨早退（与 eIdle 同口径，v1.0.2 修 D1）：异常态下 _nCnt 被清零亦不得伪造完成 / the same empty bank exit as the idle phase
                _bEmptyOff := TRUE; // 仅置信息级标记，不迁移、不置 bDone / raise the informational flag only
            ELSE // 有已上电轨：正常逆序起步 / a powered bank, start the reverse sequence
                _nStep := UDINT_TO_DINT(_nCnt) - 1; // 逆向起步（断电逆序）/ start reverse
                IF _nStep < 0 THEN // 二重防御（空轨已在上面早退）/ a second line of defence
                    _nStep := 0; // 钳到 0 号轨，防负下标越界读 / clamp to the rail zero against the negative index read
                END_IF
                _eState := E_DL_RailPhase.eRampDn; // 迁入断电步进相 / enter the ramp down phase
            END_IF
        ELSIF _bFault THEN // 前置条件消失 / the prerequisite gone
            _eState := E_DL_RailPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    E_DL_RailPhase.eRampDn: // 断电步进相（逆序，边界二）/ the ramp down phase in the reverse order
        IF NOT abRailFb[_nStep] THEN // 当前轨反馈已消失（断电完成判据）/ the current rail feedback gone
            IF _nCnt > 0 THEN // 无符号下溢闸（0 减 1 会回绕，先判再减）/ the underflow guard before the decrement
                _nCnt := _nCnt - 1; // 完成轨数回退 / step the completed count back
            END_IF
            _nStep := _nStep - 1; // 逆向推进 / step reverse
            IF _nStep < 0 THEN // 全轨断完 / all rails off
                _nCnt := 0; // 完成轨数清零 / clear the completed count
                _bDone := TRUE; // 置完成单拍 / raise the done pulse
                _eState := E_DL_RailPhase.eIdle; // 迁回空闲 / back to idle
            END_IF
        ELSIF tonStep.Q THEN // 步进超时 / the step timeout
            _bFault := TRUE; // 锁存超时故障 / latch the timeout fault
        ELSIF _bFault THEN // 前置条件消失 / the prerequisite gone
            _eState := E_DL_RailPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_RailPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置故障锁存 / latch the fault
END_CASE

// 段 4｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 4, the latch to phase gate
IF _bFault AND (_eState <> E_DL_RailPhase.eIdle) THEN // 已锁存但不在空闲相（本件锁存即弃用本轮迁空闲）/ latched, the round is discarded to idle
    _eState := E_DL_RailPhase.eIdle; // 迁回空闲 / back to idle
END_IF

// 段 5｜统一出口（内部副本单点映射；故障码锁存回放，R187）/ segment 5, the unified outlet
uOnCnt := _nCnt; // 已上电轨数出口 / the powered count outlet
bDone := _bDone; // 完成单拍出口 / the done pulse outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    IF _bCfgBad THEN // 组态成因（独立码值，R190）/ the configuration cause
        eErr := 16#0001_0642; // 故障级：轨数组态非法 / fault grade, the illegal rail count
    ELSE // 超时成因 / the timeout cause
        eErr := 16#0001_0643; // 故障级：步进反馈超时 / fault grade, the step feedback timeout
    END_IF
ELSE // 无故障 / no fault
    IF _bEmptyOff THEN // 空轨断电请求已忽略（信息级不置 bError，R285）/ the empty bank request ignored, informational without bError
        eErr := 16#0001_0655; // 信息级：空轨断电请求已忽略 / informational, the empty bank off request ignored
    ELSE // 无事件 / no event
        eErr := 16#0000_0000; // 正常 / ok
    END_IF
END_IF
END_FUNCTION_BLOCK
