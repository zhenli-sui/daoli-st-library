(*==============================================================================
 * 组件名称 (Component)  : FB_DL_OccScheduleWindow
 * 所属子库 (Sublibrary) : DL_Process
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 功能块（FUNCTION_BLOCK）· 多窗作息排程 ·
 *                         Level 2 行业池 9.5 节 P0 链路闭环示范
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；仅依赖 Standard.library（R_TRIG /
 *                         MIN）与本库 DL_Base 已入库组件，零厂商方言
 * 功能描述 (Function)   : 多窗作息排程块（最多 4 窗并行）。日期/时刻全部引脚
 *                         注入（零全局耦合红线：禁读 CPU 本地钟）→ 调用
 *                         FC_DL_DayOfWeekCalc 换算当日星期（ISO-8601 序）
 *                         → 内部 4 实例复用 FB_DL_TimeWindowCheck 逐窗判定
 *                         （每日窗矩阵 + 节假日覆盖位）→ 输出占用合成、
 *                         占用开始沿单发、活动窗号（多窗同开取最小号）与
 *                         预启动占位（提前启机预热/预冷用）。
 * 设计要点 (Key notes)  : ① 每窗占用 = 窗实例 bInWindow（内部已合成 总使能
 *                           AND 星期位 AND 时刻窗），总使能引脚折入
 *                           bEnableDay := aWinEnable[i] AND NOT aHoliday-
 *                           Override[i]（节假日强制当日该窗关闭）；窗实例的
 *                           aWeekdayEnable 由本块按 aWeekdayWin[i, 当日星期]
 *                           单日位展开为 7 日表填充；
 *                         ② 预启动占位：折算「占用开始时刻 − tPreLeadTime」
 *                           分钟域判定。推导：窗开始分钟 uStartMin（UINT 域，
 *                           0..1439，与 FB_DL_TimeWindowCheck 折算口径一致）；
 *                           当 提前量 ≤ 开始时刻 时预启带 = [开始−提前, 开始)
 *                           （左闭右开）；当 提前量 > 开始时刻（跨零点回绕）
 *                           时预启带 = [开始+24h−提前, 开始)∪[0, 开始)，即
 *                           [开始+1440−lead, 1440) 与 [0, 开始) 的并——本块
 *                           统一用 TIME 域表达（T#24H 回绕式），时刻折算先
 *                           USINT→DINT 扩宽再乘 60 防溢出（复用窗实例口径，
 *                           声明一致）；预启带归属注入日期当日窗（跨零点前段
 *                           归属前一日期的同一窗组态，调用方按日切换注入即可）；
 *                         ③ 窗实例与沿检测实例在主体无条件周期刷新（R7，
 *                           严禁置于 IF/CASE 分支）；
 *                         ④ 【事件型+日切换沿，免首扫（R23）】输入输出均为
 *                           电平/日历注入，无连续量同步语义，窗判定为组合
 *                           逻辑逐拍重算，故不设 bInit 首扫判据；
 *                         ⑤ 日期越界（FC 返回 eInvalid）→ 全窗按不在窗处理
 *                           + 信息级 0005_0210；各窗实例信息级码 0001_0202
 *                           不透传，本块归并为自身码 0005_0211（头注释声明）；
 *                         ⑥ bReset 上升沿清除当拍信息级码（日切换后防陈旧码
 *                           残留），不影响窗判定结果（沿用窗实例 D2 语义）；
 *                         ⑦ 本块无浮点量，非有限值防御不适用（公约 0.8 N/A）。
 * 枚举归属 (Enum note)  : 复用 E_DL_Weekday（DL_Base，随 FC_DL_DayOfWeekCalc
 *                         同文件发布的既有公开契约，直接引用，禁止重定义）；
 *                         本块不新增任何 DUT。
 * 依赖     (Depends)    : FB_DL_TimeWindowCheck（DL_Base，4 实例复用）；
 *                         FC_DL_DayOfWeekCalc + E_DL_Weekday（DL_Base）；
 *                         Standard.library：R_TRIG / MIN。
 * 开源溯源 (Origin)     : 原创实现（参考 OSCAT Building 时钟排程族与
 *                         Siemens LGF 定时开关族的公开行为定义，clean-room）。
 *                         仅借鉴「多窗排程 + 星期使能矩阵 + 节假日覆盖」的
 *                         公开行为语义；多实例单一语义组合架构、预启动占位、
 *                         时间引脚注入均为本库独立设计，未复制任何源码行。
 * 故障码表 (Error codes):
 *   16#0005_0210【信息级】日期参数越界（年/月/日，FC 返回 eInvalid），全窗
 *                 按不在窗处理
 *   16#0005_0211【信息级】窗时刻参数越界（各窗实例 0001_0202 码不透传，本块
 *                 归并为自身码；实例侧越界已钳位照常计算，本块预启动判定对
 *                 参数越界窗按跳过处理）
 *   【02xx 段信息级占位声明（规格 §7 有意裁定，R11 留档）】0210/0211 占用
 *   02xx 段：日历排程块全部事件均为信息级（无安全联锁、无锁存故障位），
 *   故障级段整体保留给后续工艺联锁件，沿用 FB_DL_TimeWindowCheck 先例，
 *   避免读者误判为故障级。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 数组索引域校验+USINT→DINT
 *                             扩宽防溢出+TIME 回绕防御（提前量钳位）；无浮点量，
 *                             非有限值防御不适用（R23 事件型）
 *                         R5 ✓ 全变量中英双语同行注释
 *                         R6 不适用（组合逻辑+沿检测，无状态机；星期换算
 *                           CASE 含 ELSE 兜底）
 *                         R7 ✓ 4 个窗实例 + 2 个 R_TRIG 实例主体无条件周期刷新
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 06 · 泳道 C · 契约出处 ROUND_PLAN_R6 §3.15
 * 验收向量 (Acceptance) :
 *   V1 单窗占用链：窗 1 On=08:00/Off=18:00 使能，Now=07:59 → bOccupied=
 *      FALSE；08:00 当拍 bPulseOnOccupy=TRUE 单发且 bOccupied=TRUE；
 *      18:00 当拍 bOccupied=FALSE（左闭右开与窗实例一致）
 *   V2 四窗并行：窗 2 与窗 4 同时在窗 → uActiveWin=2（多窗同开取最小号）
 *   V3 节假日覆盖：aHolidayOverride[1]=TRUE → 当日窗 1 强制不在窗，其余窗
 *      不受影响
 *   V4 预启动提前量（含跨零点回绕）：tPreLeadTime=T#30M，窗 On=06:00 →
 *      Now=05:35 bPreStart=TRUE 且 bOccupied=FALSE，06:00 当拍 bPreStart
 *      随占用置位而清零；跨零点窗 On=00:10、提前量 30 分 → Now=23:50 时
 *      bPreStart=TRUE（预启带 [23:40, 00:10)，回绕式 开始+24h−提前=23:40）
 *   V5 日期越界降级：uMonth=13 → FC 返回 eInvalid → 全窗不在窗 +
 *      0005_0210；bReset 沿当拍清码
 *   V6 星期矩阵按日生效：aWeekdayWin[1,6]=FALSE（周六位）→ 周六窗 1 不在窗，
 *      周一~周五正常
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 调用示例 (Instance guide)：
 *   fbOcc.uYear := 2026; fbOcc.uMonth := 11; fbOcc.uDay := 15;   // 日历注入
 *   fbOcc.uHourNow := stClock.hour; fbOcc.uMinNow := stClock.min;
 *   fbOcc.aWinEnable[1] := TRUE; fbOcc.aHourOn[1] := 8;         // 窗 1 组态，其余 3 窗同构
 *   fbOcc(tPreLeadTime := T#30M, bReset := bDaySwReset);         // 周期调用
 *   预热/预冷联动：bPreStart → AHU 通风预启（非占用占位）；bPulseOnOccupy
 *   → 占用开始沿一次性事件（照明/门禁联动）。uActiveWin 供 HMI 显示当前窗。
 *----------------------------------------------------------------------------*)

FUNCTION_BLOCK FB_DL_OccScheduleWindow
VAR_INPUT
    uYear              : UINT;             // 日期注入-年（Injected date year）[年] 有效域 1980..2099，越界返回 eInvalid（透传 FC_DL_DayOfWeekCalc）
    uMonth             : USINT;            // 日期注入-月（Injected month）[月] 有效域 1..12，越界按日期非法处理
    uDay               : USINT;            // 日期注入-日（Injected day）[日] 有效域 1..当月天数（含闰年），越界按日期非法处理
    uHourNow           : USINT;            // 当前时刻注入-时（Injected time hour）[h] 0..23，越界按不在窗处理（禁读 CPU 钟，公约 0.9）
    uMinNow            : USINT;            // 当前时刻注入-分（Injected time minute）[min] 0..59
    aWinEnable         : ARRAY[1..4] OF BOOL;          // 各窗使能（Window enables）[1] 窗 1..4，FALSE 时该窗恒不在窗
    aHourOn            : ARRAY[1..4] OF USINT;         // 各窗开启时刻-时（Window on hours）[h] 0..23，越界该窗预启动跳过（实例侧钳位照算）
    aMinOn             : ARRAY[1..4] OF USINT;         // 各窗开启时刻-分（Window on minutes）[min] 0..59
    aHourOff           : ARRAY[1..4] OF USINT;         // 各窗关闭时刻-时（Window off hours）[h] 0..23，支持跨零点窗
    aMinOff            : ARRAY[1..4] OF USINT;         // 各窗关闭时刻-分（Window off minutes）[min] 0..59
    aWeekdayWin        : ARRAY[1..4, 1..7] OF BOOL;    // 各窗星期使能矩阵（Per-window weekday matrix）[1] 第二维 1=周一..7=周日（ISO 序）
    aHolidayOverride   : ARRAY[1..4] OF BOOL;          // 节假日覆盖位（Holiday overrides）[1] TRUE=当日该窗强制关闭
    tPreLeadTime       : TIME := T#30M;    // 预启动提前量（Pre-start lead time）默认 T#30M，防御钳位 ≤ T#12H，占用开始前输出预启动占位
    bReset             : BOOL := FALSE;    // 复位（Reset）[1] 上升沿：清除当拍信息级码（不影响窗判定）
END_VAR
VAR_OUTPUT
    bOccupied          : BOOL;             // 占用中（Occupied）[1] 任一有效窗在窗内
    bPreStart          : BOOL;             // 预启动占位（Pre-start placeholder）[1] 未占用且距某有效窗开始 ≤ 提前量
    bPulseOnOccupy     : BOOL;             // 占用开始沿单发（Occupancy start edge）[1] TRUE 持续一拍
    uActiveWin         : USINT;            // 当前活动窗号（Active window index）1..4，0=无，多窗同开取最小号
    uErrorId           : UDINT;            // 信息级码（Info code）16#0005_0210 日期非法 / 16#0005_0211 窗参数越界；0 = 无
END_VAR
VAR
    _fbWin1            : FB_DL_TimeWindowCheck;  // 窗 1 判定实例（Window 1 checker instance）
    _fbWin2            : FB_DL_TimeWindowCheck;  // 窗 2 判定实例（Window 2 checker instance）
    _fbWin3            : FB_DL_TimeWindowCheck;  // 窗 3 判定实例（Window 3 checker instance）
    _fbWin4            : FB_DL_TimeWindowCheck;  // 窗 4 判定实例（Window 4 checker instance）
    fbTrigReset        : R_TRIG;                 // 复位信号上升沿检测实例（Reset edge detector）
    fbTrigOccupy       : R_TRIG;                 // 占用开始沿检测实例（Occupancy edge detector），CLK = bOccupied
    _eWd               : E_DL_Weekday := E_DL_Weekday.eInvalid;  // 星期换算返回值（Weekday calc result，复用 DL_Base 既有枚举）
    _uErrDow           : UDINT;                  // 星期换算返回码（Weekday calc code）16#0001_0201 = 日期越界
    _bDateOk           : BOOL;                   // 日期有效性（Date valid）
    _uWd               : USINT;                  // 当日星期 USINT 域（Current weekday）1..7，0=非法
    _bWdOk             : BOOL;                   // 星期索引有效性（Weekday index valid）
    _bTimeOk           : BOOL;                   // 当前时刻有效性（Time-of-day valid）
    _abWdSel           : ARRAY[1..7] OF BOOL;    // 单日位展开表（Expanded single-day table），喂窗实例 aWeekdayEnable
    abEnDay            : ARRAY[1..4] OF BOOL;    // 各窗日总使能（Per-window day enable）= 窗使能 AND NOT 节假日覆盖
    abWdBit            : ARRAY[1..4] OF BOOL;    // 各窗当日星期位（Per-window weekday bit）
    abWinValid         : ARRAY[1..4] OF BOOL;    // 各窗今日有效（Per-window valid today）= 日使能 AND 星期位 AND 开启参数合法
    abOccWin           : ARRAY[1..4] OF BOOL;    // 各窗占用结果（Per-window occupancy）
    abPreBand          : ARRAY[1..4] OF BOOL;    // 各窗预启带命中（Per-window pre-start band hit）
    _nNowMin           : DINT;                   // 当前时刻折算分钟（Now in minutes）0..1439，USINT→DINT 扩宽防溢出
    _nStartMin         : DINT;                   // 窗开始折算分钟（Start in minutes）0..1439，扩宽防溢出
    _atStartT          : ARRAY[1..4] OF TIME;    // 各窗开始时刻 TIME 域（Per-window start time），分钟折算防溢出后换域
    _tNowT             : TIME;                   // 当前时刻 TIME 域（Now in TIME domain），预启带比较用
    _tLeadT            : TIME;                   // 生效提前量（Effective lead time）防御钳位 ≤ T#12H
    _i                 : USINT;                  // 循环索引（Loop index）1..4，固定界防死循环
    _j                 : USINT;                  // 循环索引（Loop index）1..7，固定界防死循环
END_VAR

// -----------------------------------------------------------------------------
// 段 1｜复位沿实例无条件周期刷新（R7 红线：严禁移入 IF/CASE 分支）
// -----------------------------------------------------------------------------
fbTrigReset(CLK := bReset);                 // 复位沿检测

// -----------------------------------------------------------------------------
// 段 2｜出口默认值与时刻有效性（事件型逐拍重算，无状态驻留）
// -----------------------------------------------------------------------------
uErrorId := 16#0000_0000;                   // 信息级码每拍重算
bOccupied := FALSE;                         // 占用合成默认 FALSE
bPreStart := FALSE;                         // 预启动默认 FALSE
bPulseOnOccupy := FALSE;                    // 沿单发默认 FALSE（段 10 覆盖）
uActiveWin := 0;                            // 活动窗号默认无
_bTimeOk := (uHourNow <= 23) AND (uMinNow <= 59);   // 时刻域检查（越界预启动跳过）

// -----------------------------------------------------------------------------
// 段 3｜星期换算：FC_DL_DayOfWeekCalc 公开接口直接调用（不内联重实现）
// -----------------------------------------------------------------------------
_eWd := FC_DL_DayOfWeekCalc(uYear := uYear, uMonth := uMonth, uDay := uDay,
                            uErrorId => _uErrDow);              // 日期 → 星期（ISO 序）
_bDateOk := (_uErrDow = 16#0000_0000);                          // 返回码 0 = 日期合法
IF NOT _bDateOk THEN
    uErrorId := 16#0005_0210;               // 日期非法【信息级】：全窗按不在窗处理
END_IF

// 星期枚举 → USINT 索引显式映射（strict 枚举不整型直赋；CASE+ELSE 兜底）
CASE _eWd OF
    E_DL_Weekday.eMonday:    _uWd := 1;     // 周一（ISO 1）
    E_DL_Weekday.eTuesday:   _uWd := 2;     // 周二（ISO 2）
    E_DL_Weekday.eWednesday: _uWd := 3;     // 周三（ISO 3）
    E_DL_Weekday.eThursday:  _uWd := 4;     // 周四（ISO 4）
    E_DL_Weekday.eFriday:    _uWd := 5;     // 周五（ISO 5）
    E_DL_Weekday.eSaturday:  _uWd := 6;     // 周六（ISO 6）
    E_DL_Weekday.eSunday:    _uWd := 7;     // 周日（ISO 7）
    ELSE
        _uWd := 0;                          // eInvalid / 未预期：当日全窗不使能
END_CASE
_bWdOk := (_uWd >= 1) AND (_uWd <= 7);      // 索引域校验（防矩阵越界，R4）

// -----------------------------------------------------------------------------
// 段 4｜公共量预计算：日使能 / 星期位 / 窗有效性 / 开始时刻折算（分钟域扩宽）
// -----------------------------------------------------------------------------
FOR _i := 1 TO 4 DO
    abEnDay[_i] := aWinEnable[_i] AND (NOT aHolidayOverride[_i]);   // 日总使能 = 窗使能 AND NOT 节假日
    abWdBit[_i] := FALSE;                   // 星期位默认 FALSE（索引非法时全窗不使能）
    IF _bWdOk THEN
        abWdBit[_i] := aWeekdayWin[_i, _uWd];   // 当日星期位（索引 1..7 已校验）
    END_IF
    abWinValid[_i] := abEnDay[_i] AND abWdBit[_i]
                   AND (aHourOn[_i] <= 23) AND (aMinOn[_i] <= 59);
                                            // 今日有效 = 日使能 AND 星期位 AND 开启参数合法
    _nStartMin := aHourOn[_i];              // USINT → DINT 扩宽（先赋值再乘防溢出）
    _nStartMin := (_nStartMin * 60) + aMinOn[_i];   // 开窗分钟 0..1439
    _atStartT[_i] := T#1M * _nStartMin;     // 分钟域 → TIME 域（MUL(TIME, 整数) 标准序）
END_FOR

_nNowMin := uHourNow;                       // USINT → DINT 扩宽
_nNowMin := (_nNowMin * 60) + uMinNow;      // 当前分钟 0..1439（越界值仅预启带门控弃用）
_tNowT := T#1M * _nNowMin;                  // 当前时刻 → TIME 域
_tLeadT := tPreLeadTime;                    // 提前量原值生效
IF _tLeadT > T#12H THEN
    _tLeadT := T#12H;                       // 防御钳位：提前量组态域建议 ≤ 半日，回绕式防负时长
END_IF

// -----------------------------------------------------------------------------
// 段 5~8｜窗 1~4 实例逐拍无条件刷新（R7：调用与输入准备均不入 IF/CASE 分支）
//        每窗：单日位展开 → 实例调用 → 占用收集 → 实例码归并 → 预启带判定
// -----------------------------------------------------------------------------

// ---- 窗 1（Window 1）----
FOR _j := 1 TO 7 DO
    _abWdSel[_j] := abWdBit[1];             // aWeekdayWin[1, 当日] 单日位展开为 7 日表
END_FOR
_fbWin1(uHourNow := uHourNow, uMinNow := uMinNow,
        bEnableDay := abEnDay[1], aWeekdayEnable := _abWdSel, uWeekdayNow := _uWd,
        uHourOn := aHourOn[1], uMinOn := aMinOn[1],
        uHourOff := aHourOff[1], uMinOff := aMinOff[1], bReset := FALSE);
                                            // 窗 1 实例刷新（bReset 恒 FALSE：实例码仅当拍归并）
abOccWin[1] := _fbWin1.bInWindow;           // 窗 1 占用结果
IF _bDateOk AND (_fbWin1.uErrorId <> 16#0000_0000) THEN
    uErrorId := 16#0005_0211;               // 实例码不透传，归并为本块 0211【信息级】
END_IF
abPreBand[1] := FALSE;                      // 预启带默认未命中
IF abWinValid[1] AND _bTimeOk THEN
    IF _tLeadT <= _atStartT[1] THEN
        abPreBand[1] := (_tNowT >= (_atStartT[1] - _tLeadT)) AND (_tNowT < _atStartT[1]);
                                            // 同日内预启带 [开始−提前, 开始) 左闭右开
    ELSE
        abPreBand[1] := (_tNowT >= ((_atStartT[1] + T#24H) - _tLeadT))
                    OR (_tNowT < _atStartT[1]);
                                            // 跨零点回绕：预启带 [开始+24h−提前, 24h)∪[0, 开始)
    END_IF
END_IF

// ---- 窗 2（Window 2）----
FOR _j := 1 TO 7 DO
    _abWdSel[_j] := abWdBit[2];             // aWeekdayWin[2, 当日] 单日位展开
END_FOR
_fbWin2(uHourNow := uHourNow, uMinNow := uMinNow,
        bEnableDay := abEnDay[2], aWeekdayEnable := _abWdSel, uWeekdayNow := _uWd,
        uHourOn := aHourOn[2], uMinOn := aMinOn[2],
        uHourOff := aHourOff[2], uMinOff := aMinOff[2], bReset := FALSE);
                                            // 窗 2 实例刷新
abOccWin[2] := _fbWin2.bInWindow;           // 窗 2 占用结果
IF _bDateOk AND (_fbWin2.uErrorId <> 16#0000_0000) THEN
    uErrorId := 16#0005_0211;               // 实例码归并【信息级】
END_IF
abPreBand[2] := FALSE;                      // 预启带默认未命中
IF abWinValid[2] AND _bTimeOk THEN
    IF _tLeadT <= _atStartT[2] THEN
        abPreBand[2] := (_tNowT >= (_atStartT[2] - _tLeadT)) AND (_tNowT < _atStartT[2]);
                                            // 同日内预启带
    ELSE
        abPreBand[2] := (_tNowT >= ((_atStartT[2] + T#24H) - _tLeadT))
                    OR (_tNowT < _atStartT[2]);
                                            // 跨零点回绕预启带
    END_IF
END_IF

// ---- 窗 3（Window 3）----
FOR _j := 1 TO 7 DO
    _abWdSel[_j] := abWdBit[3];             // aWeekdayWin[3, 当日] 单日位展开
END_FOR
_fbWin3(uHourNow := uHourNow, uMinNow := uMinNow,
        bEnableDay := abEnDay[3], aWeekdayEnable := _abWdSel, uWeekdayNow := _uWd,
        uHourOn := aHourOn[3], uMinOn := aMinOn[3],
        uHourOff := aHourOff[3], uMinOff := aMinOff[3], bReset := FALSE);
                                            // 窗 3 实例刷新
abOccWin[3] := _fbWin3.bInWindow;           // 窗 3 占用结果
IF _bDateOk AND (_fbWin3.uErrorId <> 16#0000_0000) THEN
    uErrorId := 16#0005_0211;               // 实例码归并【信息级】
END_IF
abPreBand[3] := FALSE;                      // 预启带默认未命中
IF abWinValid[3] AND _bTimeOk THEN
    IF _tLeadT <= _atStartT[3] THEN
        abPreBand[3] := (_tNowT >= (_atStartT[3] - _tLeadT)) AND (_tNowT < _atStartT[3]);
                                            // 同日内预启带
    ELSE
        abPreBand[3] := (_tNowT >= ((_atStartT[3] + T#24H) - _tLeadT))
                    OR (_tNowT < _atStartT[3]);
                                            // 跨零点回绕预启带
    END_IF
END_IF

// ---- 窗 4（Window 4）----
FOR _j := 1 TO 7 DO
    _abWdSel[_j] := abWdBit[4];             // aWeekdayWin[4, 当日] 单日位展开
END_FOR
_fbWin4(uHourNow := uHourNow, uMinNow := uMinNow,
        bEnableDay := abEnDay[4], aWeekdayEnable := _abWdSel, uWeekdayNow := _uWd,
        uHourOn := aHourOn[4], uMinOn := aMinOn[4],
        uHourOff := aHourOff[4], uMinOff := aMinOff[4], bReset := FALSE);
                                            // 窗 4 实例刷新
abOccWin[4] := _fbWin4.bInWindow;           // 窗 4 占用结果
IF _bDateOk AND (_fbWin4.uErrorId <> 16#0000_0000) THEN
    uErrorId := 16#0005_0211;               // 实例码归并【信息级】
END_IF
abPreBand[4] := FALSE;                      // 预启带默认未命中
IF abWinValid[4] AND _bTimeOk THEN
    IF _tLeadT <= _atStartT[4] THEN
        abPreBand[4] := (_tNowT >= (_atStartT[4] - _tLeadT)) AND (_tNowT < _atStartT[4]);
                                            // 同日内预启带
    ELSE
        abPreBand[4] := (_tNowT >= ((_atStartT[4] + T#24H) - _tLeadT))
                    OR (_tNowT < _atStartT[4]);
                                            // 跨零点回绕预启带
    END_IF
END_IF

// -----------------------------------------------------------------------------
// 段 9｜占用合成与活动窗号（多窗同开取最小号；日期非法时全窗自然为 FALSE）
// -----------------------------------------------------------------------------
bOccupied := abOccWin[1] OR abOccWin[2] OR abOccWin[3] OR abOccWin[4];
                                            // 任一有效窗在窗内即占用
FOR _i := 1 TO 4 DO
    IF abOccWin[_i] AND (uActiveWin = 0) THEN
        uActiveWin := _i;                   // 取最小活动窗号（升序首中）
    END_IF
END_FOR

bPreStart := (NOT bOccupied) AND _bTimeOk
         AND (abPreBand[1] OR abPreBand[2] OR abPreBand[3] OR abPreBand[4]);
                                            // 预启动：未占用 AND 时刻合法 AND 任一有效窗预启带命中

// -----------------------------------------------------------------------------
// 段 10｜占用开始沿单发（实例无条件周期刷新，沿输出持续一拍）
// -----------------------------------------------------------------------------
fbTrigOccupy(CLK := bOccupied);             // 占用上升沿检测（主体无条件调用）
bPulseOnOccupy := fbTrigOccupy.Q;           // 占用开始沿单发输出

// -----------------------------------------------------------------------------
// 段 11｜复位沿消费：清除当拍信息级码（触发实例已在段 1 无条件刷新）
// -----------------------------------------------------------------------------
IF fbTrigReset.Q THEN
    uErrorId := 16#0000_0000;               // 复位沿当拍清信息级码（下一拍重新评估）
END_IF

END_FUNCTION_BLOCK
