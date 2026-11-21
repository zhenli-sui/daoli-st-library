(*==============================================================================
 * 组件名称 (Component)  : FB_DL_DualEdgeTrig
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.1
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 双边沿检测器。同一实例一次给出上升沿 / 下降沿 / 任意跳变
 *                         三种单扫描周期脉冲与当前电平，并累计上升/下降次数。
 *                         替代"一处用 R_TRIG、另一处用 NOT 取下降沿"的散乱写法，
 *                         统一多工位取沿的语义。计数器达上限后饱和停增并告警（不回绕）。
 * 开源溯源 (Origin)     : 原创实现。语义参照 IEC 61131-3 标准 R_TRIG 定义与
 *                         PLCopen Coding Guidelines 的单一事件源原则。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 计数饱和+首扫抑制
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无边沿无关状态机，见下）
 *                         R7 ✓ 三实例主体最前部无条件刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件不存在顺序状态机，仅为边沿锁存与计数，
 *                         无 CASE 可写；非法状态不可能出现（唯一状态即"运行"），
 *                         故以本节说明替代 ELSE 兜底，符合 R6"无状态机则标注 N/A"口径。
 * 修订历史 (Revision)   :
 *   2026-11-14  v1.0.0  首版入库（Phase 1 冷启动 · Level 0 批次）
 *   2026-11-14  v1.0.1  修复事件校正极性反接缺陷：上升/下降两路的事件
 *                       与"上一周期电平"的与项被写反，导致真实跳变周期被自身屏蔽、
 *                       两个事件输出恒为 FALSE（计数永不增长）。改为上升沿与
 *                       "上周期为低"相与、下降沿与"上周期为高"相与，与
 *                       bLastLevel 的更新时机（事件判定之后）保持一致。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_DualEdgeTrig
VAR_INPUT
    bSignal    : BOOL;            // 待检测信号，建议已消抖 / Signal to detect, pre-debounced recommended
    bEnable    : BOOL := TRUE;    // 使能标志，FALSE 时所有事件强制 FALSE / Enable flag, FALSE forces all events FALSE
    bReset     : BOOL;            // 复位信号，上升沿清零计数器并抑制当周期事件 / Reset, rising edge clears counters and suppresses events
END_VAR
VAR_OUTPUT
    bLevel     : BOOL;            // 当前电平，始终直通 / Current level, always pass-through
    bRising    : BOOL;            // 上升沿，单扫描周期脉冲 / Rising edge, one-scan pulse
    bFalling   : BOOL;            // 下降沿，单扫描周期脉冲 / Falling edge, one-scan pulse
    bChanged   : BOOL;            // 任意跳变 = 上升 OR 下降 / Any transition = rising OR falling
    uRiseCount : UDINT;           // 累计上升沿次数 / Accumulated rising edge count
    uFallCount : UDINT;           // 累计下降沿次数 / Accumulated falling edge count
    uErrorId   : UDINT;           // 故障码，仅计数器饱和告警 / Error code, counter saturation warning only
END_VAR
VAR
    fbTrigRise  : R_TRIG;         // 上升沿检测实例 / Rising edge detector instance
    fbTrigFall  : R_TRIG;         // 下降沿检测实例，输入取反信号 / Falling edge detector instance on inverted signal
    fbTrigReset : R_TRIG;         // 复位信号上升沿检测实例 / Reset rising edge detector instance
    bLastLevel  : BOOL;           // 上一周期电平，用于事件校正 / Previous level, used for event qualification
    bFirstScan  : BOOL := TRUE;   // 上电首扫标志，TRUE 期间抑制全部事件 / First-scan flag, suppresses all events while TRUE
END_VAR
VAR CONSTANT
    DL_EDGE_COUNT_MAX : UDINT := 16#FFFF_FFFE;  // 计数饱和上限，达上限停增不回绕 / Counter saturation limit, no wrap-around
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：三个 R_TRIG 实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *      下降沿走"取反信号"的对称路径，避免手写 IF NOT 分支时漏掉首扫抑制
 *-----------------------------------------------------------------------------*)
fbTrigRise(CLK := bSignal);
fbTrigFall(CLK := NOT bSignal);
fbTrigReset(CLK := bReset);

IF bFirstScan THEN
    (*--------------------------------------------------------------------------
     * 段 2｜上电首扫（边界 B2）：同步电平与历史电平，三类事件全部清零
     *      R_TRIG 首扫本身可能因 CLK 为 TRUE 而输出 Q，故必须显式抑制一周期
     *      First scan: synchronize levels and clear all events explicitly
     *-------------------------------------------------------------------------*)
    bLevel     := bSignal;
    bLastLevel := bSignal;
    bRising    := FALSE;
    bFalling   := FALSE;
    bChanged   := FALSE;
    bFirstScan := FALSE;
ELSE

    (* 段 3｜电平直通：使能关闭时电平仍必须真实反映输入（边界 B6） *)
    (* Level pass-through: level must stay truthful even when disabled (boundary B6) *)
    bLevel := bSignal;

    IF fbTrigReset.Q THEN
        (*----------------------------------------------------------------------
         * 段 4｜复位语义（边界 B5）：清计数、抑制当周期事件、同步历史电平
         *      Reset: clear counters, suppress current-scan events, resync last level
         *---------------------------------------------------------------------*)
        uRiseCount := 16#0000_0000;
        uFallCount := 16#0000_0000;
        uErrorId   := 16#0000_0000;
        bRising    := FALSE;
        bFalling   := FALSE;
    ELSE
        IF bEnable THEN
            (*------------------------------------------------------------------
             * 段 5｜事件判定（边界 B1/B3）：R_TRIG 的 Q 再与上一周期电平做校正
             *      校正的目的：实例被跨任务共享或重复调用时 bLastLevel 尚未建立，
             *      单靠 Q 会把"初始电平"误当成一次跳变
             *      Event qualification: Q is AND-ed with the previous level
             *      极性口径（v1.0.1 修正）：真实上升沿那一周期 bLastLevel 必为 FALSE，
             *      故上升沿与 NOT bLastLevel 相与；下降沿取反信号做 CLK，
             *      跳变周期 bLastLevel 必为 TRUE，故下降沿与 bLastLevel 相与。
             *      上一版两路极性接反，跳变周期被自身屏蔽，事件恒不成立。
             *      Polarity: a rise implies the previous level was low, and the
             *      falling path clocks on the inverted signal, so its previous
             *      level is high. v1.0.1 corrects the two qualifiers that were swapped.
             *-----------------------------------------------------------------*)
            bRising  := fbTrigRise.Q AND NOT bLastLevel;
            bFalling := fbTrigFall.Q AND bLastLevel;
        ELSE
            (* 使能关闭：事件全部清零，但历史电平在本段末尾继续跟踪（边界 B6） *)
            (* Disabled: clear all events, yet last level keeps tracking at the end of this block *)
            bRising  := FALSE;
            bFalling := FALSE;
        END_IF

        IF bRising THEN
            (*------------------------------------------------------------------
             * 段 6｜上升计数：饱和停增，禁止回绕归零（边界 B4）
             *      Rising count: saturate at limit, wrap-around is forbidden
             *-----------------------------------------------------------------*)
            IF uRiseCount < DL_EDGE_COUNT_MAX THEN
                uRiseCount := uRiseCount + 1;
            ELSE
                uErrorId := 16#0001_0007;
            END_IF
        END_IF

        IF bFalling THEN
            (*------------------------------------------------------------------
             * 段 7｜下降计数：与上升计数同一饱和策略，保证两路对称
             *      Falling count: identical saturation policy for symmetry
             *-----------------------------------------------------------------*)
            IF uFallCount < DL_EDGE_COUNT_MAX THEN
                uFallCount := uFallCount + 1;
            ELSE
                uErrorId := 16#0001_0007;
            END_IF
        END_IF
    END_IF

    (* 段 8｜跳变合成：bChanged 由两路事件或运算得到，天然互斥（边界 B3） *)
    (* Transition composition: bChanged is the OR of both events, mutually exclusive by nature *)
    bChanged := bRising OR bFalling;

    (* 段 9｜历史电平更新：必须放在事件判定之后，且禁用时也执行（边界 B6） *)
    (* Last level update: must follow event evaluation and also runs while disabled *)
    bLastLevel := bSignal;
END_IF
END_FUNCTION_BLOCK
