(*
  ==================================================================
  组件名 Component  : FB_DL_FeedOverrideRamp
  分类   Category   : DL_Motion
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : 进给倍率斜坡（PLCopen 风格 0~150%）：正常相按「加速/
                      减速」分离速率把 fOvrOut 斜坡逼近钳位后的 fOvrIn；
                      bZeroFast 为显式最高优先级仲裁——TRUE 时无条件以
                      fRateZeroPctS 向 0% 斜坡（压倒正常跟踪）；bAtCmd 用
                      1E-6 容差判到达（禁浮点判等）。
  来源   Source     : t1-6-plcopen（PLCopen TC 系列倍率语义：借「倍率域与
                      速率限制」公开口径，实现零源码复制）
  互引   Cross-ref  : FB_DL_RateLimiter（同族通用限速率器，本件为其倍率域
                      特化件，速率仲裁口径一致）；FB_DL_OverrideSelector
                      （上游倍率源选择件，其输出可接本件 fOvrIn）
  平台   Platform   : 纯 IEC 61131-3 四则，三平台通用
  依赖   Depends    : 无标准库依赖（无定时器/无沿检测）
  设计偏差 Deviation: 时间基准按本库「时间注入」纪律：新增输入 fCallCycleS
                      （调用方注入扫描周期 [s]），本件不读平台时刻函数；
                      斜坡步长 = 速率 × fCallCycleS。
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 输入 0~150 显式钳位 + 输出 0~150 显式钳位 +
                      非有限闸 + 容差判到达（禁 =）+ 除法零处（无除法面）
                      R5 全变量双语同行注释/R6 纯仲裁无 ENUM 状态机（仲裁
                      优先级线性结构，非相态迁移，见头注说明）
                      R7 无定时器与沿检测实例/R8 速率与容差常量化
  契约   Contract   : 失能相输出行为写死（FB33-4 声明，不静默）：bEnable=
                      FALSE → fOvrOut 冻结保持上次值、bAtCmd=FALSE，速率
                      配置不复检（恢复使能后重新生效）；bZeroFast 使能独立
                      于 bEnable（安全归零不受失能门控压制，头注安全侧口径）。
  错误码 Codes      : 01【故障级】速率配置非法（fRateIncPctS / fRateDecPctS /
                      fRateZeroPctS 任一 ≤ 0 或非有限，或 fCallCycleS ≤ 0 /
                      非有限）；故障相输出冻结保持 + bError（R45 配对）
  码位反证 Note     : 仅一码依据（R90 反证）：三个速率任一非法的处置完全
                      同形（冻结 + 拒斜坡），输出组合不可区分，合并不丢信息。
  验收   Acceptance : V1 30→80% 增速斜坡按 fRateIncPctS ｜ V2 80→30% 按
                      fRateDecPctS ｜ V3 bZeroFast → 以 fRateZeroPctS 归零，
                      bEnable=FALSE 时仍归零（仲裁显式）｜ V4 速率 0 → 码 01
                      + 冻结 ｜ V5 到达 ±1E-6 内 bAtCmd=TRUE ｜ V6 全程不出
                      [0,150]
  变更   Revision   : 2026-11-22  v1.0.0  R66 首版（编码阶段批 3 序 8）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_FeedOverrideRamp
VAR_INPUT
    fOvrIn       : LREAL := 0.0;    // 倍率请求 [%]，0~150 钳位 / the override request, clamped 0 to 150
    bEnable      : BOOL := FALSE;   // 使能（失能=冻结保持，头注契约写死）[-] / the enable, false freezes the output
    bZeroFast    : BOOL := FALSE;   // 快速归零仲裁（最高优先级，独立于使能）[-] / the fast zero arbitration, the top priority
    fRateIncPctS : LREAL := 50.0;   // 增速率 [%/s]，须 > 0 / the increase rate, must be positive
    fRateDecPctS : LREAL := 50.0;   // 减速率 [%/s]，须 > 0 / the decrease rate, must be positive
    fRateZeroPctS: LREAL := 200.0;  // 归零速率 [%/s]，须 > 0（仲裁用）/ the zero rate, must be positive
    fCallCycleS  : LREAL := 0.01;   // 调用方注入扫描周期 [s]，须 > 0 / the caller injected scan cycle in seconds
END_VAR
VAR_OUTPUT
    fOvrOut      : LREAL := 0.0;    // 倍率输出 [%]，全程钳位 0~150 / the override output, always clamped 0 to 150
    bAtCmd       : BOOL := FALSE;   // 到达指示（1E-6 容差判到达）[-] / the at command flag by tolerance
    bError       : BOOL := FALSE;   // 配置故障标志（R45 配对）/ the configuration fault flag
    uErrorId     : UDINT := 16#0000_0000; // 错误码，0=正常，01=速率配置非法 [码] / the error code [code]
END_VAR
VAR
    _fTarget     : LREAL := 0.0;    // 本拍斜坡目标 [%] / the per scan ramp target
    _fRate       : LREAL := 0.0;    // 本拍选用速率 [%/s] / the per scan selected rate
    _fStep       : LREAL := 0.0;    // 本拍斜坡步长 [%] / the per scan ramp step
    _bCfgOk      : BOOL := FALSE;   // 本拍配置有效性 [-] / the per scan configuration validity
END_VAR
VAR CONSTANT
    FOR_OVR_MIN  : LREAL := 0.0;      // 倍率域下限 [%] / the override domain lower clamp
    FOR_OVR_MAX  : LREAL := 150.0;    // 倍率域上限 [%]（PLCopen 倍率域口径）/ the override domain upper clamp
    FOR_AT_EPS   : LREAL := 1.0E-6;   // 到达容差 [%]（禁浮点判等）/ the arrival tolerance
    FOR_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    FOR_ERR_NONE : UDINT := 16#0000_0000; // 无错误 [码] / no error [code]
    FOR_ERR_RATE : UDINT := 16#0000_0001; // 码 01：速率配置非法 / code 01, illegal rate configuration
END_VAR

// 段 1｜配置闸（码 01）：三速率与扫描周期逐项有限 + 正域 / segment 1, the configuration gate
_bCfgOk := (fRateIncPctS > 0.0) AND (fRateIncPctS = fRateIncPctS)
       AND (fRateDecPctS > 0.0) AND (fRateDecPctS = fRateDecPctS)
       AND (fRateZeroPctS > 0.0) AND (fRateZeroPctS = fRateZeroPctS)
       AND (fCallCycleS > 0.0) AND (fCallCycleS = fCallCycleS);   // 逐项自反判 NaN + 正域 / per item NaN reflex and positivity
IF _bCfgOk THEN
    bError := FALSE;                 // 配置恢复即清标志（信息级随当拍，无锁存面）/ cleared when the config recovers
    uErrorId := FOR_ERR_NONE;
ELSE
    bError := TRUE;                  // 故障标志（R45 配对）/ the fault flag
    uErrorId := FOR_ERR_RATE;        // 码 01 / code 01
    bAtCmd := FALSE;                 // 故障相到达指示撤销（头注契约）/ revoke the arrival flag in the fault phase
    RETURN;                          // 故障相输出冻结保持 fOvrOut（头注契约），不再斜坡 / frozen output, no ramping
END_IF

// 段 2｜请求钳位与非有限闸：非有限请求按 0% 安全侧处理 / segment 2, the request clamp and finiteness gate
IF (fOvrIn <> fOvrIn) OR (ABS(fOvrIn) > FOR_FIN_MAX) THEN
    _fTarget := FOR_OVR_MIN;         // 非有限请求落 0%（安全侧）/ a non finite request lands at zero
ELSIF fOvrIn < FOR_OVR_MIN THEN
    _fTarget := FOR_OVR_MIN;         // 下钳 / clamp low
ELSIF fOvrIn > FOR_OVR_MAX THEN
    _fTarget := FOR_OVR_MAX;         // 上钳 / clamp high
ELSE
    _fTarget := fOvrIn;              // 合法请求直取 / take the valid request
END_IF

// 段 3｜归零优先仲裁（显式优先序：bZeroFast > bEnable 跟踪，线性仲裁无状态相）
//      segment 3, the explicit arbitration, zero fast outranks the tracking
IF bZeroFast THEN
    _fTarget := FOR_OVR_MIN;         // 归零目标（压倒请求）/ the zero target overrides the request
    _fRate := fRateZeroPctS;         // 归零专用速率 / the dedicated zero rate
ELSIF NOT bEnable THEN
    bAtCmd := FALSE;                 // 失能相到达指示撤销（头注契约写死）/ revoke the arrival flag in the disabled phase
    RETURN;                          // 失能相：输出冻结保持 fOvrOut（头注契约写死）/ the disabled phase freezes
ELSE
    IF fOvrOut < _fTarget THEN
        _fRate := fRateIncPctS;      // 向上用增速率 / the increase rate upward
    ELSE
        _fRate := fRateDecPctS;      // 向下用减速率 / the decrease rate downward
    END_IF
END_IF

// 段 4｜斜坡推进（步长 = 速率 × 周期，周期已闸 > 0）/ segment 4, the ramp advance
_fStep := _fRate * fCallCycleS;      // 本拍步长 [%] / the per scan step
IF fOvrOut < _fTarget - FOR_AT_EPS THEN
    fOvrOut := fOvrOut + _fStep;     // 向上斜坡 / ramp up
    IF fOvrOut > _fTarget THEN fOvrOut := _fTarget; END_IF   // 不越过目标 / never past the target
ELSIF fOvrOut > _fTarget + FOR_AT_EPS THEN
    fOvrOut := fOvrOut - _fStep;     // 向下斜坡 / ramp down
    IF fOvrOut < _fTarget THEN fOvrOut := _fTarget; END_IF
END_IF

// 段 5｜输出钳位（双保险）与到达判定 / segment 5, the output clamp and the arrival test
IF fOvrOut < FOR_OVR_MIN THEN
    fOvrOut := FOR_OVR_MIN;          // 下限钳位 / clamp low
END_IF
IF fOvrOut > FOR_OVR_MAX THEN
    fOvrOut := FOR_OVR_MAX;          // 上限钳位 / clamp high
END_IF
bAtCmd := ABS(fOvrOut - _fTarget) < FOR_AT_EPS;  // 容差判到达（禁 =）/ arrival by tolerance
END_FUNCTION_BLOCK
