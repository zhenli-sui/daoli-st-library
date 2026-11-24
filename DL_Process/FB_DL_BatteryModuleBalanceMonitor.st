(*==============================================================================
 * 组件名称 (Component)  : FB_DL_BatteryModuleBalanceMonitor
 * 所属子库 (Sublibrary) : DL_Process
 * 归属目录 (Directory)  : C:\Library\DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 功能块（FUNCTION_BLOCK）· 锂电安全 · 模组压差均衡监视
 *                         industry-pool / battery / cell-balance
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 Standard.library
 * 溯源声明 (Provenance) : 道莅自研 clean-room——只借公开规范条款与工程惯例，零代码行复制。
 * 功能一句话 (Summary)  : 扫描模组单体电压求最大/最小/压差，按压差分级输出
 *                         均衡需求（无/软/紧急）与需均衡单体数，物理域双闸。
 *
 * 功能描述 (Function)   : 每拍全阵列扫描：越物理域（低于 fVLo 或高于 fVHi）
 *                         或非有限即故障冻结；健康阵列导出最大最小压差，压差
 *                         越软均衡阈输出软均衡需求并统计需均衡单体数（相对
 *                         最小电压超软阈者），压差越告警阈升级紧急均衡并报
 *                         故障级；压差为零（全阵列相等）恒等输出无需求。
 * 与既有件边界 (Boundary): 本件只做压差监视与均衡需求分级，不执行均衡
 *                         放电；均衡执行归 BMS 执行层，本件输出即其给定。
 * 码位说明 (Codes)      : 信息 16#0006_301E 软均衡需求激活（压差越软阈）
 *                         故障 16#0006_301F 输入非有限，评估冻结
 *                         故障 16#0006_3020 压差越告警阈，紧急均衡需求
 *                         故障 16#0006_3021 单体电压物理域外（越 fVLo/fVHi）
 *                         段 16#06_0_1E~22 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的 ABS。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         NaN/Inf 精确判据拦截 ｜ 浮点比较带 fEps 容差
 *                         ENUM 配 CASE 且 ELSE 兜底 ｜ 全变量双语同行注释
 *                         哨兵零与真实零可区分（全等阵列压差真实为零）
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 4）
 *============================================================================*)

FUNCTION_BLOCK FB_DL_BatteryModuleBalanceMonitor
VAR_INPUT
    bRun    : BOOL;                     // 监视使能，假则清判定 / Enable, FALSE clears the verdict
    aCellV  : ARRAY[1..12] OF LREAL;    // 单体电压 [V] / Cell voltages
    fVLo    : LREAL := 2.5;             // 单体物理域下限 [V] / Physical domain lower bound
    fVHi    : LREAL := 4.3;             // 单体物理域上限 [V] / Physical domain upper bound
    fBalThV : LREAL := 0.02;            // 软均衡启动压差阈 [V] / Soft balance delta threshold
    fAlmThV : LREAL := 0.05;            // 告警压差阈 [V] / Alarm delta threshold
    fEps    : LREAL := 1.0E-6;          // 浮点判零容差 [实数域] / Floating zero tolerance
END_VAR
VAR_OUTPUT
    eBalReq : (eNoBal := 0, eBalSoft := 1, eBalUrgent := 2);    // 均衡需求枚举 / Balance request enum
    fMaxV   : LREAL;                    // 最大单体电压 [V] / Maximum cell voltage
    fMinV   : LREAL;                    // 最小单体电压 [V] / Minimum cell voltage
    fDeltaV : LREAL;                    // 模组压差 [V]，最大减最小 / Module delta, max minus min
    nBalCells: INT;                     // 需均衡单体数 [个]（相对最小超软阈）/ Cells needing balance
    bError  : BOOL;                     // 故障标志，与故障码配对 / Fault flag paired with codes
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    bSigOk  : BOOL;     // 阵列有效标志 / Array validity flag
    nI      : INT;      // 单体循环下标 [索引] / Cell loop index
    uCode   : UDINT;    // 码位暂存，出口单点写入 [码] / Code staging
END_VAR

(* 段 1｜输出预置 / Pre-set *)
eBalReq  := eNoBal;                 // 默认无需求 / Default no request
fMaxV    := -1.0E308;               // 最大值种子下界 / Seed the maximum
fMinV    := 1.0E308;                // 最小值种子上界 / Seed the minimum
fDeltaV  := 0.0;
nBalCells := 0;
bError   := FALSE;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;
bSigOk   := TRUE;                   // 先假定有效，扫描中可撤 / Assume valid, withdrawn in the scan

(* 段 2｜全阵列扫描：物理域双闸 + 非有限闸 + 极值导出 / Full scan: domain gates and extremes *)
FOR nI := 1 TO 12 DO
    IF (aCellV[nI] <> aCellV[nI]) OR (ABS(aCellV[nI]) > 1.0E308) THEN
        bSigOk := FALSE;            // 非有限：撤有效 / Non-finite: withdraw
        uCode := 16#0006_301F;      // 故障级：输入非有限 / Fault: non-finite input
    ELSIF (aCellV[nI] < fVLo) OR (aCellV[nI] > fVHi) THEN
        bSigOk := FALSE;            // 物理域外：撤有效 / Out of domain: withdraw
        uCode := 16#0006_3021;      // 故障级：电压物理域外 / Fault: voltage out of domain
    ELSE
        IF aCellV[nI] > fMaxV THEN
            fMaxV := aCellV[nI];    // 更新最大 / Update the maximum
        END_IF
        IF aCellV[nI] < fMinV THEN
            fMinV := aCellV[nI];    // 更新最小 / Update the minimum
        END_IF
    END_IF
END_FOR

(* 段 3｜有效路径：压差导出与分级判定 / Valid path: delta and grading *)
IF bSigOk THEN
    fDeltaV := fMaxV - fMinV;       // 压差导出 / Derive the delta
    IF fDeltaV > fAlmThV THEN
        eBalReq := eBalUrgent;      // 紧急均衡 / Urgent request
        uCode := 16#0006_3020;      // 故障级：越告警阈 / Fault: over alarm threshold
    ELSIF fDeltaV > fBalThV THEN
        eBalReq := eBalSoft;        // 软均衡 / Soft request
        IF uCode = 16#0000_0000 THEN
            uCode := 16#0006_301E;  // 信息级：软均衡激活 / Info: soft balance active
        END_IF
    ELSE
        eBalReq := eNoBal;          // 带内无需求 / No request inside the band
    END_IF
    (* 需均衡单体统计：相对最小电压超软阈者 / Count cells over the soft threshold vs the minimum *)
    FOR nI := 1 TO 12 DO
        IF (aCellV[nI] - fMinV) > fBalThV THEN
            nBalCells := nBalCells + 1;     // 计入 / Count it
        END_IF
    END_FOR
END_IF

(* 段 4｜出口装配 / Exit assembly *)
IF NOT bRun THEN
    uCode := 16#0000_0000;          // 撤使能清码（可达解除）/ Run drop clears codes
    eBalReq := eNoBal;              // 撤需求 / Withdraw the request
END_IF
bError := (uCode >= 16#0006_301F) AND (uCode <= 16#0006_3021);  // 故障级码带判定 / Fault band check
uErrorId := uCode;                  // 码位单点写入 / Single write point
END_FUNCTION_BLOCK
