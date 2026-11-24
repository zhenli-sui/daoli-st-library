(*==============================================================================
 * 名称 : FC_DL_HystWindow3 —— 三带迟滞带位判定（低/中/高，回差记忆由调用方持有）
 * 分类 / 前缀 / 版本 : DL_Algo / FC_DL_ / 1.0.0
 * 溯源 : 开源语义参考（OSCAT/AixOCAT 族，MIT）或 clean-room IEC 实现，未复制源码
 * 平台 : 纯 IEC 61131-3
 * 功能说明 : 返回三带带位：0=低带、1=中带、2=高带。上行走「上行门限」进带
 *            （fIn>=fLowOn 进中带、fIn>=fHighOn 进高带），下行走「下行门限」
 *            退带（fIn<fLowOff 退低带、fIn<fHighOff 退中带），回差由门限对
 *            (fLowOn/fLowOff) 与 (fHighOn/fHighOff) 构成，历史带位经
 *            nPrevState 由调用方持有回传。
 *            边界处理：fLowOff<=fLowOn<fHighOff<=fHighOn 不满足判参数非法
 *            （eErr、返回 0、bValid=FALSE）；nPrevState 非 0/1/2 时走 ELSE
 *            兜底按电平重判；输入非有限（NaN/±Inf）置 eErr。
 * 错误码 : 16#0001_1C01 = 门限次序非法（不满足 fLowOff<=fLowOn<fHighOff<=fHighOn），或输入非有限
 *          eErr=0 且 bValid=TRUE 表示带位可用
 * 状态机 : R6 标注 N/A（纯函数无顺序状态，带位记忆由调用方持有，本件以 ELSE 兜底替代 CASE 收口）
 * 红线 : R1/R2/R3 ✓ 零全局/零IO/纯IEC ｜ R4 ✓ 非有限拦截/门限校验 ｜ R10 ✓ 标准转换 ｜ R11 ✓ 分号收尾 ｜ R15 ✓ 无保留字撞名
 * 修订记录 : 2026-11-23 v1.0.0 首次入库（R76）
 *============================================================================*)
FUNCTION FC_DL_HystWindow3 : INT
VAR_INPUT
    fIn       : LREAL;   // 被判定输入量 [工程单位] / input value under test
    fLowOn    : LREAL;   // 低带→中带上行门限 [工程单位] / rising threshold low-to-mid
    fLowOff   : LREAL;   // 中带→低带下行门限 [工程单位] / falling threshold mid-to-low
    fHighOn   : LREAL;   // 中带→高带上行门限 [工程单位] / rising threshold mid-to-high
    fHighOff  : LREAL;   // 高带→中带下行门限 [工程单位] / falling threshold high-to-mid
    nPrevState: INT;     // 上一拍带位 0/1/2（调用方持有）/ previous band, caller-held
END_VAR
VAR_OUTPUT
    eErr   : UDINT;    // 故障码，0=正常，1C01=参数非法或非有限 / error code
    bError : BOOL;     // TRUE=本件发生故障 / TRUE when fault occurred
    bValid : BOOL;     // TRUE=带位可用 / TRUE when band is usable
END_VAR
VAR
    _nRet : INT;       // 带位计算中间值 / band intermediate
END_VAR

FC_DL_HystWindow3 := 0;                      // 带位预设 0（低带）/ preset band to low
eErr   := 16#0000_0000;                      // 故障码清零 / clear error code
bError := FALSE;                             // 故障标志清零 / clear error flag
bValid := TRUE;                              // 预设输出可用 / preset valid flag

IF (fIn <> fIn) OR ((fIn - fIn) <> (fIn - fIn))            // fIn 非有限 / NaN or infinite
   OR (fLowOn <> fLowOn) OR ((fLowOn - fLowOn) <> (fLowOn - fLowOn))   // fLowOn 非有限 / NaN or infinite
   OR (fLowOff <> fLowOff) OR ((fLowOff - fLowOff) <> (fLowOff - fLowOff)) // fLowOff 非有限 / NaN or infinite
   OR (fHighOn <> fHighOn) OR ((fHighOn - fHighOn) <> (fHighOn - fHighOn)) // fHighOn 非有限 / NaN or infinite
   OR (fHighOff <> fHighOff) OR ((fHighOff - fHighOff) <> (fHighOff - fHighOff)) THEN  // fHighOff 非有限 / NaN or infinite
    eErr   := 16#0001_1C01;                  // 置非有限故障码 / set non-finite code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 带位不可用 / band not usable
    RETURN;                                  // 返回 0 / return zero
END_IF

IF NOT ((fLowOff <= fLowOn) AND (fLowOn < fHighOff) AND (fHighOff <= fHighOn)) THEN    // 门限次序校验 / threshold order check
    eErr   := 16#0001_1C01;                  // 置参数非法码 / set invalid-parameter code
    bError := TRUE;                          // 置故障标志 / set error flag
    bValid := FALSE;                         // 带位不可用 / band not usable
    RETURN;                                  // 返回 0 / return zero
END_IF

_nRet := nPrevState;                         // 取上一拍带位 / take previous band

IF _nRet = 0 THEN                            // 低带滞回分支 / low band hysteresis branch
    IF fIn >= fLowOn THEN                    // 上穿中带门限 / rising past mid entry
        _nRet := 1;                          // 进中带 / enter mid band
    END_IF
ELSIF _nRet = 1 THEN                         // 中带滞回分支 / mid band hysteresis branch
    IF fIn >= fHighOn THEN                   // 上穿高带门限 / rising past high entry
        _nRet := 2;                          // 进高带 / enter high band
    ELSIF fIn < fLowOff THEN                 // 下穿低带退出门限 / falling past low exit
        _nRet := 0;                          // 退低带 / fall to low band
    END_IF
ELSIF _nRet = 2 THEN                         // 高带滞回分支 / high band hysteresis branch
    IF fIn < fHighOff THEN                   // 下穿中带退出门限 / falling past mid exit
        _nRet := 1;                          // 退中带 / fall to mid band
    END_IF
ELSE                                         // ELSE 兜底：非法带位按电平重判 / else: re-judge by level
    IF fIn >= fHighOn THEN                   // 电平在高带门限上 / level above high entry
        _nRet := 2;                          // 判高带 / judge high band
    ELSIF fIn >= fLowOn THEN                 // 电平在中带门限上 / level above low entry
        _nRet := 1;                          // 判中带 / judge mid band
    ELSE                                     // 电平在低带 / level in low band
        _nRet := 0;                          // 判低带 / judge low band
    END_IF
END_IF

FC_DL_HystWindow3 := _nRet;                  // 回写带位 / write back band

END_FUNCTION
