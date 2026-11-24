(*
  ==================================================================
  组件名 Component  : FB_DL_InputShaperZv
  分类   Category   : DL_Algo
  复杂度 Complexity  : 中
  版本   Version    : 1.0.1
  功能   Purpose    : ZV（Zero Vibration）双脉冲输入整形器。按阻尼比 ζ 与固有频率
                      ωn 合成两脉冲序列（幅值 1/(1+A) 与 A/(1+A)，间隔 Δt），
                      触发沿到达时先出首脉冲，经 Δt 后出次脉冲，用于抑制指令
                      阶跃激起的残余振动。
  来源   Source     : self-std（公开控制理论 ZV 整形器语义）
  溯源   Origin     : ZV 输入整形属公开控制理论（Singer & Seering 公开文献语义），
                      道莅 clean-room 自研实现，未复制任何厂商私有库源码。
  平台   Platform   : 纯 IEC 61131-3（EXPT / SQRT / TON / R_TRIG / 标准转换函数）
  分工声明 Split     : 与 FB_DL_NotchFilter（反馈侧频域抑制属主）分工——后者对
                      测量信号做在线滤波；本件只整形前馈指令时序，不接管反馈、
                      不做滤波、不判机械到位。
  作者   Author     : 道莅代码库 · PLC 编程专家（R60）
  归属 Ownership     : E_DL_ZvPhase 属主为本文件（全库唯一定义，R264）；
                      引用件只引用不重声明（D13 返修补行）。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 时间口径单一化（R342）：Δt 内部一律以秒计算，转 TIME 时
                         统一乘 1000 后经 LREAL_TO_TIME 落毫秒，禁跨日历类型链；
                      二 采样约定：首脉冲在触发沿当拍输出，次脉冲在 Δt 到期拍
                         输出，两脉冲均为单拍（统一出口段每拍先预置 FALSE，R256）；
                      三 有限性闸显式枚举全部浮点输入（R272 自证：声明区 LREAL
                         输入共 2 个——fWn 与 fZeta——闸内逐个引用，无遗漏）；
                      四 域闸：fWn ≤ 0 判故障级码并冻结输出；ζ 域 [0, 0.95) 钳位，
                         越域置信息级码（ζ = 0 为无阻尼极限，取 A = 1 双等幅脉冲，
                         √(1−ζ²) = 1 结构性安全）；
                      五 使能 bEnable = FALSE 时语义为「冻结保持 + 清未决次脉冲」
                         （不再出脉冲，幅值与间隔保持末次有效值）——R191 声明行；
                      六 故障解除路径：eFault 相由复位沿迁回空闲并清锁存（bReset
                         为输入引脚，恒可达，R152 自证）；
                      七 时序滞后声明（D12 返修登记）：tonGap 的 PT 取上拍
                         _tDelay（段 0 刷新先于段 3 参数换算），ωn 突变拍 Δt
                         生效滞后一扫描拍；上层如需同拍生效，须在触发前一拍
                         稳定参数（显式声明，非遗漏）。
  错误码   Codes    :
    16#0002_0610【信息级】阻尼比 ζ 越域已钳位到 [0, 0.95)
    16#0002_0611【故障级】浮点入参非有限（NaN / Inf），输出冻结
    16#0002_0612【故障级】固有频率 ωn ≤ 0（域非法），输出冻结
  验收   Acceptance :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 ωn=10 rad/s、ζ=0 → A=1、幅值各 0.5、Δt=0.314159 s（314 ms）
    V2 ωn=10 rad/s、ζ=0.3 → A=0.371、幅值 0.7290/0.2710、Δt=0.3296 s
    V3 ζ=1.5 → 钳到 0.95、码 0610、序列仍出（bValid = TRUE）
    V4 ωn=0 → 码 0612、两脉冲恒假、eState = eFault
  修订记录 Revision  :
    2026-11-21  v1.0.0  R60 首版（批 2 · 序号 8）
    2026-11-21  v1.0.1  R61 返修：D12 边界段声明 tonGap PT 一拍滞后口径；
                        D13 补 E_DL_ZvPhase 属主 Ownership 行
  ==================================================================
*)

TYPE E_DL_ZvPhase :
(
    eIdle  := 0,  // 空闲：无未决次脉冲 / idle, no pending second pulse
    eWaitB := 10, // 等次脉冲：首脉冲已出，Δt 计时中 / waiting for the second pulse while the gap runs
    eFault := 20  // 故障：参数非法，输出冻结 / fault, the parameters are illegal and the outlet is frozen
);
END_TYPE

FUNCTION_BLOCK FB_DL_InputShaperZv
VAR_INPUT
    bEnable : BOOL := TRUE;       // 使能，FALSE 时冻结保持并清未决脉冲（边界五）/ the enable, false freezes and clears the pending pulse
    bTrig   : BOOL := FALSE;      // 整形触发电平，上升沿发起双脉冲序列 / the shaping trigger, the rising edge starts the pair
    bReset  : BOOL := FALSE;      // 复位沿：清故障锁存与未决序列并回空闲 / the reset edge, clears the latch and the pending pair
    fWn     : LREAL := 10.0;      // 固有角频率 [弧度每秒]，必须 > 0 / the natural angular frequency, must be positive
    fZeta   : LREAL := 0.1;       // 阻尼比 [-]，域 [0, 0.95) / the damping ratio inside the half open domain
END_VAR
VAR_OUTPUT
    bPulseA : BOOL := FALSE;      // 首脉冲单拍（触发沿当拍）[-] / the first pulse on the trigger scan
    bPulseB : BOOL := FALSE;      // 次脉冲单拍（Δt 到期拍）[-] / the second pulse on the expiry scan
    fAmpA   : LREAL := 0.5;       // 首脉冲幅值系数 [-]，与次脉冲之和为一 / the first amplitude coefficient
    fAmpB   : LREAL := 0.5;       // 次脉冲幅值系数 [-] / the second amplitude coefficient
    tDelay  : TIME := T#0S;       // 双脉冲间隔 Δt [毫秒] / the gap between the two pulses
    eState  : E_DL_ZvPhase;       // 主状态机当前态 [状态] / the current state of the main machine
    bValid  : BOOL := FALSE;      // 参数有效且序列可用标志 [-] / the parameters valid and the pair usable flag
    bError  : BOOL := FALSE;      // 故障锁存位 [-] / the latched fault bit
    eErr    : UDINT := 16#0000_0000; // 错误码，0 = 正常 / the error code, zero is ok
END_VAR
VAR
    _bInit    : BOOL := FALSE;                       // 首拍初始化标志（R310）/ the first scan flag
    _eState   : E_DL_ZvPhase := E_DL_ZvPhase.eIdle;  // 内部状态寄存器，段 4 唯一写点 / the internal state register, single writer
    _bPulseA  : BOOL := FALSE;                       // 首脉冲内部位，段 1 预清段 6 映射 / the internal first pulse bit, preset then mapped
    _bPulseB  : BOOL := FALSE;                       // 次脉冲内部位，段 1 预清段 6 映射 / the internal second pulse bit, preset then mapped
    _bPending : BOOL := FALSE;                       // 未决次脉冲位（间隔计时使能源）/ the pending second pulse flag driving the gap timer
    _bFault   : BOOL := FALSE;                       // 故障锁存副本（仅复位沿清除）/ the fault latch copy, cleared only on the reset edge
    _bFin     : BOOL := FALSE;                       // 浮点有限性闸结果（逐拍重算）/ the finiteness gate result, recomputed every scan
    _fZetaUse : LREAL := 0.0;                        // 钳位后的阻尼比工作副本 [-] / the clamped damping ratio copy
    _fA        : LREAL := 0.0;                       // 幅值比 A = exp(−ζπ/√(1−ζ²)) [-] / the amplitude ratio
    _fRoot     : LREAL := 1.0;                       // √(1−ζ²) 工作副本 [-] / the root working copy
    _fDtSec    : LREAL := 0.0;                       // 双脉冲间隔 [秒] / the gap in seconds
    _tDelay    : TIME := T#0S;                       // 内部间隔副本，段 6 单点映射 / the internal gap copy, mapped once in segment six
    rtTrig     : R_TRIG;                            // 触发沿实例，段 0 无条件刷新 / the trigger edge instance, refreshed unconditionally
    tonGap     : TON;                               // 间隔定时器，段 0 无条件刷新 / the gap timer, refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_ZV_ZETAMAX : LREAL := 0.95;                  // 阻尼比上界（开区间）[-] / the damping ratio upper bound, exclusive
    DL_ZV_PI      : LREAL := 3.14159265358979323846; // 圆周率（LREAL 精度字面量，R51）/ the pi constant at the long real precision
    DL_ZV_E       : LREAL := 2.71828182845904523536; // 自然常数（EXPT 底数，禁厂商 EXP 方言）/ the natural base used with the standard power operator
    DL_ZV_MS      : LREAL := 1000.0;                // 秒到毫秒的换算因子 [毫秒每秒] / the seconds to milliseconds factor
END_VAR

// 段 0｜沿检测与间隔定时器无条件周期刷新（禁入分支，R7；IN 串故障锁存门控，FB50-1）/ segment 0, the unconditional refresh with the latch gate
rtTrig(CLK := bTrig); // 触发沿 / the trigger edge
tonGap(IN := _bPending AND _bFin AND (NOT _bFault), PT := _tDelay); // 间隔计时：未决且参数有效且无锁存 / the gap timing only while pending and valid

// 段 1｜首拍初始化与单拍标志预清（仅单拍标志入清单，R32 FB32-1；R256）/ segment 1, the first scan init and the one shot preset
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _bPending := FALSE; // 未决位显式清零 / clear the pending flag explicitly
    _bFault := FALSE; // 故障锁存显式清零 / clear the fault latch explicitly
    _eState := E_DL_ZvPhase.eIdle; // 状态显式落空闲 / place the state to idle explicitly
END_IF
_bPulseA := FALSE; // 首脉冲预清零 / preset the first pulse false
_bPulseB := FALSE; // 次脉冲预清零 / preset the second pulse false

// 段 2｜参数有限性闸：显式枚举全部浮点输入 fWn 与 fZeta（R272 覆盖自证，边界三）/ segment 2, the finiteness gate enumerating every floating input
_bFin := (fWn = fWn) AND ((fWn - fWn) = (fWn - fWn)) AND (fZeta = fZeta) AND ((fZeta - fZeta) = (fZeta - fZeta)); // NaN 自反判 + Inf 差值自减判，两输入逐项 / the NaN reflexive and Inf difference tests on both inputs

// 段 3｜参数域闸：频率正域与阻尼比钳位（域闸覆盖参与换算的每个引脚，边界四）/ segment 3, the domain gate covering every pin used in the computation
IF NOT _bFin THEN // 非有限参数 / a non finite parameter
    _bFault := TRUE; // 锁存故障（段 5 迁移相）/ latch the fault, the segment five migrates the phase
ELSIF fWn <= 0.0 THEN // 频率域非法 / an illegal frequency domain
    _bFault := TRUE; // 锁存故障 / latch the fault
ELSE // 参数域合法：计算整形系数 / the parameters are legal, compute the shaping coefficients
    IF fZeta < 0.0 THEN // 阻尼比低于下界 / the damping below the floor
        _fZetaUse := 0.0; // 钳到零（无阻尼极限）/ clamp to zero, the undamped limit
    ELSIF fZeta >= DL_ZV_ZETAMAX THEN // 阻尼比达上界 / the damping at the bound
        _fZetaUse := 0.84375; // 钳到域几何内点 27/32（落在 [0, 0.95) 内，二级回退，R117）/ clamp to the interior point 27 over 32
    ELSE // 域内 / inside the domain
        _fZetaUse := fZeta; // 原值接管 / take the value as is
    END_IF
    _fRoot := SQRT(1.0 - _fZetaUse * _fZetaUse); // √(1−ζ²)：ζ ≤ 0.95 保证 > 0.31（结构性安全）/ the root is provably positive
    _fA := EXPT(DL_ZV_E, 0.0 - _fZetaUse * DL_ZV_PI / _fRoot); // A = exp(−ζπ/√(1−ζ²)) / the amplitude ratio
    fAmpA := 1.0 / (1.0 + _fA); // 首脉冲幅值（除子 ≥ 1 恒正）/ the first coefficient with a divisor of at least one
    fAmpB := _fA / (1.0 + _fA); // 次脉冲幅值 / the second coefficient
    _fDtSec := DL_ZV_PI / (fWn * _fRoot); // Δt = π/(ωn√(1−ζ²)) [秒] / the gap in seconds
    _tDelay := LREAL_TO_TIME(_fDtSec * DL_ZV_MS); // 秒口径单一化后落毫秒（R342）/ the single second domain converted to milliseconds
END_IF

// 段 4｜主状态机（ENUM + CASE，ELSE 拦非法态）/ segment 4, the main machine with the illegal state guard
CASE _eState OF
    E_DL_ZvPhase.eIdle: // 空闲相：等触发沿 / the idle phase waiting for the trigger edge
        IF bEnable AND _bFin AND (NOT _bFault) AND (fWn > 0.0) AND rtTrig.Q THEN // 迁入判据带全量闸位复检（R274）/ the entry with the full gate recheck
            _bPulseA := TRUE; // 首脉冲（触发沿当拍，边界二）/ the first pulse on the trigger scan
            _bPending := TRUE; // 置未决次脉冲 / raise the pending second pulse
            _eState := E_DL_ZvPhase.eWaitB; // 迁入等次脉冲相 / enter the waiting phase
        END_IF
    E_DL_ZvPhase.eWaitB: // 等次脉冲相 / the waiting phase
        IF tonGap.Q THEN // 间隔到期：出次脉冲 / the gap expired, raise the second pulse
            _bPulseB := TRUE; // 次脉冲单拍 / the second pulse
            _bPending := FALSE; // 清未决位 / clear the pending flag
            _eState := E_DL_ZvPhase.eIdle; // 迁回空闲 / back to idle
        ELSIF (NOT bEnable) OR (NOT _bFin) OR _bFault THEN // 出口二：失能 / 参数转非有限 / 锁存（前置条件消失）/ the second exit with the prerequisite gone
            _bPending := FALSE; // 清未决位（弃用序列，不出次脉冲）/ discard the pending pair
            _eState := E_DL_ZvPhase.eIdle; // 迁回空闲 / back to idle
        END_IF
    E_DL_ZvPhase.eFault: // 故障相：锁存保持，等复位沿（解除可达，边界六）/ the fault phase held until the reset edge
        IF bReset THEN // 复位电平（复位作用域：清锁存 + 清未决 + 迁相位）/ the reset with the declared scope
            _bFault := FALSE; // 清故障锁存 / clear the fault latch
            _bPending := FALSE; // 清未决序列 / clear the pending pair
            _eState := E_DL_ZvPhase.eIdle; // 故障相迁出边回空闲 / the exit edge back to idle
        END_IF
    ELSE // 非法枚举值拦截 / the illegal enumeration guard
        _eState := E_DL_ZvPhase.eIdle; // 落回空闲 / force back to idle
        _bFault := TRUE; // 置故障锁存 / latch the fault
END_CASE

// 段 5｜故障锁存迁移闸（置于解除段之后防同拍抢迁，R258）/ segment 5, the fault latch to phase gate placed after the release
IF _bFault AND (_eState <> E_DL_ZvPhase.eFault) THEN // 已锁存但不在故障相 / latched but not in the fault phase
    _eState := E_DL_ZvPhase.eFault; // 迁入故障相 / enter the fault phase
END_IF

// 段 6｜统一出口（内部副本单点映射，R180；故障码锁存回放，R187）/ segment 6, the unified outlet
bPulseA := _bPulseA AND bEnable; // 首脉冲出口（失能不出脉冲）/ the first pulse outlet gated by the enable
bPulseB := _bPulseB AND bEnable; // 次脉冲出口（失能不出脉冲）/ the second pulse outlet gated by the enable
tDelay := _tDelay; // 间隔出口 / the gap outlet
eState := _eState; // 状态出口 / the state outlet
bError := _bFault; // 故障位出口（与锁存同源）/ the fault bit outlet from the same latch
bValid := _bFin AND (fWn > 0.0) AND (NOT _bFault); // 参数可用标志（逐拍重算）/ the usable flag recomputed every scan
IF _bFault THEN // 故障锁存回放优先 / the latched fault replays first
    IF NOT _bFin THEN // 非有限成因（独立码值，R190）/ the non finite cause with its own code
        eErr := 16#0002_0611; // 故障级：浮点入参非有限 / fault grade, a non finite floating input
    ELSE // 频率域成因 / the frequency domain cause
        eErr := 16#0002_0612; // 故障级：固有频率非正 / fault grade, the natural frequency is not positive
    END_IF
ELSIF ABS(_fZetaUse - fZeta) > 1.0E-9 THEN // 阻尼比被钳位（浮点差值比较，禁等号；信息级逐拍重算）/ the damping clamped, compared by tolerance
    eErr := 16#0002_0610; // 信息级：阻尼比越域已钳位 / informational, the damping clamped
    bError := FALSE; // 信息级不置 bError（R45 配对口径：仅故障级置位）/ the informational code never raises the fault bit
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
