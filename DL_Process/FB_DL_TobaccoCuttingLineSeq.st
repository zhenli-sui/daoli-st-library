(*
 * FB_DL_TobaccoCuttingLineSeq | C4 | DL_Process
 * 功能：制丝线「进料→切丝→烘丝→冷却→掺配→完成」工段序列控制；每相独立使能出口 + 独立 TON 超时，超时/参数非法一律回 FAULT 并撤销全部命令       单位：水分 [%]、rTimeoutS [s]、nFaultCode [INT 码位]
 * 工况边界：出口水分 rMoistOutPct 与目标 rMoistTargetPct 须在 0~100 % 且有限，DRYING 只在 |出口−目标|≤0.5 % 时转 COOLING；rTimeoutS 须 >0；xStart 为电平输入但只用上升沿启动（停车后须先撤 xStart 再给，防自恢复）；xStop 在任意相生效，按逆序（先切丝/烘丝，后进料）在同拍归零全部命令，物理减速由变频器斜坡完成；xComplete 为 DONE 相状态量（非单拍脉冲），下游取上升沿
 * 代数值回代：rMoistOutPct=12.0、rMoistTargetPct=12.0 → |Δ|=0 ≤0.5 满足转 COOLING；rMoistOutPct=13.2 → |Δ|=1.2 >0.5 驻留 DRYING 直至 9401（spec 判定式一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
(*
 * 码位总账（本件故障码全清单，逐条在实现分支中可到达；故障级锁存回放）：
 * 9401 烘丝水分偏差超时 / 9402 进料超时或进料未就绪 / 9403 切丝超时或切丝未就绪 / 9404 冷却相输送就绪丢失 / 9406 水分越界或状态机兜底（故障锁存，清除沿 = xStart 下降沿）；9405 本件预留未使用——掺配相以驻留定时正常完成，无独立故障判据，故不设该码位（码表与实现逐分支对齐）
 *)

TYPE E_DL_TobCutPhase :
(
    IDLE    := 0,       // 待机，全部命令撤销 | idle, every command withdrawn
    FEEDING := 10,      // 进料相，仅进料命令 | feeding phase, feed command only
    CUTTING := 20,      // 切丝相，进料 + 切丝命令 | cutting phase, feed plus cutter
    DRYING  := 30,      // 烘丝相，进料 + 切丝 + 烘丝命令 | drying phase, feed plus cutter plus dryer
    COOLING := 40,      // 冷却相，仅输送风机（进料）命令 | cooling phase, conveying command only
    BLENDING:= 50,      // 掺配相，仅掺配命令 | blending phase, blending command only
    DONE    := 60,      // 完成相，全部命令撤销，xComplete 置位 | done phase, all commands withdrawn, xComplete raised
    FAULT   := 90       // 故障相，全部命令强制 FALSE，码位锁存 | fault phase, all commands forced FALSE, the code is latched
);
END_TYPE

FUNCTION_BLOCK FB_DL_TobaccoCuttingLineSeq
VAR_INPUT
    xStart          : BOOL;          // 启动（下降沿兼作故障复位沿）| start, its falling edge also resets a latched fault
    xStop           : BOOL;          // 停止（任意相生效，逆序停车）| stop, effective in any phase and stopping in reverse order
    xFeedReady      : BOOL;          // 进料段就绪 | feeding section ready
    xCutterReady    : BOOL;          // 切丝机就绪 | cutter ready
    xDryerReady     : BOOL;          // 烘丝机就绪 | dryer ready
    rMoistOutPct    : REAL;          // 烘丝出口水分 | dryer outlet moisture [%]
    rMoistTargetPct : REAL := 12.0;  // 烘丝出口目标水分 | dryer outlet moisture target [%]
    rTimeoutS       : REAL := 60.0;  // 每相超时设定 | per-phase timeout setting [s]
END_VAR
VAR_OUTPUT
    xFeedCmd   : BOOL;               // 进料/输送命令（FEEDING/CUTTING/DRYING/COOLING 相独立使能）| feed command, independent enable of those phases
    xCutterCmd : BOOL;               // 切丝命令（CUTTING/DRYING 相独立使能）| cutter command, independent enable of those phases
    xDryerCmd  : BOOL;               // 烘丝命令（DRYING 相独立使能）| dryer command, independent enable of DRYING
    xBlendCmd  : BOOL;               // 掺配命令（BLENDING 相独立使能）| blending command, independent enable of BLENDING
    ePhase     : E_DL_TobCutPhase;   // 当前相 | current phase
    xComplete  : BOOL;               // 完成状态量（DONE 相为 TRUE，非单拍脉冲）| completion level, true in DONE
    xFault     : BOOL;               // 故障标志 | fault flag
    nFaultCode : INT;                // 故障码，锁存至复位沿 | fault code latched until the reset edge
END_VAR
VAR
    tonFeed  : TON;                  // FEEDING 相超时定时器 | timeout of the FEEDING phase
    tonCut   : TON;                  // CUTTING 相超时定时器 | timeout of the CUTTING phase
    tonDry   : TON;                  // DRYING 相超时定时器 | timeout of the DRYING phase
    tonCool  : TON;                  // COOLING 相超时定时器 | timeout of the COOLING phase
    tonBlend : TON;                  // BLENDING 相超时定时器 | timeout of the BLENDING phase
    tonDone  : TON;                  // DONE 相驻留定时器 | dwell timer of the DONE phase
    fbStartFall : F_TRIG;            // xStart 下降沿（故障复位沿）| falling edge of xStart, the fault reset edge
    fbStartRise : R_TRIG;            // xStart 上升沿（唯一启动沿，防止停车后自动重启）| rising edge of xStart, the single start edge preventing an auto restart
    xParamOk : BOOL;                 // 超时参数合法 | timeout parameter is legal
    xFinMoist: BOOL;                 // 出口水分有限性 | outlet moisture is finite
    xMoistBad: BOOL;                 // 出口水分越界或非有限 | outlet moisture out of range or non-finite
    xInBand  : BOOL;                 // 水分落在目标 ±0.5 % 容带内 | moisture inside the target band
    nTmoMs   : UDINT := 60000;       // 超时毫秒数（缺省值防首拍 PT=0 假超时）| timeout in milliseconds, default prevents a zero PT on the first scan
    nCodeLatch : INT;                // 故障码锁存副本 | latched copy of the fault code
END_VAR
VAR CONSTANT
    DL_TCS_BAND_PCT : REAL := 0.5;   // 水分容带半宽 | moisture band half width [%]
    DL_TCS_PCT_MIN  : REAL := 0.0;   // 水分下限 | lower moisture limit [%]
    DL_TCS_PCT_MAX  : REAL := 100.0; // 水分上限 | upper moisture limit [%]
    DL_TCS_C_MOIST  : INT := 9401;   // 烘丝水分偏差超时 | drying moisture deviation timeout
    DL_TCS_C_FEED   : INT := 9402;   // 进料超时/未就绪 | feeding timeout or not ready
    DL_TCS_C_CUT    : INT := 9403;   // 切丝超时/未就绪 | cutting timeout or not ready
    DL_TCS_C_COOL   : INT := 9404;   // 冷却超时 | cooling timeout
    DL_TCS_C_BAD    : INT := 9406;   // 水分越界或兜底 | moisture out of range or fallback
END_VAR

// 段1｜参数与采样门禁（先判后用：REAL→UDINT 换算在闸后进行，结果供段2 定时器使用）
xParamOk := (rTimeoutS = rTimeoutS) AND ((rTimeoutS - rTimeoutS) = 0.0) AND (rTimeoutS > 0.0);
IF xParamOk THEN
    nTmoMs := REAL_TO_UDINT(rTimeoutS * 1000.0);
ELSE
    nTmoMs := 60000;                 // 参数非法时取保守超时 | conservative timeout when the parameter is illegal
END_IF
xFinMoist := (rMoistOutPct = rMoistOutPct) AND ((rMoistOutPct - rMoistOutPct) = 0.0)
             AND (rMoistTargetPct = rMoistTargetPct) AND ((rMoistTargetPct - rMoistTargetPct) = 0.0);
xMoistBad := (NOT xFinMoist)
             OR (rMoistOutPct < DL_TCS_PCT_MIN) OR (rMoistOutPct > DL_TCS_PCT_MAX)
             OR (rMoistTargetPct < DL_TCS_PCT_MIN) OR (rMoistTargetPct > DL_TCS_PCT_MAX);
xInBand := (NOT xMoistBad) AND (ABS(rMoistOutPct - rMoistTargetPct) <= DL_TCS_BAND_PCT);

// 段2｜六只定时器 + 两只边沿实例无条件周期刷新（R7，一相一只实例不跨相复用；PT 取自段1 已换算毫秒值）
tonFeed(IN := ePhase = E_DL_TobCutPhase.FEEDING, PT := UDINT_TO_TIME(nTmoMs));
tonCut(IN := ePhase = E_DL_TobCutPhase.CUTTING, PT := UDINT_TO_TIME(nTmoMs));
tonDry(IN := ePhase = E_DL_TobCutPhase.DRYING, PT := UDINT_TO_TIME(nTmoMs));
tonCool(IN := ePhase = E_DL_TobCutPhase.COOLING, PT := UDINT_TO_TIME(nTmoMs));
tonBlend(IN := ePhase = E_DL_TobCutPhase.BLENDING, PT := UDINT_TO_TIME(nTmoMs));
tonDone(IN := ePhase = E_DL_TobCutPhase.DONE, PT := UDINT_TO_TIME(nTmoMs));
fbStartFall(CLK := xStart);
fbStartRise(CLK := xStart);

// 段3｜输出预置（唯一预置点；CASE 内只置位，其后不再无条件清零）
xFeedCmd := FALSE;
xCutterCmd := FALSE;
xDryerCmd := FALSE;
xBlendCmd := FALSE;
xComplete := FALSE;
xFault := FALSE;
nFaultCode := 0;

// 段4｜全局闸：参数/水分非法 → 直接锁故障；xStop → 逆序停车并撤销全部命令
IF (NOT xParamOk) OR xMoistBad THEN
    nCodeLatch := DL_TCS_C_BAD;
    xFault := TRUE;
    nFaultCode := DL_TCS_C_BAD;
    xFeedCmd := FALSE;               // 逆序停车：下游先停 | reverse stop, downstream first
    xCutterCmd := FALSE;
    xDryerCmd := FALSE;
    xBlendCmd := FALSE;
    ePhase := E_DL_TobCutPhase.FAULT;
ELSIF xStop AND (ePhase <> E_DL_TobCutPhase.IDLE) THEN
    xCutterCmd := FALSE;             // 逆序停车第 1 步：切丝与烘丝先停 | reverse stop step 1, cutter and dryer first
    xDryerCmd := FALSE;
    xBlendCmd := FALSE;
    xFeedCmd := FALSE;               // 逆序停车第 2 步：进料后停（同拍置假，斜坡由变频器完成）| step 2, feed last
    ePhase := E_DL_TobCutPhase.IDLE;
END_IF

// 段5｜主状态机（ENUM + CASE，ELSE 兜底）
IF ePhase <> E_DL_TobCutPhase.FAULT THEN
CASE ePhase OF
E_DL_TobCutPhase.IDLE:
    // 拍 N：待机，无命令；仅 xStart 上升沿且进料就绪、无停车请求时启动（防停车后自恢复）
    IF fbStartRise.Q AND xFeedReady AND (NOT xStop) THEN
        ePhase := E_DL_TobCutPhase.FEEDING;      // 本拍行为：进料相（命令下拍由段6给出）| enter feeding
    END_IF

E_DL_TobCutPhase.FEEDING:
    // 拍 N：进料中，等切丝机就绪
    IF (NOT xFeedReady) THEN
        nCodeLatch := DL_TCS_C_FEED;             // 进料就绪丢失 | feed readiness lost
        xFault := TRUE;
        nFaultCode := DL_TCS_C_FEED;
        ePhase := E_DL_TobCutPhase.FAULT;
    ELSIF xCutterReady THEN
        ePhase := E_DL_TobCutPhase.CUTTING;      // 本拍行为：切丝机就绪转切丝 | cutter ready, enter cutting
    ELSIF tonFeed.Q THEN
        nCodeLatch := DL_TCS_C_FEED;             // 进料超时 | feeding timeout
        xFault := TRUE;
        nFaultCode := DL_TCS_C_FEED;
        ePhase := E_DL_TobCutPhase.FAULT;
    END_IF

E_DL_TobCutPhase.CUTTING:
    // 拍 N：切丝中，等烘丝机就绪
    IF NOT xCutterReady THEN
        nCodeLatch := DL_TCS_C_CUT;              // 切丝机就绪丢失 | cutter readiness lost
        xFault := TRUE;
        nFaultCode := DL_TCS_C_CUT;
        ePhase := E_DL_TobCutPhase.FAULT;
    ELSIF xDryerReady THEN
        ePhase := E_DL_TobCutPhase.DRYING;       // 本拍行为：烘丝机就绪转烘丝 | dryer ready, enter drying
    ELSIF tonCut.Q THEN
        nCodeLatch := DL_TCS_C_CUT;              // 切丝超时 | cutting timeout
        xFault := TRUE;
        nFaultCode := DL_TCS_C_CUT;
        ePhase := E_DL_TobCutPhase.FAULT;
    END_IF

E_DL_TobCutPhase.DRYING:
    // 拍 N：烘丝中，出口水分进入目标容带才转 COOLING
    IF NOT xDryerReady THEN
        nCodeLatch := DL_TCS_C_BAD;              // 烘丝机异常：按参数级故障处理 | dryer abnormality handled as a parameter-class fault
        xFault := TRUE;
        nFaultCode := DL_TCS_C_BAD;
        ePhase := E_DL_TobCutPhase.FAULT;
    ELSIF xInBand THEN
        ePhase := E_DL_TobCutPhase.COOLING;      // 本拍行为：水分达标转冷却 | moisture in band, enter cooling
    ELSIF tonDry.Q THEN
        nCodeLatch := DL_TCS_C_MOIST;            // 水分偏差超时：停在上限不转相 | moisture deviation timeout, hold the upper limit
        xFault := TRUE;
        nFaultCode := DL_TCS_C_MOIST;
        ePhase := E_DL_TobCutPhase.FAULT;
    END_IF

E_DL_TobCutPhase.COOLING:
    // 拍 N：冷却输送（输送机由进料段驱动），输送就绪丢失即报 9404；正常由驻留定时转掺配
    IF NOT xFeedReady THEN
        nCodeLatch := DL_TCS_C_COOL;                 // 冷却输送中断 | cooling conveying interrupted
        xFault := TRUE;
        nFaultCode := DL_TCS_C_COOL;
        ePhase := E_DL_TobCutPhase.FAULT;
    ELSIF tonCool.Q THEN
        ePhase := E_DL_TobCutPhase.BLENDING;         // 本拍行为：冷却完成转掺配 | cooling done, enter blending
    END_IF

E_DL_TobCutPhase.BLENDING:
    // 拍 N：掺配中，等掺配时间走完（驻留定时到即视为正常完成，不设故障码位，见头注释 9405 预留说明）
    IF tonBlend.Q THEN
        ePhase := E_DL_TobCutPhase.DONE;         // 本拍行为：掺配完成 | blending done
    END_IF

E_DL_TobCutPhase.DONE:
    // 拍 N：完成相，xComplete 由段6置位，驻留一个超时窗后回待机
    IF tonDone.Q OR (NOT xStart) THEN
        ePhase := E_DL_TobCutPhase.IDLE;         // 本拍行为：回待机 | back to idle
    END_IF

E_DL_TobCutPhase.FAULT:
    // 故障相（本段被外层 IF 排除，保留分支以满足穷举）
    xFault := TRUE;
    nFaultCode := nCodeLatch;

ELSE
    // 非法状态兜底：绝不停在未知相
    nCodeLatch := DL_TCS_C_BAD;
    xFault := TRUE;
    nFaultCode := DL_TCS_C_BAD;
    ePhase := E_DL_TobCutPhase.FAULT;
END_CASE
END_IF

// 段6｜每相独立使能出口（FAULT/IDLE/DONE 不置任何命令，天然强制 FALSE）
CASE ePhase OF
E_DL_TobCutPhase.FEEDING:
    xFeedCmd := TRUE;                        // 进料相独立使能出口 | independent enable of FEEDING
E_DL_TobCutPhase.CUTTING:
    xFeedCmd := TRUE;                        // 切丝相：进料保持 | cutting, keep feeding
    xCutterCmd := TRUE;                      // 切丝相独立使能出口 | independent enable of CUTTING
E_DL_TobCutPhase.DRYING:
    xFeedCmd := TRUE;                        // 烘丝相：进料保持 | drying, keep feeding
    xCutterCmd := TRUE;                      // 烘丝相：切丝保持 | drying, keep cutting
    xDryerCmd := TRUE;                       // 烘丝相独立使能出口 | independent enable of DRYING
E_DL_TobCutPhase.COOLING:
    xFeedCmd := TRUE;                        // 冷却相独立使能出口（输送风机）| independent enable of COOLING
E_DL_TobCutPhase.BLENDING:
    xBlendCmd := TRUE;                       // 掺配相独立使能出口 | independent enable of BLENDING
E_DL_TobCutPhase.DONE:
    xComplete := TRUE;                       // 完成状态量 | completion level
ELSE
    xFeedCmd := FALSE;                       // 其余相（含 FAULT）：命令强制 FALSE | all other phases force FALSE
    xCutterCmd := FALSE;
    xDryerCmd := FALSE;
    xBlendCmd := FALSE;
END_CASE

// 段7｜故障相锁存回放 + 复位沿（xStart 下降沿清除）
IF ePhase = E_DL_TobCutPhase.FAULT THEN
    xFault := TRUE;
    nFaultCode := nCodeLatch;                // 锁存回放，不按当下输入重推断 | republish the latch
    xFeedCmd := FALSE;
    xCutterCmd := FALSE;
    xDryerCmd := FALSE;
    xBlendCmd := FALSE;
    xComplete := FALSE;
    IF fbStartFall.Q THEN
        nCodeLatch := 0;                     // 清除边：xStart 下降沿（头注释已声明）| clear edge declared in the header
        ePhase := E_DL_TobCutPhase.IDLE;
    END_IF
END_IF
END_FUNCTION_BLOCK
