(*
  ==================================================================
  组件名 Component  : FB_DL_IonFanInterlock
  分类   Category   : DL_Device
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e/st 类型前缀制（R265）
  码位   Code ID    : 16#0003_0717 / 0718 / 0719 / 071A（故障级）｜ 16#0003_071B / 071C（信息级）
  版本   Version    : 1.0.1
  复杂度 Complexity  : 中
  功能   Purpose    : 离子风机「运行反馈 + 风速下限 + 平衡电压」三判据合取，输出下游设备的
                      许可位（半导体 / 锂电装配段 ESD 防护联锁）。
  开源溯源 Origin    : IEC 61131-3 标准语义的道莅防御性实现（clean-room，无第三方代码行）；
                      NE107 诊断分级口径（Failure / OutOfSpec）为公开标准的分类借鉴，
                      零代码复制；闸门、迟滞、非对称许可与码位 100% 自有。
  许可证 License    : MIT
  参考   Reference  : IEC 61131-3:2013 §6.6 算术运算符；ISA-107 / NE107 诊断分级语义
                      （分类借鉴）；离子风机效能判据的公开 ESD 工程口径
  平台   Platform   : 纯 IEC 61131-3（TON / CASE / 四则 / 比较），三平台通用
  依赖   Depends    : 仅 Standard.library（TON 属标准定时器）
  分工声明 Split     : FB_DL_VacIonizerBalance 为平衡电压测量 / 标定属主（本件只消费其
                      结果或现场模拟量，绝不重算平衡）；FB_DL_AirShowerInterlockSeq 为
                      风淋门物流联锁；FB_DL_EsdGroundMonitor 为接地连续性；本件为离子风机
                      效能联锁，四件边界写死（R216 双向互引，选型见 MANUAL_DL_Device）。
  归属 Ownership     : E_DL_IonFanPhase 属主为本文件（全库唯一定义，R264）；引用件只引用
                      不重声明。
  ------------------------------------------------------------------
  边界 Boundary     :
                      一 许可发放非对称（本件核心安全口径，写死）：许可发放可延迟（须三判据
                         同时满足并持续 tConfirm），许可撤除零延时（任一判据失效当拍即
                         bPermit = FALSE）——TON 只作用于「发放」，撤除不经过任何定时器；
                      二 首拍 _bInit → bPermit := FALSE（出厂默认 F，禁首拍误许可）；bEnable
                         由 F 转 T 且判据已满足时仍须完整走完 tConfirm（禁跳过确认窗）；
                      三 判据迟滞（fHystPct）两方向分别定义，禁合成单一阈值：
                         风速下限：低于 fSpeedMin × (1 − h%) 置警、高于 fSpeedMin × (1 + h%) 复原；
                         平衡上限：高于 fBalanceLimV 置警、低于 fBalanceLimV × (1 − h%) 复原
                         （方向性证明：限 5 V 时 6 V 置警、回落 4.9 V 仍报警，因 4.9 > 4.75）；
                      四 非有限输入（fAirSpeed / fBalanceV 为 NaN 或 ±Inf）一律保守判不满足并
                         置对应故障码，区分「测点坏」与「真超标」（前者 bValid = FALSE +
                         独立码，后者为信息级 OutOfSpec）；
                      五 组态域闸：fSpeedMin ≤ 0、fBalanceLimV ≤ 0、tConfirm ≤ T#0S、fHystPct < 0
                         或任一限值非有限 → 组态故障码 + bPermit := FALSE；
                      六 状态机 ENUM + CASE 必带 ELSE；ELSE 落 eAlarm 并清许可（禁静默）；
                         TON 段 0 无条件刷新（禁入分支，R7）；TON IN 串组态闸与使能；
                      七 故障码逐拍重算不锁存（本件无 bReset 引脚，R152 解除路径自证：
                         解除路径 = 修正组态 / 恢复测点，两条恒可达）；首因保序由判据顺序保证；
                      八 bEnable = FALSE（v1.0.1 返修 R63 · 修 R62-D3：按 R300 取「实现串
                         bEnable」口径）：bPermit := FALSE、三报警位（bAlarmSpeed /
                         bAlarmBalance / bAlarmFan）全部串 bEnable 归零、bError 串
                         bEnable 归零、eErr 归零不发码——失能相不再外显 Failure 级
                         假故障（R191 名实双出口：信号出口与状态出口同源）；
                      九 段序（v1.0.1 顺带消除 R62-D6 轻项）：组态域闸先行（段 0），
                         段 1 判据与 tonConfirm 使用本拍组态位，不再引用上一拍值。
  错误码 Codes      :
    16#0003_0717【故障级】组态非法（fSpeedMin ≤ 0 / fBalanceLimV ≤ 0 / tConfirm ≤ 0 / fHystPct < 0 / 限值非有限）
    16#0003_0718【故障级】风机运行反馈丧失（Failure 级，零延时撤销许可）
    16#0003_0719【故障级】风速测点非有限（NaN 或 ±Inf，测点坏而非真超标）
    16#0003_071A【故障级】平衡电压测点非有限（NaN 或 ±Inf，测点坏而非真超标）
    16#0003_071B【信息级】风速低于下限（OutOfSpec，bAlarmSpeed = TRUE）
    16#0003_071C【信息级】平衡电压超限（OutOfSpec，bAlarmBalance = TRUE）
  码位反证 Note     :
    0719 / 071A 与 071B / 071C 必须分开：测点坏的处置人是仪表工（换探头 / 查接线），
    真超标的处置人是工艺工程师（调风机 / 查高压发生器），而两者的 bPermit 与报警位组合
    完全相同（bPermit = FALSE、报警位 TRUE），仅靠输出无法区分，故各自独立码（R90）。
  验收 Acceptance   :
    算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
    V1 三判据全满足并持续 tConfirm → bPermit = TRUE、eState = ePermit
    V2 tConfirm 未到即撤除 → 全程 bPermit = FALSE
    V3 许可态下 bFanRun 掉电 → 同拍 bPermit = FALSE + bAlarmFan（零延时撤除向量）
    V4 fAirSpeed = NaN → bPermit = FALSE + 码 0719 + bValid = FALSE
    V5 fSpeedMin = 0 → 码 0717 + bPermit = FALSE
    V6 风速在 fSpeedMin 上下抖动 3%（小于迟滞 5%）→ 判据不反复跳
    V7 平衡电压 +6 V（限 5 V）→ bAlarmBalance = TRUE、bPermit = FALSE；回落 4.9 V 仍报警
    V8 首拍 → bPermit = FALSE
    V9 bEnable 由 F 转 T 且判据已满足 → 仍需完整 tConfirm
  修订记录 Revision  :
    2026-11-21  v1.0.0  R62 首版（批 4 · 序号 11；承接 ROADMAP R56-1086 半勾项）
    2026-11-21  v1.0.1  R63 返修 R3（R62-D3 中）：出口三报警位与 bError 全部串 bEnable，
                        失能相不再外显 Failure 级假故障；eErr 回放失能相归零；
                        顺带消除 R62-D6（轻）：组态闸提为段 0 先行，tonConfirm 改用本拍组态位
  ==================================================================
*)
TYPE E_DL_IonFanPhase :
(
    eIdle   := 0,  // 空闲：未使能或已失能 / idle, disabled
    eWarmup := 10, // 确认中：三判据满足并正在计时 tConfirm / confirming, the three criteria hold while the timer runs
    ePermit := 20, // 已许可：下游允许运行 / permitted, the downstream may run
    eAlarm  := 30  // 判据失效报警：许可已撤除 / an alarm, the permit has been withdrawn
);
END_TYPE

FUNCTION_BLOCK FB_DL_IonFanInterlock
VAR_INPUT
    bEnable       : BOOL := TRUE;        // 使能，FALSE 时清许可并回空闲（边界八）/ the enable, false clears the permit and returns to idle
    bFanRun       : BOOL := FALSE;       // 风机运行反馈 [-] / the fan running feedback
    fAirSpeed     : LREAL := 0.0;        // 出风速度 [米每秒]，必须有限 / the air speed, must be finite
    fSpeedMin     : LREAL := 0.5;        // 风速下限 [米每秒]，须 > 0 / the air speed floor, must be positive
    fBalanceV     : LREAL := 0.0;        // 离子平衡电压实测 [伏]，必须有限 / the measured balance voltage, must be finite
    fBalanceLimV  : LREAL := 5.0;        // 平衡电压绝对上限 [伏]，须 > 0 / the balance voltage absolute limit, must be positive
    tConfirm      : TIME := T#3S;        // 判据持续确认窗 [毫秒]，须 > 0 / the confirmation window, must be positive
    fHystPct      : LREAL := 5.0;        // 判据迟滞 [%]，须 ≥ 0 / the criterion hysteresis in percent, non negative
END_VAR
VAR_OUTPUT
    bPermit       : BOOL := FALSE;            // 下游允许运行（安全侧默认 FALSE，边界一）/ the downstream permit, safe side default false
    bAlarmSpeed   : BOOL := FALSE;            // 风速判据报警（OutOfSpec 级）[-] / the air speed alarm
    bAlarmBalance : BOOL := FALSE;            // 平衡电压判据报警（OutOfSpec 级）[-] / the balance voltage alarm
    bAlarmFan     : BOOL := FALSE;            // 风机运行反馈丧失报警（Failure 级）[-] / the fan feedback loss alarm
    eState        : E_DL_IonFanPhase;         // 状态机出口 [状态] / the state machine outlet
    bValid        : BOOL := FALSE;            // 测量可用（无测点故障与组态故障）[-] / the measurement is usable
    eErr          : UDINT := 16#0000_0000;    // 错误码，0 = 正常 / the error code, zero is ok
    bError        : BOOL := FALSE;            // 故障标志（故障级码同拍置位，R45 配对）/ the fault flag raised with a fault level code
END_VAR
VAR
    _bInit      : BOOL := FALSE;                        // 首拍初始化标志（R310）/ the first scan flag
    _eState     : E_DL_IonFanPhase := E_DL_IonFanPhase.eIdle; // 内部状态寄存器 / the internal state register
    _bFanOk     : BOOL := FALSE;                        // 风机运行判据（逐拍重算）/ the fan criterion
    _bSpeedOk   : BOOL := FALSE;                        // 风速判据（带迟滞，逐拍重算）/ the air speed criterion with hysteresis
    _bBalOk     : BOOL := FALSE;                        // 平衡电压判据（带迟滞，逐拍重算）/ the balance criterion with hysteresis
    _bAllOk     : BOOL := FALSE;                        // 三判据合取（逐拍重算）/ the conjunction of the three criteria
    _bAlmSpd    : BOOL := FALSE;                        // 风速报警迟滞状态（跨拍保持）/ the air speed alarm hysteresis state
    _bAlmBal    : BOOL := FALSE;                        // 平衡电压报警迟滞状态（跨拍保持）/ the balance alarm hysteresis state
    _bFinSpd    : BOOL := FALSE;                        // 风速测点有限标记（逐拍重算）/ the air speed finiteness flag
    _bFinBal    : BOOL := FALSE;                        // 平衡测点有限标记（逐拍重算）/ the balance finiteness flag
    _bCfgBad    : BOOL := FALSE;                        // 组态非法标记（逐拍重算）/ the configuration fault flag
    _fSpdTrip   : LREAL := 0.0;                         // 风速置警阈值 [米每秒] / the air speed trip threshold
    _fSpdRele   : LREAL := 0.0;                         // 风速复原阈值 [米每秒] / the air speed release threshold
    _fBalTrip   : LREAL := 0.0;                         // 平衡置警阈值（绝对值）[伏] / the balance trip threshold
    _fBalRele   : LREAL := 0.0;                         // 平衡复原阈值（绝对值）[伏] / the balance release threshold
    _fBalAbs    : LREAL := 0.0;                         // 平衡电压绝对值 [伏] / the absolute balance voltage
    _fPctScale  : LREAL := 0.0;                         // 迟滞百分比换算中间量 [−] / the hysteresis percentage intermediate
    tonConfirm  : TON;                                  // 判据持续确认定时器，段 0 无条件刷新 / the confirmation timer refreshed unconditionally
END_VAR  // R64 结构补齐：VAR 段缺失的 END_VAR（门禁机械修复）
VAR CONSTANT
    DL_IFI_ZERO  : LREAL := 0.0;   // 实数零常量 [工程单位] / the real zero constant
    DL_IFI_HUND  : LREAL := 100.0; // 百分比换算系数 [%] / the percentage scaling factor
    DL_IFI_TIME0 : TIME := T#0S;   // 时间零常量 [毫秒] / the time zero constant
END_VAR

// 段 0｜组态域闸先行（v1.0.1 修 R62-D6：tonConfirm 与判据段改用本拍组态位，禁用上一拍值，R272 全量点名）/ segment 0, the configuration gate runs first
_bCfgBad := (fSpeedMin <> fSpeedMin) OR ((fSpeedMin - fSpeedMin) <> (fSpeedMin - fSpeedMin)) OR (fSpeedMin <= DL_IFI_ZERO)
         OR (fBalanceLimV <> fBalanceLimV) OR ((fBalanceLimV - fBalanceLimV) <> (fBalanceLimV - fBalanceLimV)) OR (fBalanceLimV <= DL_IFI_ZERO)
         OR (fHystPct <> fHystPct) OR ((fHystPct - fHystPct) <> (fHystPct - fHystPct)) OR (fHystPct < DL_IFI_ZERO)
         OR (tConfirm <= DL_IFI_TIME0); // 组态非法（含 tConfirm 非正与迟滞负值）/ an illegal configuration including a non positive window and a negative hysteresis

// 段 1｜判据预计算与定时器无条件周期刷新（禁入分支，R7）：IN = 三判据合取 AND 使能 AND 无组态故障 / segment 1, the criteria precompute and the unconditional timer refresh
_bFanOk := bFanRun; // 风机运行判据（无迟滞，掉电即失效）/ the fan criterion without hysteresis, it fails as soon as the feedback drops
_bFinSpd := (fAirSpeed = fAirSpeed) AND ((fAirSpeed - fAirSpeed) = (fAirSpeed - fAirSpeed)); // 风速测点有限 / the air speed sample is finite
_bFinBal := (fBalanceV = fBalanceV) AND ((fBalanceV - fBalanceV) = (fBalanceV - fBalanceV)); // 平衡测点有限 / the balance sample is finite
// 迟滞阈值预计算（组态闸在段 2，故此处先按域内假设算，域外值不作为判据依据）/ the hysteresis thresholds are precomputed here, the configuration gate in segment two decides whether they are used
_fPctScale := fHystPct / DL_IFI_HUND; // 迟滞小数化 [−] / the hysteresis as a fraction
_fSpdTrip := fSpeedMin * (1.0 - _fPctScale); // 风速置警阈值 = 下限 × (1 − h) [米每秒] / the trip threshold
_fSpdRele := fSpeedMin * (1.0 + _fPctScale); // 风速复原阈值 = 下限 × (1 + h) [米每秒] / the release threshold
_fBalTrip := fBalanceLimV; // 平衡置警阈值 = 绝对上限 [伏] / the balance trip threshold equals the limit
_fBalRele := fBalanceLimV * (1.0 - _fPctScale); // 平衡复原阈值 = 上限 × (1 − h) [伏] / the balance release threshold
_fBalAbs := ABS(fBalanceV); // 平衡电压绝对值（正负偏等量处理，迟滞对称）[伏] / the absolute balance voltage
// 风速判据：非有限即保守判不满足（边界四）/ the air speed criterion treats a non finite sample as failing
IF _bFinSpd THEN // 测点有限才用迟滞判据 / the hysteresis runs only on a finite sample
    IF NOT _bAlmSpd THEN // 未报警态 / the released state
        IF fAirSpeed < _fSpdTrip THEN // 跌破置警阈值 / below the trip threshold
            _bAlmSpd := TRUE; // 置报警迟滞状态 / set the alarm state
        END_IF
    ELSE // 已报警态 / the tripped state
        IF fAirSpeed > _fSpdRele THEN // 回升超过复原阈值 / above the release threshold
            _bAlmSpd := FALSE; // 复原 / release
        END_IF
    END_IF
    _bSpeedOk := NOT _bAlmSpd; // 判据结果由迟滞状态派生 / the criterion derives from the hysteresis state
ELSE // 测点非有限：保守判不满足并置报警（区分码见段 6）/ a non finite sample conservatively fails and raises the alarm
    _bAlmSpd := TRUE; // 保守落报警态 / conservatively trip
    _bSpeedOk := FALSE; // 判据不满足 / the criterion fails
END_IF
// 平衡判据：非有限即保守判不满足（边界四）/ the balance criterion treats a non finite sample as failing
IF _bFinBal THEN // 测点有限才用迟滞判据 / the hysteresis runs only on a finite sample
    IF NOT _bAlmBal THEN // 未报警态 / the released state
        IF _fBalAbs > _fBalTrip THEN // 超过置警阈值 / above the trip threshold
            _bAlmBal := TRUE; // 置报警迟滞状态 / set the alarm state
        END_IF
    ELSE // 已报警态 / the tripped state
        IF _fBalAbs < _fBalRele THEN // 回落低于复原阈值（限 5 V 时 4.9 V 仍在报警带内）/ below the release threshold, four point nine volts still sits inside the band
            _bAlmBal := FALSE; // 复原 / release
        END_IF
    END_IF
    _bBalOk := NOT _bAlmBal; // 判据结果由迟滞状态派生 / the criterion derives from the hysteresis state
ELSE // 测点非有限：保守判不满足并置报警 / a non finite sample conservatively fails and raises the alarm
    _bAlmBal := TRUE; // 保守落报警态 / conservatively trip
    _bBalOk := FALSE; // 判据不满足 / the criterion fails
END_IF
_bAllOk := _bFanOk AND _bSpeedOk AND _bBalOk; // 三判据合取 / the conjunction
IF _bCfgBad THEN // 组态非法：合取强制失满足（组态阈值不可信，可能是 NaN）/ an illegal configuration forces the conjunction to fail
    _bAllOk := FALSE; // 合取清零（阈值可能是 NaN）/ clear the conjunction, the thresholds may be NaN
END_IF
tonConfirm(IN := _bAllOk AND bEnable AND (NOT _bCfgBad), PT := tConfirm); // 确认窗计时（使能 + 组态闸串入，组态位为本拍值）/ the confirmation window with the enable and the configuration gate in series

// 段 1｜首拍初始化（R310；出厂默认无许可，边界二）/ segment 1, the first scan init with the safe default
IF NOT _bInit THEN // 首拍一拍 / the first scan
    _bInit := TRUE; // 置首拍标志 / raise the first scan flag
    _eState := E_DL_IonFanPhase.eIdle; // 状态显式落空闲 / place the state to idle
    _bAlmSpd := FALSE; // 风速报警迟滞态显式清零 / clear the air speed alarm state explicitly
    _bAlmBal := FALSE; // 平衡报警迟滞态显式清零 / clear the balance alarm state explicitly
    bPermit := FALSE; // 许可显式落假（出厂默认 F）/ force the permit false on the first scan
END_IF

// 段 2｜首拍初始化（R310；出厂默认无许可，边界二）/ segment 2, the first scan init with the safe default
// 段 3｜主状态机（ENUM + CASE，ELSE 兜底并清许可；安全相迁移带全量闸位复检，R274）/ segment 3, the main machine
CASE _eState OF
    E_DL_IonFanPhase.eIdle: // 空闲相（失能时驻留，驻留由分支表达，禁自赋值死语句，R261）/ the idle phase, dwelling is expressed by the branch
        IF bEnable AND _bCfgBad THEN // 使能但组态非法（边界五）/ enabled with an illegal configuration
            _eState := E_DL_IonFanPhase.eAlarm; // 迁入报警相 / enter the alarm phase
        ELSIF bEnable THEN // 使能且组态合法 / enabled with a legal configuration
            _eState := E_DL_IonFanPhase.eWarmup; // 迁入确认相（确认窗自下一拍起计）/ enter the confirmation phase, the window counts from the next scan
        END_IF
    E_DL_IonFanPhase.eWarmup: // 确认相：TON 计时中 / the confirmation phase
        IF (NOT bEnable) OR _bCfgBad THEN // 退出条件一：失能或组态非法（前置条件已消失）/ exit one, the prerequisite disappeared
            _eState := E_DL_IonFanPhase.eAlarm; // 迁入报警相 / enter the alarm phase
        ELSIF tonConfirm.Q AND _bAllOk THEN // 退出条件二：确认窗到且三判据仍满足（安全相迁移全量复检）/ exit two, the window elapsed with the criteria still holding
            _eState := E_DL_IonFanPhase.ePermit; // 迁入已许可相 / enter the permitted phase
        ELSIF NOT _bAllOk THEN // 退出条件三：判据在窗内失效 / exit three, a criterion failed inside the window
            _eState := E_DL_IonFanPhase.eAlarm; // 迁入报警相 / enter the alarm phase
        END_IF
    E_DL_IonFanPhase.ePermit: // 已许可相 / the permitted phase
        IF NOT _bAllOk THEN // 任一判据失效：零延时撤除（边界一）/ any criterion failed, the permit is withdrawn with no delay
            _eState := E_DL_IonFanPhase.eAlarm; // 同拍迁入报警相 / enter the alarm phase on the same scan
        ELSIF (NOT bEnable) OR _bCfgBad THEN // 失能或组态非法 / disabled or an illegal configuration
            _eState := E_DL_IonFanPhase.eAlarm; // 迁入报警相 / enter the alarm phase
        END_IF
    E_DL_IonFanPhase.eAlarm: // 报警相 / the alarm phase
        IF NOT bEnable THEN // 退出条件一：失能 / exit one, disabled
            _eState := E_DL_IonFanPhase.eIdle; // 回空闲 / back to idle
        ELSIF _bAllOk AND (NOT _bCfgBad) THEN // 退出条件二：三判据全恢复且组态合法（须重走确认窗）/ exit two, every criterion recovered, the window restarts
            _eState := E_DL_IonFanPhase.eWarmup; // 回确认相（不直接回许可相，禁跳过确认窗）/ back to confirmation, never jumping straight to permitted
        END_IF
    ELSE // 非法枚举值拦截（边界六：落报警相并清许可，禁静默）/ the illegal enumeration guard
        _eState := E_DL_IonFanPhase.eAlarm; // 落报警相 / force the alarm phase
END_CASE

// 段 4｜统一出口（R191 名实双出口：bPermit 与 eState 同源；安全侧默认 FALSE；三报警位与 bError 全部串 bEnable，v1.0.1 修 R62-D3）/ segment 4, the unified outlet
eState := _eState; // 状态出口 / the state outlet
bPermit := (_eState = E_DL_IonFanPhase.ePermit) AND _bAllOk AND bEnable AND (NOT _bCfgBad); // 许可出口：态 + 合取 + 使能 + 组态四重同源（同拍撤除）/ the permit outlet with four sources, withdrawn on the same scan
bAlarmFan := (NOT bFanRun) AND bEnable; // 风机反馈丧失（Failure 级，无迟滞；串 bEnable，失能不外显假故障，v1.0.1）/ the fan feedback loss without hysteresis, gated by the enable so the disabled phase shows no false failure
bAlarmSpeed := _bAlmSpd AND bEnable; // 风速报警出口（迟滞状态派生；串 bEnable，v1.0.1）/ the air speed alarm outlet gated by the enable
bAlarmBalance := _bAlmBal AND bEnable; // 平衡报警出口（迟滞状态派生；串 bEnable，v1.0.1）/ the balance alarm outlet gated by the enable
bValid := (NOT _bCfgBad) AND _bFinSpd AND _bFinBal; // 测量可用：组态合法且两测点均有限 / usable, a legal configuration and two finite samples
bError := bEnable AND (_bCfgBad OR (NOT _bFinSpd) OR (NOT _bFinBal) OR (NOT bFanRun)); // 故障位串 bEnable（v1.0.1 修 R62-D3：失能相不外显 Failure 级假故障，R45 配对随码回放段同口径）/ the fault bit gated by the enable, aligned with the replay segment

// 段 5｜码位回放（首因保序：组态 → 风机 → 风速测点 → 平衡测点 → 信息级；失能相不发码，v1.0.1）/ segment 5, the code replay with the first cause kept first, silent while disabled
IF NOT bEnable THEN // 失能相：不发任何码（Failure 级假故障不再外显，v1.0.1 修 R62-D3）/ the disabled phase emits no code at all
    eErr := 16#0000_0000; // 归零 / zero
ELSIF _bCfgBad THEN // 组态成因优先 / the configuration cause comes first
    eErr := 16#0003_0717; // 故障级：组态非法 / fault grade, an illegal configuration
ELSIF NOT _bFinSpd THEN // 风速测点坏（与真超标分开，R90）/ the air speed sample is broken, kept apart from a real overshoot
    eErr := 16#0003_0719; // 故障级：风速测点非有限 / fault grade, the air speed sample is not finite
ELSIF NOT _bFinBal THEN // 平衡测点坏 / the balance sample is broken
    eErr := 16#0003_071A; // 故障级：平衡电压测点非有限 / fault grade, the balance sample is not finite
ELSIF NOT bFanRun THEN // 风机反馈丧失（Failure 级）/ the fan feedback loss
    eErr := 16#0003_0718; // 故障级：风机运行反馈丧失 / fault grade, the fan feedback is lost
ELSIF _bAlmSpd THEN // 风速真低于下限（OutOfSpec）/ the air speed really is below the floor
    eErr := 16#0003_071B; // 信息级：风速低于下限 / informational, the air speed is below the floor
ELSIF _bAlmBal THEN // 平衡真超限（OutOfSpec）/ the balance really is over the limit
    eErr := 16#0003_071C; // 信息级：平衡电压超限 / informational, the balance voltage is over the limit
ELSE // 无事件 / no event
    eErr := 16#0000_0000; // 正常 / ok
END_IF
END_FUNCTION_BLOCK
