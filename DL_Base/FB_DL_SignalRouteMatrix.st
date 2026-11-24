//==============================================================================
// 功能块：FB_DL_SignalRouteMatrix ｜ 中文名称：2×N 可组态信号路由矩阵
// 所属子库：DL_Base ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3，零方言）
// 功能描述：2 源 × 4 通道可组态路由矩阵：每通道独立使能 + 来源选择（源 A /
//           源 B / 空置），输出 = 使能 AND 所选源。断源哨兵：存在"通道使能
//           且已选源"但其源信号为 FALSE 时置该源断源哨兵位（正常传递同时
//           留痕，供上层诊断区分"真信号 FALSE"与"通道空置 FALSE"）。
// 开源溯源 (Origin)：原创实现（t2-1-lgf-bitlogic 位逻辑语义深化，零外部源码
//           行，clean-room 独立编写）
// 公开接口清单：输入 aSrcA / aSrcB / {bEnCh1..4, eSelCh1..4}；
//               输出 {bOutCh1..4} / bSrcALost / bSrcBLost / bValid
// 错误码表：无状态机码轨（组合路由无故障级条件）；断源诊断经
//           bSrcALost / bSrcBLost 哨兵位表达，不占用 16#0001 段码位
// 状态机：E_DL_RouteSel（本文件唯一定义，全库唯一属主）：
//           eNone = 0 / eSrcA = 1 / eSrcB = 2；非法选择值走 CASE ELSE 兜底
//           （输出 FALSE 安全侧 + 声明哨兵）
// 边界行为：① 空置通道输出恒 FALSE 且不计入断源哨兵；
//           ② 断源哨兵不屏蔽输出（传递与诊断解耦）；
//           ③ 无定时器/沿实例（纯组合逻辑，无周期刷新义务）；
//           ④ CASE 带 ELSE 非法选择值兜底（输出 FALSE 安全侧）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 13）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RouteSel（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 通道来源选择，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RouteSel :
(
    eNone := 0,    // 空置：通道不选源，输出恒 FALSE / Idle, no source selected
    eSrcA := 1,    // 选源 A / Source A selected
    eSrcB := 2     // 选源 B / Source B selected
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SignalRouteMatrix
 * 调用约定: 每个扫描周期无条件调用一次；纯组合路由，无跨拍驻留状态。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_SignalRouteMatrix
VAR_INPUT
    aSrcA   : BOOL := FALSE;           // 源 A 信号 [—] / Source A signal
    aSrcB   : BOOL := FALSE;           // 源 B 信号 [—] / Source B signal
    bEnCh1  : BOOL := FALSE;           // 通道 1 使能 / Channel 1 enable
    eSelCh1 : E_DL_RouteSel := E_DL_RouteSel.eNone; // 通道 1 来源选择 / Channel 1 source select
    bEnCh2  : BOOL := FALSE;           // 通道 2 使能 / Channel 2 enable
    eSelCh2 : E_DL_RouteSel := E_DL_RouteSel.eNone; // 通道 2 来源选择 / Channel 2 source select
    bEnCh3  : BOOL := FALSE;           // 通道 3 使能 / Channel 3 enable
    eSelCh3 : E_DL_RouteSel := E_DL_RouteSel.eNone; // 通道 3 来源选择 / Channel 3 source select
    bEnCh4  : BOOL := FALSE;           // 通道 4 使能 / Channel 4 enable
    eSelCh4 : E_DL_RouteSel := E_DL_RouteSel.eNone; // 通道 4 来源选择 / Channel 4 source select
END_VAR
VAR_OUTPUT
    bOutCh1 : BOOL;                    // 通道 1 路由输出 / Channel 1 routed output
    bOutCh2 : BOOL;                    // 通道 2 路由输出 / Channel 2 routed output
    bOutCh3 : BOOL;                    // 通道 3 路由输出 / Channel 3 routed output
    bOutCh4 : BOOL;                    // 通道 4 路由输出 / Channel 4 routed output
    bSrcALost : BOOL;                  // 断源哨兵：有通道选 A 但源 A 为 FALSE / Source-A lost sentinel
    bSrcBLost : BOOL;                  // 断源哨兵：有通道选 B 但源 B 为 FALSE / Source-B lost sentinel
    bValid  : BOOL;                    // 输出可用标志 / Outputs usable flag
END_VAR

// ---- 段 0｜出口默认值：哨兵每拍重算（组合诊断位不锁存）----
bSrcALost := FALSE;                   // 源 A 断源哨兵先清零 / Source-A lost sentinel cleared first
bSrcBLost := FALSE;                   // 源 B 断源哨兵先清零 / Source-B lost sentinel cleared first
bValid    := TRUE;                    // 可用标志默认 TRUE / Usable flag preset TRUE

// ---- 段 1｜通道 1/2 路由（CASE 带 ELSE；空置与非法值安全侧输出 FALSE）----
CASE eSelCh1 OF                       // 通道 1 来源判决 / Channel 1 source decision
    E_DL_RouteSel.eNone:               // 空置：输出 FALSE，不计哨兵 / Idle, FALSE, no sentinel
        bOutCh1 := FALSE;              // 通道 1 输出 / Channel 1 output
    E_DL_RouteSel.eSrcA:               // 选源 A：使能闸 + 断源哨兵留痕 / Source A, enable gate plus lost sentinel
        bOutCh1 := bEnCh1 AND aSrcA;   // 通道 1 输出 / Channel 1 output
        bSrcALost := bSrcALost OR (bEnCh1 AND NOT aSrcA); // 断源哨兵累积 / Lost sentinel accumulate
    E_DL_RouteSel.eSrcB:               // 选源 B：使能闸 + 断源哨兵留痕 / Source B, enable gate plus lost sentinel
        bOutCh1 := bEnCh1 AND aSrcB;   // 通道 1 输出 / Channel 1 output
        bSrcBLost := bSrcBLost OR (bEnCh1 AND NOT aSrcB); // 断源哨兵累积 / Lost sentinel accumulate
    ELSE                               // 非法选择值兜底（R21：CASE 必带 ELSE）
        bOutCh1 := FALSE;              // 安全侧输出 FALSE / Safe-side FALSE output
END_CASE
CASE eSelCh2 OF                       // 通道 2 来源判决 / Channel 2 source decision
    E_DL_RouteSel.eNone:               // 空置：输出 FALSE，不计哨兵 / Idle, FALSE, no sentinel
        bOutCh2 := FALSE;              // 通道 2 输出 / Channel 2 output
    E_DL_RouteSel.eSrcA:               // 选源 A：使能闸 + 断源哨兵留痕 / Source A, enable gate plus lost sentinel
        bOutCh2 := bEnCh2 AND aSrcA;   // 通道 2 输出 / Channel 2 output
        bSrcALost := bSrcALost OR (bEnCh2 AND NOT aSrcA); // 断源哨兵累积 / Lost sentinel accumulate
    E_DL_RouteSel.eSrcB:               // 选源 B：使能闸 + 断源哨兵留痕 / Source B, enable gate plus lost sentinel
        bOutCh2 := bEnCh2 AND aSrcB;   // 通道 2 输出 / Channel 2 output
        bSrcBLost := bSrcBLost OR (bEnCh2 AND NOT aSrcB); // 断源哨兵累积 / Lost sentinel accumulate
    ELSE                               // 非法选择值兜底（R21：CASE 必带 ELSE）
        bOutCh2 := FALSE;              // 安全侧输出 FALSE / Safe-side FALSE output
END_CASE

// ---- 段 2｜通道 3/4 路由（同段 1 口径）----
CASE eSelCh3 OF                       // 通道 3 来源判决 / Channel 3 source decision
    E_DL_RouteSel.eNone:               // 空置：输出 FALSE，不计哨兵 / Idle, FALSE, no sentinel
        bOutCh3 := FALSE;              // 通道 3 输出 / Channel 3 output
    E_DL_RouteSel.eSrcA:               // 选源 A：使能闸 + 断源哨兵留痕 / Source A, enable gate plus lost sentinel
        bOutCh3 := bEnCh3 AND aSrcA;   // 通道 3 输出 / Channel 3 output
        bSrcALost := bSrcALost OR (bEnCh3 AND NOT aSrcA); // 断源哨兵累积 / Lost sentinel accumulate
    E_DL_RouteSel.eSrcB:               // 选源 B：使能闸 + 断源哨兵留痕 / Source B, enable gate plus lost sentinel
        bOutCh3 := bEnCh3 AND aSrcB;   // 通道 3 输出 / Channel 3 output
        bSrcBLost := bSrcBLost OR (bEnCh3 AND NOT aSrcB); // 断源哨兵累积 / Lost sentinel accumulate
    ELSE                               // 非法选择值兜底（R21：CASE 必带 ELSE）
        bOutCh3 := FALSE;              // 安全侧输出 FALSE / Safe-side FALSE output
END_CASE
CASE eSelCh4 OF                       // 通道 4 来源判决 / Channel 4 source decision
    E_DL_RouteSel.eNone:               // 空置：输出 FALSE，不计哨兵 / Idle, FALSE, no sentinel
        bOutCh4 := FALSE;              // 通道 4 输出 / Channel 4 output
    E_DL_RouteSel.eSrcA:               // 选源 A：使能闸 + 断源哨兵留痕 / Source A, enable gate plus lost sentinel
        bOutCh4 := bEnCh4 AND aSrcA;   // 通道 4 输出 / Channel 4 output
        bSrcALost := bSrcALost OR (bEnCh4 AND NOT aSrcA); // 断源哨兵累积 / Lost sentinel accumulate
    E_DL_RouteSel.eSrcB:               // 选源 B：使能闸 + 断源哨兵留痕 / Source B, enable gate plus lost sentinel
        bOutCh4 := bEnCh4 AND aSrcB;   // 通道 4 输出 / Channel 4 output
        bSrcBLost := bSrcBLost OR (bEnCh4 AND NOT aSrcB); // 断源哨兵累积 / Lost sentinel accumulate
    ELSE                               // 非法选择值兜底（R21：CASE 必带 ELSE）
        bOutCh4 := FALSE;              // 安全侧输出 FALSE / Safe-side FALSE output
END_CASE

// ---- 段 3｜统一出口：可用标志（纯组合无防御失败路径）----
bValid := TRUE;                       // 组合路由恒可用 / Combinational routing always usable
END_FUNCTION_BLOCK