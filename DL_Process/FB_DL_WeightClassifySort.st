// =====================================================================
// FB_DL_WeightClassifySort.st
// 重量四档分级剔除（复用库内判档律 + 剔除口放行 + 档位计数）
// Weight 4-band classification with reject gate and band counters
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_0476 ~ 16#0005_047A (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: packaging, weight-sorting, classification, reject
// 枚举属主: E_DL_WeightClass —— 本文件为全库唯一属主, 其他件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 9)
// 分层声明: 判档律消费 DL_Base 的 FC_DL_LimitClassify（四阈值五档, 返回
//           E_DL_LimitBand）, 本件不重写分级律, 只做判档→剔除口→计数编排;
//           区间归属沿用判档件闭区间口径（等于阈值归更严档, 容差判等）
// =====================================================================
// ---------------------------------------------------------------------
// 枚举定义: E_DL_WeightClass (全库唯一属主, 其他件只引用不重声明;
//           R30 序 11 称重剔除秤件引用本枚举)
// ---------------------------------------------------------------------
TYPE E_DL_WeightClass :
(
    eLL,            // 严重欠重档 / Severely underweight band
    eL,             // 欠重档 / Underweight band
    eOK,            // 合格档 / Ok band
    eH,             // 超重档 / Overweight band
    eHH             // 严重超重档 / Severely overweight band
);
END_TYPE

FUNCTION_BLOCK FB_DL_WeightClassifySort
VAR_INPUT
    bPartInZone : BOOL := FALSE;    // 检重区有件信号（分类触发沿）/ Part in check zone, classification trigger
    fWeight_g   : REAL := 0.0;      // 称重值 0~5000 g / Measured weight [g]
    fTh_LL_g    : REAL := 150.0;    // 低低阈值（严重欠重）0~5000 g / Low-low threshold [g]
    fTh_L_g     : REAL := 250.0;    // 低阈值（欠重）0~5000 g / Low threshold [g]
    fTh_H_g     : REAL := 750.0;    // 高阈值（超重）0~5000 g / High threshold [g]
    fTh_HH_g    : REAL := 850.0;    // 高高阈值（严重超重）0~5000 g / High-high threshold [g]
    bRejectArm  : BOOL := FALSE;    // 剔除口布防 / Reject gate armed
END_VAR
VAR_OUTPUT
    eClass      : E_DL_WeightClass := E_DL_WeightClass.eOK;  // 本件判档结果 / Classification result
    bRejectOut  : BOOL := FALSE;    // 剔除口放行脉冲（单拍自清）/ Reject gate pulse, one cycle
    uOkCount    : UDINT := 0;       // 合格计数 / Ok count
    uNgCount    : UDINT := 0;       // 不合格计数（含欠/超重/传感器故障/组态故障安全分流）/ Ng count
    eErr        : UDINT := 16#0005_0476;  // 错误码 / Error code
END_VAR
VAR
    rtrPart     : R_TRIG;           // 有件沿检测, 每拍无条件刷新 / Part edge, refreshed every cycle
    bCfgErr     : BOOL := FALSE;    // 阈值组态非法标记 / Threshold configuration error flag
    eBand       : E_DL_LimitBand := E_DL_LimitBand.eInvalid;  // 判档件返回档 / Band returned by classifier
    bBandInv    : BOOL := FALSE;    // 判档返回非法档标记 / Classifier invalid-band flag
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_0476 信息 分级正常（判档完成, OK 或常规 NG 计数）
//   16#0005_0477 故障 阈值组态非法（阈值非有限或越出 0~5000 g 域, 或判档件
//                返回非法档: 阈值序倒置）; 解除式 = 恢复合法单调阈值组态
//   16#0005_0478 故障 重量非有限（传感器故障, NG 侧安全分流, 与超重 NG 区分）,
//                解除式 = 称重值恢复有限且量程内
//   16#0005_0479 信息 超量程（负重为负或超 5000 g, 按 NG 安全分流计数）
//   16#0005_047A 信息 剔除脉冲输出拍（单拍信息, 随剔除口放行同拍发出）
// ---------------------------------------------------------------------

// ---- 有件沿实例无条件刷新 / Unconditional part edge refresh ----
rtrPart(CLK := bPartInZone);

// ---- 阈值组态闸: 四阈值逐一判非有限与量程域（单调性交由判档件校验）
//      Threshold config gate: finite and domain check per threshold ----
bCfgErr := FALSE;                   // 组态标记复位 / Reset config flag
IF (fTh_LL_g <> fTh_LL_g) OR (fTh_LL_g < 0.0) OR (fTh_LL_g > 5000.0) THEN
    bCfgErr := TRUE;                // 低低阈值非法 / Low-low threshold illegal
END_IF
IF (fTh_L_g <> fTh_L_g) OR (fTh_L_g < 0.0) OR (fTh_L_g > 5000.0) THEN
    bCfgErr := TRUE;                // 低阈值非法 / Low threshold illegal
END_IF
IF (fTh_H_g <> fTh_H_g) OR (fTh_H_g < 0.0) OR (fTh_H_g > 5000.0) THEN
    bCfgErr := TRUE;                // 高阈值非法 / High threshold illegal
END_IF
IF (fTh_HH_g <> fTh_HH_g) OR (fTh_HH_g < 0.0) OR (fTh_HH_g > 5000.0) THEN
    bCfgErr := TRUE;                // 高高阈值非法 / High-high threshold illegal
END_IF

// ---- 剔除口缺省收口（单拍脉冲当拍自清）/ Reject pulse default off, self-clearing ----
bRejectOut := FALSE;
bBandInv := FALSE;                  // 非法档标记复位 / Reset invalid-band flag

// ---- 有件沿触发判档编排 / Part edge triggers classification orchestration ----
IF rtrPart.Q THEN
    IF (fWeight_g <> fWeight_g) OR (ABS(fWeight_g) >= 1.0E12) THEN
        // 传感器故障: NG 侧安全分流, 独立故障码 / Sensor fault: NG safe routing, distinct code
        eClass := E_DL_WeightClass.eLL;     // 分流到欠重侧 / Route to underweight side
        bRejectOut := bRejectArm;           // 布防时剔除 / Reject when armed
        uNgCount := uNgCount + 1;           // NG 计数 / Count NG
        eErr := 16#0005_0478;               // 传感器故障码 / Sensor fault code
    ELSIF (fWeight_g < 0.0) OR (fWeight_g > 5000.0) THEN
        // 超量程（含负重为负）: NG 安全分流 / Out of range incl. negative: NG safe routing
        eClass := E_DL_WeightClass.eHH;     // 分流到超重侧 / Route to overweight side
        bRejectOut := bRejectArm;
        uNgCount := uNgCount + 1;
        eErr := 16#0005_0479;               // 超量程信息码 / Over-range info code
    ELSIF bCfgErr THEN
        // 组态故障: 安全侧拒绝分档, 按 NG 分流 / Config fault: safe side, route as NG
        eClass := E_DL_WeightClass.eLL;
        bRejectOut := bRejectArm;
        uNgCount := uNgCount + 1;
        eErr := 16#0005_0477;               // 组态故障码 / Config fault code
    ELSE
        // 判档律消费: 调 DL_Base 判档函数, 闭区间口径 / Consume classifier, closed-interval convention
        eBand := FC_DL_LimitClassify(REAL_TO_LREAL(fWeight_g),
                                     REAL_TO_LREAL(fTh_LL_g),
                                     REAL_TO_LREAL(fTh_L_g),
                                     REAL_TO_LREAL(fTh_H_g),
                                     REAL_TO_LREAL(fTh_HH_g));
        CASE eBand OF
            E_DL_LimitBand.eLowTripped:     // 低低档 → 严重欠重 / Low-low to severely under
                eClass := E_DL_WeightClass.eLL;
            E_DL_LimitBand.eLowWarn:        // 低档 → 欠重 / Low to under
                eClass := E_DL_WeightClass.eL;
            E_DL_LimitBand.eNormal:         // 正常档 → 合格 / Normal to ok
                eClass := E_DL_WeightClass.eOK;
            E_DL_LimitBand.eUpWarn:         // 高档 → 超重 / High to over
                eClass := E_DL_WeightClass.eH;
            E_DL_LimitBand.eUpTripped:      // 高高档 → 严重超重 / High-high to severely over
                eClass := E_DL_WeightClass.eHH;
            ELSE                            // 非法档兜底: NG 安全侧 / Invalid band fallback: NG safe side
                eClass := E_DL_WeightClass.eLL;
                bBandInv := TRUE;           // 置非法档标记 / Set invalid-band flag
        END_CASE
        // 档位计数与剔除口放行 / Band counting and reject gate
        IF eClass = E_DL_WeightClass.eOK THEN
            uOkCount := uOkCount + 1;       // 合格计数 / Count ok
        ELSE
            uNgCount := uNgCount + 1;       // 不合格计数 / Count ng
        END_IF
        bRejectOut := bRejectArm AND (eClass <> E_DL_WeightClass.eOK);  // 非 OK 布防剔除 / Reject non-ok when armed
        IF bBandInv THEN
            eErr := 16#0005_0477;           // 判档非法兜底码 / Invalid band code
        ELSE
            eErr := 16#0005_0476;           // 分级正常 / Classification normal
        END_IF
    END_IF
END_IF

END_FUNCTION_BLOCK
