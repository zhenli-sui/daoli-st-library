(*
  ==================================================================
  组件名 Component  : FB_DL_AnalogOutFailsafe
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.1
  功能   Purpose    : 模拟量输出失保通道：正常相把 fOutReq（0~100 钳位）经
                      斜坡限速送达 fOutAct；看门狗超时 / 请求非有限 / 配置
                      非法任一成立即锁存故障，按 eFailMode 走冻结或安全值
                      侧（安全值侧斜坡回程限速，不跳变）。bError 锁存，
                      解除式（可达自证·电平式 v1.0.1）：使能 + 心跳在 +
                      无超时 + 配置恢复 + 请求有限 → 清锁存回正常相。
  来源   Source     : t2-8-ne43（NE43 失效安全方向口径：借「失效落安全侧」
                      语义，实现零源码复制）
  互引   Cross-ref  : FB_DL_AnalogSignalHealth（上游信号健康诊断件，可把其
                      bHealthy 布到本件 bWatchdog 心跳引脚）
  平台   Platform   : 纯 IEC 61131-3（TON/R_TRIG/ENUM+CASE/LREAL 四则）
  依赖   Depends    : 仅 Standard.library（TON/R_TRIG 属标准件）
  归属   Ownership  : E_DL_FailMode 与 E_DL_AnaOutFsState 属主为本文件
                      （全库唯一定义，R264）；引用件只引用不重声明。
  设计偏差 Deviation: 时间基准按本库「时间注入」纪律：新增输入 fCallCycleS
                      （调用方注入扫描周期 [s]，FB_DL_CycleTimeMeasure 语义），
                      本件不读平台时刻函数；斜坡步长 = fRampRatePctS × fCallCycleS。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 输出 0~100 显式钳位 + 非有限三闸（请求/安全值/周期）
                      + 除法零处（无除法面）/R5 全变量双语同行注释
                      R6 ENUM+CASE 含 ELSE 兜底，eFault 分支显式出现
                      R7 tonWd 段 0 无条件刷新（IN = NOT bWatchdog，
                      v1.0.1 订正反相：断线达整定才超时）
                      R8 钳位与阈值常量化
  错误码 Codes      : 16#0007_1001【故障级·锁存】看门狗超时（心跳丢失）
                      16#0007_1002【故障级·锁存】配置非法（斜坡速率 ≤ 0 /
                      安全值非有限 / 扫描周期 ≤ 0）
                      16#0007_1003【故障级·锁存】请求非有限（NaN/±Inf）
                      锁存解除（可达自证·电平式 v1.0.1）：bEnable + 心跳在
                      （bWatchdog=TRUE 且 tonWd 未超时）+ 配置恢复 + 请求
                      有限 → 清锁存回 eNormal；三成因解除条件均为电平恒可
                      满足，无「置位即永久」路径（R66 终审修：弃沿式解除，
                      恒真心跳缺省组态下沿式对 1002/1003 不可达）。
  码位反证 Note     : 1001/1002/1003 分立依据（R190 归因唯一）：三成因
                      （超时/配置/请求）各有独立观测入口与独立处置面，
                      禁共用码导致某成因永不赋值。
  验收   Acceptance : V1 正常跟踪：斜坡达目标 + bAtCmd 语义 ｜ V2 心跳断
                      tWdTimeout → 锁存 1001 + 按 eFailMode 动作 ｜
                      V3 fOutReq=NaN → 锁存 1003 + 安全侧 ｜ V4 fRampRatePctS=0
                      → 锁存 1002 ｜ V5 故障中恢复心跳 + 使能 → 解锁回正常
                      ｜ V6 eFreeze → 冻结保持当前值不回程 ｜ V7 全程输出
                      不出 [0,100]
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 3 序 7）
                      2026-11-22  v1.0.1  R66 终审就地修（3 严重）：①tonWd
                      IN 反相订正（IN=NOT bWatchdog，原写法健康心跳驻留
                      tWdTimeout 即误锁 1001、真断线反不检测）；②锁存期
                      eFrozen/eSafeHold 运行路径打通（段 6 弃整体旁路，段 5
                      改锁存起点单次迁入）；③锁存解除弃沿式改电平式（删
                      rtWdRecover，恒真心跳下沿式对 1002/1003 不可达）。
  ==================================================================
*)
TYPE E_DL_FailMode :
(
    eFreeze    := 0,  // 失保动作=冻结保持当前输出 [-] / the fail action freezes the current output
    eSafeValue := 1   // 失保动作=斜坡回程到 fSafeValue [-] / the fail action ramps to the safe value
);
END_TYPE

TYPE E_DL_AnaOutFsState :
(
    eIdle    := 0,   // 失能：bEnable=FALSE，输出冻结保持 [-] / the disabled phase, outputs frozen
    eNormal  := 10,  // 正常：斜坡跟踪请求 [-] / the normal phase, ramping toward the request
    eFrozen  := 20,  // 失保冻结：保持故障瞬间的当前值 [-] / the fail frozen phase, holding the fault time value
    eSafeHold:= 30,  // 失保安全值：斜坡回程到安全值并保持 [-] / the fail safe phase, ramping to the safe value
    eFault   := 40   // 锁存故障：锁存驻留，解除沿回正常 [-] / the latched fault phase dwelling until the release edge
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalogOutFailsafe
VAR_INPUT
    fOutReq      : LREAL := 0.0;    // 输出请求 [%]，0~100 钳位，非有限按安全侧 / the output request, clamped, non finite goes safe side
    bEnable      : BOOL := FALSE;   // 使能，FALSE 冻结输出保持（失能语义写死，FB33-4）[-] / the enable, false freezes the output
    bWatchdog    : BOOL := TRUE;    // 上游心跳电平（TRUE=心跳在）[-] / the upstream heartbeat level
    eFailMode    : E_DL_FailMode := E_DL_FailMode.eSafeValue; // 失保模式（冻结/安全值）[-] / the fail mode
    fSafeValue   : LREAL := 0.0;    // 失保安全值 [%]，须有限（非有限判配置非法）/ the fail safe value, must be finite
    fRampRatePctS: LREAL := 10.0;   // 斜坡速率 [%/s]，须 > 0（≤ 0 判配置非法）/ the ramp rate, must be positive
    tWdTimeout   : TIME := T#2S;    // 看门狗超时整定 [ms] / the watchdog timeout setting
    fCallCycleS  : LREAL := 0.01;   // 调用方注入扫描周期 [s]，须 > 0 / the caller injected scan cycle in seconds
END_VAR
VAR_OUTPUT
    fOutAct      : LREAL := 0.0;    // 实际输出 [%]，全程钳位 0~100 / the actual output, always clamped 0 to 100
    eState       : E_DL_AnaOutFsState := E_DL_AnaOutFsState.eIdle; // 状态机出口 [状态] / the state machine outlet
    bError       : BOOL := FALSE;   // 故障锁存标志（解除沿清除，R45 配对）/ the latched fault flag, cleared by the release edge
    uErrorId     : UDINT := 16#0000_0000; // 故障码，0=正常；锁存回放至解除沿 [码] / the latched fault code replayed to the release edge
END_VAR
VAR
    _bInit       : BOOL := FALSE;   // 首拍初始化标志（R310）/ the first scan flag
    _eState      : E_DL_AnaOutFsState := E_DL_AnaOutFsState.eIdle; // 内部状态寄存器 / the internal state register
    _bFaultLatch : BOOL := FALSE;   // 故障锁存副本（仅解除沿清除）/ the fault latch copy, cleared only by the release edge
    _uLatch      : UDINT := 16#0000_0000; // 故障码锁存副本（仅解除沿清除，FB33-1）/ the latched code copy
    _bCfgOk      : BOOL := FALSE;   // 本拍配置有效性 [-] / the per scan configuration validity
    _fStep       : LREAL := 0.0;    // 本拍斜坡步长 [%] / the per scan ramp step
    _fTarget     : LREAL := 0.0;    // 本拍斜坡目标 [%] / the per scan ramp target
    _bClampReq   : BOOL := FALSE;   // 本拍请求被钳位标志（信息性，未设码）[-] / the per scan request clamp flag, informational
    tonWd        : TON;             // 看门狗定时器实例，段 0 无条件刷新 / the watchdog timer instance refreshed unconditionally
END_VAR
VAR CONSTANT
    AOF_OUT_MIN  : LREAL := 0.0;      // 输出下限 [%] / the output lower clamp
    AOF_OUT_MAX  : LREAL := 100.0;    // 输出上限 [%] / the output upper clamp
    AOF_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    AOF_ERR_NONE : UDINT := 16#0000_0000; // 无故障 [码] / no fault [code]
    AOF_ERR_WDTO : UDINT := 16#0007_1001; // 码 1001：看门狗超时 / code 1001, watchdog timeout
    AOF_ERR_CFG  : UDINT := 16#0007_1002; // 码 1002：配置非法 / code 1002, illegal configuration
    AOF_ERR_REQ  : UDINT := 16#0007_1003; // 码 1003：请求非有限 / code 1003, non finite request
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜定时器与沿检测无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      The timer and edge instances refresh unconditionally, never in a branch
 *-----------------------------------------------------------------------------*)
tonWd(IN := NOT bWatchdog, PT := tWdTimeout);   // 心跳断线计时（v1.0.1 订正 IN 反相：断线达整定才超时）/ the heartbeat loss timing, IN inverted per R66 review

(*------------------------------------------------------------------------------
 * 段 1｜首拍初始化：输出从钳位后的请求值起（避免首拍跳变）
 *      First scan init: the output starts from the clamped request
 *-----------------------------------------------------------------------------*)
IF NOT _bInit THEN
    _bInit := TRUE;                         // 首拍标志落位 / arm the first scan flag
    IF (fOutReq >= AOF_OUT_MIN) AND (fOutReq <= AOF_OUT_MAX) AND (fOutReq = fOutReq) THEN
        fOutAct := fOutReq;                 // 有限且在域内直接落位 / land directly when finite and inside
    ELSE
        fOutAct := AOF_OUT_MIN;             // 首拍非法请求落安全下限 / land on the safe lower limit
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 2｜配置闸（归因唯一 R190）：速率 ≤ 0 / 安全值非有限 / 周期 ≤ 0 → 配置非法
 *      The configuration gate with unique attribution per cause
 *-----------------------------------------------------------------------------*)
_bCfgOk := (fRampRatePctS > 0.0)
       AND (fSafeValue = fSafeValue) AND (ABS(fSafeValue) <= AOF_FIN_MAX)
       AND (fCallCycleS > 0.0) AND (fCallCycleS = fCallCycleS);   // 三配置面逐项闸 / each configuration face gated

(*------------------------------------------------------------------------------
 * 段 3｜故障成因判定与锁存（锁存回放，不在故障相按当下输入重推断）
 *      Fault cause determination and latching, replayed not re inferred in the fault phase
 *-----------------------------------------------------------------------------*)
IF tonWd.Q THEN                                // 成因一：心跳超时 / cause one, the heartbeat timeout
    _bFaultLatch := TRUE;
    _uLatch := AOF_ERR_WDTO;
ELSIF NOT _bCfgOk THEN                         // 成因二：配置非法 / cause two, illegal configuration
    _bFaultLatch := TRUE;
    _uLatch := AOF_ERR_CFG;
ELSIF (fOutReq <> fOutReq) OR (ABS(fOutReq) > AOF_FIN_MAX) THEN  // 成因三：请求非有限 / cause three, non finite request
    _bFaultLatch := TRUE;
    _uLatch := AOF_ERR_REQ;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜锁存解除（可达自证）：使能 + 无超时 + 配置恢复 + 心跳恢复上升沿
 *      The latch release, reachable by construction: enable, no timeout, config ok, heartbeat re entry edge
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch AND bEnable AND bWatchdog AND (NOT tonWd.Q) AND _bCfgOk
   AND (fOutReq = fOutReq) AND (ABS(fOutReq) <= AOF_FIN_MAX) THEN
    _bFaultLatch := FALSE;                     // 清锁存副本（v1.0.1 电平式解除：三成因条件恒可满足）/ clear the latch, level based, always satisfiable
    _uLatch := AOF_ERR_NONE;                   // 清锁存码 / clear the latched code
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜输出映射（名实双出口 R191）：bError/uErrorId 与锁存副本同源
 *      The outlet mapping, the flag and code mirror the latch copy
 *-----------------------------------------------------------------------------*)
IF _bFaultLatch THEN
    bError   := TRUE;                          // 故障标志（R45 配对）/ the fault flag
    uErrorId := _uLatch;                       // 锁存回放 / the latched replay
    IF (_eState = E_DL_AnaOutFsState.eIdle) OR (_eState = E_DL_AnaOutFsState.eNormal) THEN
        _eState := E_DL_AnaOutFsState.eFault;  // 锁存起点迁入故障相（v1.0.1：单次迁入，失保相驻留期不再被回写）/ enter the fault phase at latch onset only
    END_IF
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜状态机（ENUM + CASE，含 ELSE 兜底；eFault 分支显式出现）
 *      The state machine with the else catch all, the fault phase explicit
 *-----------------------------------------------------------------------------*)
IF (NOT bEnable) AND (NOT _bFaultLatch) THEN   // 失能回空闲（v1.0.1：锁存期失保动作优先，不被失能覆盖）/ disable forces idle, the fail action outranks while latched
    _eState := E_DL_AnaOutFsState.eIdle;
END_IF
CASE _eState OF
    E_DL_AnaOutFsState.eIdle:                  // 失能相：输出冻结保持 / the idle phase, output frozen
        IF bEnable AND _bCfgOk AND (NOT _bFaultLatch) THEN
            _eState := E_DL_AnaOutFsState.eNormal;  // 使能迁入正常相 / enter the normal phase on enable
        END_IF
    E_DL_AnaOutFsState.eNormal:                // 正常相：斜坡跟踪请求 / the normal phase, ramp tracking
        IF NOT bEnable THEN
            _eState := E_DL_AnaOutFsState.eIdle;    // 使能撤销回空闲 / back to idle on disable
        ELSIF _bFaultLatch THEN
            _eState := E_DL_AnaOutFsState.eFault;   // 锁存迁入故障相 / enter the fault phase on latch
        ELSE
            IF (fOutReq <> fOutReq) OR (ABS(fOutReq) > AOF_FIN_MAX) THEN
                _fTarget := AOF_OUT_MIN;            // 请求非有限按安全侧下限处理（头注契约）/ a non finite request goes to the safe lower limit
            ELSE
                _bClampReq := FALSE;                // 重置钳位信息位 / reset the clamp flag
                _fTarget := fOutReq;                // 合法请求直取 / take the valid request
                IF _fTarget < AOF_OUT_MIN THEN
                    _fTarget := AOF_OUT_MIN;        // 请求下钳 / clamp the request low
                    _bClampReq := TRUE;             // 记录钳位（信息性）/ mark the clamp
                END_IF
                IF _fTarget > AOF_OUT_MAX THEN
                    _fTarget := AOF_OUT_MAX;        // 请求上钳 / clamp the request high
                    _bClampReq := TRUE;
                END_IF
            END_IF
            _fStep := fRampRatePctS * fCallCycleS;  // 本拍步长 [%]（周期已闸 > 0）/ the per scan step, the cycle gated
            IF fOutAct < _fTarget - 1.0E-9 THEN
                fOutAct := fOutAct + _fStep;        // 向上斜坡 / ramp up
                IF fOutAct > _fTarget THEN fOutAct := _fTarget; END_IF  // 不越过目标 / never past the target
            ELSIF fOutAct > _fTarget + 1.0E-9 THEN
                fOutAct := fOutAct - _fStep;        // 向下斜坡 / ramp down
                IF fOutAct < _fTarget THEN fOutAct := _fTarget; END_IF
            END_IF
        END_IF
    E_DL_AnaOutFsState.eFrozen:                // 失保冻结相：保持当前值（eFreeze 模式落点）/ the fail frozen phase
        IF NOT _bFaultLatch THEN
            _eState := E_DL_AnaOutFsState.eNormal;  // 解除后回正常 / back to normal on release
        ELSIF eFailMode = E_DL_FailMode.eSafeValue THEN
            _eState := E_DL_AnaOutFsState.eSafeHold; // 驻留期切安全值模式：一次完成切换沿 / a mode switch during the dwell lands in one edge
        END_IF
    E_DL_AnaOutFsState.eSafeHold:              // 失保安全值相：斜坡回程到安全值 / the fail safe phase
        IF NOT _bFaultLatch THEN
            _eState := E_DL_AnaOutFsState.eNormal;  // 解除后回正常 / back to normal on release
        ELSIF eFailMode = E_DL_FailMode.eFreeze THEN
            _eState := E_DL_AnaOutFsState.eFrozen;  // 驻留期切冻结模式：一次完成切换沿 / a mode switch during the dwell lands in one edge
        ELSE
            _fStep := fRampRatePctS * fCallCycleS;  // 回程同样限速（斜坡回程限速契约）/ the return path is rate limited too
            IF fOutAct < fSafeValue - 1.0E-9 THEN
                fOutAct := fOutAct + _fStep;
                IF fOutAct > fSafeValue THEN fOutAct := fSafeValue; END_IF
            ELSIF fOutAct > fSafeValue + 1.0E-9 THEN
                fOutAct := fOutAct - _fStep;
                IF fOutAct < fSafeValue THEN fOutAct := fSafeValue; END_IF
            END_IF
        END_IF
    E_DL_AnaOutFsState.eFault:                 // 故障相（显式分支）：按失保模式落冻结/安全值侧
        // eFault 分支动作：本拍按 eFailMode 迁入 eFrozen（保持）或 eSafeHold（回程）；
        // 拍 N 进入故障相 → 本拍完成模式落点 → 拍 N+1 起在对应失保相执行保持/回程
        // the fault phase lands the fail mode in one scan, the hold or ramp runs from the next scan
        IF NOT _bFaultLatch THEN
            _eState := E_DL_AnaOutFsState.eNormal;  // 解除回正常 / back to normal on release
        ELSIF eFailMode = E_DL_FailMode.eFreeze THEN
            _eState := E_DL_AnaOutFsState.eFrozen;  // 冻结模式落点 / land the freeze mode
        ELSE
            _eState := E_DL_AnaOutFsState.eSafeHold; // 安全值模式落点（含非法枚举兜底）/ land the safe mode, also the else style fallback
        END_IF
    ELSE                                        // 非法状态兜底（R 非法态拦截）：落故障相并锁存配置码
        _eState := E_DL_AnaOutFsState.eFault;   // 强制故障相 / force the fault phase
        _bFaultLatch := TRUE;                   // 非法态按锁存处置（R ELSE 兜底不静默）/ an illegal state latches
        _uLatch := AOF_ERR_CFG;
        bError := TRUE;                         // 名实双出口同步 / sync the outlets
        uErrorId := _uLatch;
    END_CASE

(*------------------------------------------------------------------------------
 * 段 7｜输出钳位（双保险切断线）与状态发布 / segment 7, the output clamp and state publish
 *-----------------------------------------------------------------------------*)
IF fOutAct < AOF_OUT_MIN THEN
    fOutAct := AOF_OUT_MIN;                     // 输出下限钳位 / clamp the output low
END_IF
IF fOutAct > AOF_OUT_MAX THEN
    fOutAct := AOF_OUT_MAX;                     // 输出上限钳位 / clamp the output high
END_IF
IF (fOutAct <> fOutAct) THEN                    // 防御：任何路径不得把非有限送出口 / no non finite may reach the outlet
    fOutAct := AOF_OUT_MIN;                     // 落安全下限 / land on the safe lower limit
    _eState := E_DL_AnaOutFsState.eFault;       // 落故障相 / land the fault phase
    _bFaultLatch := TRUE;
    _uLatch := AOF_ERR_REQ;
    bError := TRUE;
    uErrorId := _uLatch;
END_IF
eState := _eState;                              // 状态出口（名实双出口 R191）/ publish the state
END_FUNCTION_BLOCK
