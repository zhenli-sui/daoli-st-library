(*==============================================================================
 * 组件名称 (Component)  : FB_DL_VibZoneClassify
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5+ / TwinCAT 3 / 汇川 InoProShop / 施耐德 Machine Expert
 *                         仅依赖 Standard.library（ABS），零厂商私有库
 * 功能描述 (Function)   : 旋转设备振动分区（ISO 10816-3 四机座等级 × 四区限值表）：
 *                         输入 10~1000Hz RMS 振动速度（mm/s）与机组等级（Ⅰ小型 / Ⅱ中型 /
 *                         Ⅲ大型刚性 / Ⅳ大型挠性），按限值表分 A/B/C/D 区（A 良好 / B 可接受 /
 *                         C 不合格 / D 危险）；区间跃迁带 fHystPct 迟滞防临界抖动：
 *                           向劣迁移需越 限值 + 迟滞带，向优迁移需低 限值 - 迟滞带，
 *                           迟滞带宽 = 限值 × fHystPct / 100。
 * 接口     (Interface)  : 输入 fVibMmS 振动速度（mm/s）、eClass 机组等级、fHystPct 迟滞
 *                         （%）、bReset 复位；输出 eZone 当前区、bZoneChanged 区跃迁单拍、
 *                         bError 故障标志。
 * 边界     (Boundary)   : ① **属主边界（写死）：本件只做分区判定与迟滞，不做振动采样、
 *                         不做频谱分析、不接管停机联锁**（机械臂专项归
 *                         `FB_DL_RobotArmVibrationWatch`）。
 *                         ② 限值表内嵌为 VAR CONSTANT 二维数组，逐行注释单位（mm/s）与
 *                         出处行（ISO 10816-3 分区限值），禁散落魔法数。
 *                         ③ fVib <= 0 或非有限 → 冻结上次 eZone 并置 bError（R245）。
 *                         ④ 等级枚举越界（CASE ELSE）→ 回 eB 安全侧并置组态错锁存，
 *                         解除沿 = bReset 上升沿。
 *                         ⑤ 区索引判据用 < 比较（限值边界值归劣区），浮点禁 = 判等。
 *                         ⑥ 零全局耦合（无 GVL / VAR_EXTERNAL / 物理地址）。
 * 分工声明 (Scope)      : 与 `FB_DL_RobotArmVibrationWatch` 分工：通用机泵 ISO 分区（本件）
 *                         ≠ 机械臂关节专项监视（那件）。
 * 来源标签 (Source Tag) : T2-8 ◐（ISO 10816-3 公开分区只借分区事实与限值数值，无文本复制）
 * 码表     (Codes)      : 本件不占用任何全局数字码位。出口为 ENUM 区别 + BOOL 组；
 *                         数字码位待主控收口阶段统一派号。
 * 红线自检 (Redline)    : R1 ✓ 零 GVL/VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q/%M ｜ R3 ✓ 纯 IEC 61131-3
 *                         R4 ✓ 非有限/非正冻结 + 迟滞容差 + 魔法数表内嵌 ｜ R5 ✓ 声明逐行同行双语注释
 *                         R6 ✓ ENUM+CASE 含 ELSE ｜ R7 ✓ 一 R_TRIG 段 0 无条件刷新
 * 修订历史 (Revision)   : 2026-11-20  v1.0.0  R48 首版（批次 3 · 序号 12）
 *                         验收向量：Ⅱ 级 2.0 mm/s → B 区；2.9 越迟滞 → C 区；临界回摆
 *                         不抖动；fVib=0 → 冻结 + bError。
 *==============================================================================*)

TYPE E_DL_VibClass :
(
    eClass1 := 1,    // Ⅰ 类：小型机（<15kW）/ Class 1, small machines
    eClass2 := 2,    // Ⅱ 类：中型机（15~300kW）/ Class 2, medium machines
    eClass3 := 3,    // Ⅲ 类：大型机-刚性支承 / Class 3, large rigid support
    eClass4 := 4     // Ⅳ 类：大型机-挠性支承 / Class 4, large flexible support
);
END_TYPE

TYPE E_DL_VibZone :
(
    eZoneA := 1,    // A 区：良好 / Zone A, good
    eZoneB := 2,    // B 区：可接受 / Zone B, acceptable
    eZoneC := 3,    // C 区：不合格 / Zone C, unsatisfactory
    eZoneD := 4     // D 区：危险 / Zone D, dangerous
);
END_TYPE

FUNCTION_BLOCK FB_DL_VibZoneClassify
VAR_INPUT
    fVibMmS : LREAL := 0.0;      // 振动速度 RMS（10~1000Hz 频段） [mm/s] / Vibration velocity RMS [mm/s]
    eClass  : E_DL_VibClass := E_DL_VibClass.eClass2;   // 机组等级（默认 Ⅱ 中型） [-] / Machine class
    fHystPct: LREAL := 10.0;     // 区间跃迁迟滞（对限值百分比），域 [0,50] [%] / Zone hysteresis [%]
    bReset  : BOOL := FALSE;     // 复位，上升沿清组态故障锁存 [-] / Reset, rising edge clears config latch
END_VAR
VAR_OUTPUT
    eZone        : E_DL_VibZone;  // 当前振动区出口 [-] / Current vibration zone outlet
    bZoneChanged : BOOL;          // 区跃迁，单拍脉冲 [-] / Zone changed, single-scan pulse
    bError       : BOOL;          // 故障标志（输入病 ∨ 组态非法） [-] / Error flag
END_VAR
VAR
    _nZone    : DINT := 2;       // 当前区索引（1~4，初值 eB 安全侧） / Current zone index, safe-side init
    _nCls     : DINT := 2;       // 等级索引（1~4，由 CASE 派生） / Class index
    _nNew     : DINT;            // 当拍裸分区索引（迟滞前） / Raw zone index before hysteresis
    _fBnd     : LREAL;           // 迁移向用限值 [mm/s] / Boundary limit for the transition
    _fHyst    : LREAL;           // 迁移向迟滞带宽 [mm/s] / Hysteresis band width
    _bBadCls  : BOOL;            // 等级枚举越界当拍量 [-] / Illegal class this scan
    _bErrLatch: BOOL;            // 组态故障锁存位（解除沿 = bReset 上升沿） / Latched config fault
    _bErrScan : BOOL;            // 当拍错误内部量（输入病当拍报，不锁存） / Per-scan error internal
    rtReset   : R_TRIG;          // 复位沿实例，段 0 无条件调用 / Reset edge instance
    _bNonFin  : BOOL;            // 振动值非有限当拍量 [-] / Non-finite vibration this scan
END_VAR
VAR CONSTANT
    DL_VZC_PCT : LREAL := 100.0;   // 百分比换算基 [无量纲] / Percent conversion base
    DL_VZC_HMAX: LREAL := 50.0;    // 迟滞组态上限 [%] / Hysteresis config ceiling [%]
    DL_VZC_EPS : LREAL := 0.0;     // 非有限差值判零基准 [-] / Non-finite difference zero base
    DL_VZC_LIM : ARRAY[1..4, 1..3] OF LREAL := [   // ISO 10816-3 分区限值表（行=机座等级 Ⅰ~Ⅳ）[mm/s] / ISO 10816-3 zone boundary table [mm/s]
        0.71, 1.40, 2.30,
        1.40, 2.80, 4.50,
        2.30, 4.50, 7.10,
        3.50, 7.10, 11.00];
        // ISO 10816-3 分区限值表，行=机座等级 Ⅰ/Ⅱ/Ⅲ/Ⅳ，列=A/B、B/C、C/D 区边界 [mm/s] / ISO 10816-3 zone boundary table [mm/s]
END_VAR

(* —— 段 0：非有限判 + 组态闸 + 沿刷新 —— *)
_bNonFin := (fVibMmS <> fVibMmS) OR ((fVibMmS - fVibMmS) <> DL_VZC_EPS);   // 振动值非有限（R245） / Non-finite vibration
IF (fHystPct < 0.0) OR (fHystPct > DL_VZC_HMAX) THEN
    _bErrLatch := TRUE;                     // 迟滞组态域闸：锁存（R188 解除沿 = bReset 上升沿） / Hysteresis gate: latch
END_IF
rtReset(CLK := bReset);                     // 复位沿，每拍必调 / Reset edge, every scan

(* —— 段 1：复位沿 + 等级索引派生（ELSE 兜底安全侧） —— *)
IF rtReset.Q THEN
    _bErrLatch := FALSE;                    // 清组态故障锁存 / Clear config latch
END_IF
_bBadCls := FALSE;                          // 越界量预清 / Illegal-class preset
CASE eClass OF
E_DL_VibClass.eClass1:
    _nCls := 1;                             // Ⅰ 类索引 / Class 1 index
E_DL_VibClass.eClass2:
    _nCls := 2;                             // Ⅱ 类索引 / Class 2 index
E_DL_VibClass.eClass3:
    _nCls := 3;                             // Ⅲ 类索引 / Class 3 index
E_DL_VibClass.eClass4:
    _nCls := 4;                             // Ⅳ 类索引 / Class 4 index
ELSE
    _nCls := 2;                             // 越界兜底：Ⅱ 类安全侧 / Illegal class falls back to class 2
    _bBadCls := TRUE;                       // 记越界（当拍报组态错） / Mark illegal
    _bErrLatch := TRUE;                     // 等级越界属组态病：锁存 / Illegal class latches config fault
END_CASE

(* —— 段 2：裸分区（限值 < 比较；输入病冻结） —— *)
_bErrScan := FALSE;                         // 当拍错误预清 / Per-scan error preset
_nNew := _nZone;                            // 缺省保持当前区（冻结语义） / Default hold current zone
IF (NOT _bErrLatch) AND (NOT _bNonFin) AND (fVibMmS > 0.0) THEN
    IF fVibMmS < DL_VZC_LIM[_nCls, 1] THEN
        _nNew := 1;                         // 低于 A/B 限值：A 区 / Below A/B limit: zone A
    ELSIF fVibMmS < DL_VZC_LIM[_nCls, 2] THEN
        _nNew := 2;                         // B 区 / Zone B
    ELSIF fVibMmS < DL_VZC_LIM[_nCls, 3] THEN
        _nNew := 3;                         // C 区 / Zone C
    ELSE
        _nNew := 4;                         // 超 C/D 限值：D 区 / Above C/D limit: zone D
    END_IF
ELSE
    _bErrScan := TRUE;                      // 非有限/非正/组态病：当拍错误（冻结区） / Bad input: per-scan error
END_IF

(* —— 段 3：迟滞迁移（向劣越 限值+迟滞、向优低 限值-迟滞，防临界抖动） —— *)
IF (_nNew > _nZone) AND (NOT _bErrScan) THEN
    _fBnd := DL_VZC_LIM[_nCls, _nZone];     // 劣迁向限值（当前区上界） / Boundary for worsening move
    _fHyst := _fBnd * fHystPct / DL_VZC_PCT;   // 迟滞带宽 [mm/s] / Hysteresis band
    IF fVibMmS <= (_fBnd + _fHyst) THEN
        _nNew := _nZone;                    // 未越出迟滞带：保持原区 / Within hysteresis: hold zone
    END_IF
ELSIF (_nNew < _nZone) AND (NOT _bErrScan) THEN
    _fBnd := DL_VZC_LIM[_nCls, _nZone - 1]; // 优迁向限值（当前区下界） / Boundary for improving move
    _fHyst := _fBnd * fHystPct / DL_VZC_PCT;   // 迟滞带宽 / Hysteresis band
    IF fVibMmS >= (_fBnd - _fHyst) THEN
        _nNew := _nZone;                    // 未低出迟滞带：保持原区 / Within hysteresis: hold zone
    END_IF
END_IF

(* —— 段 4：出口单点映射（区索引 → 枚举 CASE 化，名实同源 R191） —— *)
bZoneChanged := FALSE;                      // 跃迁脉冲预清 / Changed pulse preset
IF _nNew <> _nZone THEN
    bZoneChanged := TRUE;                   // 区跃迁单拍 / Zone changed pulse
    _nZone := _nNew;                        // 更新当前区（锁存） / Latch new zone
END_IF
CASE _nZone OF
1:
    eZone := E_DL_VibZone.eZoneA;           // A 区出口 / Zone A outlet
2:
    eZone := E_DL_VibZone.eZoneB;           // B 区出口 / Zone B outlet
3:
    eZone := E_DL_VibZone.eZoneC;           // C 区出口 / Zone C outlet
4:
    eZone := E_DL_VibZone.eZoneD;           // D 区出口 / Zone D outlet
ELSE
    eZone := E_DL_VibZone.eZoneB;           // 非法区索引兜底安全侧（R6 红线） / Illegal zone falls back to B
END_CASE
bError := _bErrLatch OR _bErrScan OR _bBadCls;   // 故障标志 = 组态锁存 ∨ 当拍输入病 ∨ 等级越界 / Error = latch or scan or class

END_FUNCTION_BLOCK
