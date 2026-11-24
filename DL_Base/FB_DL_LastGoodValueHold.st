(*
  ==================================================================
  组件名 Component  : FB_DL_LastGoodValueHold
  分类   Category   : DL_Base
  前缀   Naming     : FB_DL_ ｜ b/n/u/f/t/e 类型前缀制（R265）
  版本   Version    : 1.0.0
  功能   Purpose    : NE43 信号质量失效保持件：bSigOk=TRUE（质量好）时
                      透传 fInVal 并刷新保持载体；bSigOk=FALSE（NE43 超
                      量程/欠量程/断线诊断失效）时输出冻结为最后有效值
                      fLastGood，同时 tonStale 累计陈旧时长，超 tStaleMax
                      置信息码 01 与 bStale（输出仍保持最后有效值，不静
                      默）。失效时无历史有效值（首件语义）bValid=FALSE
                      并置信息码 03。tStaleMax ≤ 0 配置非法电平面码 02。
  来源   Source     : t2-8-ne43（NE43 欠量程/超量程诊断语义为公开行业
                      口径（NAMUR NE43），实现零源码复制）
  互引   Cross-ref  : FB_DL_AnalogOutFailsafe（同族失效安全件：其面向模
                      出通道失效替代，本件面向模拟量输入信号质量保持，
                      二者可级联——本件输出喂其输入）
  平台   Platform   : 纯 IEC 61131-3（TON/LREAL 四则/TIME 比较）
  依赖   Depends    : 仅 Standard.library（TON 属标准件）
  红线   Redline    : R1 零全局/VAR_EXTERNAL/R2 零 %I/%Q/R3 纯 IEC 标准
                      R4 输入非有限闸 + 配置闸显式 + TON 实例段 0 无条件
                      刷新/R5 全变量双语同行注释/R6 配置故障电平面无状
                      态机（CASE 不适用，头注说明）/R7 tonStale 无条件周
                      期调用/R8 阈值常量化
  契约   Contract   : 码 02 配置非法为电平面（当拍复判）：故障拍 bValid=
                      FALSE、fOut 冻结保持、bError=TRUE，恢复即恢复；
                      码 01/03 为信息级不置 bError。信号恢复（bSigOk 上
                      升）即透传刷新载体并清陈旧计时（TON 随 IN=FALSE
                      自清零，R188 自复位语义）。
  错误码 Codes      : 01【信息级】陈旧超限（保持时长超 tStaleMax，输出
                      仍为最后有效值）
                      02【故障级·电平面】tStaleMax ≤ T#0MS 配置非法
                      03【信息级】失效且无保持载体（从未收到有效值，
                      fOut 冻结 0）
  码位反证 Note     : 01/02/03 分立依据（R90）：01 在时效面（载体存在但
                      老化）、02 在配置面、03 在载体面（从未有过）可观测；
                      03 若并入 01，则「等一等会有值」与「永远不会有值」
                      不可区分，故必须分立；02 为故障级置 bError，与
                      01/03 信息级双通道可区分。
  验收   Acceptance : V1 质量好透传 → fOut=fInVal，bValid ｜ V2 失效 →
                      fOut 冻结最后值，bStale=FALSE（未超限）｜ V3 失效
                      超 tStaleMax → 码 01 + bStale ｜ V4 tStaleMax=0 →
                      码 02（电平面）｜ V5 上电即失效 → 码 03，bValid=
                      FALSE ｜ V6 恢复 → 透传 + 陈旧清零
  变更   Revision   : 2026-11-22  v1.0.0  R67 首版（编码阶段批 3 序 3）
  ==================================================================
*)
FUNCTION_BLOCK FB_DL_LastGoodValueHold
VAR_INPUT
    fInVal    : LREAL := 0.0;      // 输入测量值 [工程单位] / the input measured value
    bSigOk    : BOOL := FALSE;     // 信号质量好（NE43 诊断有效）[-] / the signal quality ok flag
    tStaleMax : TIME := T#60S;     // 陈旧时长上限 [ms]，须 > 0 / the staleness limit, must be positive
END_VAR
VAR_OUTPUT
    fOut     : LREAL := 0.0;       // 保持输出（最后有效值或透传）[工程单位] / the hold output
    bStale   : BOOL := FALSE;      // 陈旧超限指示（码 01 同源）[-] / the stale limit indicator
    bValid   : BOOL := FALSE;      // 输出可用标志（有有效载体且配置合法）[-] / the output usability flag
    bError   : BOOL := FALSE;      // 配置故障标志（电平面，恢复即清，R45 配对）/ the configuration fault flag
    uErrorId : UDINT := 16#0000_0000; // 错误码，0=正常，01/02/03 见头注 [码] / the error code [code]
END_VAR
VAR
    tonStale   : TON;              // 陈旧计时实例，段 0 无条件刷新 / the staleness timer instance refreshed unconditionally
    _fLastGood : LREAL := 0.0;     // 最后有效值保持载体 [工程单位] / the last good value hold carrier
    _bHasLast  : BOOL := FALSE;    // 保持载体是否存在（首件判据）[-] / the carrier existence flag
    _bCfgOk    : BOOL := FALSE;    // 本拍配置有效性 [-] / the per scan configuration validity
    _bSigFin   : BOOL := FALSE;    // 本拍输入有限性 [-] / the per scan input finiteness
END_VAR
VAR CONSTANT
    LGV_FIN_MAX  : LREAL := 1.7976931348623157E308; // LREAL 有限上限 / the finite LREAL limit
    LGV_ERR_NONE : UDINT := 16#0000_0000;           // 无错误 [码] / no error [code]
    LGV_ERR_STALE: UDINT := 16#0000_0001;           // 码 01：陈旧超限（信息级）/ code 01, stale limit, info level
    LGV_ERR_CFG  : UDINT := 16#0000_0002;           // 码 02：配置非法 / code 02, illegal configuration
    LGV_ERR_NOVAL: UDINT := 16#0000_0003;           // 码 03：无保持载体（信息级）/ code 03, no carrier, info level
END_VAR

(*------------------------------------------------------------------------------
 * 段 0｜定时器无条件刷新区（红线 R7）：严禁移入 IF / CASE
 *      The timer instance refreshes unconditionally, never inside a branch
 *-----------------------------------------------------------------------------*)
tonStale(IN := (NOT bSigOk) AND _bHasLast, PT := tStaleMax);  // 陈旧计时（失效且有载体才计时；恢复随 IN=FALSE 自清零，R188）/ the staleness timing, self clearing on recovery

(*------------------------------------------------------------------------------
 * 段 1｜错误码本拍预置 / segment 1, the error code per scan preset
 *-----------------------------------------------------------------------------*)
uErrorId := LGV_ERR_NONE;      // 预置无错误 / preset no error
bStale := FALSE;               // 陈旧指示预清（码 01 同源重算）/ preset the stale indicator

(*------------------------------------------------------------------------------
 * 段 2｜配置闸（电平面，当拍复判，码 02）+ 输入有限性闸
 *      The configuration gate and the input finiteness gate
 *-----------------------------------------------------------------------------*)
_bCfgOk := (tStaleMax > T#0MS);  // 配置闸（TIME 直接比较，三平台一致）/ the configuration gate
_bSigFin := (fInVal = fInVal) AND (ABS(fInVal) <= LGV_FIN_MAX);  // 输入非有限闸（NaN 自反判 + Inf 兜底）/ the input finite gate
IF NOT _bCfgOk THEN
    bError := TRUE;              // 故障标志（R45 配对）/ the fault flag
    uErrorId := LGV_ERR_CFG;     // 码 02 / code 02
    bValid := FALSE;             // 配置非法不出数 / no output on illegal configuration
    RETURN;                      // fOut 冻结保持（头注契约）/ the output frozen
ELSE
    bError := FALSE;             // 配置恢复即清（电平面契约）/ cleared when the configuration recovers
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜质量好相：透传刷新载体（含非有限拒收，码 03 语义延用）
 *      The good quality phase, pass through and refresh the carrier
 *-----------------------------------------------------------------------------*)
IF bSigOk AND _bSigFin THEN
    _fLastGood := fInVal;        // 载体刷新 / refresh the carrier
    _bHasLast := TRUE;           // 载体存在 / the carrier exists
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜失效相与出口映射：透传或保持，码 01/03 信息级
 *      The failed phase and the outlet mapping, the info codes
 *-----------------------------------------------------------------------------*)
IF bSigOk AND _bSigFin THEN
    fOut := fInVal;              // 透传 / pass through
ELSIF _bHasLast THEN
    fOut := _fLastGood;          // 保持最后有效值（锁存载体，非实时镜像混用）/ hold the last good value, the carrier not a live mirror
ELSE
    fOut := 0.0;                 // 无载体冻结 0（头注契约）/ frozen zero without a carrier
END_IF
IF (NOT bSigOk) OR (NOT _bSigFin) THEN
    IF NOT _bHasLast THEN
        uErrorId := LGV_ERR_NOVAL;  // 码 03：失效且从未有载体（信息级）/ code 03, no carrier, info level
        bValid := FALSE;            // 无值可保 / nothing to hold
    ELSE
        IF tonStale.Q THEN
            uErrorId := LGV_ERR_STALE;  // 码 01：陈旧超限（信息级，不置 bError）/ code 01, stale, info level
            bStale := TRUE;             // 陈旧指示（与码 01 同源，R191 名实双出口）/ the stale indicator
        END_IF
        bValid := TRUE;             // 有载体即可用（保持值有效语义）/ usable with a carrier
    END_IF
ELSE
    bValid := TRUE;                 // 质量好透传可用 / usable while passing through
END_IF
END_FUNCTION_BLOCK
