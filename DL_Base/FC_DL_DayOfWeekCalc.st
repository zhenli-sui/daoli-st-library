(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DayOfWeekCalc
 * 所属子库 (Sublibrary) : DL_Base
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3 整数运算，零库依赖，零厂商方言
 * 分类     (Category)   : 函数（FUNCTION）· 日历/星期换算 · Level 0 DL_Base 补强件
 * 功能描述 (Function)   : 年月日 → 星期几换算原子函数（ISO-8601 序：周一=1 …
 *                         周日=7）。参数域校验（年 1980..2099、月 1..12、日按
 *                         当月天数含闰年 4/100/400 判定），越界一律返回
 *                         eInvalid(0) 并置参数非法码 16#0001_0201。算法为
 *                         Sakamoto 公开算法 clean-room 实现：纯整数分段计算，
 *                         无浮点、无除零风险（除数均为非零常量 4/100/400/7）、
 *                         无循环语句（无 WHILE/REPEAT，无死锁义务，机检口径
 *                         本组件按纯分段计算豁免循环计数器审查）。
 * 开源溯源 (Origin)     : 来源标签 lgf-datetime（Siemens LGF V5.2.1 · 3.1 Date
 *                         and timer operations 章）。仅取 LGF「星期计算可拆为
 *                         独立原子 FC」的粒度结论与时间量引脚注入约定；LGF 定时
 *                         开关依赖读 CPU 本地钟，本库零全局耦合红线禁止此耦合，
 *                         日期一律由引脚注入。星期编号取 ISO-8601 周一=1，与
 *                         LGF 周日=1 惯例的差异已在规格书 §4.1 与手册显式声明
 *                         （与 GB/T 7408、MES 排产惯例一致）。核心算法为
 *                         Sakamoto 公开算法 clean-room 重写，未复制任何源码行。
 * 本文件内含       : TYPE E_DL_Weekday（星期枚举，归属 DL_Base，随本函数同文件）
 *                    FUNCTION FC_DL_DayOfWeekCalc
 * 依赖     (Depends)    : 无（纯整数运算，零 DL_ 内部依赖，可单独编译）
 * 故障码表 (Error codes) : 16#0001_0201【信息级】日期参数越界（年/月/日），
 *                          返回 eInvalid(0)；0 = 无故障。沿用 DL_Base 既有
 *                          16#0001_xxxx 段，与 VERSION.md 故障码表无冲突。
 * 红线自检 (Redline)    : R1 ✓ 零全局变量表与外部变量引用 ｜ R2 ✓ 零物理 IO 地址直写
 *                         R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 越界防御+常量除数防除零+闰年处理
 *                         R5 ✓ 全变量中英双语同行注释 ｜ R6 不适用（无状态机，纯函数）
 *                         R7 不适用（无定时器/边沿实例）
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库 · Round 05 · 泳道 B · 契约出处 ROUND_PLAN_R5 §4.1
 * 验收向量 (Acceptance) :
 *   V1 合法基准：2026-11-15 → eSunday(7)，uErrorId=0（Sakamoto 手算复核）
 *   V2 合法基准：2026-01-01 → eThursday(4)；2000-01-01 → eSaturday(6)
 *   V3 闰年边界：2024-02-29 → 合法返回（2024 为闰年，4 整除且非 100 整除）；
 *      2100-02-29 → 0001_0201（2100 为世纪非闰年，100 整除非 400 整除）；
 *      2000-02-29 → 合法返回（400 整除）
 *   V4 年越界：1979 / 2100 → eInvalid(0) + 0001_0201
 *   V5 月/日越界：uMonth=0 / 13、uDay=0 / 32、4-30、2-30 → 0001_0201
 *   V6 端年端日：1980-01-01（周三）与 2099-12-31（周四）合法返回
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_Weekday（归属 DL_Base，与 FC_DL_DayOfWeekCalc 同文件）
 * 含义: ISO-8601 星期序，周一=1 … 周日=7；0 保留为非法/未计算值。
 *----------------------------------------------------------------------------*)
{attribute 'qualified_only'}
{attribute 'strict'}
TYPE E_DL_Weekday :
(
    eInvalid   := 0,   // 非法/未计算（Invalid），参数越界时的返回值
    eMonday    := 1,   // 周一（Monday，ISO-8601 = 1），MES 排产周首日
    eTuesday   := 2,   // 周二（Tuesday，ISO-8601 = 2）
    eWednesday := 3,   // 周三（Wednesday，ISO-8601 = 3）
    eThursday  := 4,   // 周四（Thursday，ISO-8601 = 4）
    eFriday    := 5,   // 周五（Friday，ISO-8601 = 5）
    eSaturday  := 6,   // 周六（Saturday，ISO-8601 = 6）
    eSunday    := 7    // 周日（Sunday，ISO-8601 = 7），GB/T 7408 周末日
) UINT;
END_TYPE

(*==============================================================================
 * 函数: FC_DL_DayOfWeekCalc
 * 返回值即规格引脚 eWeekday（星期几，ISO-8601 序）；非法参数返回 eInvalid(0)。
 *============================================================================*)
FUNCTION FC_DL_DayOfWeekCalc : E_DL_Weekday
VAR_INPUT
    uYear  : UINT;    // 年份（Year）[年]，有效域 1980..2099，越界返回 eInvalid
    uMonth : USINT;   // 月（Month）[月]，有效域 1..12，越界返回 eInvalid
    uDay   : USINT;   // 日（Day）[日]，有效域 1..当月天数（含闰年 2 月 29 日），越界返回 eInvalid
END_VAR
VAR_OUTPUT
    uErrorId : UDINT; // 参数非法码（Error code）：16#0001_0201 = 日期越界；0 = 合法
END_VAR
VAR
    _nY    : DINT;    // 算法内部年（1~2 月按 Sakamoto 惯例回退一年）[年]
    _nT    : DINT;    // Sakamoto 月修正表值（Month offset of Sakamoto table）
    _nWd   : DINT;    // 星期原始值（Raw weekday）0=周日..6=周六
    _nIso  : DINT;    // ISO-8601 星期（ISO weekday）1=周一..7=周日
    _nDim  : DINT;    // 当月天数（Days in month）28..31
    _bLeap : BOOL;    // 闰年标志（Leap year flag），判定规则 4/100/400
END_VAR

// 段 0｜出口默认值先赋（公约 0.8 精神：防御路径之前），越界路径直接沿用此默认
FC_DL_DayOfWeekCalc := E_DL_Weekday.eInvalid;  // 默认返回非法枚举
uErrorId := 16#0001_0201;                      // 默认携带参数越界码（信息级）

// 段 1｜参数域校验：年（规格 §4.1 固定域 1980..2099）
IF (uYear < 1980) OR (uYear > 2099) THEN
    RETURN;                                    // 年越界：保持默认 eInvalid + 0001_0201
END_IF

// 段 2｜参数域校验：月
IF (uMonth < 1) OR (uMonth > 12) THEN
    RETURN;                                    // 月越界：保持默认
END_IF

// 段 3｜闰年判定（4/100/400 三段规则：世纪年须 400 整除）
_nY    := uYear;                               // UINT → DINT 隐式扩宽，无精度损失
_bLeap := (( (_nY MOD 4) = 0) AND ( (_nY MOD 100) <> 0))
       OR ( (_nY MOD 400) = 0);                // 整除判定用 MOD，除数为非零常量，无除零风险

// 段 4｜当月天数与日校验（CASE 兜底分支为不可达防御位，R6 精神）
CASE uMonth OF
    1, 3, 5, 7, 8, 10, 12:  _nDim := 31;       // 大月 31 天
    4, 6, 9, 11:            _nDim := 30;       // 小月 30 天
    2:                                          // 二月按闰年分档
        IF _bLeap THEN
            _nDim := 29;                       // 闰年二月 29 天
        ELSE
            _nDim := 28;                       // 平年二月 28 天
        END_IF
    ELSE
        _nDim := 0;                            // 不可达防御位（月已校验 1..12）
END_CASE
IF (uDay < 1) OR (uDay > _nDim) THEN
    RETURN;                                    // 日越界（含平年 2-29、小月 31 日）：保持默认
END_IF

// 段 5｜Sakamoto 分段计算：1~2 月按惯例回退一年再取月修正表
IF uMonth < 3 THEN
    _nY := _nY - 1;                            // 1~2 月回退一年（Sakamoto 惯例）
END_IF
CASE uMonth OF
    1:  _nT := 0;                              // 月修正表（Sakamoto table，一月）
    2:  _nT := 3;                              // 二月
    3:  _nT := 2;                              // 三月
    4:  _nT := 5;                              // 四月
    5:  _nT := 0;                              // 五月
    6:  _nT := 3;                              // 六月
    7:  _nT := 5;                              // 七月
    8:  _nT := 1;                              // 八月
    9:  _nT := 4;                              // 九月
    10: _nT := 6;                              // 十月
    11: _nT := 2;                              // 十一月
    12: _nT := 4;                              // 十二月
    ELSE
        _nT := 0;                              // 不可达防御位（月已校验 1..12）
END_CASE

// 段 6｜星期合成：纯整数四则 + 常量模 7，结果域 0=周日..6=周六
_nWd := (_nY + (_nY / 4) - (_nY / 100) + (_nY / 400) + _nT + uDay) MOD 7;
//  说明：除数 4/100/400/7 均为非零常量，DINT 正数域整除，无除零风险（R4）

// 段 7｜ISO-8601 换算：0(周日)→7，1..6(周一..周六)→1..6
_nIso := ((_nWd + 6) MOD 7) + 1;

// 段 8｜映射到枚举（strict 枚举不允许整型直赋，显式 CASE 映射）
CASE _nIso OF
    1: FC_DL_DayOfWeekCalc := E_DL_Weekday.eMonday;     // 周一
    2: FC_DL_DayOfWeekCalc := E_DL_Weekday.eTuesday;    // 周二
    3: FC_DL_DayOfWeekCalc := E_DL_Weekday.eWednesday;  // 周三
    4: FC_DL_DayOfWeekCalc := E_DL_Weekday.eThursday;   // 周四
    5: FC_DL_DayOfWeekCalc := E_DL_Weekday.eFriday;     // 周五
    6: FC_DL_DayOfWeekCalc := E_DL_Weekday.eSaturday;   // 周六
    7: FC_DL_DayOfWeekCalc := E_DL_Weekday.eSunday;     // 周日
    ELSE
        FC_DL_DayOfWeekCalc := E_DL_Weekday.eInvalid;   // 不可达防御位（_nIso 恒 1..7）
END_CASE

uErrorId := 16#0000_0000;                      // 合法路径清码

END_FUNCTION
