(*
    FC_DL_LeapYearChk —— 闰年判定原子
    ------------------------------------------------------------------
    分类      : DL_Base / Calendar
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（格里高利历闰年判定，纯整数四级取余）；
                判定律与库内 FB_DL_YearWindowCheck 的闰年判定同源同序（库内复用，
                不另立第四套闰年律）；年份窗口闸、双律/三律切换、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : 质保期、维护周期、年度检定、闰日补偿都要先回答「这一年二月有没有 29 号」。
                本件把这个判定从 FB_DL_YearWindowCheck 里抽成原子函数，供日期运算族
                与用户代码直接调用，避免每处各写一遍、各错一处。
                核心防御：① 纯整数取余比较，禁浮点、禁除法——(y MOD 4)、（y MOD 100）、
                   （y MOD 400）三个判据全部是非负操作数，不存在负数取余的平台歧义；
                ② 双律/三律由 bFullRule 显式选择，不猜测：
                   两律 (y MOD 4 = 0 且 y MOD 100 <> 0) 是现场最常用口径；
                   三律再加 y MOD 400 = 0，用于跨 2000 年这类整百年的场景。
                   在 1900~2099 窗口内两律与三律只在 2000 年一个点分歧
                   （1900 非闰、2000 是闰），故整百年一律发信息级提示，
                   让调用方知道这一年的结论取决于哪一套律；
                ③ 年份域外直接升故障级，返回 FALSE 且 bValid = FALSE——
                   对域外年份做静默猜测（例如按两律硬算）会把 2100 判成闰年，
                   而 2100 不是闰年，这种错会一路传到质保到期日；
                ④ 结果用 BOOL 返回，bValid 区分「判否」与「判不了」：
                   FALSE 可能是「不是闰年」，也可能是「没判」，两者绝不可混淆。
                职责边界：年度窗口与周期判定归 FB_DL_YearWindowCheck；周次计算归
                FC_DL_WeekOfYearCalc；日期加减归 FC_DL_DateAddDays；本件只管闰年原子判定。
    编译门槛  : 主路径只用 IEC 61131-3 的 MOD 运算符与 UINT 整数比较，
                无内建函数依赖，三平台与任何编译器均无门槛。
    错误码    : 16#0001_0430 整百年（y MOD 100 = 0），两律与三律在此处分歧，结论取决于 bFullRule——信息级，值可用
                16#0001_0431 预留禁用（信息级，不得挪用）
                16#0001_0366 年份超出 1900~2099 窗口——故障级，返回 FALSE，bValid = FALSE
                16#0001_0367 预留（故障级，不得挪用）
                16#0001_0368 预留禁用（故障级，不得挪用）
    码位总账  : 16#0001_0430 用 / 16#0001_0431 预留 ｜ 16#0001_0366 用 / 16#0001_0367 预留 / 16#0001_0368 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
                年份是引脚量而非内部锁存，调用方可逐调用传入不同年份。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_LeapYearChk : BOOL
VAR_INPUT
    nYear            : UINT;                  // 待判定年份 [年]，有效域 1900~2099 / year under test [year], valid domain 1900 to 2099
    bFullRule        : BOOL := FALSE;         // FALSE = 两律；TRUE = 四百年律在内的三律 / FALSE uses the two rules, TRUE adds the four hundred year rule
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，eErr 为故障级时 TRUE / error flag, TRUE on fault-level eErr
    bValid           : BOOL;                  // 判定是否有效（域外年份为 FALSE，此时返回值不是结论）/ verdict valid, FALSE when the year is out of domain
END_VAR
VAR CONSTANT
    DL_YEAR_MIN      : UINT := 1900;          // 年份窗口下界 [年] / lower bound of the year window [year]
    DL_YEAR_MAX      : UINT := 2099;          // 年份窗口上界 [年] / upper bound of the year window [year]
    DL_YEAR_STEP4    : UINT := 4;             // 四年律取余基数 [年] / modulus of the four year rule [year]
    DL_YEAR_STEP100  : UINT := 100;           // 百年律取余基数 [年] / modulus of the hundred year rule [year]
    DL_YEAR_STEP400  : UINT := 400;           // 四百年律取余基数 [年] / modulus of the four hundred year rule [year]
    DL_UINT_ZERO     : UINT := 0;             // 无符号零常量，避免裸字面量 [年] / unsigned zero constant [year]
END_VAR
VAR
    bLeap            : BOOL;                  // 闰年判定中间结果 / leap year verdict intermediate
    bCentury         : BOOL;                  // 整百年标志，用于提示两律三律分歧 / century flag used by the divergence hint
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_LeapYearChk := FALSE;                   // 故障缺省返回 FALSE（不是闰年）/ fault default returns FALSE, not a leap year
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 预置无故障 / preset no fault
bValid := FALSE;                              // 预置判定无效，通过闸门后置位 / preset an invalid verdict, set TRUE after the gate
bLeap := FALSE;                               // 判定中间结果预置 / preset the verdict intermediate
bCentury := FALSE;                            // 整百年标志预置 / preset the century flag

// 段 2｜年份窗口闸：域外不猜，直接升故障级 / segment 2, year window gate, never guess
IF (nYear < DL_YEAR_MIN) OR (nYear > DL_YEAR_MAX) THEN
    eErr := 16#0001_0366;                     // 故障级：年份超窗口 / fault level, the year is out of the window
    bError := TRUE;                           // 置故障标志 / raise the error flag
    bValid := FALSE;                          // 判定无效：返回值不是结论 / the verdict is invalid, the return is no conclusion
    FC_DL_LeapYearChk := FALSE;               // 确定缺省值 / deterministic default
    RETURN;                                   // 出口 / exit
END_IF

// 段 3｜两律判定（与库内 FB_DL_YearWindowCheck 同源同序）/ segment 3, the two rule verdict
bLeap := (nYear MOD DL_YEAR_STEP4 = DL_UINT_ZERO)
         AND (nYear MOD DL_YEAR_STEP100 <> DL_UINT_ZERO); // 四年一闰且百年不闰 / divisible by four and not by one hundred

// 段 4｜四百年律（按 bFullRule 显式并入，整百年因此可判为闰）/ segment 4, the four hundred year rule
IF bFullRule THEN
    IF nYear MOD DL_YEAR_STEP400 = DL_UINT_ZERO THEN
        bLeap := TRUE;                        // 四百年一闰，覆盖两律的否定结论 / divisible by four hundred overrides the negative verdict
    END_IF
END_IF

// 段 5｜整百年分歧提示（信息级，不置 bError）/ segment 5, century divergence hint at info level
bCentury := (nYear MOD DL_YEAR_STEP100 = DL_UINT_ZERO);
IF bCentury THEN
    eErr := 16#0001_0430;                     // 信息级：整百年，结论取决于采用两律还是三律 / info level, the verdict depends on the selected rule set
END_IF

// 段 6｜发布结论 / segment 6, publish the verdict
FC_DL_LeapYearChk := bLeap;                   // TRUE = 闰年 [布尔] / TRUE means a leap year [boolean]
bValid := TRUE;                               // 窗口内判定有效 / the verdict inside the window is valid
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
