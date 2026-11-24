//==============================================================================
// 功能块：FB_DL_SensorSupplyWatch ｜ 中文名称：传感器供电电压窗口监视
// 所属子库：DL_Device ｜ 版本：v1.0.1 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3，零方言）
// 功能描述：传感器供电电压窗口监视：欠压/过压分级判出（越窗经 tDebounce
//           去抖确认才声明；恢复回正常同样需在窗连续 tDebounce，故障/恢复
//           同一去抖口径，R73 返修），出口按 NE43 四态约定（00 = 正常 /
//           01 = 工作但不正常 / 11 = 故障 / 10 = 无诊断）输出枚举与双 BOOL。
//           窗口参数引脚注入（fVMin / fVMax），非魔法数。
//           同族分工：多通道窗口均值 + 迟滞判限（逐通道掩码诊断）属
//           FB_DL_SensorSupplyMon；本件为单通道供电窗口 NE43 四态监视，
//           互不替代（R73 互引）。
// 开源溯源 (Origin)：候选队列 WINDOW2（oscatBasic，MIT 许可，
//           https://github.com/tkucic/brOscatLib/blob/main/oscatBasic/WINDOW2.st）
//           ——窗口比较行为定义参考；原名 WINDOW2 → 道莅
//           FB_DL_SensorSupplyWatch，clean-room 独立重写（去抖确认 + NE43
//           出口为道莅防御规范增量，零源码行复制）
// 公开接口清单：输入 fSupplyV / fVMin / fVMax / tDebounce；
//               输出 bSupplyOk / bUnder / bOver / eN43 / uErrCode / bValid
// 错误码表：16#0003_0750 信息级（输入非有限判无效，NE43 报 11 故障态，
//           不置 bError——供电异常是工况事实非软件故障）/
//           16#0003_0751 预留禁用（不得挪用）
// 状态机：E_DL_N43State（本文件唯一定义，全库唯一属主，NE43 四态口径）：
//           eOk = 0 / eUnderRange = 1 / eOverRange = 2 / eInvalid = 3
// 边界行为：① 输入非有限 → eInvalid（NE43 = 11 故障态）+ 信息码；
//           ② 越窗经 tDebounce 去抖确认才置 bUnder/bOver（抖动不误报）；
//             恢复回正常同样经在窗去抖 tonOk 确认（同口径，R73 返修）；
//           ③ fVMax <= fVMin 参数倒置 → 视配置故障按 eInvalid 处理；
//           ④ TON ×2 每拍无条件刷新（不入分支，红线 R7）；
//           ⑤ CASE 带 ELSE 非法态兜底归 eInvalid。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 3 · 序 15）
//           v1.0.1 2026-11-23 R73 返修：恢复判定并入故障判定同一去抖口径
//           （新增 tonOk 在窗去抖 + bInOk 暂存，bSupplyOk 改由统一出口按
//           eN43 = eOk 声明）；并补与 FB_DL_SensorSupplyMon 的同族分工互引。
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举: E_DL_N43State（归属本功能块，同文件发布，全库唯一属主）
 * 含义: NE43 四态诊断出口口径，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_N43State :
(
    eOk         := 0,   // NE43 = 00：正常 / Normal
    eUnderRange := 1,   // NE43 = 01：欠压（工作但不正常）/ Undervoltage, working but not normal
    eOverRange  := 2,   // NE43 = 01：过压（工作但不正常）/ Overvoltage, working but not normal
    eInvalid    := 3    // NE43 = 11：无效/故障（输入非有限或参数倒置）/ Invalid or fault
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_SensorSupplyWatch
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_SensorSupplyWatch
VAR_INPUT
    fSupplyV  : LREAL := 24.0;         // 供电电压实测值 [伏特] / Measured supply voltage [V]
    fVMin     : LREAL := 21.6;         // 电压窗口下限 [伏特]，引脚注入 / Voltage window floor [V], injected via the pin
    fVMax     : LREAL := 26.4;         // 电压窗口上限 [伏特]，引脚注入 / Voltage window ceiling [V], injected via the pin
    tDebounce : TIME  := T#500MS;      // 越窗去抖确认延时 [毫秒] / Out-of-window debounce delay [ms]
END_VAR
VAR_OUTPUT
    bSupplyOk : BOOL;                  // 供电正常声明（去抖后）/ Supply normal declaration after debounce
    bUnder    : BOOL;                  // 欠压声明（去抖确认后）/ Undervoltage declared after debounce
    bOver     : BOOL;                  // 过压声明（去抖确认后）/ Overvoltage declared after debounce
    eN43      : E_DL_N43State;         // NE43 四态出口 / NE43 four-state outlet
    uErrCode  : UDINT;                 // 信息级码，0 = 无信息 / Info-level code, 0 = none
    bValid    : BOOL;                  // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonUnder  : TON;                   // 欠压去抖定时器，每拍无条件刷新 / Undervoltage debounce timer, refreshed every scan
    tonOver   : TON;                   // 过压去抖定时器，每拍无条件刷新 / Overvoltage debounce timer, refreshed every scan
    tonOk     : TON;                   // 在窗恢复去抖定时器，每拍无条件刷新 / In-window recovery debounce timer, refreshed every scan
    bInUnder  : BOOL;                  // 本拍欠压越窗（未确认）/ Undervoltage window violation this scan, unconfirmed
    bInOver   : BOOL;                  // 本拍过压越窗（未确认）/ Overvoltage window violation this scan, unconfirmed
    bInOk     : BOOL;                  // 本拍在窗暂存（恢复去抖输入）/ In-window staged this scan, recovery debounce input
    bParamBad : BOOL;                  // 参数倒置声明 / Parameter inversion flag
END_VAR
VAR CONSTANT
    DL_SSV_INF   : LREAL := 1.7976931348623157E308; // LREAL 幅值上限 / LREAL magnitude ceiling
    DL_SSV_CODE_INV : UDINT := 16#0003_0750; // 信息级：输入非有限或参数倒置码 / Info code: non-finite input or inverted parameters
END_VAR

// ---- 段 1｜定时器无条件刷新（红线 R7：禁入条件分支）----
tonUnder(IN := bInUnder, PT := tDebounce); // 欠压去抖按越窗态断输入 / Under timer input per violation state
tonOver(IN := bInOver, PT := tDebounce);   // 过压去抖按越窗态断输入 / Over timer input per violation state
tonOk(IN := bInOk, PT := tDebounce);       // 在窗恢复去抖按在窗态断输入 / Ok timer input per in-window state

// ---- 段 2｜出口默认值：入口即赋确定值 ----
bSupplyOk := FALSE;                   // 正常声明默认 FALSE / Normal declaration preset FALSE
bUnder    := FALSE;                   // 欠压声明默认 FALSE / Undervoltage preset FALSE
bOver     := FALSE;                   // 过压声明默认 FALSE / Overvoltage preset FALSE
bInUnder  := FALSE;                   // 越窗暂存先清零 / Violation stage cleared first
bInOver   := FALSE;                   // 越窗暂存先清零 / Violation stage cleared first
bInOk     := FALSE;                   // 在窗暂存先清零 / In-window stage cleared first
bParamBad := FALSE;                   // 参数倒置声明先清零 / Parameter inversion preset FALSE
uErrCode  := 16#0000_0000;            // 信息码每拍重算（信息级不锁存）/ Info code recomputed, never latched
bValid    := TRUE;                    // 可用标志默认 TRUE / Usable flag preset TRUE
// 注：eN43 为跨拍状态量，不在此预置（初始值 = eOk，由段 5 状态机推进）
// Note: eN43 is a cross-scan state, preset skipped here, advanced by the segment-5 machine

// ---- 段 3｜输入防御与参数闸：非有限或窗口倒置 → eInvalid（NE43 = 11）----
IF (fSupplyV <> fSupplyV) OR (ABS(fSupplyV) > DL_SSV_INF)
   OR (fVMin <> fVMin) OR (ABS(fVMin) > DL_SSV_INF)
   OR (fVMax <> fVMax) OR (ABS(fVMax) > DL_SSV_INF)
   OR (fVMax <= fVMin) THEN
    bParamBad := (fVMax <= fVMin) OR (fVMin <> fVMin) OR (fVMax <> fVMax); // 参数倒置归因 / Parameter inversion attribution
    eN43     := E_DL_N43State.eInvalid; // NE43 故障态 / NE43 invalid state
    uErrCode := DL_SSV_CODE_INV;        // 信息级留痕（不置 bError）/ Info trace, no fault flag
    bValid   := TRUE;                   // 出口确定（无效是合法诊断结论）/ Outlets deterministic
    RETURN;                             // 结构早退（去抖声明保持 FALSE）/ early exit
END_IF

// ---- 段 4｜窗口比较（WINDOW2 行为定义口径）：越窗暂存，去抖确认 ----
IF fSupplyV < fVMin THEN
    bInUnder := TRUE;                   // 欠压越窗暂存 / Undervoltage violation staged
ELSIF fSupplyV > fVMax THEN
    bInOver := TRUE;                    // 过压越窗暂存 / Overvoltage violation staged
END_IF
bUnder    := tonUnder.Q;               // 欠压去抖确认声明 / Undervoltage confirmed
bOver     := tonOver.Q;               // 过压去抖确认声明 / Overvoltage confirmed
bInOk     := (NOT bInUnder) AND (NOT bInOver); // 本拍在窗暂存（恢复去抖输入）/ In-window staged, recovery debounce input

// ---- 段 5｜NE43 出口装配（CASE 带 ELSE；非法态兜底归 eInvalid）----
CASE eN43 OF
    E_DL_N43State.eOk:                 // 正常相：双向未确认越窗
        IF bUnder THEN
            eN43 := E_DL_N43State.eUnderRange; // 升欠压态 / Rise to undervoltage
        ELSIF bOver THEN
            eN43 := E_DL_N43State.eOverRange;  // 升过压态 / Rise to overvoltage
        END_IF
    E_DL_N43State.eUnderRange:         // 欠压态：可升过压或经在窗去抖回正常
        IF bOver THEN
            eN43 := E_DL_N43State.eOverRange;  // 升过压态 / Rise to overvoltage
        ELSIF tonOk.Q THEN                 // 恢复闸：在窗连续 tDebounce 才回正常（与故障判定同口径，R73）/ Recovery gate, same debounce discipline
            eN43 := E_DL_N43State.eOk;         // 回正常态 / Back to normal
        END_IF
    E_DL_N43State.eOverRange:          // 过压态：可落欠压或经在窗去抖回正常
        IF bUnder THEN
            eN43 := E_DL_N43State.eUnderRange; // 落欠压态 / Fall to undervoltage
        ELSIF tonOk.Q THEN                 // 恢复闸：同口径（R73）/ Recovery gate, same discipline
            eN43 := E_DL_N43State.eOk;         // 回正常态 / Back to normal
        END_IF
    E_DL_N43State.eInvalid:            // 无效态：输入恢复合法后按同口径去抖迁移（段 3 早退承担整拍重评）
        IF bUnder THEN
            eN43 := E_DL_N43State.eUnderRange; // 恢复欠压态（去抖确认后）/ Recover to undervoltage after debounce
        ELSIF bOver THEN
            eN43 := E_DL_N43State.eOverRange;  // 恢复过压态（去抖确认后）/ Recover to overvoltage after debounce
        ELSIF tonOk.Q THEN                     // 恢复闸：在窗连续 tDebounce（同口径，R73）/ Recovery gate, same discipline
            eN43 := E_DL_N43State.eOk;         // 恢复正常态 / Recover to normal
        END_IF                                 // 未满任一确认窗：滞留 eInvalid / Stay invalid until a window completes
    ELSE                               // 非法态兜底（R21：CASE 必带 ELSE）
        eN43 := E_DL_N43State.eInvalid; // 拦截非法值归无效态 / Catch illegal value to invalid
END_CASE

// ---- 段 6｜统一出口：正常声明按 NE43 态装配（恢复经 tonOk 去抖后才成立，R73）----
bSupplyOk := (eN43 = E_DL_N43State.eOk); // 正常 = 仅 NE43 正常态（双向去抖同口径）/ Normal = NE43 ok state only, both directions debounced
END_FUNCTION_BLOCK