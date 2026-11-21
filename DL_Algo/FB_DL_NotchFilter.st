(*
    FB_DL_NotchFilter —— 二阶陷波滤波（中心频率与 Q 可调）
    ------------------------------------------------------------------
    分类      : DL_Algo / Filter
    前缀      : FB_DL_
    版本      : 1.0.0
    溯源      : T2-1 LGF · Measurement（只借「滤波归测量组」的分类事实）；
                陷波器双线性变换为公开数字信号处理公式，系数式、闸门顺序、码位分级
                100% 自有；clean-room 重写，未复制任何闭源厂商源码，
                参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R18）
    ------------------------------------------------------------------
    功能说明  : 抑制固定频率机械共振（丝杠固有频率、皮带拍频、伺服 300~800 Hz 尖叫）
                的带阻滤波；库内 LowPassFilter / HighPassFilter / SecondOrderFilter 都
                不带「中心频率 + Q 可调」的带阻形态，本件补该缺口；
                三道硬闸依次为：采样周期闸（决定采样频率，除零源头）、奈奎斯特闸
                （中心频率必须低于 0.45 倍采样频率，超了陷波会变成放大器）、
                系数分母闸（1 加 alpha 近零时拒绝重算并旁路）；
                参数在线改动只重算系数、保留历史状态不清零，避免改参瞬间断控制；
                输出双侧限幅并置饱和标志，是滤波发散前的最后一道防线。
    错误码    : 16#0002_2501 参数在线变更已重算系数（状态保留），或输出限幅生效——信息级，不置故障
                16#0002_2502 预留禁用（信息级，不得挪用）
                16#0002_2510 采样周期非法（不大于 0）——故障级，旁路输出
                16#0002_2511 中心频率超奈奎斯特 0.45 倍 / Q 越界 / 系数分母近零 / 限幅值非法——故障级，旁路输出
                16#0002_2512 预留禁用（故障级，不得挪用）
    码位总账  : 16#0002_2501 用 / 16#0002_2502 预留 ｜ 16#0002_2510 用 / 16#0002_2511 用 / 16#0002_2512 预留
    状态机    : 无 CASE，滤波状态由四个历史值承载，非法状态由参数闸拦截，不可能出现
    采样约定  : fbTrigReset 在本体首部无条件刷新；tSampleTime 必须等于本块所在任务的
                实际周期，否则中心频率与 Q 的物理含义失真，该参数不由本块测量。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R18）
*)
FUNCTION_BLOCK FB_DL_NotchFilter
VAR_INPUT
    bEnable      : BOOL;                       // 使能，FALSE 时输出跟随输入并保持状态 / enable, FALSE passes the input through and keeps the state
    bReset       : BOOL;                       // 复位，上升沿清内部历史值 / reset, rising edge clears the internal history
    fIn          : REAL := 0.0;                // 输入信号，一般接位置或速度反馈 [用户单位] / input signal, usually a position or speed feedback [user unit]
    fCenterFreq  : REAL := 50.0;               // 陷波中心频率 [Hz]，范围 0.1~1000.0 / notch centre frequency [Hz], range 0.1~1000.0
    fQuality     : REAL := 2.0;                // 品质因数 Q [无量纲]，范围 0.1~50.0，越大陷波越窄 / quality factor Q [dimensionless], range 0.1~50.0, larger is narrower
    tSampleTime  : TIME := T#10MS;             // 采样周期 [ms]，范围 1~1000，必须等于任务周期 / sample period [ms], range 1~1000, must equal the task period
    fOutLimit    : REAL := 1.0E6;              // 输出幅值限幅，防系数病态发散 [用户单位]，必须大于 0 / output magnitude limit against ill-conditioned divergence [user unit], must exceed zero
END_VAR
VAR_OUTPUT
    fOut      : REAL;                          // 滤波输出 [用户单位] / filtered output [user unit]
    bSaturated: BOOL;                          // 输出被限幅（发散前兆）/ output clamped, a divergence precursor
    uCoeffRev : UDINT;                         // 系数重算次数，参数在线改动监视 [次] / coefficient recomputation count for online change monitoring [times]
    eErr      : UDINT;                         // 错误码，0=正常 / error id, 0=ok
    bError    : BOOL;                          // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
END_VAR
VAR
    fbTrigReset : R_TRIG;                      // 复位沿检测实例，本体首部无条件刷新 / reset edge instance, refreshed unconditionally
    fB0         : REAL;                        // 归一化分子系数 b0 [无量纲] / normalised numerator coefficient b0 [dimensionless]
    fB1         : REAL;                        // 归一化分子系数 b1 [无量纲] / normalised numerator coefficient b1 [dimensionless]
    fB2         : REAL;                        // 归一化分子系数 b2 [无量纲] / normalised numerator coefficient b2 [dimensionless]
    fA1         : REAL;                        // 归一化分母系数 a1 [无量纲] / normalised denominator coefficient a1 [dimensionless]
    fA2         : REAL;                        // 归一化分母系数 a2 [无量纲] / normalised denominator coefficient a2 [dimensionless]
    fA0         : REAL;                        // 分母基准，防零闸的被除数 [无量纲] / denominator base, the divisor under the zero gate [dimensionless]
    fX1         : REAL;                        // 输入历史值一 [用户单位] / input history one [user unit]
    fX2         : REAL;                        // 输入历史值二 [用户单位] / input history two [user unit]
    fY1         : REAL;                        // 输出历史值一 [用户单位] / output history one [user unit]
    fY2         : REAL;                        // 输出历史值二 [用户单位] / output history two [user unit]
    fOmega      : REAL;                        // 归一化角频率 [弧度] / normalised angular frequency [rad]
    fAlpha      : REAL;                        // 带宽系数 [无量纲] / bandwidth coefficient [dimensionless]
    fFs         : REAL;                        // 采样频率 [Hz] / sampling frequency [Hz]
    fCosW       : REAL;                        // 归一化角频率余弦，系数复用 [无量纲] / cosine of the normalised angular frequency, reused by the coefficients [dimensionless]
    fTs         : REAL;                        // 采样周期秒值 [s] / sample period in seconds [s]
    fPrevFc     : REAL;                        // 上一拍中心频率，变更检测 [Hz] / previous centre frequency for change detection [Hz]
    fPrevQ      : REAL;                        // 上一拍品质因数，变更检测 [无量纲] / previous quality factor for change detection [dimensionless]
    fPrevTs     : REAL;                        // 上一拍采样周期，变更检测 [s] / previous sample period for change detection [s]
    fY          : REAL;                        // 滤波结果中间量 [用户单位] / filter result intermediate [user unit]
    bInit       : BOOL := FALSE;               // 首扫标志，初值 FALSE，判据 NOT bInit / first-scan flag, initial FALSE, tested with NOT
    bParamBad   : BOOL;                        // 参数非法标志，本拍旁路 / parameter invalid flag, bypass this cycle
END_VAR
VAR CONSTANT
    DL_NOTCH_PI2      : REAL := 6.283185307;   // 二倍圆周率 [无量纲] / twice pi [dimensionless]
    DL_NOTCH_NYQ_RATIO: REAL := 0.45;          // 中心频率上限对采样频率的比值 [无量纲] / centre frequency cap as a fraction of the sampling frequency [dimensionless]
    DL_NOTCH_Q_MIN    : REAL := 0.1;           // Q 下限 [无量纲] / quality factor lower bound [dimensionless]
    DL_NOTCH_Q_MAX    : REAL := 50.0;          // Q 上限 [无量纲] / quality factor upper bound [dimensionless]
    DL_NOTCH_FC_MIN   : REAL := 0.1;           // 中心频率下限 [Hz] / centre frequency lower bound [Hz]
    DL_NOTCH_FC_MAX   : REAL := 1000.0;        // 中心频率上限 [Hz] / centre frequency upper bound [Hz]
    DL_NOTCH_TS_MAX   : REAL := 1.0;           // 采样周期上限秒值 [s] / sample period upper bound in seconds [s]
    DL_NOTCH_MS_SEC   : REAL := 1000.0;        // 毫秒转秒的除数，恒非零 [ms/s] / milliseconds to seconds divisor, never zero [ms/s]
    DL_NOTCH_TWO      : REAL := 2.0;           // 系数式中的常数二 [无量纲] / constant two in the coefficient formulas [dimensionless]
    DL_NOTCH_ONE      : REAL := 1.0;           // 系数式中的常数一 [无量纲] / constant one in the coefficient formulas [dimensionless]
    DL_NOTCH_CNT_MAX  : UDINT := 16#FFFF_FFFE; // 重算计数饱和值 [次] / recomputation counter saturation value [times]
    DL_FLOAT_EPS      : REAL := 1.0E-6;        // 浮点判等容差 [无量纲] / float equality tolerance [dimensionless]
    DL_NOTCH_INF_GUARD: REAL := 4.0E38;        // 非有限幅值判定阈值 [用户单位] / non-finite magnitude guard [user unit]
    DL_NOTCH_ZERO     : REAL := 0.0;           // 零值常量，避免裸字面量 [无量纲] / zero constant, avoids a bare literal [dimensionless]
END_VAR

// 段 1｜边沿实例无条件周期刷新（红线：严禁放入条件分支）/ segment 1, unconditional edge refresh
fbTrigReset(CLK := bReset);

// 段 2｜输出与错误状态预置 / segment 2, preset outputs and error status
eErr := 0;                                     // 预置无错误 / preset no error
bError := FALSE;                               // 预置无故障 / preset no fault
bSaturated := FALSE;                           // 预置未限幅 / preset not limited
bParamBad := FALSE;                            // 预置参数合法 / preset parameters valid

// 段 3｜首扫初始化（初值 FALSE，判据 NOT bInit）/ segment 3, first-scan initialisation
IF NOT bInit THEN
    fX1 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fX2 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fY1 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fY2 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    uCoeffRev := 0;                            // 重算计数清零 / clear the recomputation counter
    fPrevFc := -DL_NOTCH_ONE;                  // 用不可能的值初始化，保证首拍必重算一次 / initialise with an impossible value so the first cycle always recomputes
    fPrevQ := -DL_NOTCH_ONE;                   // 同理用不可能值保证首拍必重算 / likewise impossible so first cycle recomputes
    fPrevTs := -DL_NOTCH_ONE;                  // 同理用不可能值保证首拍必重算 / likewise impossible so first cycle recomputes
    bInit := TRUE;                             // 首扫只做一次 / first scan runs once only
END_IF

// 段 4｜使能闸：失能即旁路且保持滤波状态 / segment 4, enable gate bypasses and keeps the state
IF NOT bEnable THEN
    fOut := fIn;                               // 输出跟随输入 / output follows the input
    RETURN;                                    // 失能即出口 / disabled is the exit
END_IF

// 段 5｜采样周期闸：决定采样频率，是全部除法的源头 / segment 5, sample period gate
IF tSampleTime <= T#0MS THEN
    eErr := 16#0002_2510;                      // 采样周期非法故障码 / illegal sample period fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOut := fIn;                               // 旁路输出 / bypass the output
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF
fTs := TIME_TO_REAL(tSampleTime) / DL_NOTCH_MS_SEC; // 毫秒转秒 / milliseconds to seconds
IF (ABS(fTs) <= DL_FLOAT_EPS) OR (fTs > DL_NOTCH_TS_MAX) THEN
    eErr := 16#0002_2510;                      // 秒值近零或超上限，同属采样周期非法 / seconds near zero or above the cap, both are an illegal sample period
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOut := fIn;                               // 旁路输出 / bypass the output
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 6｜奈奎斯特闸与 Q 域闸：超了陷波会变成放大器 / segment 6, Nyquist and quality factor gate
fFs := DL_NOTCH_ONE / fTs;                     // 采样频率，分母已过闸 / sampling frequency, the divisor already passed the gate
IF (fCenterFreq < DL_NOTCH_FC_MIN) OR (fCenterFreq > DL_NOTCH_FC_MAX) THEN
    eErr := 16#0002_2511;                      // 中心频率越界故障码 / centre frequency out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bParamBad := TRUE;                         // 本拍旁路 / bypass this cycle
END_IF
IF fCenterFreq >= (DL_NOTCH_NYQ_RATIO * fFs) THEN
    eErr := 16#0002_2511;                      // 超奈奎斯特上限故障码 / above the Nyquist cap fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bParamBad := TRUE;                         // 本拍旁路 / bypass this cycle
END_IF
IF (fQuality < DL_NOTCH_Q_MIN) OR (fQuality > DL_NOTCH_Q_MAX) THEN
    eErr := 16#0002_2511;                      // Q 越界故障码 / quality factor out of range fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bParamBad := TRUE;                         // 本拍旁路 / bypass this cycle
END_IF
IF fOutLimit <= DL_FLOAT_EPS THEN
    eErr := 16#0002_2511;                      // 限幅值非法故障码（限幅失效等于失去发散保护）/ illegal limit fault id, a dead limit means no divergence protection
    bError := TRUE;                            // 置故障标志 / raise the error flag
    bParamBad := TRUE;                         // 本拍旁路 / bypass this cycle
END_IF
IF bParamBad THEN
    fOut := fIn;                               // 参数非法一律旁路 / any invalid parameter bypasses the filter
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 7｜系数计算与分母防零闸 / segment 7, coefficient computation with the denominator guard
fOmega := DL_NOTCH_PI2 * fCenterFreq * fTs;    // 归一化角频率 / normalised angular frequency
fAlpha := SIN(fOmega) / (DL_NOTCH_TWO * fQuality); // 带宽系数，Q 已过闸恒非零 / bandwidth coefficient, the divisor is safe because Q passed the gate
fA0 := DL_NOTCH_ONE + fAlpha;                  // 分母基准 / denominator base
IF ABS(fA0) <= DL_FLOAT_EPS THEN
    eErr := 16#0002_2511;                      // 系数分母近零故障码 / coefficient denominator near zero fault id
    bError := TRUE;                            // 置故障标志 / raise the error flag
    fOut := fIn;                               // 旁路输出 / bypass the output
    RETURN;                                    // 故障级提前返回 / early return on fault
END_IF

// 段 8｜参数变更检测：变更只重算系数，历史状态保留不清零 / segment 8, parameter change detection keeps the state
IF (ABS(fCenterFreq - fPrevFc) > DL_FLOAT_EPS)
   OR (ABS(fQuality - fPrevQ) > DL_FLOAT_EPS)
   OR (ABS(fTs - fPrevTs) > DL_FLOAT_EPS) THEN
    fCosW := COS(fOmega);                      // 角频率余弦，四个系数共用 / cosine shared by the coefficients
    fB0 := DL_NOTCH_ONE / fA0;                 // 分子 b0，分母已过闸 / numerator b0, the divisor passed the gate
    fB1 := -DL_NOTCH_TWO * fCosW / fA0;        // 分子 b1 / numerator b1
    fB2 := fB0;                                // 分子 b2 与 b0 对称 / numerator b2 is symmetric to b0
    fA1 := -DL_NOTCH_TWO * fCosW / fA0;        // 分母 a1 / denominator a1
    fA2 := (DL_NOTCH_ONE - fAlpha) / fA0;      // 分母 a2 / denominator a2
    IF uCoeffRev < DL_NOTCH_CNT_MAX THEN
        uCoeffRev := uCoeffRev + 1;            // 饱和加一，绝不回绕 / saturating increment, never wraps
    END_IF
    eErr := 16#0002_2501;                      // 在线改参提示（信息级不置故障）/ online change hint, info level never raises a fault
    fPrevFc := fCenterFreq;                    // 记录中心频率 / remember the centre frequency
    fPrevQ := fQuality;                        // 记录品质因数 / remember the quality factor
    fPrevTs := fTs;                            // 记录采样周期 / remember the sample period
END_IF

// 段 9｜复位沿清状态（优先于滤波运算）/ segment 9, reset clears the history before filtering
IF fbTrigReset.Q THEN
    fX1 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fX2 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fY1 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
    fY2 := DL_NOTCH_ZERO;                      // 历史值清零 / clear the history
END_IF

// 段 10｜直接 I 型二阶差分方程 / segment 10, direct form one second order difference equation
fY := fB0 * fIn + fB1 * fX1 + fB2 * fX2 - fA1 * fY1 - fA2 * fY2; // 二阶带阻 / second order band stop
IF (fY <> fY) OR (fY > DL_NOTCH_INF_GUARD) OR (fY < -DL_NOTCH_INF_GUARD) THEN
    fY := fY1;                                 // 非有限即退回上一拍输出，绝不让 NaN 进入状态 / non-finite falls back to the previous output, a NaN never enters the state
    bSaturated := TRUE;                        // 标记异常 / flag the anomaly
    eErr := 16#0002_2501;                      // 异常提示（信息级不置故障）/ anomaly hint, info level never raises a fault
END_IF

// 段 11｜输出双侧限幅 / segment 11, symmetrical output clamping
IF fY > fOutLimit THEN
    fY := fOutLimit;                           // 上侧限幅 / clamp the upper side
    bSaturated := TRUE;                        // 标记限幅 / flag the clamp
    eErr := 16#0002_2501;                      // 限幅提示（信息级不置故障）/ clamp hint, info level never raises a fault
ELSIF fY < -fOutLimit THEN
    fY := -fOutLimit;                          // 下侧限幅 / clamp the lower side
    bSaturated := TRUE;                        // 标记限幅 / flag the clamp
    eErr := 16#0002_2501;                      // 限幅提示（信息级不置故障）/ clamp hint, info level never raises a fault
END_IF

// 段 12｜状态推进与输出 / segment 12, push the state and publish the output
fX2 := fX1;                                    // 输入历史后移 / shift the input history
fX1 := fIn;                                    // 记录本拍输入 / record this cycle input
fY2 := fY1;                                    // 输出历史后移 / shift the output history
fY1 := fY;                                     // 记录本拍输出 / record this cycle output
fOut := fY;                                    // 对外输出 / publish the output
END_FUNCTION_BLOCK
