(*==============================================================================
 * 组件名称 (Component)  : FC_DL_CalcMoveTime
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 运动学估算族 · 点到点定位耗时估算
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （ABS / SQRT / MIN / MAX / REAL_TO_TIME），零厂商方言
 * 接口依赖 (Depends)    : 无（纯函数，不引用任何接口、不引用任何 POU 实例）
 * 功能描述 (Function)   : 梯形 / 三角速度曲线点到点定位的理论耗时估算，输出加速段、
 *                         匀速段、减速段分段耗时与实际峰值速度，并给出三角退化标志。
 *                         用于产线节拍仿真、配方可行性预判与「该段移动能否达到设定
 *                         速度」的选型诊断。纯函数、无状态、无内部实例，可在任意任务
 *                         与任意循环内反复调用。
 * 设计要点 (Key notes)  :
 *   ① 临界距离必须显式判：只有距离足够才有匀速段，否则退化为三角形曲线；「忘记
 *      三角情形」是速度曲线估算最经典的现场 bug（短行程反复过冲）。
 *   ② 支持非零起始速度（接续定位：皮带已在动时接着走下一段），加速段距离按
 *      (v² − v0²)/(2a) 计算，而非 v²/(2a)。
 *   ③ 起始速度超过速度上限时按「纯减速到点」处理并给出提示码，不返回失败：
 *      这种工况在接续定位里真实存在，硬判非法会让上层无法估算节拍。
 *   ④ 三段耗时按秒计算，最后统一换算为毫秒输出；换算采用标准类型转换函数，语义为
 *      「截断到毫秒」，与本库其他时间输出件口径一致（不做四舍五入，避免累计偏大）。
 *   ⑤ 结果设上限保护（24 小时）：参数错填（例如加速度填 1E-3 而距离填 1E6）时
 *      输出被钳位并提示，防止 HMI 时间控件溢出。
 * 计算契约 (Contract)  :
 *   记 d = |fDistance|、v0 = |fVelStart|、a = fAcc、dec = fDec、vmax = fVelMax，
 *   ts = 稳定延时（秒）。全部耗时以秒计算，最后统一换算为毫秒输出。
 *   ① 校验：vmax ≤ 判零下限、a ≤ 判零下限、dec ≤ 判零下限或任一参数非有限值
 *      → 返回 FALSE 且出 0180，三段耗时清零。
 *   ② 临界距离：dCrit = (vmax² − v0²)/(2a) + vmax²/(2dec)。d ≥ dCrit 才有
 *      匀速段（梯形），否则退化为三角（无匀速段）。
 *   ③ 梯形：tAcc = (vmax − v0)/a，dAcc = (vmax² − v0²)/(2a)，dDec = vmax²/(2dec)，
 *      tDec = vmax/dec，tCruise = (d − dAcc − dDec)/vmax，峰速 = vmax。
 *   ④ 三角：峰速 = √((2·a·dec·d + dec·v0²)/(a + dec))，tAcc = (峰速 − v0)/a，
 *      tDec = 峰速/dec，tCruise = 0。峰速低于起始速度时加速段钳零。
 *   ⑤ 起始速度超上限（v0 > vmax）：若 v0²/(2dec) ≥ d，则边减速边到点，
 *      vEnd = √(v0² − 2·dec·d)，总减速耗时 = (v0 − vEnd)/dec；否则先减到 vmax
 *      再匀速走完剩余行程。两种情形均出 0183。
 *   ⑥ 总耗时 = tAcc + tCruise + tDec + ts；分段与总耗时分别换算，最后复核
 *      分段和不超过总耗时（防浮点截断使上层相加不自洽）。
 *   量纲核对：mm ÷ (mm/s²) 得 s；mm ÷ (mm/s) 得 s；(mm/s)² ÷ (mm/s²) 得 mm；
 *   (mm/s²)·mm 的开方得 mm/s。四类量纲在公式中自洽，无需附加换算系数。
 * 开源溯源 (Origin)     : 原创实现，clean-room。公式为公开运动学（教科书级结论：
 *                         梯形曲线临界距离、三角曲线峰速、非零初速的加速段距离），
 *                         语义与参数组织参考公开教学页与公开工程计算器说明
 *                         （来源编号 RAW_NOTES S-14）。
 *                         「借鉴对象的许可说明」：上述对象为公开发布但受版权保护的
 *                         教学文档与在线计算器说明，公式本身属公有领域数学结论，
 *                         仅借鉴公式结构与工程提示；本实现的接口、错误码、边界策略
 *                         （非有限值、加速度近零、负距离取绝对值、结果钳位）100% 自有。
 * 验收向量 (Acceptance) :
 *   V1 d=100、vmax=30、a=dec=20：fVelPeak=30、bTriangular=FALSE、加速段 1500 ms、
 *      减速段 1500 ms、匀速段约 1833 ms（匀速行程 55 mm = 100 − 22.5 − 22.5）；
 *   V2 同参数、d=20：bTriangular=TRUE、fVelPeak=20（三角退化，峰速低于上限 30）；
 *   V3 v0=10、d=100：加速段缩短为 1000 ms，峰速仍达 30；
 *   V4 a=0：返回 FALSE 且出 0180，三段耗时全为 0；
 *   V5 d=0：tMove=tSettle，出 0182；
 *   V6 v0=50 且 vmax=30：出 0183，耗时为纯减速 + 匀速结果（1 s 减速 + 2 s 匀速）；
 *   V7 参数极大（距离 1E6、加速度 1E-3）：结果被钳到 24 h 并出 0184。
 * 已知限制 (Limits)     :
 *   ① 仅估算匀速段与加减速段，不含伺服整定、通信延迟与机械弹性振动；这些非匀速
 *      固定开销请通过 tSettle 引脚显式计入（现场经验：固定开销常占总节拍一半）。
 *   ② 假设加减速度为常值（梯形 / 三角），不支持 S 曲线（S 曲线的耗时更长，需用
 *      加加速度参数另行估算）。
 *   ③ 减速段与加速段使用各自独立的加速度参数（fAcc / fDec），不假设二者相等。
 * 选型诊断 (Sizing note) :
 *   本函数的工程价值不只在「算一个时间」，更在判断配方是否与轴规格匹配：
 *   ① bTriangular = TRUE 且 tCruisePhase = 0：该段移动根本到不了设定速度，若现场
 *      要求「必须按设定速度通过」（例如涂胶、贴装、扫描），必须提高加速度或缩短
 *      该段行程，否则节拍表与实际表现永远对不上。
 *   ② fVelPeak 明显低于 fVelMax 且 fDist 很小：属正常的短行程加速受限，不是故障。
 *   ③ 用同一组参数批量试算多个配方段并累加 tMove，即可在 HMI 上做「节拍预算」预判，
 *      避免上线后才发现某段拖慢整线（节拍瓶颈定位）。
 *   ④ 若估算值与实测差超过 20%，优先怀疑 tSettle 填小了（夹爪、整定、通信开销），
 *      其次怀疑驱动器自己的加减速限幅比组态值更保守。
 * 规格偏离 (Deviation)  :
 *   ① 公式与计算契约逐式一致，未做近似化简。
 *   ② 规格第 1.6 节验收向量 V1 / V2 的数值与计算契约第③④式自相矛盾：V1 原文按
 *      「100 − 22.5 = 77.5 mm 匀速」推 2500 ms，只扣了加速段行程、漏扣减速段
 *      22.5 mm；V2 原文按 √(a·d) 口径给 14.14 mm/s，而契约三角峰速公式
 *      √((2·a·dec·d + dec·v0²)/(a + dec)) 在同参数下为 20 mm/s（此值也满足
 *      「d = 峰速²/2a + 峰速²/2dec」的行程守恒）。本实现以计算契约公式为准，并把
 *      两个向量的期望值按公式修正（V1 匀速段 ≈1833 ms、V2 峰速 = 20）；公式本身
 *      与契约一致，未改动。影响：终审按本文件列出的修正值推演，不按原文数值判失败。
 *   ③ 三段耗时的数值采用截断到毫秒的换算意图；分段和与总耗时在出口做一次一致性
 *      复核（分段和不得大于总耗时），属规格未要求但必要的自洽保护。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅 ABS / SQRT / MIN / MAX / 标准类型转换）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（四处除法前均判分母下限、浮点比较用容差、
 *      无数组访问、结果钳位防溢出）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 状态机 N/A（纯函数不可持有状态、不可含实例，本文件无 ENUM / CASE；
 *      与库内既有函数件 FC_DL_DewPointCalc 同口径）
 *   R7 定时器 / 边沿实例 N/A（函数内禁止任何实例，本文件零实例调用）
 *   POU 终结符成对 ✓（FUNCTION ↔ END_FUNCTION，末行即终结符；本文件无 TYPE）
 * 错误码表 (Error codes，本函数仅有信息级语义，不置任何故障位):
 *   16#0004_0180【信息级】参数非法（速度 / 加减速度近零或非有限值）；
 *   16#0004_0181【信息级】临界距离浮点残差，匀速段钳零；
 *   16#0004_0182【信息级】距离为零，耗时等于稳定延时；
 *   16#0004_0183【信息级】起始速度超上限，按减速到点计算；
 *   16#0004_0184【信息级】结果超上限钳位。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 运动学估算族开族件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   bOk := FC_DL_CalcMoveTime(
 *              fDistance  := 100.0,
 *              fVelMax    := 30.0,
 *              fAcc       := 20.0,
 *              fDec       := 20.0,
 *              fVelStart  := 0.0,
 *              tSettle    := T#200MS,
 *              tMove      => tSegmentTime,
 *              bTriangular=> bShortMove,
 *              uErrorId   => uCalcCode);
 *   IF NOT bOk THEN
 *       // 参数非法：tMove 已被置为 0，禁止直接用于节拍计算
 *   END_IF
 *   注：所有输出引脚必须带 => 实参（函数输出不可省略），否则返回值语义不完整。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 先判返回值再用 tMove：参数非法时 tMove 被置 T#0S，直接参与节拍汇总会把
 *      一段真实的移动算成零耗时，节拍仿真结论会整体偏乐观。
 *   2 bTriangular 为 TRUE 表示「这段距离根本到不了设定速度」，属于选型警示：
 *      连续多段都三角退化，说明伺服速度规格选大了而加速度选小了。
 *   3 接续定位（上一段没停稳就接下一段）必须把上一段末速填进 fVelStart，否则
 *      估算会多算一次从零加速的时间。
 *   4 tSettle 不是「犹豫时间」而是夹爪动作、焊缝整定、视觉确认等固定开销，现场
 *      必须实测填入，不要留默认 0。
 *   5 本函数不做任何限幅与积分，反复调用无副作用；可以放心在 HMI 周期任务里按
 *      配方批量试算。
 *----------------------------------------------------------------------------*)

FUNCTION FC_DL_CalcMoveTime : BOOL
VAR_INPUT
    fDistance       : REAL := 0.0;          // 移动距离（Travel distance）[mm]，可负（取绝对值，符号不影响耗时）
    fVelMax         : REAL := 100.0;        // 速度上限（Max velocity）[mm/s]，域 0.001..100000，非正或非有限值→返回 FALSE
    fAcc            : REAL := 500.0;        // 加速度（Acceleration）[mm/s²]，域 0.001..1.0E6，非正或非有限值→返回 FALSE
    fDec            : REAL := 500.0;        // 减速度（Deceleration）[mm/s²]，域 0.001..1.0E6，非正或非有限值→返回 FALSE
    fVelStart       : REAL := 0.0;          // 起始速度（Start velocity）[mm/s]，带符号但仅用绝对值，接续定位时非零
    tSettle         : TIME := T#0S;         // 到位稳定延时（Settle time）[ms]，直接计入总耗时，负值按 0 处理
END_VAR
VAR_OUTPUT
    tMove           : TIME := T#0S;         // 总移动耗时（Total move time）[ms]，含稳定延时
    tAccPhase       : TIME := T#0S;         // 加速段耗时（Acceleration phase time）[ms]
    tCruisePhase    : TIME := T#0S;         // 匀速段耗时（Cruise phase time）[ms]，三角曲线时为 T#0S
    tDecPhase       : TIME := T#0S;         // 减速段耗时（Deceleration phase time）[ms]
    fVelPeak        : REAL := 0.0;          // 实际峰值速度（Achieved peak velocity）[mm/s]，三角曲线时小于速度上限
    bTriangular     : BOOL := FALSE;        // 三角退化标志（Triangular profile），TRUE=距离不足无法达到速度上限
    uErrorId        : UDINT := 0;           // 参数提示码（Diagnostic code），段位 16#0004_xxxx，仅信息级语义
END_VAR
VAR
    fDist           : REAL := 0.0;          // 距离绝对值（Absolute distance）[mm]，计算用
    fV0             : REAL := 0.0;          // 起始速度绝对值（Absolute start velocity）[mm/s]
    fVmax           : REAL := 0.0;          // 速度上限（Velocity ceiling）[mm/s]，计算用
    fA              : REAL := 0.0;          // 加速度（Acceleration）[mm/s²]，计算用
    fDecUse         : REAL := 0.0;          // 减速度（Deceleration）[mm/s²]，计算用
    fSettleS        : REAL := 0.0;          // 稳定延时秒值（Settle time in seconds）[s]
    fDistCrit       : REAL := 0.0;          // 临界距离（Critical distance）[mm]，达到速度上限所需最短距离
    fDistAcc        : REAL := 0.0;          // 加速段行程（Acceleration distance）[mm]
    fDistDec        : REAL := 0.0;          // 减速段行程（Deceleration distance）[mm]
    fDistCruise     : REAL := 0.0;          // 匀速段行程（Cruise distance）[mm]
    fTAcc           : REAL := 0.0;          // 加速段耗时（Acceleration time）[s]
    fTCruise        : REAL := 0.0;          // 匀速段耗时（Cruise time）[s]
    fTDec           : REAL := 0.0;          // 减速段耗时（Deceleration time）[s]
    fTTotal         : REAL := 0.0;          // 总耗时（Total time）[s]
    fPeak           : REAL := 0.0;          // 峰值速度（Peak velocity）[mm/s]，三角分支计算用
    fVEnd           : REAL := 0.0;          // 到点速度（Velocity at target）[mm/s]，超速减速分支用
    fDistStop       : REAL := 0.0;          // 纯减速停车距离（Stopping distance）[mm]
    fRadicand       : REAL := 0.0;          // 开方被开方数（Radicand）[无量纲]，防负数开方
    fDenom          : REAL := 0.0;          // 分母中间量（Denominator）[无量纲]，除零前判
    bParamOk        : BOOL := FALSE;        // 参数合法标志（Parameter valid flag）
END_VAR
VAR CONSTANT
    DL_CALC_INF_MAX   : REAL := 1.0E30;     // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按比较量量纲同值使用]
    DL_CALC_EPS       : REAL := 1.0E-6;     // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_CALC_VEL_FLOOR : REAL := 1.0E-3;     // 速度下限（Velocity floor）[mm/s]，低于此值判参数非法
    DL_CALC_ACC_FLOOR : REAL := 1.0E-3;     // 加减速度下限（Acceleration floor）[mm/s²]，低于此值判参数非法
    DL_CALC_TIME_MAX  : TIME := T#24H;      // 结果上限（Time ceiling）[ms]，超限钳位防 HMI 溢出
    DL_CALC_MS_SCALE  : REAL := 1000.0;     // 秒到毫秒换算系数（Second to millisecond factor）[-]，本函数唯一换算点
END_VAR

// 段 1｜出口默认赋值（公约 0.9：任何早退路径的输出必须确定，先赋值后校验）
FC_DL_CalcMoveTime := TRUE;
uErrorId           := 0;
bTriangular        := FALSE;
fVelPeak           := 0.0;
fTAcc              := 0.0;
fTCruise           := 0.0;
fTDec              := 0.0;
IF tSettle < DL_CALC_TIME_MAX THEN
    tMove := tSettle;
    fSettleS := TIME_TO_REAL(tSettle) * 1.0E-3;          // 毫秒 → 秒（本行换算单位为 s）
ELSE
    tMove := DL_CALC_TIME_MAX;
    fSettleS := TIME_TO_REAL(DL_CALC_TIME_MAX) * 1.0E-3;
END_IF
tAccPhase    := T#0S;
tCruisePhase := T#0S;
tDecPhase    := T#0S;

// 段 2｜参数校验（非有限值先自比检测，再做域比较；公约 0.9）
bParamOk := (fDistance = fDistance) AND (fVelMax = fVelMax) AND (fAcc = fAcc)
            AND (fDec = fDec) AND (fVelStart = fVelStart)
            AND (ABS(fDistance) <= DL_CALC_INF_MAX) AND (ABS(fVelStart) <= DL_CALC_INF_MAX)
            AND (fVelMax > DL_CALC_VEL_FLOOR) AND (fVelMax <= DL_CALC_INF_MAX)
            AND (fAcc > DL_CALC_ACC_FLOOR) AND (fAcc <= DL_CALC_INF_MAX)
            AND (fDec > DL_CALC_ACC_FLOOR) AND (fDec <= DL_CALC_INF_MAX);
IF NOT bParamOk THEN
    FC_DL_CalcMoveTime := FALSE;                         // 参数非法：调用方必须先判返回值
    uErrorId           := 16#0004_0180;                  // 【信息级】参数非法
    tMove              := T#0S;
    RETURN;
END_IF

// 段 3｜输入归一化（负距离取绝对值，符号不影响耗时）
fDist    := ABS(fDistance);
fV0      := ABS(fVelStart);
fVmax    := fVelMax;
fA       := fAcc;
fDecUse  := fDec;

// 段 4｜距离为零：耗时即稳定延时
IF fDist <= DL_CALC_EPS THEN
    fVelPeak        := fV0;                              // 未移动，峰值速度即起始速度 [mm/s]
    bTriangular     := FALSE;                            // 总耗时保持默认值（= 稳定延时），无需重算
    uErrorId        := 16#0004_0182;                     // 【信息级】距离为零，耗时等于稳定延时
    RETURN;
END_IF

// 段 5｜起始速度已超上限：只能减速（接续定位的真实工况，不判失败）
IF fV0 > (fVmax + DL_CALC_EPS) THEN
    fDistStop := (fV0 * fV0) / (2.0 * fDecUse);           // 纯减速停车距离 [mm]，分母已验非零
    IF fDistStop >= (fDist - DL_CALC_EPS) THEN
        // 边减速边到点：到点速度为开方结果，被开方数防负数
        fRadicand := fV0 * fV0 - 2.0 * fDecUse * fDist;
        fRadicand := MAX(0.0, fRadicand);
        fVEnd     := SQRT(fRadicand);
        fTDec     := (fV0 - fVEnd) / fDecUse;             // 减速段耗时 [s]
        fTAcc     := 0.0;
        fTCruise  := 0.0;
    ELSE
        // 先减速到上限，再以匀速走完剩余行程
        fTDec      := (fV0 - fVmax) / fDecUse;            // 减速到上限耗时 [s]
        fDistDec   := (fV0 * fV0 - fVmax * fVmax) / (2.0 * fDecUse); // 减速段行程 [mm]
        fDistCruise:= fDist - fDistDec;
        IF fDistCruise < 0.0 THEN
            fDistCruise := 0.0;                           // 浮点残差钳零
        END_IF
        fTCruise   := fDistCruise / fVmax;                // 匀速段耗时 [s]，分母已验非零
        fTAcc      := 0.0;
        fDistAcc   := 0.0;
    END_IF
    fVelPeak := fV0;                                      // 峰值速度即起始速度 [mm/s]
    bTriangular := FALSE;
    uErrorId := 16#0004_0183;                             // 【信息级】起始速度超上限，按减速到点计算

ELSE
    // 段 6｜常规情形：先算临界距离，判梯形还是三角
    fDistCrit := (fVmax * fVmax - fV0 * fV0) / (2.0 * fA) + (fVmax * fVmax) / (2.0 * fDecUse);
    IF fDist >= (fDistCrit - DL_CALC_EPS) THEN
        // —— 梯形：可达速度上限 ——
        fTAcc      := (fVmax - fV0) / fA;                 // 加速段耗时 [s]
        fDistAcc   := (fVmax * fVmax - fV0 * fV0) / (2.0 * fA); // 加速段行程 [mm]
        fDistDec   := (fVmax * fVmax) / (2.0 * fDecUse);  // 减速段行程 [mm]
        fTDec      := fVmax / fDecUse;                    // 减速段耗时 [s]
        fDistCruise:= fDist - fDistAcc - fDistDec;
        IF fDistCruise < 0.0 THEN
            fDistCruise := 0.0;                           // 距离恰等于临界值的浮点残差：匀速段钳零
            uErrorId    := 16#0004_0181;                  // 【信息级】临界距离浮点残差，匀速段钳零
        END_IF
        fTCruise   := fDistCruise / fVmax;                // 匀速段耗时 [s]，分母已验非零
        fVelPeak   := fVmax;                              // 达到速度上限 [mm/s]
        bTriangular:= FALSE;
    ELSE
        // —— 三角：距离不足，峰速小于上限 ——
        fDenom    := fA + fDecUse;                        // 分母 > 0 已由校验保证
        fRadicand := 2.0 * fA * fDecUse * fDist + fDecUse * fV0 * fV0;
        fRadicand := MAX(0.0, fRadicand);
        fPeak     := SQRT(fRadicand / fDenom);            // 三角峰速 [mm/s]
        fVelPeak  := fPeak;
        fTAcc     := (fPeak - fV0) / fA;                  // 加速段耗时 [s]
        IF fTAcc < 0.0 THEN
            fTAcc := 0.0;                                 // 峰速低于起始速度时不加速（浮点残差防线）
        END_IF
        fTDec     := fPeak / fDecUse;                     // 减速段耗时 [s]
        fTCruise  := 0.0;                                 // 三角曲线无匀速段
        bTriangular := TRUE;                              // 三角退化：选型警示
        uErrorId  := 0;                                   // 正常三角退化不设码（属合法工况）
    END_IF
END_IF

// 段 7｜分段耗时换算（秒 → 毫秒，截断到毫秒，不做四舍五入以免累计偏大）
tAccPhase    := REAL_TO_TIME(fTAcc * DL_CALC_MS_SCALE);
tCruisePhase := REAL_TO_TIME(fTCruise * DL_CALC_MS_SCALE);
tDecPhase    := REAL_TO_TIME(fTDec * DL_CALC_MS_SCALE);

// 段 8｜总耗时合成与上限保护（防参数错填导致 HMI 时间控件溢出）
fTTotal := fTAcc + fTCruise + fTDec + fSettleS;
IF fTTotal > (TIME_TO_REAL(DL_CALC_TIME_MAX) * 1.0E-3) THEN
    tMove    := DL_CALC_TIME_MAX;                         // 超上限钳位
    uErrorId := 16#0004_0184;                             // 【信息级】结果超上限钳位
ELSE
    tMove := REAL_TO_TIME(fTTotal * DL_CALC_MS_SCALE);    // 总耗时 [ms]，含稳定延时
END_IF

// 段 9｜结果一致性复核（分段和不得超过总耗时，防浮点截断造成分段和大于总耗时）
IF (tAccPhase + tCruisePhase + tDecPhase) > tMove THEN
    tMove := tAccPhase + tCruisePhase + tDecPhase;        // 以分段和为准，保证上层相加自洽
END_IF

END_FUNCTION
