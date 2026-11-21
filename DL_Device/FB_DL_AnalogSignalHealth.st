// ==============================================================================
// 组件名 Component  : FB_DL_AnalogSignalHealth
// 分类   Category   : DL_Device
// 前缀   Naming     : FB_DL_ ｜ b/f/e/t/u 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 中
// 功能   Purpose    : 4-20mA 模拟量信号健康诊断：断线（< 3.6 mA）、超上限
//                      （> fSatHigh）、低限（fSatLow ≤ 值 < 3.6 之外的
//                      低带口径见边界三）、卡滞（变化率绝对值持续
//                      <= fStuckBand 超 tStuck）；报警锁存至 bReset 上升沿，
//                      沿脉冲单拍。供变送器回路质量监视与预测性维护。
// 开源溯源 Origin    : 西门子 LGF 分类语义借鉴，clean-room 重写（LGF
//                      Process Diagnostics「模拟量断线 / 饱和监视」分类学
//                      口径借鉴，只借骨不抄肉，判据与实现零代码复制）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6 TON / R_TRIG 语义；NAMUR
//                      NE43 信号电平分级公开条款（借 3.6/4/20/20.5 mA
//                      分级语义，不抄文）
// 平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / LREAL 比较），三平台通用
// 依赖   Depends    : 仅 Standard.library（TON / R_TRIG 属标准件）
// 分工声明 Split     : FB_DL_SignalStuckWatch（通用卡滞监视）/ FB_DL_Analog
//                      Transmitter（模拟量变换）与本件互引；本件为 4-20mA
//                      回路专属健康分级（NE43 口径 + 回路卡滞三合一），
//                      通用信号冻结监视归 SignalStuckWatch（R216）。
// 归属 Ownership     : E_DL_AshHealth 属主为本文件（全库唯一定义，R264）；
//                      引用件只引用不重声明。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 TON 无条件刷新（R7）：tonStuck 于段 0 顶层调用，IN 串「有变化即
//      重置」口径——IN := 变化率绝对值 <= fStuckBand（有变化时 IN 为
//      FALSE 计时自清，卡滞即「无变化持续超窗」）；首拍 / 复位后
//      _bPrevValid = FALSE 不计时（防假前值参与变化率）；
//   二 判据分级（R190 归因唯一，独立码位）：fMa 非有限 → eInvalid
//      （bValid = FALSE 通道，无码位）；fMa < 3.6 → eWireBreak（断线）；
//      fMa >= 3.6 且 fMa < fSatLow → eSatLow（低限）；fMa > fSatHigh →
//      eSatHigh（超上限）；其余正常带内 tonStuck.Q → eStuck（卡滞）；
//      以上皆否 → eOk；
//   三 低限口径声明：3.6 mA 硬断线阈值与 fSatLow 组态阈值分离——
//      fSatLow 默认 3.6（与硬阈值重合），调用方可上调 fSatLow 收紧
//      低带；fSatLow 下调低于 3.6 时低限带被硬阈值吸收（合法组态）；
//   四 报警锁存：_bAlarmLatch 置位后保持至 bReset 上升沿（锁存解除式
//      可达自证：输入引脚恒可达，R152）；首报码 _uErrLatch 锁存回放
//      （FB33-1：不在故障态按当下输入重新推断）；bAlarmEdge 单拍
//      （新报警沿，已锁存期不再发）；
//   五 组态守卫（防御性补码，R272 逐项点名）：fSatLow >= fSatHigh、
//      fSatLow / fSatHigh / fStuckBand 非有限、fStuckBand < 0、
//      tStuck <= 0 任一成立 → eHealth = eInvalid、bValid = FALSE、
//      报警锁存（故障级 0735）；
//   六 卡滞窗与报警锁存互锁：_bAlarmLatch 期间 tonStuck.IN 强制 FALSE
//      （复位沿同拍不重锁，FB50-1），复位后 _bPrevValid 清零重练；
//   七 失能（bEn = FALSE）语义写死（R303 离相清零）：eHealth 回 eOk、
//      报警锁存 / 码锁存清零、bValid = FALSE（失能不是故障）；
//   八 无除法；无全局、无外部变量、无物理地址；无状态机 CASE
//      （IF 判据链，末位 ELSE 兜底为 eOk）。
// 错误码 Codes      :
//   16#0003_0201【信息级】断线（fMa < 3.6 mA，NE43 口径）→ eWireBreak
//   16#0003_0202【信息级】超上限（fMa > fSatHigh）→ eSatHigh
//   16#0003_0203【信息级】低限（3.6 ≤ fMa < fSatLow）→ eSatLow
//   16#0003_0204【信息级】卡滞（变化率 <= fStuckBand 持续 tStuck）→ eStuck
//   16#0003_0735【故障级】组态非法（fSatLow >= fSatHigh / 参数非有限 /
//                fStuckBand < 0 / tStuck <= 0）→ eInvalid + bValid = FALSE
//   注：0201~0204 段位按本轮任务定稿启用（信息级，经 eErr / bAlarm
//   通道表达）；fMa 非有限走 eInvalid 无码位（bValid = FALSE 通道）。
//   0201~0204 四码分立依据（R90）：处置人不同（断线查接线、超限查
//   量程组态、低限查供电、卡滞查管路 / 变送器膜片），场景互斥可还原。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 fMa = 3.0 → eWireBreak + 码 0201 + bAlarm 锁存
//   V2 fMa = 21.0 → eSatHigh + 码 0202；fMa = 3.7（fSatLow = 4.0）→ eSatLow
//   V3 fMa 恒 12.000 ± 0.01 超 10s → eStuck + 码 0204
//   V4 fMa 恒定但 < 3.6 → 断线优先（卡滞窗被门控不计时）
//   V5 fMa = NaN → eInvalid + bValid = FALSE（无码位）
//   V6 bReset 上升沿 → 锁存清零、卡滞计时重练（_bPrevValid 清零）
//   V7 bEn = FALSE → 全出口清零回 eOk（R303）
//   V8 fSatLow = 25（>= fSatHigh）→ 0735 + eInvalid
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 3 · 序号 9，LGF Process Diagnostics 补口）
// ==============================================================================
TYPE E_DL_AshHealth :
(
    eOk        := 0,  // 健康带内 / ok, the signal in the healthy band
    eWireBreak := 10, // 断线：fMa < 3.6 mA（NE43 口径）/ the wire break under the hard threshold
    eSatHigh   := 20, // 超上限：fMa > fSatHigh / the saturation above the configured high
    eSatLow    := 30, // 低限：3.6 <= fMa < fSatLow / the low limit under the configured low
    eStuck     := 40, // 卡滞：变化率持续不超带超窗 / the stuck value through the window
    eInvalid   := 50  // 无效：输入非有限或组态非法 / invalid, a non finite input or configuration
);
END_TYPE

FUNCTION_BLOCK FB_DL_AnalogSignalHealth
VAR_INPUT
    fMa        : LREAL;         // 实测电流 [mA]（4-20mA 回路）/ the measured current in milliamps
    bEn        : BOOL := TRUE;  // 使能 [-]，FALSE 时出口清零回 eOk（R303）/ the enable
    fSatLow    : LREAL := 3.6;  // 低限阈值 [mA]，须 < fSatHigh / the low limit threshold
    fSatHigh   : LREAL := 20.5; // 超上限阈值 [mA]，NE43 口径默认 20.5 / the saturation high threshold
    fStuckBand : LREAL := 0.05; // 卡滞变化带 [mA]，变化率绝对值 <= 此值视为无变化 / the stuck band of the rate
    tStuck     : TIME := T#10S; // 卡滞判定窗 [毫秒]，须 > 0 / the stuck window, above zero
    bReset     : BOOL := FALSE; // 报警复位电平，上升沿清锁存（边界四解除式）/ the reset level, its rising edge releases the latch
END_VAR
VAR_OUTPUT
    eHealth    : E_DL_AshHealth := E_DL_AshHealth.eOk; // 健康状态出口 [状态] / the health outlet
    bAlarm     : BOOL := FALSE; // 报警锁存 [-]，任一非 eOk 状态置位至复位 / the latched alarm
    bAlarmEdge : BOOL := FALSE; // 新报警沿脉冲 [-]，单拍有效 / the new alarm edge pulse, single scan
    bValid     : BOOL := FALSE; // 判据可用 [-]，输入非有限或组态非法为 FALSE / the criteria usable flag
    eErr       : UDINT := 16#0000_0000; // 错误码，0 = 正常（首报码锁存回放）/ the error code, zero is ok
END_VAR
VAR
    _fPrevMa     : LREAL := 0.0;  // 前拍 mA 快照 [mA]（卡滞变化率基准）/ the previous scan snapshot of fMa
    _bPrevValid  : BOOL := FALSE; // 前值有效标志 [-]（首拍 / 复位后不参与变化率）/ the previous value valid flag
    _bAlarmLatch : BOOL := FALSE; // 报警锁存副本 [-]（仅复位沿清除）/ the alarm latch copy
    _uErrLatch   : UDINT := 16#0000_0000; // 首报码锁存 [码]（复位沿清除，FB33-1）/ the latched first report code
    _bAlarmNew   : BOOL := FALSE; // 本拍新报警标志 [-]（沿脉冲源，单拍）/ the new alarm flag of this scan
    _eHealthInt  : E_DL_AshHealth := E_DL_AshHealth.eOk; // 健康状态内部判定 [状态] / the internal health verdict
    _uCodeNow    : UDINT := 16#0000_0000; // 本拍判据码 [码] / the verdict code of this scan
    _bMaBad      : BOOL;          // fMa 非有限标志（逐拍重算）/ the input fault flag
    _bCfgBad     : BOOL;          // 组态非法标志（逐拍重算）/ the configuration fault flag
    _bInBand     : BOOL;          // 处于正常工作带 [-]（卡滞计时前提）/ the in band flag, the stuck timer premise
    _bDeltaSmall : BOOL;          // 变化率不超带 [-]（卡滞计时条件）/ the small rate flag
    rtReset      : R_TRIG;        // 复位沿实例，段 0 无条件刷新（R7）/ the reset edge instance refreshed unconditionally
    tonStuck     : TON;           // 卡滞窗定时器，段 0 无条件刷新 / the stuck window timer refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_ASH_WIRE  : LREAL := 3.6;            // 硬断线阈值 [mA]（NE43 口径）/ the hard wire break threshold
    DL_ASH_FMAX  : LREAL := 1.0E30;         // 非有限筛查幅值上限 [mA] / the finiteness screening cap
    DL_ASH_TIME0 : TIME := T#0S;            // 时间零常量 [毫秒] / the time zero constant
    DL_ASH_ZEROU : UDINT := 16#0000_0000;   // 码零常量 / the code zero constant
    DL_ASH_E_WIRE  : UDINT := 16#0003_0201; // 信息级：断线 / the wire break code
    DL_ASH_E_SATHI : UDINT := 16#0003_0202; // 信息级：超上限 / the saturation high code
    DL_ASH_E_SATLO : UDINT := 16#0003_0203; // 信息级：低限 / the low limit code
    DL_ASH_E_STUCK : UDINT := 16#0003_0204; // 信息级：卡滞 / the stuck code
    DL_ASH_E_CFG   : UDINT := 16#0003_0735; // 故障级：组态非法 / the configuration fault code
END_VAR

// 段 0｜定时器与沿实例无条件周期刷新（禁入分支，R7）/ segment 0, the unconditional refresh
rtReset(CLK := bReset);          // 复位沿 / the reset edge
_bMaBad := (fMa <> fMa) OR ((fMa - fMa) <> 0.0) OR (ABS(fMa) > DL_ASH_FMAX); // 输入非有限（NaN 自反判 + Inf 差值自反判 + 幅值上界，R272）/ the input non finite
_bCfgBad := (fSatLow >= fSatHigh)                                        // 低限不低于上限 / the low limit above the high
         OR (fSatLow <> fSatLow) OR ((fSatLow - fSatLow) <> 0.0) OR (ABS(fSatLow) > DL_ASH_FMAX)     // fSatLow 非有限 / fSatLow non finite
         OR (fSatHigh <> fSatHigh) OR ((fSatHigh - fSatHigh) <> 0.0) OR (ABS(fSatHigh) > DL_ASH_FMAX) // fSatHigh 非有限 / fSatHigh non finite
         OR (fStuckBand < 0.0)                                           // 变化带为负 / a negative band
         OR (fStuckBand <> fStuckBand) OR ((fStuckBand - fStuckBand) <> 0.0) OR (ABS(fStuckBand) > DL_ASH_FMAX) // fStuckBand 非有限 / fStuckBand non finite
         OR (tStuck <= DL_ASH_TIME0);                                    // 卡滞窗非正 / a non positive window
_bInBand := (NOT _bMaBad) AND (NOT _bCfgBad) AND (fMa >= DL_ASH_WIRE) AND (fMa >= fSatLow) AND (fMa <= fSatHigh); // 正常工作带（卡滞计时前提，边界二）/ the healthy band, the stuck timer premise
_bDeltaSmall := _bPrevValid AND (ABS(fMa - _fPrevMa) <= fStuckBand); // 变化率不超带（有变化时为 FALSE 计时自清，边界一）/ the rate within the band
tonStuck(IN := bEn AND _bInBand AND (NOT _bAlarmLatch) AND _bDeltaSmall, PT := tStuck); // 卡滞窗计时（串使能 / 带 / 锁存门控，FB50-1；锁存期 IN 强制 FALSE 防复位同拍重锁，边界六）/ the stuck window with the full gating

// 段 1｜单拍量预清零 + 复位沿作用域（R256 / R311）/ segment 1, the preset and the reset edge scope
bAlarmEdge := FALSE;             // 沿脉冲预清零（单拍信息位）/ preset the edge pulse false
IF rtReset.Q THEN                // 复位沿（作用域声明：清双锁存 + 重练卡滞计时，R311）/ the reset edge with the declared scope
    _bAlarmLatch := FALSE;       // 清报警锁存（唯一解除路径，边界四自证可达）/ clear the alarm latch
    _uErrLatch := DL_ASH_ZEROU;  // 清首报码锁存 / clear the latched code
    _bPrevValid := FALSE;        // 前值失效（卡滞计时重练，防旧基线误判）/ invalidate the previous value
    _fPrevMa := 0.0;             // 前值显式清零 [mA] / clear the previous value explicitly
END_IF

// 段 2｜失能分支：出口清零回 eOk，不 faults（R303 离相清零声明行）/ segment 2, the disabled branch
IF NOT bEn THEN                  // 失能 / disabled
    _eHealthInt := E_DL_AshHealth.eOk; // 强制健康态 / force the healthy state
    _bAlarmLatch := FALSE;       // 清报警锁存（使能断开 ≠ 信号故障）/ clear the alarm latch
    _uErrLatch := DL_ASH_ZEROU;  // 清码锁存 / clear the latched code
    _bPrevValid := FALSE;        // 前值失效（重新使能后重练）/ invalidate the previous value
    eHealth := _eHealthInt;      // 状态出口 / the health outlet
    bAlarm := FALSE;             // 报警位复位 / the alarm bit resets
    bAlarmEdge := FALSE;         // 沿脉冲复位 / the edge pulse resets
    bValid := FALSE;             // 失能即不可用 / not usable while disabled
    eErr := DL_ASH_ZEROU;        // 失能不发码 / no code while disabled
    RETURN;                      // 早退 / early return
END_IF

// 段 3｜判据分级链（边界二 / 五：R190 归因唯一，末位 ELSE 兜底 eOk）/ segment 3, the verdict chain
IF _bCfgBad THEN                 // 组态非法优先（故障级 0735）/ the configuration fault first
    _eHealthInt := E_DL_AshHealth.eInvalid; // 无效态 / the invalid state
    _uCodeNow := DL_ASH_E_CFG;   // 故障级码 / the fault code
ELSIF _bMaBad THEN               // 输入非有限 / a non finite input
    _eHealthInt := E_DL_AshHealth.eInvalid; // 无效态 / the invalid state
    _uCodeNow := DL_ASH_ZEROU;   // 无码位（bValid = FALSE 通道表达，边界二）/ no code, the validity channel speaks
ELSIF fMa < DL_ASH_WIRE THEN     // 硬断线阈值之下（NE43 口径）/ under the hard wire break threshold
    _eHealthInt := E_DL_AshHealth.eWireBreak; // 断线态 / the wire break state
    _uCodeNow := DL_ASH_E_WIRE;  // 信息级 0201 / the wire break code
ELSIF fMa < fSatLow THEN         // 低限带（fMa >= 3.6 已由上分支证明）/ the low limit band
    _eHealthInt := E_DL_AshHealth.eSatLow;   // 低限态 / the low limit state
    _uCodeNow := DL_ASH_E_SATLO; // 信息级 0203 / the low limit code
ELSIF fMa > fSatHigh THEN        // 超上限 / over the high threshold
    _eHealthInt := E_DL_AshHealth.eSatHigh;  // 超上限态 / the saturation state
    _uCodeNow := DL_ASH_E_SATHI; // 信息级 0202 / the saturation code
ELSIF tonStuck.Q THEN            // 卡滞超窗（正常带内才有资格判，边界二 / 六）/ stuck through the window
    _eHealthInt := E_DL_AshHealth.eStuck;    // 卡滞态 / the stuck state
    _uCodeNow := DL_ASH_E_STUCK; // 信息级 0204 / the stuck code
ELSE                             // 兜底：健康 / the fallback, healthy
    _eHealthInt := E_DL_AshHealth.eOk;       // 健康态 / the healthy state
    _uCodeNow := DL_ASH_ZEROU;   // 无码 / no code
END_IF

// 段 4｜报警锁存与首报码（边界四：锁存回放，FB33-1）/ segment 4, the alarm latch and the first report code
_bAlarmNew := FALSE;             // 新报警标志预清零 / preset the new alarm flag false
IF _eHealthInt <> E_DL_AshHealth.eOk THEN // 判据非健康 / the verdict not healthy
    IF NOT _bAlarmLatch THEN     // 首次报警 / a first alarm
        _bAlarmNew := TRUE;      // 置新报警标志（沿脉冲源，单拍）/ raise the new alarm flag
        _uErrLatch := _uCodeNow; // 首报码锁存（此后回放，不按当下输入重推断）/ latch the first code for the replay
    END_IF
    _bAlarmLatch := TRUE;        // 报警锁存至复位沿 / latch the alarm to the reset edge
END_IF

// 段 5｜统一出口（名实双出口同源，R191）/ segment 5, the unified outlet
eHealth := _eHealthInt;          // 状态出口 / the health outlet
bAlarm := _bAlarmLatch;          // 报警位与锁存同源 / the alarm bit from the latch
bAlarmEdge := _bAlarmNew;        // 沿脉冲单拍（已锁存期不再发）/ the single scan edge pulse
bValid := (NOT _bMaBad) AND (NOT _bCfgBad); // 判据可用（无输入 / 组态故障）/ usable without faults
IF _bAlarmLatch THEN             // 报警锁存回放优先 / the latched code replays first
    eErr := _uErrLatch;          // 首报码回放 / replay the latched code
ELSE                             // 无报警 / no alarm
    eErr := DL_ASH_ZEROU;        // 正常 / ok
END_IF

// 段 6｜前拍快照更新（边界一：仅有限值更新，非有限保旧值）/ segment 6, the previous value update
IF NOT _bMaBad THEN              // 输入有限才更新基准 / update the baseline only on a finite input
    _fPrevMa := fMa;             // 前拍快照刷新 [mA] / refresh the snapshot
    _bPrevValid := TRUE;         // 前值有效 / the previous value valid
END_IF
END_FUNCTION_BLOCK
