(*==============================================================================
 * 组件名称 (Component)  : FB_DL_RTrigEx
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG），零厂商方言
 * 功能描述 (Function)   : 上升沿检测防御包装。内部委托 IEC 61131-3 标准 R_TRIG
 *                         实例完成沿检测内核，外围统一首扫时序行为（首扫按 CLK
 *                         当前值建立基线、不产假边沿）并保证输出严格单拍。
 * 溯源     (Origin)     : IEC 61131-3 标准语义的道莅防御性实现
 *                         （接口语义由 IEC 61131-3 定义，clean-room 重写，
 *                         参考公开标准条款）
 * 码位     (Diag Codes) : 无错误码（纯语义包装，输入为单布尔量，无域可校验）
 *                         本件不占用 014D~015D / 0226~022B 任何码位
 * 类型裁定 (Type Note)  : 本件无诊断字引脚，错误码声明以本节替代
 * 依赖     (Depends)    : 无 DL_ 内部依赖；Standard.library: R_TRIG
 * 红线自检 (Redline)    : R1 ✓ 零全局变量与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 首扫不假触发+单拍输出
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A（无顺序状态机，见下）
 *                         R7 ✓ R_TRIG 实例主体无条件周期刷新
 * 说明     (Note)       : R6 标注 N/A —— 本组件为单步沿检测，不存在顺序状态机，
 *                         无 CASE 可写；非法状态不可能出现（唯一状态即"运行"），
 *                         故以本节说明替代 ELSE 兜底，符合"无状态机则标注 N/A"口径。
 * 防御行为声明 (Defense): ① 首扫不产假边沿：部分平台 R_TRIG 首扫在 CLK=TRUE 时会
 *                           输出 Q=TRUE（平台行为不一致），本件统一为首扫抑制一拍，
 *                           从第二拍起交付标准沿语义；
 *                         ② 单拍输出保证：bQ 仅在真实上升沿所在扫描周期为 TRUE，
 *                           下一拍自动归 FALSE（由内建 R_TRIG 语义保证）；
 *                         ③ 上电即处于 TRUE 的 CLK 不算沿（与"沿=跳变"定义一致）。
 * 修订历史 (Revision)   :
 *   2026-11-16  v1.0.0  首版入库（R14 批 1 · T0 快车道）
 *============================================================================*)
FUNCTION_BLOCK FB_DL_RTrigEx
VAR_INPUT
    bCLK : BOOL;  // 时钟输入，检测其低→高跳变 / Clock input, detects its low-to-high transition
END_VAR
VAR_OUTPUT
    bQ : BOOL;    // 单拍上升沿脉冲，仅在跳变所在扫描周期为 TRUE / One-scan rising-edge pulse, TRUE only on the scan of the transition
END_VAR
VAR
    fbTrig : R_TRIG;  // 内建上升沿检测实例，承担沿检测内核 / Built-in rising-edge instance, owns the edge-detection kernel
    xInit  : BOOL;    // 首扫初始化标志，FALSE=尚未完成上电初始化 / First-scan init flag, FALSE = power-on init not yet done
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜无条件刷新区（红线 R7）：R_TRIG 实例严禁进入任何 IF / CASE 分支
 *      Unconditional refresh zone (red line R7): no instance call inside IF / CASE
 *-----------------------------------------------------------------------------*)
fbTrig(CLK := bCLK);  // 每扫描周期无条件喂入时钟 / Feed clock unconditionally every scan

(*------------------------------------------------------------------------------
 * 段 2｜首扫初始化（历史教训⑤口径）：置于逻辑最前，首扫抑制内建实例输出一拍，
 *      统一各平台 R_TRIG 首扫行为差异
 *      First-scan init (lesson 5): placed at the very front; suppress the built-in
 *      output for one scan to unify cross-platform first-scan behavior
 *-----------------------------------------------------------------------------*)
IF NOT xInit THEN
    xInit := TRUE;   // 置初始化完成标志 / Mark init as done
    bQ    := FALSE;  // 首扫强制 FALSE，不产假边沿 / Force FALSE on first scan, no false edge
ELSE
    bQ := fbTrig.Q;  // 非首扫：直通内建沿检测输出（天然单拍）/ Non-first scan: pass through built-in edge output (single-scan by nature)
END_IF
END_FUNCTION_BLOCK
