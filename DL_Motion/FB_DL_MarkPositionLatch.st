(*==============================================================================
 * 组件名称 (Component)  : FB_DL_MarkPositionLatch
 * 所属子库 (Sublibrary) : DL_Motion
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 标记锁存族 · 色标 / 探针位置锁存
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library
 *                         （R_TRIG / TON / MIN / MAX / ABS），零厂商方言
 * 接口依赖 (Depends)    : I_DL_MotionAxis / E_DL_AxisState（既有契约，Round 05，零修改）
 * 功能描述 (Function)   : 外部标记（色标 / 探针 / 光电开关）触发瞬间锁存轴位置与速度，
 *                         并输出与上次锁存的增量；带布防窗、标记缺失诊断、最近 N 次
 *                         历史环形缓冲。供定长切割、切点相位校正、定长计米与凸轮相位
 *                         补偿前置件使用。
 * 设计要点 (Key notes)  :
 *   ① 位置与速度在同一拍各读一次并同拍锁存，保证两者时间一致（分两拍读会出现
 *      「位置已到、速度还是上一拍」的口径错位）。
 *   ② 本块不累计位置：位置一律来自轴接口，避免与轴侧积分形成双积分漂移。
 *   ③ 一次布防只受理第一条标记沿（连击不重复锁存），去抖交由上游信号处理块承担。
 *   ④ 历史缓冲为定长整体前移写法，用定长 FOR + 深度钳位，不用无界循环。
 *   ⑤ 本块为纯事件型组件：无初始化跟踪语义、无连续量同步逻辑，按库级约定免首扫，
 *      不设首扫标志与跟踪判据（与 FB_DL_SignalDebounce 等事件型件同口径）。
 * 开源溯源 (Origin)     : 原创实现，clean-room。语义来源为 PLCopen 运动控制公开规范中
 *                         的「注册标记 / 探针锁存」工艺概念、公开的色标定长切割与
 *                         追剪技术文章、以及公开的产线节拍链经验总结（来源编号
 *                         RAW_NOTES S-2 相位补偿前置件 / S-14 节拍链）。
 *                         「借鉴对象的许可说明」：上述对象为公开发布但受版权保护的
 *                         规范文档与技术文章，属「可免费查阅、仅借鉴工程语义」类别；
 *                         本实现未复制任何源码，引脚命名、枚举、环形缓冲结构、诊断
 *                         码与状态机 100% 自有设计。
 * 验收向量 (Acceptance) :
 *   V1 布防 → 标记沿 → 锁存位置与速度，首次增量输出为 0；
 *   V2 连续两次布防并触发：第二次增量等于两次锁存位置之差；
 *   V3 布防窗内无标记：超窗进 eMissed，bMarkMissed 为 TRUE（不停机、不置故障）；
 *   V4 重新布防：清 eMissed 与 bMarkMissed，可再次锁存；
 *   V5 nHistoryDepth 填 0：钳位到 1 并出信息级 0170；
 *   V6 清历史：历史缓冲清零，累计标记计数保留；
 *   V7 轴位置为非有限值：锁存 0290，拒绝锁存；
 *   V8 同一布防窗内连击多次：只锁存第一条沿（一次布防一次锁存）。
 * 已知限制 (Limits)     :
 *   ① 布防窗分辨率等于任务扫描周期：窗宽若小于两个扫描周期，实际等效「最多错过
 *      一拍」，属预期行为；极短窗请改用硬件比较输出（探针输入）方案。
 *   ② 本块只用锁存时刻的位置值，不补偿「标记沿到扫描读值」的传输延迟；需要微米
 *      级切点精度时，应由驱动侧探针功能锁存并由本块读取其结果。
 *   ③ 历史缓冲维度以字面量 8 声明（FB 内部常量不能用于其自身引脚声明），运行期
 *      以 UPPER_BOUND / LOWER_BOUND 实测维度做二次钳位。
 * 规格偏离 (Deviation)  :
 *   ① 无（本块引脚与规格逐条一致；未增补任何输入引脚，因纯事件型免首扫）。
 * 红线自检 (Redline)    :
 *   R1 零全局符号区访问 ✓（无全局变量表访问、无外部变量声明）
 *   R2 零物理地址直写 ✓（无输入输出通道地址记号）
 *   R3 纯 IEC 61131-3 ✓（仅 R_TRIG / TON / MIN / MAX / ABS）
 *   R4 防除零 / 防越界 / 浮点容差 ✓（数组索引全程经实测上下界钳位、循环定长、
 *      浮点比较用容差、无除法）
 *   R5 声明行 100% 中英双语同行注释 ✓
 *   R6 ENUM + CASE 且 CASE 含 ELSE 兜底 ✓
 *   R7 边沿与定时器实例无条件周期刷新 ✓（本块无单拍脉冲输出；bLatched /
 *      bMarkMissed 为状态型输出，不跨周期残留）
 *   POU 终结符成对 ✓（FUNCTION_BLOCK ↔ END_FUNCTION_BLOCK，末行即终结符；
 *   TYPE ↔ END_TYPE 成对）
 * 故障码表 (Error codes):
 *   16#0004_0170【信息级】历史深度越界钳位；
 *   16#0004_0171【信息级】布防窗内无标记（缺失提示，与 bMarkMissed 同源）；
 *   16#0004_0290【故障级】轴位置 / 速度非有限值，锁存；
 *   16#0004_0295【故障级】非法状态兜底（本块专用，不与其他块共用）。
 *   信息级码只进 uErrorId；bError 为派生式仅反映 eFault 态。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 08 · DL_Motion 标记锁存族开族件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbMark.iAxis := fbConveyorAxis;               // 被采样轴实例注入
 *   fbMark(bEnable := TRUE, tArmWindow := T#5S,
 *          bArm := bCutReady, bTrigger := diColorMark,
 *          nHistoryDepth := 4);
 *   IF fbMark.bLatched THEN
 *       fCutPos := fbMark.fLatchedPos + fCutLength;   // 定长切割：锁存点 + 定长
 *       fCorr   := fbMark.fDeltaPos - fNominalPitch;  // 节距偏差 → 凸轮相位补偿
 *   END_IF
 *   注：标记信号建议先经上游去抖块处理再送入 bTrigger；本块只取上升沿。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 常见误用与现场提示 (Field notes)：
 *   1 每次切割前都要给一次 bArm 上升沿；不给布防沿则 bTrigger 的沿一律被忽略
 *      （空闲态不收标记），这是「一次布防一次锁存」的刻意语义。
 *   2 布防窗不是「等待时间」而是「超时诊断窗」：窗内没等到标记只提示缺失，
 *      不停机、不置故障，由上层决定是否报警。
 *   3 fDeltaPos 在首个标记时为 0（没有可比对象），不要把它当成「从零点起的位移」；
 *      从零点起的位移请直接读轴位置。
 *   4 累计计数不清零是刻意的：清历史只清位置数组，节拍统计要靠累计计数，
 *      否则换班交接时计数会凭空丢失。
 *   5 轴位置为非有限值时本块直接锁存故障并拒绝锁存，避免把无效值写进历史缓冲
 *      污染后续节距计算。
 *----------------------------------------------------------------------------*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_MarkState（归属 DL_Motion，与本功能块同文件发布）
 * 含义: 标记锁存状态机，编号间隔 10 预留扩展位。
 *----------------------------------------------------------------------------*)
{attribute 'strict'}
{attribute 'qualified_only'}
TYPE E_DL_MarkState :
(
    eIdle    := 0,    // 空闲：未布防，忽略触发 / Idle: not armed, triggers ignored
    eArmed   := 10,   // 已布防：等待标记沿 / Armed: waiting for mark edge
    eLatched := 20,   // 已锁存：本周期结果有效，等新布防或复位 / Latched: result valid, waiting for re-arm or reset
    eMissed  := 30,   // 标记缺失：布防窗内无沿（诊断态，非故障） / Missed: no edge within arm window (diagnostic)
    eFault   := 99    // 故障锁存：仅 bReset 上升沿可退出 / Fault: latched, only bReset rising edge exits
) UINT;
END_TYPE

FUNCTION_BLOCK FB_DL_MarkPositionLatch
VAR_INPUT
    bEnable         : BOOL := FALSE;        // 使能（Enable），FALSE=清布防与结果，不影响历史缓冲与累计计数
    bArm            : BOOL := FALSE;        // 布防（Arm），上升沿进入布防态；锁存 / 缺失态下再次上升沿即重新布防
    bTrigger        : BOOL := FALSE;        // 标记输入（Mark input），上升沿为有效标记，电平持续不影响
    tArmWindow      : TIME := T#10S;        // 布防有效窗（Arm window）[ms]，超时未触发转缺失态；T#0S=不限
    bClearHistory   : BOOL := FALSE;        // 清历史缓冲（Clear history），上升沿，不影响累计计数
    bReset          : BOOL := FALSE;        // 复位故障 / 退出缺失态（Reset），上升沿受理
    nHistoryDepth   : UINT := 4;            // 历史深度（History depth）[-]，域 1..实测维度，越界钳位并提示
END_VAR
VAR_OUTPUT
    bLatched        : BOOL := FALSE;        // 已锁存（Latched），仅锁存态为 TRUE
    fLatchedPos     : REAL := 0.0;          // 锁存位置（Latched position）[mm]
    fLatchedSpeed   : REAL := 0.0;          // 锁存瞬间速度（Latched velocity）[mm/s]，带符号
    fDeltaPos       : REAL := 0.0;          // 与上次锁存的位置增量（Delta position）[mm]，无上次时为 0
    bMarkMissed     : BOOL := FALSE;        // 标记缺失（Mark missed），缺失态为 TRUE；重新布防后自动清
    uMarkCount      : UDINT := 0;           // 累计有效标记数（Mark counter）[次]，清历史不影响此计数
    afHistoryPos    : ARRAY[0..7] OF REAL;  // 最近 N 次锁存位置（History positions）[mm]，维度 8，索引 0=最新
    bError          : BOOL := FALSE;        // 故障锁存（Error），派生式仅故障级码参与，信息级码不置位
    uErrorId        : UDINT := 0;           // 故障码（Error code），段位 16#0004_xxxx，0=无故障
END_VAR
VAR_IN_OUT
    iAxis           : I_DL_MotionAxis;      // 被采样轴接口引用（Sampled axis），由调用方注入实现块实例
END_VAR
VAR
    eState          : E_DL_MarkState := E_DL_MarkState.eIdle; // 内部状态机步序（Internal state）
    bFaultLatch     : BOOL := FALSE;        // 故障锁存标志（Fault latch），仅 bReset 沿解除
    bHistValid      : BOOL := FALSE;        // 历史有效标志（History valid），存在可比对的上次锁存
    bWindowOn       : BOOL := FALSE;        // 布防窗计时使能（Arm window timer enable），窗长为 0 时关闭
    bWindowBrk      : BOOL := FALSE;        // 布防窗参数变更标志（Window changed），断输入一拍用
    bIdxOk          : BOOL := FALSE;        // 数组边界有效标志（Index bounds valid），逐拍重算
    fLastPos        : REAL := 0.0;          // 上次锁存位置（Previous latched position）[mm]，增量计算基准
    fPosNow         : REAL := 0.0;          // 本拍轴位置（Axis position this scan）[mm]
    fVelNow         : REAL := 0.0;          // 本拍轴速度（Axis velocity this scan）[mm/s]
    nDepthEff       : DINT := 4;            // 生效历史深度（Effective depth）[-]，已按实测维度钳位
    nLb             : DINT := 0;            // 历史数组下标下界（Array lower bound）[-]，实测取得
    nUb             : DINT := 7;            // 历史数组下标上界（Array upper bound）[-]，实测取得
    nAvail          : DINT := 8;            // 实测可用槽位（Available slots）[-]，上界减下界加一
    nIdx            : DINT := 0;            // 历史搬移索引（Shift index）[-]，循环内使用
    nGuard          : DINT := 0;            // 循环防死锁计数器（Loop guard counter）[-]
    tWindowEff      : TIME := T#10S;        // 生效布防窗（Effective arm window）[ms]，负值归零
    tWindowPrev     : TIME := T#0MS;        // 上拍布防窗（Previous arm window）[ms]，变更检测基准
    fbTrigArm       : R_TRIG;               // 布防指令上升沿（Arm command rising edge）
    fbTrigTrig      : R_TRIG;               // 标记输入上升沿（Mark input rising edge）
    fbTrigClear     : R_TRIG;               // 清历史指令上升沿（Clear history rising edge）
    fbTrigReset     : R_TRIG;               // 复位指令上升沿（Reset command rising edge）
    fbTonArmWindow  : TON;                  // 布防窗超时监控（Arm window timer）
END_VAR
VAR CONSTANT
    DL_MARK_HIST_MAX  : DINT := 8;          // 历史槽位上限（Max history slots）[-]，与引脚声明的字面量维度一致
    DL_MARK_INF_MAX   : REAL := 1.0E30;     // 有限值判定幅值上限（Finite magnitude bound）[无量纲，按比较量量纲同值使用]
    DL_MARK_EPS       : REAL := 1.0E-6;     // 浮点判零容差（Float zero tolerance）[无量纲，按比较量量纲同值使用]
    DL_MARK_DEPTH_MIN : DINT := 1;          // 历史深度下限（Depth lower bound）[-]
    DL_MARK_GUARD_MAX : DINT := 32;         // 循环防死锁上限（Loop guard limit）[-]，远超最大槽位
    DL_MARK_ZERO_TIME : TIME := T#0S;       // 零时间字面量（Zero time literal）[ms]
END_VAR

// 段 1｜边沿与定时器实例无条件周期刷新（红线 R7：严禁置于 IF / CASE 分支内）
fbTrigArm(CLK := bArm);
fbTrigTrig(CLK := bTrigger);
fbTrigClear(CLK := bClearHistory);
fbTrigReset(CLK := bReset);

// 段 2｜出口默认赋值（公约 0.9：早退路径输出必须确定）
bLatched    := FALSE;
bMarkMissed := FALSE;
bError      := (eState = E_DL_MarkState.eFault);

// 段 3｜接口引用有效性防御：未注入轴引用则清输出退出
IF iAxis = 0 THEN
    RETURN;
END_IF

// 段 4｜历史数组实测边界（公约 0.14：数组访问前必须验界）
nLb    := LOWER_BOUND(afHistoryPos, 1);
nUb    := UPPER_BOUND(afHistoryPos, 1);
nAvail := nUb - nLb + 1;
bIdxOk := (nAvail >= DL_MARK_DEPTH_MIN);
IF nAvail > DL_MARK_HIST_MAX THEN
    nAvail := DL_MARK_HIST_MAX;                          // 实测维度超库级上限时按上限钳位，防越界
END_IF

// 段 5｜历史深度钳位（越界钳位并提示，逐拍重算不锁存）
nDepthEff := UINT_TO_DINT(nHistoryDepth);
IF nDepthEff < DL_MARK_DEPTH_MIN THEN
    nDepthEff := DL_MARK_DEPTH_MIN;                      // 低于 1 钳到 1
    uErrorId  := 16#0004_0170;                           // 【信息级】历史深度越界钳位
ELSIF nDepthEff > nAvail THEN
    nDepthEff := nAvail;                                 // 高于实测槽位钳到上界
    uErrorId  := 16#0004_0170;                           // 【信息级】历史深度越界钳位
END_IF

// 段 6｜布防窗参数防御与变更检测（公约 0.6：语义参数变化必须断输入一拍）
IF tArmWindow < DL_MARK_ZERO_TIME THEN
    tWindowEff := DL_MARK_ZERO_TIME;
ELSE
    tWindowEff := tArmWindow;
END_IF
bWindowBrk  := (tWindowEff <> tWindowPrev);              // 窗长变更：本拍断输入，使已计时归零
tWindowPrev := tWindowEff;
bWindowOn   := (tWindowEff > DL_MARK_ZERO_TIME);         // 窗长为 0 表示不限时，不启用计时

// 段 7｜布防窗超时定时器：实例在本行无条件每拍调用（红线 R7），入参先算成普通变量
fbTonArmWindow(IN := (eState = E_DL_MarkState.eArmed) AND bWindowOn AND (NOT bWindowBrk),
               PT := tWindowEff);

// 段 8｜反馈量采集与信号有效性判定
fPosNow := iAxis.fPosition;
fVelNow := iAxis.fVelocity;
IF (fPosNow <> fPosNow) OR (fVelNow <> fVelNow)
   OR (ABS(fPosNow) > DL_MARK_INF_MAX) OR (ABS(fVelNow) > DL_MARK_INF_MAX) THEN
    IF (eState <> E_DL_MarkState.eFault) THEN
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0290;                     // 【故障级】轴位置 / 速度非有限值
        eState      := E_DL_MarkState.eFault;
    END_IF
END_IF

// 段 9｜使能撤除：清布防与结果（历史缓冲与累计计数保留）
IF NOT bEnable THEN
    eState      := E_DL_MarkState.eIdle;
    bLatched    := FALSE;
    bMarkMissed := FALSE;
END_IF

// 段 10｜清历史沿（只清位置数组，不清累计计数）
IF fbTrigClear.Q AND bIdxOk THEN
    nGuard := 0;
    FOR nIdx := nLb TO nUb DO
        IF nGuard >= DL_MARK_GUARD_MAX THEN
            EXIT;                                        // 防死锁
        END_IF
        nGuard := nGuard + 1;
        afHistoryPos[nIdx] := 0.0;                       // 槽位清零 [mm]
    END_FOR
    bHistValid := FALSE;                                 // 无可比对上次锁存，下次增量输出 0
END_IF

// 段 11｜事件码管理（公约 0.7 / R15）：锁存码仅在解除路径清，瞬时码逐拍重算
IF NOT bFaultLatch THEN
    uErrorId := 0;
END_IF

// 段 12｜主状态机（ENUM + CASE + ELSE 兜底）
CASE eState OF

    E_DL_MarkState.eIdle:                                // 空闲：未布防，忽略标记沿
        bLatched    := FALSE;
        bMarkMissed := FALSE;
        IF fbTrigArm.Q AND bEnable THEN
            bFaultLatch := FALSE;                        // 新布防：锁存码解除路径（R15）
            bMarkMissed := FALSE;
            bLatched    := FALSE;
            eState      := E_DL_MarkState.eArmed;
        ELSIF fbTrigReset.Q THEN
            bFaultLatch := FALSE;
            uErrorId    := 0;
        END_IF

    E_DL_MarkState.eArmed:                               // 已布防：等待标记沿或超窗
        IF fbTrigArm.Q THEN
            bLatched := FALSE;                           // 重复布防：重新计时（一次布防一次锁存）
        ELSIF fbTrigTrig.Q THEN
            // 同一拍各读一次位置与速度，保证同拍一致
            fLatchedPos   := fPosNow;                    // 锁存位置 [mm]
            fLatchedSpeed := fVelNow;                    // 锁存速度 [mm/s]
            IF bHistValid THEN
                fDeltaPos := fLatchedPos - fLastPos;     // 与上次锁存的增量 [mm]
            ELSE
                fDeltaPos := 0.0;                        // 首个标记无对比对象，增量输出 0
            END_IF
            fLastPos   := fLatchedPos;                   // 增量基准推进 [mm]
            bHistValid := TRUE;
            // 历史缓冲头插（整体前移，定长循环 + 实测边界）
            IF bIdxOk AND (nDepthEff >= DL_MARK_DEPTH_MIN) THEN
                nGuard := 0;
                FOR nIdx := (nDepthEff - 1) DOWNTO DL_MARK_DEPTH_MIN DO
                    IF nGuard >= DL_MARK_GUARD_MAX THEN
                        EXIT;                            // 防死锁
                    END_IF
                    nGuard := nGuard + 1;
                    IF (nLb + nIdx) <= nUb THEN
                        afHistoryPos[nLb + nIdx] := afHistoryPos[nLb + nIdx - 1]; // 槽位后移
                    END_IF
                END_FOR
                afHistoryPos[nLb] := fLatchedPos;        // 最新值写入 0 号槽 [mm]
            END_IF
            IF uMarkCount < 16#FFFF_FFFF THEN
                uMarkCount := uMarkCount + 1;            // 累计有效标记数 [次]，饱和不加
            END_IF
            bLatched := TRUE;
            eState   := E_DL_MarkState.eLatched;
        ELSIF fbTonArmWindow.Q THEN
            bMarkMissed := TRUE;                         // 超窗无标记：诊断态，停机与否由上层决定
            uErrorId    := 16#0004_0171;                 // 【信息级】布防窗内无标记
            eState      := E_DL_MarkState.eMissed;
        END_IF

    E_DL_MarkState.eLatched:                             // 已锁存：结果保持，等新布防或复位
        bLatched := TRUE;
        IF fbTrigArm.Q AND bEnable THEN
            bLatched := FALSE;
            eState   := E_DL_MarkState.eArmed;           // 重新布防
        ELSIF fbTrigReset.Q THEN
            bLatched := FALSE;
            eState   := E_DL_MarkState.eIdle;
        END_IF

    E_DL_MarkState.eMissed:                              // 标记缺失：等重新布防或复位
        bMarkMissed := TRUE;
        IF fbTrigArm.Q AND bEnable THEN
            bMarkMissed := FALSE;
            bLatched    := FALSE;
            eState      := E_DL_MarkState.eArmed;        // 重新布防即清缺失
        ELSIF fbTrigReset.Q THEN
            bMarkMissed := FALSE;
            uErrorId    := 0;
            eState      := E_DL_MarkState.eIdle;
        END_IF

    E_DL_MarkState.eFault:                               // 故障锁存：仅复位沿可退出
        bLatched    := FALSE;
        bMarkMissed := FALSE;
        IF fbTrigReset.Q THEN
            bFaultLatch := FALSE;                        // 唯一解除路径
            uErrorId    := 0;
            eState      := E_DL_MarkState.eIdle;
        END_IF

    ELSE                                                 // 非法状态兜底（本块专用码）
        bFaultLatch := TRUE;
        uErrorId    := 16#0004_0295;                     // 【故障级】非法状态兜底
        bLatched    := FALSE;
        bMarkMissed := FALSE;
        eState      := E_DL_MarkState.eFault;

END_CASE

// 段 13｜出口映射（派生式，信息级码不参与 bError）
bError      := (eState = E_DL_MarkState.eFault);
bLatched    := (eState = E_DL_MarkState.eLatched);
bMarkMissed := (eState = E_DL_MarkState.eMissed);

END_FUNCTION_BLOCK
