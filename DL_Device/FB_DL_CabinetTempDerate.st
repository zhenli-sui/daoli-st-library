(*
    FB_DL_CabinetTempDerate —— 柜内温度降额（多点取最大 + 分级降额 + 失效保持超时报警）
    ------------------------------------------------------------------
    组件名称  : FB_DL_CabinetTempDerate
    分类      : DL_Device / ThermalManagement
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : 借鉴点 —— 变频器 / 伺服驱动器热管理的通行策略：柜内多点测温取
                最大值作为判据（热点决定降额，平均值会掩盖局部过热）、按温度
                分级给出输出降额系数（0~1 的倍率，送上层限幅）、测温点失效时
                **保持末次有效值**并计时，超时仍无有效值才报警。
                诊断分级口径参考 NE 107 的「失效 / 超出规格 / 功能检查 / 维护」
                四级分类思想（本件对应「失效需保持 + 超时上报」）。
                clean-room 声明 —— 零代码行复制；分级判据、保持结构、码位与
                双语文档全部本件自有，仅使用 IEC 61131-3 标准库 TON / R_TRIG。
                许可证 —— 本件 MIT；来源标签 ne107 指公开诊断分类术语，
                标准文本不属代码，无许可继承。
    平台      : 纯 IEC 61131-3，CODESYS 3.5 / TwinCAT 3 / InoProShop / Machine Expert 通用
    作者      : 道莅代码库 · PLC编程专家（R70 构建轮 · 批 3 · N10）
    ------------------------------------------------------------------
    功能说明  : 一 逐点筛查：abSensOk 为 FALSE 或该点温度非有限 → 该点判为失效，
                   不参与取最大（失效点绝不当作 0 °C 参与，否则热点会被掩盖）。
                二 取最大：在有效点中取最大值 fMaxTemp；有效点数为 0 时
                   fMaxTemp 保持末次有效值（_fHoldMax），并启动失效计时。
                三 分级降额（判据自上而下，先到先得）：
                   fMaxTemp >= fT3 → eTier3 系数 fK3（降额最深）
                   fMaxTemp >= fT2 → eTier2 系数 fK2
                   fMaxTemp >= fT1 → eTier1 系数 fK1
                   否则 eNormal 系数 1.0
                   分级用 ENUM + CASE，含 ELSE 兜底（非法等级 → 回 eNormal 且置 0803）。
                   分级为「逐拍重算」，不带回差 —— 柜温降额关注安全侧，且上层
                   限幅链路本身有速率限制，故不在此处引入回差（口径写死）。
                四 失效报警：全点失效持续 tSensFault → 锁存 0802（故障级），
                   并把降额系数**压到最保守值 fK3**（失效时无法判明温度，
                   必须按最深降额处置，这是失效安全方向）。
                五 部分失效（有有效点但不足全部）：置信息级 0804，bError 保持 FALSE，
                   降额照常按有效点计算。
    错误码    : 16#0002_0801 组态非法（温度分级非单调 / 系数不在 (0,1] / 非有限），锁存 —— 故障级
                16#0002_0802 全部测温点失效超时（无法判明柜温），锁存 —— 故障级
                16#0002_0803 非法降额等级枚举（CASE ELSE 兜底），锁存 —— 故障级
                16#0002_0804 部分测温点失效（仍按有效点降额运行），不锁存 —— 信息级
    码位总账  : 0801 / 0802 / 0803 用（故障级，锁存回放）｜ 0804 用（信息级，每拍重算）
    状态机    : 降额等级 E_DL_CtdTier 四态，CASE 全覆盖 + ELSE 兜底。
                判据链为逐拍组合判据，无相驻留；失效计时由 TON 自持。
    边界与披露: 一 组态闸（R272 逐项点名）：fT1 < fT2 < fT3 严格单调；三个系数均在
                   (0.0, 1.0] 内且 fK3 <= fK2 <= fK1（降额随温度单调不增，反置会导致
                   高温反而给出更大系数，属致命组态错误）；六量全部纳入非有限闸；
                二 数组下标安全：全部 FOR 循环以常量 DL_CAB_N 为界（编译期确定），
                   本件无任何「以引脚值作下标」的访问；
                三 出口语义（R191 名实双出口）：fDerateK 与 eTier 同源（同一 CASE
                   分支内成对赋值，故系数与等级恒一致）；bSensorAlarm 与 0802 同源；
                四 失能（bEn = FALSE）：fDerateK 输出**最保守值 fK3**（失能不等于
                   允许满载，安全方向），fMaxTemp 保持末次有效值，eTier 回 eNormal，
                   锁存位不被失能清除（须 bReset 上升沿）；
                五 定时器 _tonSensFault 与沿实例 _rtReset 每周期无条件调用（规则 ⑦）；
                六 零全局变量、零 VAR_EXTERNAL、零物理地址、无除法。
    修订记录  : 2026-11-22 v1.0.0 首次入库（R70 构建轮 · 批 3 · N10）
*)
TYPE E_DL_CtdTier :
(
    eNormal := 0,   (* 正常，降额系数 = 1.0 / normal, the derating factor is one *)
    eTier1  := 10,  (* 一级降额（>= fT1）/ tier one, at or above fT1 *)
    eTier2  := 20,  (* 二级降额（>= fT2）/ tier two, at or above fT2 *)
    eTier3  := 30   (* 三级降额（>= fT3，最深）/ tier three, the deepest, at or above fT3 *)
);
END_TYPE

FUNCTION_BLOCK FB_DL_CabinetTempDerate
VAR_INPUT
    bEn        : BOOL := TRUE;             (* 使能，[标志] / the enable *)
    bReset     : BOOL := FALSE;            (* 故障复位（上升沿有效），[标志] / the fault reset, rising edge *)
    arTempC    : ARRAY[1..4] OF LREAL;     (* 四个柜内测温点温度，[°C] / four cabinet temperature readings *)
    abSensOk   : ARRAY[1..4] OF BOOL;      (* 四个测温点有效性（变送器级），[标志] / the per point validity *)
    fT1        : LREAL := 45.0;            (* 一级降额起判温度，[°C]，须 < fT2 / the tier one threshold *)
    fT2        : LREAL := 55.0;            (* 二级降额起判温度，[°C]，须 < fT3 / the tier two threshold *)
    fT3        : LREAL := 65.0;            (* 三级降额起判温度，[°C]，须 > fT2 / the tier three threshold *)
    fK1        : LREAL := 0.85;            (* 一级降额系数，[无量纲]，域 (0,1] / the tier one factor *)
    fK2        : LREAL := 0.70;            (* 二级降额系数，[无量纲]，域 (0,1] / the tier two factor *)
    fK3        : LREAL := 0.50;            (* 三级降额系数（亦为失效保守值），[无量纲]，域 (0,1] / the tier three factor *)
    tSensFault : TIME := T#30S;            (* 全点失效报警延时，[ms] / the all-points-failed alarm delay *)
END_VAR
VAR_OUTPUT
    fMaxTemp     : LREAL;                  (* 有效点中的最高柜温（失效时保持末次值），[°C] / the highest valid temperature *)
    fDerateK     : LREAL := 1.0;           (* 降额系数（输出倍率），[无量纲] / the derating factor *)
    eTier        : E_DL_CtdTier := E_DL_CtdTier.eNormal; (* 降额等级出口，[等级] / the derating tier outlet *)
    bSensorAlarm : BOOL;                   (* 全点失效超时报警（保持型），[标志] / the all sensors failed alarm *)
    bPartialFail : BOOL;                   (* 部分测温点失效，[标志] / some points have failed *)
    bBusy        : BOOL;                   (* 失效计时进行中，[标志] / the failure timer is running *)
    bValid       : BOOL;                   (* 出口可信（非锁存故障），[标志] / the outlets are trustworthy *)
    bError       : BOOL;                   (* 故障标志，故障级码时为 TRUE / the error flag, TRUE on fault level *)
    nErrCode     : UDINT;                  (* 错误码，0 = 正常 / the error id, 0 = ok *)
END_VAR
VAR
    _rtReset     : R_TRIG;                 (* 复位上升沿实例（无条件调用）/ the reset rising edge instance *)
    _tonSensFault : TON;                   (* 全点失效报警计时实例（无条件调用）/ the all sensors failed timer *)
    _bFault      : BOOL;                   (* 故障锁存位，仅 bReset 上升沿解除 / the latched fault bit *)
    _nCodeLatch  : UDINT;                  (* 锁存成因码，故障期回放 / the latched cause code *)
    _bCfgBad     : BOOL;                   (* 组态非法标志（逐拍重算）/ the configuration fault flag *)
    _bEnGood     : BOOL;                   (* 运行许可（使能且无锁存故障）/ the run permit *)
    _eTier       : E_DL_CtdTier := E_DL_CtdTier.eNormal; (* 降额等级寄存器，[等级] / the tier register *)
    _fMax        : LREAL;                  (* 本轮取最大中间量，[°C] / the maximum temporary *)
    _fHoldMax    : LREAL;                  (* 末次有效最高温度（失效保持量），[°C] / the last valid maximum *)
    _bHaveMax    : BOOL;                   (* 已获得过有效最高温度，[标志] / a valid maximum was seen *)
    _nValid      : INT;                    (* 有效测温点数，[个] / the number of valid points *)
    _i           : INT;                    (* 循环下标，[号] / the loop index *)
    _bPtBad      : BOOL;                   (* 单点失效判据结果，[标志] / the point failure verdict *)
    _fK          : LREAL;                  (* 本轮降额系数中间量，[无量纲] / the factor temporary *)
END_VAR
VAR CONSTANT
    DL_CAB_N     : INT := 4;               (* 测温点数（与数组声明同源），[个] / the point count matching the arrays *)
    DL_CAB_FMAX  : LREAL := 1.0E6;         (* 非有限筛查幅值上限，[°C] / the finiteness screening cap *)
    DL_CAB_KONE  : LREAL := 1.0;           (* 满载系数（正常等级），[无量纲] / the full load factor *)
END_VAR

// 段 1｜出口预置（R256 统一出口预置）/ segment 1, preset every outlet
fDerateK     := fK3;                       // 系数出口先置最保守值（安全缺省）/ preset the factor to the most conservative value
eTier        := E_DL_CtdTier.eNormal;      // 等级出口先置正常（段 8 覆盖）/ preset the tier to normal, overwritten in segment 8
bSensorAlarm := FALSE;                     // 全点失效报警预清零（真值在段 8 由锁存映射）/ preset the alarm false
bPartialFail := FALSE;                     // 部分失效标志预清零 / preset the partial flag false
bBusy        := FALSE;                     // 忙碌标志预清零 / preset the busy flag false
bValid       := FALSE;                     // 可用标志预置假，健康路径再置真 / preset valid false
bError       := FALSE;                     // 故障标志预清零 / preset the error flag false
nErrCode     := 0;                         // 错误码预置无错 / preset the code to zero
_nValid      := 0;                         // 有效点数预清零 / preset the valid count
_fMax        := 0.0;                       // 最大值中间量预置零 / preset the maximum temporary
_fK          := fK3;                       // 系数中间量预置最保守值 / preset the factor temporary

// 段 2｜沿实例与定时器无条件调用（规则 ⑦）/ segment 2, the reset edge and the timer
_rtReset(CLK := bReset);                   // 复位沿，每周期无条件刷新 / the reset edge, refreshed every scan

// 段 3｜复位解除：唯一可到达的清除边（R188）/ segment 3, the only latch release edge
IF _rtReset.Q THEN                         // 复位上升沿 / the reset rising edge
    _bFault     := FALSE;                  // 解除故障锁存 / release the fault latch
    _nCodeLatch := 0;                      // 清锁存码 / clear the latched code
END_IF

// 段 4｜组态守卫（R272 逐项点名，含单调性反置拦截）/ segment 4, the configuration guard
_bCfgBad := (fT1 >= fT2) OR (fT2 >= fT3)                                   // 温度分级非严格单调 / the tiers are not strictly monotonic
         OR (fK1 <= 0.0) OR (fK1 > DL_CAB_KONE)                            // 一级系数域外 / the tier one factor out of range
         OR (fK2 <= 0.0) OR (fK2 > DL_CAB_KONE)                            // 二级系数域外 / the tier two factor out of range
         OR (fK3 <= 0.0) OR (fK3 > DL_CAB_KONE)                            // 三级系数域外 / the tier three factor out of range
         OR (fK3 > fK2) OR (fK2 > fK1)                                     // 降额随温度反置（致命组态错）/ the factors increase with temperature
         OR (fT1 <> fT1) OR ((fT1 - fT1) <> 0.0) OR (ABS(fT1) > DL_CAB_FMAX)
         OR (fT2 <> fT2) OR ((fT2 - fT2) <> 0.0) OR (ABS(fT2) > DL_CAB_FMAX)
         OR (fT3 <> fT3) OR ((fT3 - fT3) <> 0.0) OR (ABS(fT3) > DL_CAB_FMAX)
         OR (fK1 <> fK1) OR ((fK1 - fK1) <> 0.0) OR (ABS(fK1) > DL_CAB_FMAX)
         OR (fK2 <> fK2) OR ((fK2 - fK2) <> 0.0) OR (ABS(fK2) > DL_CAB_FMAX)
         OR (fK3 <> fK3) OR ((fK3 - fK3) <> 0.0) OR (ABS(fK3) > DL_CAB_FMAX);

// 段 5｜首次成因锁存（故障期不重推断，R189）/ segment 5, the first cause latch
IF NOT _bFault THEN                        // 未锁存才登记 / register only while healthy
    IF _bCfgBad THEN                       // 组态非法 / an illegal configuration
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0801;       // 故障级：组态非法 / fault level: an illegal configuration
    END_IF
END_IF
_bEnGood := bEn AND NOT _bFault;           // 运行许可 / the run permit

// 段 6｜逐点筛查与取最大（常量上下界，下标安全）/ segment 6, the point screening and the maximum
_nValid := 0;                              // 有效点数清零重算 / recount the valid points
_fMax   := 0.0;                            // 最大值清零重算 / reset the maximum
FOR _i := 1 TO DL_CAB_N DO                 // 常量上下界 / constant bounds
    _bPtBad := (NOT abSensOk[_i])                                  // 变送器报失效 / the transmitter reports a failure
            OR (arTempC[_i] <> arTempC[_i])                        // NaN 自反判 / the NaN test
            OR ((arTempC[_i] - arTempC[_i]) <> 0.0)                // Inf 差值自反判 / the Inf test
            OR (ABS(arTempC[_i]) > DL_CAB_FMAX);                   // 幅值上界 / the amplitude cap
    IF NOT _bPtBad THEN                    // 有效点 / a valid point
        _nValid := _nValid + 1;            // 计数 / count it
        IF _nValid = 1 THEN                // 第一个有效点 / the first valid point
            _fMax := arTempC[_i];          // 直接作为当前最大 / take it as the maximum
        ELSIF arTempC[_i] > _fMax THEN     // 后续更大值 / a later larger value
            _fMax := arTempC[_i];          // 刷新最大 / refresh the maximum
        END_IF
    END_IF
END_FOR

// 段 7｜有效点处理：全失效保持 + 部分失效信息码 / segment 7, the validity handling
IF _nValid > 0 THEN                        // 存在有效点 / at least one valid point
    _fHoldMax := _fMax;                    // 刷新末次有效最高温度 / refresh the last valid maximum
    _bHaveMax := TRUE;                     // 标记已有有效值 / mark that a valid value exists
    IF _nValid < DL_CAB_N THEN             // 有有效点但不足全部 / some points failed
        bPartialFail := TRUE;              // 部分失效标志 / the partial failure flag
        nErrCode     := 16#0002_0804;      // 信息级：部分失效（不置 bError，R45）/ info level, no fault flag
    END_IF
ELSE                                       // 全部失效 / every point failed
    bPartialFail := FALSE;                 // 全失效时部分失效位不置（归因唯一，R190）/ clear the partial flag
END_IF

// 段 8｜失效计时器无条件调用与报警锁存 / segment 8, the failure timer and its latch
_tonSensFault(IN := (_nValid = 0), PT := tSensFault); // 全点失效计时，每周期无条件调用
bBusy := _bEnGood AND (_nValid = 0) AND NOT _tonSensFault.Q; // 失效计时进行中
IF _bEnGood AND (_nValid = 0) AND _tonSensFault.Q THEN       // 全点失效超时 / all points failed long enough
    IF NOT _bFault THEN                    // 首次判定才登记 / register the cause once
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0802;       // 故障级：全点失效 / fault level: every point failed
    END_IF
END_IF

// 段 9｜最高温度出口与降额分级（ENUM + CASE + ELSE 兜底）/ segment 9, the maximum outlet and the tiering
IF _bHaveMax THEN                          // 已有有效值 / a valid value exists
    fMaxTemp := _fHoldMax;                 // 输出末次有效最高温度（失效期保持）/ output the held maximum
ELSE                                       // 从未获得有效值 / no valid value yet
    fMaxTemp := 0.0;                       // 输出零值（初值语义，已在边界声明）/ output zero, the documented initial value
END_IF
IF _bEnGood THEN                           // 运行许可成立才参与分级 / grade only while the run permit holds
    IF fMaxTemp >= fT3 THEN                // 三级判据 / the tier three criterion
        _eTier := E_DL_CtdTier.eTier3;     // 三级 / tier three
    ELSIF fMaxTemp >= fT2 THEN             // 二级判据 / the tier two criterion
        _eTier := E_DL_CtdTier.eTier2;     // 二级 / tier two
    ELSIF fMaxTemp >= fT1 THEN             // 一级判据 / the tier one criterion
        _eTier := E_DL_CtdTier.eTier1;     // 一级 / tier one
    ELSE                                   // 低于一级判据 / under the tier one threshold
        _eTier := E_DL_CtdTier.eNormal;    // 正常 / normal
    END_IF
ELSE                                       // 失能或锁存故障 / disabled or latched
    _eTier := E_DL_CtdTier.eNormal;        // 等级回正常（系数由段 10 压到最保守值）/ the tier returns to normal, the factor is clamped below
END_IF
CASE _eTier OF
    E_DL_CtdTier.eNormal:                  // 正常等级 / the normal tier
        _fK := DL_CAB_KONE;                // 系数 1.0 / the factor is one
    E_DL_CtdTier.eTier1:                   // 一级降额 / tier one
        _fK := fK1;                        // 系数取一级值 / the tier one factor
    E_DL_CtdTier.eTier2:                   // 二级降额 / tier two
        _fK := fK2;                        // 系数取二级值 / the tier two factor
    E_DL_CtdTier.eTier3:                   // 三级降额 / tier three
        _fK := fK3;                        // 系数取三级值 / the tier three factor
    ELSE                                   // 非法枚举兜底（回安全等级 + 置码，规则 ⑥）/ the illegal enumeration guard
        _eTier      := E_DL_CtdTier.eNormal; // 回安全等级 / force the safe tier
        _fK         := fK3;                // 系数压到最保守值 / clamp the factor to the most conservative
        _bFault     := TRUE;               // 置锁存 / latch it
        _nCodeLatch := 16#0002_0803;       // 故障级：非法降额等级 / fault level: an illegal tier value
END_CASE

// 段 10｜出口映射（名实双出口同源，R191；故障 / 失效压最保守系数）/ segment 10, the outlet mapping
IF _bEnGood AND NOT _bFault THEN           // 健康运行 / healthy and running
    fDerateK := _fK;                       // 系数出口取分级结果 / the factor follows the tier
    bValid   := _bHaveMax OR (_nValid > 0); // 有有效值即出口可信 / trustworthy once a valid value exists
ELSE                                       // 失能或锁存故障 / disabled or latched
    fDerateK := fK3;                       // 压到最保守系数（失效安全方向）/ clamp to the most conservative factor
    bValid   := FALSE;                     // 出口不可信 / the outlets are not trustworthy
END_IF
eTier        := _eTier;                    // 等级出口 = 寄存器（与系数同源成对赋值）/ the tier outlet mirrors the register
bSensorAlarm := _bFault AND (_nCodeLatch = 16#0002_0802); // 报警位与 0802 同源 / the alarm shares the 0802 latch
bError       := _bFault;                   // 故障标志与锁存同源 / the fault flag shares the latch
nErrCode     := _nCodeLatch;               // 锁存码回放；无锁存时保留段 7 的信息级 0804 / replay the latch, keep the info code otherwise
IF _nCodeLatch = 0 THEN                    // 无锁存故障 / no latched fault
    IF _nValid > 0 AND _nValid < DL_CAB_N THEN // 部分失效仍在 / some points still failed
        nErrCode := 16#0002_0804;          // 信息级：部分失效 / info level, a partial failure
    END_IF
END_IF
END_FUNCTION_BLOCK
