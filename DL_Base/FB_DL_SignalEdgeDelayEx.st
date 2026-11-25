//==============================================================================
// 功能块：FB_DL_SignalEdgeDelayEx ｜ 中文名称：边沿延迟输出（升/降沿独立延迟窗）
// 所属子库：DL_Base ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯标准库 TON）
// 功能描述：上升沿与下降沿各自独立延迟窗：bOut = (bIn AND tonRise.Q) OR
//           ((NOT bIn) AND NOT tonFall.Q)。输入置 TRUE 后经 tDelayRise 才
//           输出 TRUE；输入撤 FALSE 后经 tDelayFall 才输出 FALSE。输出待决
//           方向分别经 bPendRise / bPendFall 声明（延迟窗内 TRUE，供上层
//           做"已下令未生效"诊断）。
//           分工声明：与 FB_DL_PulseStretch（单脉冲展宽）及 TpRetrigger 族
//           互引——那两件做脉冲生成/展宽，本件只做电平沿延迟，互不替代；
//           与候选队列 FT_IMP（脉冲保持）同属脉冲定时族，本件取其"沿触发
//           电平保持"行为定义分类，不取其单脉冲语义。
// 开源溯源 (Origin)：候选队列 FT_IMP（oscatBasic，MIT 许可，
//           https://github.com/tkucic/brOscatLib/blob/main/oscatBasic/FT_IMP.st）
//           ——脉冲定时族行为定义分类参考；原名 FT_IMP → 道莅
//           FB_DL_SignalEdgeDelayEx，clean-room 独立重写（双沿独立延迟窗
//           为道莅增量，零源码行复制）
// 公开接口清单：输入 bIn / tDelayRise / tDelayFall；输出 bOut / bPendRise /
//               bPendFall / bValid
// 单位表：tDelayRise / tDelayFall [ms]，其余 BOOL 引脚无量纲
// 输入契约：bIn 为待整形原始电平；双窗参数允许为 0（对应方向直通）。
// 输出契约：bOut 为延迟后电平；bPendRise/bPendFall 为窗内瞬时待决声明
//           （每拍重算不锁存）；bValid 恒 TRUE（纯定时组合无故障级条件）。
// 错误码表：无状态机码轨（纯定时组合无故障级条件），不占用 16#0001 段码位
// 状态机：N/A（无状态机；TON ×2 每拍无条件刷新）
// 边界行为：① tDelayRise / tDelayFall 可为 0（直通，无延迟窗）；
//           ② TON 每拍无条件刷新（不入分支，红线 R7）；
//           ③ 延迟窗内撤使能无独立引脚——本件无使能门（纯信号整形件，
//             上层如需门控请在 bIn 前级串门）；
//           ④ 待决声明为窗内瞬时量，每拍重算不锁存。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 14）
//==============================================================================

(*==============================================================================
 * 功能块: FB_DL_SignalEdgeDelayEx
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于 TON 实例。
 * 调用示例: edgeDelay(bIn := bRawSig, tDelayRise := T#500MS,
 *                     tDelayFall := T#200MS);
 *          bOut 替代原信号进下游判据；bPendRise/bPendFall 送上位诊断。
 * 组装说明: ① 本件无使能门，如需条件化整形请在 bIn 前级串门控合取；
 *           ② 双窗独立：tDelayRise 只作用于 TRUE 建立方向，tDelayFall
 *             只作用于 FALSE 建立方向，互不干扰；
 *           ③ 与 FB_DL_PulseStretch 分工：展宽/单脉冲用那件，电平沿
 *             延迟用本件（头注释分工声明已互引）。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_SignalEdgeDelayEx
VAR_INPUT
    bIn        : BOOL := FALSE;        // 输入信号 [—] / Input signal
    tDelayRise : TIME := T#0MS;        // 上升沿延迟窗 [ms] / Rise delay window [ms]
    tDelayFall : TIME := T#0MS;        // 下降沿延迟窗 [ms] / Fall delay window [ms]
END_VAR
VAR_OUTPUT
    bOut       : BOOL;                 // 延迟后输出 [—] / Delayed output
    bPendRise  : BOOL;                 // 上升待决声明（输入 TRUE 但窗未满）/ Rise pending, input TRUE but window open
    bPendFall  : BOOL;                 // 下降待决声明（输入 FALSE 但窗未满）/ Fall pending, input FALSE but window open
    bValid     : BOOL;                 // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonRise    : TON;                  // 上升沿延迟定时器，每拍无条件刷新 / Rise delay timer, refreshed every scan
    tonFall    : TON;                  // 下降沿延迟定时器，每拍无条件刷新 / Fall delay timer, refreshed every scan
END_VAR

// ---- 段 1｜定时器无条件刷新（红线 R7：禁入条件分支）----
tonRise(IN := bIn,  PT := tDelayRise); // 上升窗计时随输入断续 / Rise timer input follows the signal
tonFall(IN := NOT bIn, PT := tDelayFall); // 下降窗计时随输入反相断续 / Fall timer input follows the inverted signal

// ---- 段 2｜输出主体：双沿门控合成（升沿等 tonRise.Q，降沿借 tonFall 未满）----
bOut := (bIn AND tonRise.Q) OR ((NOT bIn) AND (NOT tonFall.Q)); // 双沿独立延迟合成 / Dual-edge independent delay blend

// ---- 段 3｜待决声明：窗内瞬时量每拍重算（诊断用，不锁存）----
bPendRise := bIn AND (NOT tonRise.Q); // 上升窗未满待决 / Rise pending while window open
bPendFall := (NOT bIn) AND (NOT tonFall.Q); // 下降窗未满待决 / Fall pending while window open
bValid := TRUE;                       // 纯定时组合恒可用 / Pure timing combinational, always usable
END_FUNCTION_BLOCK