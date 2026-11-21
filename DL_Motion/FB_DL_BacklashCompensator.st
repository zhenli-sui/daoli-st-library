(*
    FB_DL_BacklashCompensator —— 换向背隙补偿
    ------------------------------------------------------------------
    分类      : DL_Motion / Compensation
    前缀      : FB_DL_
    版本      : 1.0.1
    溯源      : T1-6 轴级补偿语义（只借「换向补偿属运动层给定量修正」的分类事实）；
                T2-2 LBP 泵 / 辊「背隙两阶段逼近」组织方式为次源（该组织已被
                RollerGapAdjust 使用）；增量式补偿、EWMA 学习、容差闸与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 指令方向翻转瞬间在给定量上叠加一个方向性补偿量，抵消齿轮 / 丝杠反向
                间隙；并在到位后按实测偏差用 EWMA 自学习背隙估计（现场背隙随磨损变化）；
                与 FB_DL_RollerGapAdjust 的分界是后者为工艺辊缝调整顺控，本件是轴级
                给定量修正，两者不重叠；
                三道闸：负背隙取绝对值（参数习惯差异，不是故障）→ 超上限判故障
                （10 mm 以上补偿会把轴推到撞块）→ 位置非有限即旁路并清方向记忆；
                方向判定带死区，浮点判等全部带容差，杜绝边界来回翻转导致的补偿抖动；
                首拍没有历史方向时绝不补偿，否则轴会凭空跳一下。
    错误码    : 16#0004_01CB 背隙标称值为负已取绝对值 / 学习值被钳位——信息级，不置故障
                16#0004_01CC 预留禁用（信息级，不得挪用）
                16#0004_02DB 背隙标称值超上限（大于 10 mm）——故障级，补偿禁用并旁路输出
                16#0004_02DC 位置快照非有限（NaN / 正负 INF）——故障级，旁路输出并清方向记忆
                16#0004_02DD 预留禁用（故障级，不得挪用）
    码位总账  : 16#0004_01CB 用 / 16#0004_01CC 预留 ｜ 16#0004_02DB 用 / 16#0004_02DC 用 / 16#0004_02DD 预留
    状态机    : 无 CASE，方向由 bPrevDir 一个比特承载，非法状态不可能出现
    采样约定  : fbTrigReset 在本体首部无条件刷新；本件无时间量，补偿结果与任务周期无关，
                自学习按拍迭代，采样越密学习越平滑。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
                2026-11-16 v1.0.1 R18 终审修复：学习率下限常量 DL_BL_MIN_LEARN = 0.001 与引脚声明域
                0.01~0.5 不一致，改为 0.01 与声明对齐（EWMA 仍可双向收敛，无「只置不销」问题）。
                对外引脚零变更。
*)
FUNCTION_BLOCK FB_DL_BacklashCompensator
VAR_INPUT
    bEnable      : BOOL;                       // 使能，FALSE 时输出等于指令（旁路）/ enable, FALSE passes the command through
    bReset       : BOOL;                       // 上升沿清方向记忆与学习值 / rising edge clears the direction memory and the learned value
    fCmdPosition : REAL := 0.0;                // 指令位置，来自插补或定位 [mm] / commanded position from the interpolator or the positioner [mm]
    fActPosition : REAL := 0.0;                // 实际位置反馈，自学习用 [mm] / actual position feedback used for learning [mm]
    fBacklash    : REAL := 0.10;               // 背隙标称值 [mm]，范围 0.0~10.0 / nominal backlash [mm], range 0.0~10.0
    bAutoLearn   : BOOL := FALSE;              // TRUE 时按到位偏差 EWMA 更新背隙 / TRUE updates the backlash from the positioning deviation by EWMA
    fLearnTol    : REAL := 0.10;               // 学习容差，到位偏差超此值不采信 [mm] / learning tolerance, deviations above it are rejected [mm]
    fLearnGain   : REAL := 0.1;                // EWMA 学习率 [无量纲]，范围 0.01~0.5 / EWMA learning rate [dimensionless], range 0.01~0.5
END_VAR
VAR_OUTPUT
    fOutPosition : REAL;                       // 补偿后位置给定 [mm] / compensated position setpoint [mm]
    bDirPositive : BOOL;                       // 当前指令方向，TRUE 为正向 / current command direction, TRUE is positive
    fApplied     : REAL;                       // 本拍叠加的补偿量（带符号）[mm] / compensation applied this cycle with its sign [mm]
    fBacklashEst : REAL;                       // 当前背隙估计（学习值）[mm] / current backlash estimate [mm]
    bLearnActive : BOOL;                       // 本次自学习被采信 / this cycle learning was accepted
    eErr         : UDINT;                      // 错误码，0=正常 / error id, 0=ok
    bError       : BOOL;                       // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    bPrevDir    : BOOL;                        // 上一拍方向，TRUE 正向 / previous cycle direction, TRUE is positive
    bDirInit    : BOOL := FALSE;               // 方向记忆已初始化标志，初值 FALSE / direction memory initialised flag, initial FALSE
    bDirCur     : BOOL;                        // 本拍方向判定结果 / current cycle direction
    bReversed   : BOOL;                        // 方向翻转标志 / direction reversal flag
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    fEst        : REAL;                        // 背隙估计（EWMA 值）[mm] / backlash estimate produced by EWMA [mm]
    fDev        : REAL;                        // 到位偏差，实际减指令 [mm] / positioning deviation, actual minus command [mm]
    fPrevCmd    : REAL;                        // 上一拍指令位置，方向判定用 [mm] / previous commanded position used by the direction check [mm]
    fBlEff      : REAL;                        // 生效背隙标称值，取绝对值后 [mm] / effective nominal backlash after the absolute value [mm]
    fGainEff    : REAL;                        // 生效学习率，钳位后 [无量纲] / effective learning rate after clamping [dimensionless]
    fAppliedInt : REAL;                        // 补偿量中间量 [mm] / compensation intermediate [mm]
    fClamped    : REAL;                        // 钳位中间量 [mm] / clamping intermediate [mm]
    bNonFin     : BOOL;                        // 位置非有限判定标志 / position non-finite flag
END_VAR
VAR CONSTANT
    DL_BL_MAX        : REAL := 10.0;           // 背隙上限 [mm] / backlash upper bound [mm]
    DL_BL_MIN_LEARN  : REAL := 0.01;           // 学习率下限 [无量纲]，与引脚声明域 0.01~0.5 一致 / learning rate lower bound [dimensionless], aligned with the documented 0.01~0.5 pin range
    DL_BL_GAIN_MAX   : REAL := 0.5;            // 学习率上限 [无量纲] / learning rate upper bound [dimensionless]
    DL_BL_INF_GUARD  : REAL := 4.0E38;         // 非有限幅值判定阈值 [mm] / non-finite magnitude guard [mm]
    DL_FLOAT_EPS     : REAL := 1.0E-6;         // 浮点判等容差 [mm] / float equality tolerance [mm]
    DL_BL_ZERO       : REAL := 0.0;            // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
    DL_BL_ONE        : REAL := 1.0;            // 一值常量，用于符号判定 / one constant used by the sign check [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bLearnActive := FALSE;                         // 预置本次不采信学习 / preset learning not accepted
fApplied := DL_BL_ZERO;                        // 补偿量先清零 / clear the applied compensation
bReversed := FALSE;                            // 翻转标志先清 / clear the reversal flag

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fEst := MIN(MAX(ABS(fBacklash), DL_BL_ZERO), DL_BL_MAX); // 初值取标称背隙绝对值，双侧钳位 / initialise from the absolute nominal backlash, clamped both sides
    fPrevCmd := DL_BL_ZERO;                    // 指令记忆清零 / clear the command memory
    bDirInit := FALSE;                         // 方向记忆未初始化 / the direction memory is not initialised yet
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：旁路输出，不补偿 / segment 4, enable gate passes the command through
IF NOT bEnable THEN
    fOutPosition := fCmdPosition;              // 输出等于指令 / output equals the command
    fBacklashEst := fEst;                      // 估计值照常回读 / the estimate stays readable
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 5｜背隙标称值闸：负值取绝对值（参数习惯），超上限判故障 / segment 5, nominal backlash gate
fBlEff := ABS(fBacklash);                      // 负背隙取绝对值 / take the absolute value of a negative backlash
IF fBacklash < DL_BL_ZERO THEN
    eErr := 16#0004_01CB;                      // 取绝对值提示（信息级不置故障）/ absolute value hint, info level never raises a fault
END_IF
IF fBlEff > DL_BL_MAX THEN
    eErr := 16#0004_02DB;                      // 背隙超上限故障码 / backlash above the cap fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOutPosition := fCmdPosition;              // 补偿禁用，旁路输出 / compensation disabled, pass the command through
    fBacklashEst := fEst;                      // 估计值回读 / the estimate stays readable
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 6｜位置非有限闸：旁路输出并清方向记忆 / segment 6, non-finite position gate
bNonFin := (fCmdPosition <> fCmdPosition)
        OR (fCmdPosition > DL_BL_INF_GUARD) OR (fCmdPosition < -DL_BL_INF_GUARD)
        OR (fActPosition <> fActPosition)
        OR (fActPosition > DL_BL_INF_GUARD) OR (fActPosition < -DL_BL_INF_GUARD); // 双位置同口径检查 / both positions checked the same way
IF bNonFin THEN
    eErr := 16#0004_02DC;                      // 位置非有限故障码 / non-finite position fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOutPosition := fCmdPosition;              // 旁路输出 / pass the command through
    fBacklashEst := fEst;                      // 估计值回读 / the estimate stays readable
    bDirInit := FALSE;                         // 清方向记忆，防下一拍凭空跳一下 / clear the direction memory so the next cycle cannot jump
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 7｜首拍无历史方向：不补偿，只登记方向 / segment 7, no compensation without a historical direction
IF NOT bDirInit THEN
    fPrevCmd := fCmdPosition;                  // 登记指令位置 / register the commanded position
    bPrevDir := TRUE;                          // 默认按正向登记 / register the positive direction by default
    bDirInit := TRUE;                          // 方向记忆就绪 / the direction memory is ready
    bDirPositive := TRUE;                      // 对外方向 / publish the direction
    fOutPosition := fCmdPosition;              // 首拍不补偿 / no compensation on the first cycle
    fBacklashEst := fEst;                      // 估计值回读 / the estimate stays readable
    RETURN;                                    // 本拍结束 / the cycle ends here
END_IF

// 段 8｜方向判定：带死区，浮点判等全部带容差，死区内保持上一方向 / segment 8, direction detection with a dead band
IF fCmdPosition > (fPrevCmd + DL_FLOAT_EPS) THEN
    bDirCur := TRUE;                           // 越过死区向上，判正向 / above the dead band, positive
ELSIF fCmdPosition < (fPrevCmd - DL_FLOAT_EPS) THEN
    bDirCur := FALSE;                          // 越过死区向下，判负向 / below the dead band, negative
ELSE
    bDirCur := bPrevDir;                       // 死区内保持上一方向，防抖动翻转 / inside the dead band keep the previous direction against chatter
END_IF
bReversed := (bDirCur <> bPrevDir);            // 方向翻转判定 / reversal detection
bDirPositive := bDirCur;                       // 对外方向 / publish the direction

// 段 9｜复位沿：清方向记忆与学习值（优先于补偿）/ segment 9, reset clears the direction memory and the learned value
IF fbTrigReset.Q THEN
    fEst := MIN(MAX(fBlEff, DL_BL_ZERO), DL_BL_MAX); // 学习值回到标称 / the learned value returns to the nominal
    fPrevCmd := fCmdPosition;                  // 指令记忆复位 / reset the command memory
    bDirInit := FALSE;                         // 方向记忆清空 / clear the direction memory
    bReversed := FALSE;                        // 本拍不判翻转 / no reversal on the reset cycle
    fOutPosition := fCmdPosition;              // 复位拍不补偿 / no compensation on the reset cycle
    fBacklashEst := fEst;                      // 估计值回读 / the estimate stays readable
    RETURN;                                    // 复位即出口 / reset is the exit
END_IF

// 段 10｜EWMA 自学习：仅在非翻转拍、偏差在容差内且非零时采信 / segment 10, EWMA learning accepted only off the reversal cycle
fGainEff := MIN(MAX(fLearnGain, DL_BL_MIN_LEARN), DL_BL_GAIN_MAX); // 学习率双侧钳位 / clamp the learning rate both sides
IF (ABS(fLearnGain - fGainEff) > DL_FLOAT_EPS) THEN
    eErr := 16#0004_01CB;                      // 学习率钳位提示（信息级不置故障）/ learning rate clamp hint, info level never raises a fault
END_IF
IF bAutoLearn AND (NOT bReversed) THEN
    fDev := fActPosition - fCmdPosition;       // 到位偏差 / positioning deviation
    IF (ABS(fDev) <= fLearnTol) AND (ABS(fDev) > DL_FLOAT_EPS) THEN
        fEst := fEst + fGainEff * (ABS(fDev) - fEst); // 一阶 EWMA 逼近偏差绝对值 / first order EWMA towards the absolute deviation
        fClamped := MIN(MAX(fEst, DL_BL_ZERO), DL_BL_MAX); // 学习值双侧钳位 / clamp the learned value both sides
        IF ABS(fClamped - fEst) > DL_FLOAT_EPS THEN
            eErr := 16#0004_01CB;              // 学习值钳位提示（信息级不置故障）/ learned value clamp hint, info level never raises a fault
        END_IF
        fEst := fClamped;                      // 落盘钳位值 / commit the clamped value
        bLearnActive := TRUE;                  // 本次学习被采信 / this cycle learning is accepted
    END_IF
END_IF

// 段 11｜补偿量与输出：幅值不超过背隙上限，方向翻转即换符号，恒定而非逐拍累加 / segment 11, compensation and output
IF bDirCur THEN
    fAppliedInt := fEst;                       // 正向运动叠加正补偿 / a positive move carries a positive compensation
ELSE
    fAppliedInt := -fEst;                      // 负向运动叠加负补偿 / a negative move carries a negative compensation
END_IF
IF ABS(fAppliedInt) > DL_BL_MAX THEN
    IF fAppliedInt >= DL_BL_ZERO THEN
        fAppliedInt := DL_BL_MAX;              // 正向幅值兜底钳位 / positive magnitude fallback clamp
    ELSE
        fAppliedInt := -DL_BL_MAX;             // 负向幅值兜底钳位 / negative magnitude fallback clamp
    END_IF
END_IF
fApplied := fAppliedInt;                       // 对外补偿量 / publish the compensation
fOutPosition := fCmdPosition + fAppliedInt;    // 补偿后给定 / compensated setpoint
fBacklashEst := fEst;                          // 对外背隙估计 / publish the backlash estimate

// 段 12｜方向记忆推进 / segment 12, advance the direction memory
fPrevCmd := fCmdPosition;                      // 记录本拍指令 / remember this cycle command
bPrevDir := bDirCur;                           // 记录本拍方向 / remember this cycle direction
END_FUNCTION_BLOCK
