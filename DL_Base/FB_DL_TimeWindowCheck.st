(*==============================================================================
 * 组件名称 (Component)  : FB_DL_TimeWindowCheck
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         仅依赖 Standard.library（R_TRIG / MIN），零厂商方言
 * 分类     (Category)   : 功能块（FUNCTION_BLOCK）· 每日时间窗判定 · Level 0 DL_Base 补强件
 * 功能描述 (Function)   : 每日时间窗单一语义判定块（LGF mode 巨无霸反例的落实：
 *                         不设 MODE 参数，每周/每月/每年窗按矩阵扩产规则拆独立
 *                         块）。判定 = 本日总使能 AND 星期表当日位 AND 时刻窗。
 *                         时刻窗支持跨零点（如 22:00→06:00：t≥开 OR t<关）；
 *                         开=关视为 24h 全开（语义见段内注释）。窗口开/闭沿
 *                         单发脉冲供启停设备一次触发。当前时刻/星期由引脚注入
 *                         （零全局耦合红线：禁读 CPU 本地钟），典型与
 *                         FC_DL_DayOfWeekCalc 输出直连。
 * 开源溯源 (Origin)     : 来源标签 lgf-datetime（Siemens LGF V5.2.1 · 3.1 Date
 *                         and timer operations 章 定时开关族）。仅借鉴每日窗/
 *                         跨零点判定与星期使能表的公开行为语义；去 mode 巨无霸
 *                         化（单一语义拆块）、去 CPU 钟耦合（时间引脚注入）均
 *                         为本库独立设计决策，clean-room 重写，未复制任何源码行。
 * 本文件内含       : FUNCTION_BLOCK FB_DL_TimeWindowCheck
 * 依赖     (Depends)    : Standard.library: R_TRIG / MIN；建议上游搭配
 *                          FC_DL_DayOfWeekCalc（ISO 序星期源，引脚注入）。
 *                          不引用 DL_ 内其他实现文件。
 * 故障码表 (Error codes) : 16#0001_0202【信息级】时刻/星期参数越界（当前时刻越
 *                          界按 FALSE 处理；窗口参数越界按钳位后照常计算），
 *                          不置任何故障位（本块无故障锁存位）；0 = 无。沿用
 *                          DL_Base 既有 16#0001_xxxx 段，与 VERSION.md 故障码
 *                          表无冲突。
 * 【规格偏离留档 / R11 Deviation register】
 *   D1 规格 §4.2 引脚表未提供星期索引注入引脚，aWeekdayEnable[1..7] 表在块内
 *      无法自索引（时刻引脚不含日期信息）；按 R11 留档新增输入引脚
 *      uWeekdayNow : USINT := 1（当前星期注入，ISO 序 1=周一..7=周日，与
 *      §4.1 FC_DL_DayOfWeekCalc 输出同序同域），越界不读表并置信息级码。
 *   D2 规格引脚表 bReset 注释为「—」：本块定义其语义为上升沿清除当拍信息级码
 *      并强制重新评估窗口（日切换后防陈旧码残留），不影响窗口判定结果本身。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 越界防御+分钟折算 UINT 扩宽防溢出
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 不适用（组合逻辑+沿检测，无状态机）
 *                         R7 ✓ 三个 R_TRIG 实例主体无条件周期刷新（严禁入分支）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 05 · 泳道 B · 契约出处 ROUND_PLAN_R5 §4.2
 * 验收向量 (Acceptance) :
 *   V1 同日窗：On=08:00 / Off=18:00，Now=12:00 → bInWindow=TRUE；Now=07:59 /
 *      18:00 → FALSE（左闭右开）
 *   V2 跨零点窗：On=22:00 / Off=06:00，Now=23:30 或 05:59 → TRUE；Now=06:00 →
 *      FALSE；Now=21:59 → FALSE
 *   V3 24h 窗：On=Off=08:00 → 任意时刻 bInWindow=TRUE（开=关全开语义）
 *   V4 星期表：uWeekdayNow=6（周六）且 aWeekdayEnable[6]=FALSE → 不在窗，其余
 *      条件不影响；uWeekdayNow=0 或 8 → 信息级 0001_0202 且按不在窗处理
 *   V5 时刻越界：uHourNow=24 → bInWindow=FALSE + 0001_0202（当前时刻越界按
 *      FALSE 处理）；uHourOn=25 → 钳位 23 后照常计算 + 0001_0202（信息级钳位）
 *   V6 沿单发：V1 场景下 Now 由 07:59 → 08:00 当拍 bPulseOnWindowOpen=TRUE 单发；
 *      18:00 当拍 bPulseOnWindowClose=TRUE 单发
 *   V7 复位沿：越界码出现后 bReset 上升沿当拍 uErrorId 清零（触发实例无条件刷新）
 *============================================================================*)

(*==============================================================================
 * 功能块: FB_DL_TimeWindowCheck
 * 调用约定: 每个扫描周期无条件调用一次；三个 R_TRIG 实例在主体无条件周期刷新，
 *           严禁移入 IF/CASE 分支（R7）。时刻/星期由调用方每拍注入。
 *============================================================================*)
FUNCTION_BLOCK FB_DL_TimeWindowCheck
VAR_INPUT
    uHourNow        : USINT;                // 当前时刻-时（Injected local time hour）[h] 0..23，越界按不在窗处理（禁读 CPU 钟，公约 0.9）
    uMinNow         : USINT;                // 当前时刻-分（Injected local time minute）[min] 0..59
    bEnableDay      : BOOL := TRUE;         // 本日窗总使能（Day window enable），FALSE 时恒不在窗
    aWeekdayEnable  : ARRAY[1..7] OF BOOL;  // 周一~周日各日使能表（Weekday enable table），索引 1=周一（ISO 序，与 FC_DL_DayOfWeekCalc 一致）
    uWeekdayNow     : USINT := 1;           // 【偏离 D1 新增】当前星期注入（Injected weekday）1=周一..7=周日（ISO 序），越界不读表
    uHourOn         : USINT := 6;           // 窗口开启-时（Window on hour）[h] 0..23，越界钳位后照算（公约 0.2）
    uMinOn          : USINT := 0;           // 窗口开启-分（Window on minute）[min] 0..59
    uHourOff        : USINT := 22;          // 窗口关闭-时（Window off hour）[h] 0..23，支持跨零点（如 22:00→06:00）
    uMinOff         : USINT := 0;           // 窗口关闭-分（Window off minute）[min] 0..59
    bReset          : BOOL := FALSE;        // 复位（Reset）上升沿：清除当拍信息级码并重新评估（偏离 D2）
END_VAR
VAR_OUTPUT
    bInWindow           : BOOL;             // 当前处于窗口内（In window）= 本日使能 AND 星期位 AND 时刻窗
    bPulseOnWindowOpen  : BOOL;             // 窗口开启沿单发（Window open edge），TRUE 持续一拍
    bPulseOnWindowClose : BOOL;             // 窗口关闭沿单发（Window close edge），TRUE 持续一拍
    uErrorId            : UDINT;            // 信息级码（Info code）16#0001_0202 = 时刻/星期越界；0 = 无
END_VAR
VAR
    fbTrigReset     : R_TRIG;               // 复位信号上升沿检测实例（Reset edge detector）
    fbTrigOpen      : R_TRIG;               // 窗口开启沿检测实例（Window open edge detector），CLK = bInWindow
    fbTrigClose     : R_TRIG;               // 窗口关闭沿检测实例（Window close edge detector），CLK = NOT bInWindow
    uHourOnC        : USINT;                // 钳位后开启-时（Clamped on hour）[h] 0..23
    uMinOnC         : USINT;                // 钳位后开启-分（Clamped on minute）[min] 0..59
    uHourOffC       : USINT;                // 钳位后关闭-时（Clamped off hour）[h] 0..23
    uMinOffC        : USINT;                // 钳位后关闭-分（Clamped off minute）[min] 0..59
    uNowMin         : UINT;                 // 当前时刻折算分钟（Now in minutes）0..1439，USINT 域乘法越界防御
    uOnMin          : UINT;                 // 开窗时刻折算分钟（On time in minutes）0..1439
    uOffMin         : UINT;                 // 关窗时刻折算分钟（Off time in minutes）0..1439
    bTimeNowOk      : BOOL;                 // 当前时刻有效性（Now time valid）
    bWinParamOk     : BOOL;                 // 窗口参数有效性（Window params valid）
    bWeekdayOk      : BOOL;                 // 星期索引有效性（Weekday index valid）
    bTimeInWin      : BOOL;                 // 时刻窗判定结果（Time-in-window result）
    bDayOk          : BOOL;                 // 日使能合成结果（Day-enable result）
END_VAR

// -----------------------------------------------------------------------------
// 段 1｜边沿实例无条件周期刷新（R7 红线：严禁移入 IF/CASE 分支）
// -----------------------------------------------------------------------------
fbTrigReset(CLK := bReset);                 // 复位沿检测

// -----------------------------------------------------------------------------
// 段 2｜有效性判定与信息级码准备（信息级 0001_0202 只进 uErrorId，本块无故障位）
// -----------------------------------------------------------------------------
uErrorId := 16#0000_0000;                   // 每拍重算信息级码
bTimeNowOk  := (uHourNow <= 23) AND (uMinNow <= 59);               // 当前时刻域检查
bWinParamOk := (uHourOn <= 23) AND (uMinOn <= 59)
            AND (uHourOff <= 23) AND (uMinOff <= 59);          // 窗口参数域检查
bWeekdayOk  := (uWeekdayNow >= 1) AND (uWeekdayNow <= 7);      // 星期索引域检查（ISO 1..7）
IF NOT bTimeNowOk THEN
    uErrorId := 16#0001_0202;               // 当前时刻越界：按不在窗处理（引脚注释基线）
END_IF
IF NOT bWinParamOk THEN
    uErrorId := 16#0001_0202;               // 窗口参数越界：钳位后照常计算（公约 0.2）
END_IF
IF NOT bWeekdayOk THEN
    uErrorId := 16#0001_0202;               // 星期索引越界：不读表，按不在窗处理
END_IF

// -----------------------------------------------------------------------------
// 段 3｜窗口参数钳位（信息级钳位，钳位后继续计算，不中断扫描）
// -----------------------------------------------------------------------------
uHourOnC  := MIN(uHourOn, 23);              // 开启-时钳位 [h]
uMinOnC   := MIN(uMinOn, 59);               // 开启-分钳位 [min]
uHourOffC := MIN(uHourOff, 23);             // 关闭-时钳位 [h]
uMinOffC  := MIN(uMinOff, 59);              // 关闭-分钳位 [min]

// -----------------------------------------------------------------------------
// 段 4｜分钟折算（USINT×60 最大 1380 超 USINT 域，先扩宽 UINT 再运算防越界）
// -----------------------------------------------------------------------------
uOnMin := uHourOnC;                         // USINT → UINT 隐式扩宽
uOnMin := (uOnMin * 60) + uMinOnC;          // 开窗分钟 [min] 0..1439
uOffMin := uHourOffC;                       // USINT → UINT 隐式扩宽
uOffMin := (uOffMin * 60) + uMinOffC;       // 关窗分钟 [min] 0..1439
IF bTimeNowOk THEN
    uNowMin := uHourNow;                    // USINT → UINT 隐式扩宽
    uNowMin := (uNowMin * 60) + uMinNow;    // 当前分钟 [min] 0..1439
ELSE
    uNowMin := 0;                           // 时刻越界：折算值弃用，结果由 bTimeNowOk 门控
END_IF

// -----------------------------------------------------------------------------
// 段 5｜时刻窗判定（跨零点支持；开=关视为 24h 全开——语义：本日整日放行）
// -----------------------------------------------------------------------------
IF uOnMin > uOffMin THEN
    bTimeInWin := (uNowMin >= uOnMin) OR (uNowMin < uOffMin);   // 跨零点窗：t≥开 OR t<关（如 22:00→06:00）
ELSIF uOnMin < uOffMin THEN
    bTimeInWin := (uNowMin >= uOnMin) AND (uNowMin < uOffMin);  // 同日窗：开≤t<关（左闭右开）
ELSE
    bTimeInWin := TRUE;                                          // 开=关：24h 全开（每日窗单一语义特例）
END_IF

// -----------------------------------------------------------------------------
// 段 6｜日使能合成（星期越界不读表，防数组越界，R4）
// -----------------------------------------------------------------------------
IF bWeekdayOk THEN
    bDayOk := bEnableDay AND aWeekdayEnable[uWeekdayNow];       // 总使能 AND 当日星期位（索引 1..7 已校验）
ELSE
    bDayOk := FALSE;                        // 星期索引越界：按不在窗处理
END_IF

// -----------------------------------------------------------------------------
// 段 7｜总判定：当前时刻越界按 FALSE 处理；窗口参数已钳位故不再门控结果
// -----------------------------------------------------------------------------
bInWindow := bDayOk AND bTimeNowOk AND bTimeInWin;              // 在窗 = 日使能 AND 时刻有效 AND 时刻窗

// -----------------------------------------------------------------------------
// 段 8｜窗口开/闭沿单发（实例无条件周期刷新，沿输出各持续一拍）
// -----------------------------------------------------------------------------
fbTrigOpen(CLK := bInWindow);               // 开启沿检测
fbTrigClose(CLK := NOT bInWindow);          // 关闭沿检测（取反 CLK）
bPulseOnWindowOpen  := fbTrigOpen.Q;        // 开启沿单发输出
bPulseOnWindowClose := fbTrigClose.Q;       // 关闭沿单发输出

// -----------------------------------------------------------------------------
// 段 9｜复位沿消费：清除当拍信息级码（触发实例已在段 1 无条件刷新，偏离 D2）
// -----------------------------------------------------------------------------
IF fbTrigReset.Q THEN
    uErrorId := 16#0000_0000;               // 复位沿当拍清信息级码（下一拍重新评估）
END_IF

END_FUNCTION_BLOCK
