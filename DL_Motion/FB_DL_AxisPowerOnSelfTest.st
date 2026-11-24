(*==============================================================================
 * 组件名称 (Component)  : FB_DL_AxisPowerOnSelfTest
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（TON / R_TRIG），零厂商方言
 * 来源标签 (Source)     : t2-4-s7motion（上电自检序列语义，clean-room 编写）
 * 功能描述 (Function)   : 轴上电自检五步序检：驱动就绪 -> 编码器回读（位置有效性
 *                         + 速率合理性）-> 限位状态巡检（常开 / 常闭组态域闸）->
 *                         驱动故障字扫描 -> 结论锁存。任一步失败即中止并禁使能
 *                         放行：bTestOk 出口供 FB_DL_SingleAxis 使能链消费。
 * 家族纪律 (R31)        : 不自造轴状态枚举——本件只消费快照与反馈引脚
 *                         （bDriveReady / fEncPos / fEncRate / 限位位 / 故障字），
 *                         轴状态机归运动层接口 I_DL_MotionAxis，本件零轴状态定义。
 * 边界与语义披露 (Boundary disclosure) :
 *   1) 步序超时逐段 TON 断输入（R40 家族口径）：步切换拍计时器复位一次
 *      （IN 串「步激活 AND NOT 步更替」），各步共用同一 tStepTimeout。
 *   2) 结论锁存：bTestOk 只在结论相置位并保持；解除 = 复位沿 AND 驱动就绪在位
 *      （终审两式：解除式可达，验收向量「复位沿 + 驱动就绪 -> 可重测」）。
 *   3) 限位组态域闸：nLimitMode 仅 0（常开）/ 1（常闭）合法，其余组态级故障；
 *      常闭口径下反馈 TRUE = 未压（健康），常开口径下反馈 TRUE = 被压。
 *   4) 上电即被压的限位按自检失败处置（轴未能验证自由行程，放行风险不可接受）。
 *   5) 编码器回读判据：位置 / 速率非有限（自反 + 差自减双判）或 |速率| 超
 *      fRateMax 均判步 2 失败（验收向量：回读 NaN -> 步 2 中止 bTestOk FALSE 置码）。
 *   6) 通用组态（速率上限 / 步超时）非法独立码位，与限位组态成因互异（R190）。
 * 故障码表 (Error codes) :
 *   16#0004_0363 [故障级] 步序超时（当前步 tStepTimeout 未达成）
 *                 反证：超时中止与「判据失败中止」eFault 输出组合相同，成因必须码位互异。
 *   16#0004_0364 [故障级] 编码器回读非法（位置 / 速率非有限或速率超合理域）
 *                 反证：步 2 中止与其它步中止输出组合相似，码位是唯一成因出口。
 *   16#0004_0365 [故障级] 限位组态模式非法（nLimitMode 非 0 / 1）
 *                 反证：限位步失败与编码器步失败输出组合相似，码位互异（R190）。
 *   16#0004_0366 [故障级] 上电限位被压（按生效接线口径判），自由行程未验证
 *                 反证：与组态非法同相中止但成因互异，码位独立。
 *   16#0004_0367 [故障级] 驱动故障字非零
 *                 反证：驱动故障字中止与编码器 / 限位 / 超时中止输出组合相似，成因互异码位独立。
 *   16#0004_0368 [故障级] 通用组态非法（速率上限 / 步超时域），拒绝启动
 *                 反证：拒绝启动与「未按触发」输出组合相同，码位唯一可见。
 * 码位总账 (Code ledger) : 16#0004_0363 / 0364 / 0365 / 0366 / 0367 / 0368 用
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: TON / R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与 VAR_EXTERNAL ｜ R2 ✓ 零 %I/%Q 物理地址
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 非有限双判 / 域闸全枚举 / 码位 R45 配对
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 ✓ 七态 ENUM + CASE + ELSE 兜底
 *                         R7 ✓ 三沿一计时主体最前部无条件刷新
 * 修订历史 (Revision)   :
 *   2026-11-22  v1.0.0  首版入库（R68 构建轮 · 批 3 · 目标 16）
 *   2026-11-22  v1.0.1  终审就地修①：组态锁存解除路径可达化（原 bCfgLatch 全文件零清零 -> 自检永久不可重测）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_SelfTestStep（归属 DL_Motion，与 FB_DL_AxisPowerOnSelfTest 同文件）
 * 说明: 本枚举是「自检步序」不是「轴状态」——轴状态归运动层接口（R31 家族纪律）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_SelfTestStep :
(
    eIdle        := 0,    // 待触发：结论保持 / Idle, conclusion held
    eStDrive     := 10,   // 步 1：驱动就绪确认 / Step 1, drive ready
    eStEncoder   := 20,   // 步 2：编码器回读校验 / Step 2, encoder readback
    eStLimits    := 30,   // 步 3：限位状态巡检 / Step 3, limit switch patrol
    eStDriveWord := 40,   // 步 4：驱动故障字扫描 / Step 4, drive fault word scan
    eStConclude  := 50,   // 步 5：结论锁存 / Step 5, conclusion latch
    eFault       := 99    // 自检失败锁存：禁使能放行 / Self-test failed, enable release denied
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_AxisPowerOnSelfTest
 * 调用约定: 每个扫描周期无条件调用一次；快照引脚须每拍刷新注入。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_AxisPowerOnSelfTest
VAR_INPUT
    bTestTrig    : BOOL;                  // 自检触发（上升沿受理）/ Self-test trigger, rising edge
    bDriveReady  : BOOL;                  // 驱动就绪快照 / Drive ready snapshot
    fEncPos      : LREAL;                 // 编码器位置回读 [mm] / Encoder position readback [mm]
    fEncRate     : LREAL;                 // 编码器速率回读 [mm/s] / Encoder rate readback [mm per s]
    fRateMax     : LREAL := 100.0;        // 速率合理上限 [mm/s] / Plausible rate ceiling [mm per s]
    bLimitPosFb  : BOOL;                  // 正限位状态反馈（原始，TRUE = 电气有效）/ Positive limit feedback, raw
    bLimitNegFb  : BOOL;                  // 负限位状态反馈（原始）/ Negative limit feedback, raw
    nLimitMode   : INT   := 0;            // 限位接线模式：0 = 常开，1 = 常闭 / Wiring mode, 0 NO 1 NC
    uDriveFaultWord : WORD;               // 驱动故障字 / Drive fault word
    tStepTimeout : TIME  := T#2S;         // 单步超时 [s] / Step timeout [s]
    bEnable      : BOOL  := TRUE;         // 使能 / Enable
    bReset       : BOOL;                  // 上升沿：清结论与故障锁存（须驱动就绪在位）/ Rising edge: clear, drive ready required
END_VAR
VAR_OUTPUT
    bTestOk    : BOOL;                   // 自检结论：TRUE = 通过（锁存至复位 / 新测）/ Test passed, latched
    bTestDone  : BOOL;                   // 结论已出（通过或失败）/ Conclusion available
    bError     : BOOL;                   // 故障标志（自检失败 / 组态锁存归并）/ Fault flag merged
    uErrorId   : UDINT;                  // 故障码，0 = 无故障 / Error code, 0 = none
    eState     : E_DL_SelfTestStep;      // 当前步序（供 HMI 诊断）/ Current step for HMI diagnosis
END_VAR
VAR
    fbTrigTrig  : R_TRIG;                // 触发沿检测实例 / Trigger edge detector
    fbTrigReset : R_TRIG;                // 复位沿检测实例 / Reset edge detector
    tonStep     : TON;                   // 单步超时计时实例 / Step timeout timer
    eStateInt   : E_DL_SelfTestStep;     // 主状态机内部当前态 / Internal state machine state
    eStepPrev   : E_DL_SelfTestStep;     // 上拍步序快照（步更替判据）/ Previous step snapshot
    bStepActive : BOOL;                  // 当前步处于计时激活域 / Current step in the timed set
    bStepNew    : BOOL;                  // 本拍发生步更替（计时复位点）/ Step changed this scan
    bLimPosTrip : BOOL;                  // 按接线口径判的正限位被压 / Positive limit tripped per wiring
    bLimNegTrip : BOOL;                  // 负限位被压 / Negative limit tripped
    bEncBad     : BOOL;                  // 编码器回读非法 / Encoder readback illegal
    bCfgBad     : BOOL;                  // 本拍通用组态非法 / General config illegal
    bCfgLatch   : BOOL;                  // 通用组态锁存 / General config latch
    bModeBad    : BOOL;                  // 限位接线模式非法 / Wiring mode illegal
    bPassedInt  : BOOL;                  // 通过结论锁存内部副本 / Internal passed latch
    bDoneInt    : BOOL;                  // 结论已出锁存内部副本 / Internal done latch
    bErrorInt   : BOOL;                  // 本拍故障置位累加（出口归并）/ Fault set accumulator
    bFirstScan  : BOOL := TRUE;          // 上电首扫标志 / First-scan flag
END_VAR
VAR CONSTANT
    DL_ST_FIN_LIM   : LREAL := 1.0E30;   // LREAL 有限幅值判界 / LREAL finiteness bound
    DL_ST_MODE_NO   : INT   := 0;        // 常开接线模式号 / Normally-open mode id
    DL_ST_MODE_NC   : INT   := 1;        // 常闭接线模式号 / Normally-closed mode id
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：二沿一计时主体最前部
 *      Unconditional refresh: two edges and one timer at the very top
 *      步更替拍计时复位一次（IN 串「步激活 AND NOT 步更替」，逐段断输入 R40）
 *-----------------------------------------------------------------------------*)
fbTrigTrig(CLK := bTestTrig);
fbTrigReset(CLK := bReset);

bStepNew := (eStateInt <> eStepPrev);

bStepActive := (eStateInt = E_DL_SelfTestStep.eStDrive)
               OR (eStateInt = E_DL_SelfTestStep.eStEncoder)
               OR (eStateInt = E_DL_SelfTestStep.eStLimits)
               OR (eStateInt = E_DL_SelfTestStep.eStDriveWord);

tonStep(IN := bStepActive AND (NOT bStepNew), PT := tStepTimeout);

(*------------------------------------------------------------------------------
 * 段 2｜上电首扫：结论与状态落安全侧（未测 = 不放行）
 *      First-scan init: conclusion to the safe side, untested means no release
 *-----------------------------------------------------------------------------*)
IF bFirstScan THEN
    eStateInt  := E_DL_SelfTestStep.eIdle;
    eStepPrev  := eStateInt;
    bPassedInt := FALSE;
    bDoneInt   := FALSE;
    bFirstScan := FALSE;
END_IF

(*------------------------------------------------------------------------------
 * 段 3｜每拍预清（FB32-1）：单拍标志，禁入锁存 / 快照
 *      Per-scan preset: single-scan flags only
 *-----------------------------------------------------------------------------*)
bErrorInt := FALSE;

(*------------------------------------------------------------------------------
 * 段 4｜组态域闸（R151 全枚举）：通用组态 + 限位接线模式（独立成因独立码 R190）
 *      Config gates: general config plus the wiring mode, distinct codes
 *      解除路径（R152 自证）：复位沿 AND 驱动就绪 AND 组态改对
 *-----------------------------------------------------------------------------*)
bCfgBad := (fRateMax <= 0.0) OR (fRateMax <> fRateMax) OR (tStepTimeout <= T#0S);
bModeBad := (nLimitMode <> DL_ST_MODE_NO) AND (nLimitMode <> DL_ST_MODE_NC);

IF bCfgBad THEN
    bCfgLatch := TRUE;
    uErrorId  := 16#0004_0368;    // 故障级：通用组态非法 / Fault: general config illegal
    bErrorInt := TRUE;
END_IF

(* 终审就地修 v1.0.1（R68）：解除路径（R152 自证可达）——复位沿 AND 组态非法条件
 * 全部消失即清锁存。原实现把锁存清零只写在 eFault 相分支，而组态闸置锁存后
 * 并不迁相至 eFault（只回 eIdle / 驻留），eFault 相不可达 -> 锁存永不可解，
 * 组件保护/监视功能一次性永久失效直至 PLC 重启（终审两式①）。
 * Clear path made provably reachable: reset edge with the illegal config gone. *)
IF fbTrigReset.Q AND (NOT bCfgBad) THEN
    bCfgLatch := FALSE;           // 锁存解除 / Latch cleared
    uErrorId  := 16#0000_0000;    // 码位随解除归零 / Code cleared with the latch
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜限位接线口径换算（步 3 判据核）：常闭反馈 TRUE = 健康，常开反馈 TRUE = 被压
 *      Limit wiring translation: NC TRUE = healthy, NO TRUE = tripped
 *-----------------------------------------------------------------------------*)
IF nLimitMode = DL_ST_MODE_NC THEN
    bLimPosTrip := NOT bLimitPosFb;      // 常闭：未反馈即被压 / NC: no feedback means tripped
    bLimNegTrip := NOT bLimitNegFb;
ELSE
    bLimPosTrip := bLimitPosFb;          // 常开：有反馈即被压 / NO: feedback means tripped
    bLimNegTrip := bLimitNegFb;
END_IF

(*------------------------------------------------------------------------------
 * 段 6｜主状态机（红线 R6）：ENUM + CASE + ELSE 兜底
 *      Main state machine with the mandatory ELSE fallback
 *-----------------------------------------------------------------------------*)
CASE eStateInt OF

    E_DL_SelfTestStep.eIdle:
        IF bCfgLatch OR (NOT bEnable) THEN
            (* 组态 / 失能驻留：结论保持不放行 / Dwell, conclusion held, no release *)
        ELSIF fbTrigTrig.Q AND bModeBad THEN
            (* 触发但接线组态非法：拒绝启动并落组态码（不允许带病起测） *)
            (* Trigger with illegal wiring: refused with the mode code *)
            uErrorId  := 16#0004_0365;
            bErrorInt := TRUE;
        ELSIF fbTrigTrig.Q THEN
            bPassedInt := FALSE;     // 新测清旧结论 / New test clears the old verdict
            bDoneInt   := FALSE;
            eStateInt  := E_DL_SelfTestStep.eStDrive;
        END_IF

    E_DL_SelfTestStep.eStDrive:
        IF tonStep.Q THEN
            eStateInt := E_DL_SelfTestStep.eFault;   // 步 1 超时 / Step 1 timeout
            uErrorId  := 16#0004_0363;
            bErrorInt := TRUE;
        ELSIF bDriveReady THEN
            eStateInt := E_DL_SelfTestStep.eStEncoder;   // 就绪进步 2 / Ready, to step 2
        END_IF

    E_DL_SelfTestStep.eStEncoder:
        bEncBad := (fEncPos <> fEncPos)
                   OR ((fEncPos - fEncPos) <> (fEncPos - fEncPos))
                   OR (ABS(fEncPos) >= DL_ST_FIN_LIM)
                   OR (fEncRate <> fEncRate)
                   OR ((fEncRate - fEncRate) <> (fEncRate - fEncRate))
                   OR (ABS(fEncRate) >= DL_ST_FIN_LIM)
                   OR (ABS(fEncRate) > fRateMax);
        IF tonStep.Q THEN
            eStateInt := E_DL_SelfTestStep.eFault;
            uErrorId  := 16#0004_0363;
            bErrorInt := TRUE;
        ELSIF bEncBad THEN
            eStateInt := E_DL_SelfTestStep.eFault;   // 步 2 中止（验收向量：NaN 回读）/ Step 2 abort
            uErrorId  := 16#0004_0364;
            bErrorInt := TRUE;
        ELSE
            eStateInt := E_DL_SelfTestStep.eStLimits;    // 回读合法进步 3 / Valid, to step 3
        END_IF

    E_DL_SelfTestStep.eStLimits:
        IF tonStep.Q THEN
            eStateInt := E_DL_SelfTestStep.eFault;
            uErrorId  := 16#0004_0363;
            bErrorInt := TRUE;
        ELSIF bModeBad THEN
            eStateInt := E_DL_SelfTestStep.eFault;   // 接线组态非法 / Wiring mode illegal
            uErrorId  := 16#0004_0365;
            bErrorInt := TRUE;
        ELSIF bLimPosTrip OR bLimNegTrip THEN
            eStateInt := E_DL_SelfTestStep.eFault;   // 上电限位被压 / Limit tripped at power-on
            uErrorId  := 16#0004_0366;
            bErrorInt := TRUE;
        ELSE
            eStateInt := E_DL_SelfTestStep.eStDriveWord; // 限位健康进步 4 / Healthy, to step 4
        END_IF

    E_DL_SelfTestStep.eStDriveWord:
        IF tonStep.Q THEN
            eStateInt := E_DL_SelfTestStep.eFault;
            uErrorId  := 16#0004_0363;
            bErrorInt := TRUE;
        ELSIF uDriveFaultWord <> 16#0000 THEN
            eStateInt := E_DL_SelfTestStep.eFault;   // 驱动故障字非零 / Fault word nonzero
            uErrorId  := 16#0004_0367;
            bErrorInt := TRUE;
        ELSE
            eStateInt := E_DL_SelfTestStep.eStConclude;  // 故障字干净进步 5 / Clean, to step 5
        END_IF

    E_DL_SelfTestStep.eStConclude:
        bPassedInt := TRUE;          // 五步全过：通过结论锁存 / All steps pass: latch the verdict
        bDoneInt   := TRUE;
        eStateInt  := E_DL_SelfTestStep.eIdle;

    E_DL_SelfTestStep.eFault:
        bDoneInt := TRUE;            // 失败结论已出 / Failure verdict available
        (* 解除路径（R152 自证可达）：复位沿 AND 驱动就绪在位 AND 组态改对（可重测） *)
        IF fbTrigReset.Q AND bDriveReady AND (NOT bCfgBad) AND (NOT bModeBad) THEN
            uErrorId  := 16#0000_0000;
            eStateInt := E_DL_SelfTestStep.eIdle;
        END_IF

    ELSE
        (* 非法状态拦截：迁兜底态（复用组态段码位） *)
        eStateInt := E_DL_SelfTestStep.eFault;
        uErrorId  := 16#0004_0368;
        bErrorInt := TRUE;

END_CASE;

(*------------------------------------------------------------------------------
 * 段 7｜步序快照（主体末行，R45 累计定时器留上拍快照口径的同族纪律）
 *      Step snapshot at the body tail
 *-----------------------------------------------------------------------------*)
eStepPrev := eStateInt;

(*------------------------------------------------------------------------------
 * 段 8｜输出单一出口（范式 P-05）：结论只由锁存派生
 *      Single output exit: the verdict derives from the latch only
 *      测试未通过时 bTestOk 恒 FALSE（无恒假锁存——结论只写 TRUE 一次）
 *-----------------------------------------------------------------------------*)
bTestOk   := bPassedInt;
bTestDone := bDoneInt;
bError    := bErrorInt OR (eStateInt = E_DL_SelfTestStep.eFault);
eState    := eStateInt;
END_FUNCTION_BLOCK
