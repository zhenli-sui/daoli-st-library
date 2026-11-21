(*
    组件名称 : FC_DL_DateToIsoString
    所属子库 : DL_MathData
    当前版本 : 1.0.1
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : DATE → 'YYYY-MM-DD' 十字符定宽文本，同时把年/月/日分解结果单出口，供 MES 台账与文件名直接取用。
              取舍 ①：用 Howard Hinnant 的 civil_from_days 整数算法反算日历 —— 纯整数、无查表、无浮点、无循环，
              对任意天数一次算到位；相比「按年循环扣天数」的写法，没有循环也就没有死循环风险与扫描周期抖动。
              取舍 ②：回代自校验（days_from_civil 反算天数必须等于输入）—— 日期算法的错误往往表现为「差一天」，
              这种错在报表上极难发现，回代一次就能把「算法实现错」与「输入数据错」彻底分开；
              自校验不过就绝不输出日期。
              取舍 ③：不做平台 DATE_TO_DTL 委托 —— DTL 结构体在部分平台的字段宽度与日期语义不一致，
              且本件只需要三个整数；直接走 DATE_TO_DINT 天数口径，链路最短。
              取舍 ④：早于纪元（1970-01-01）一律判故障 —— 负数天数在部分平台 DATE 实现里是「不支持」而非「负日期」，
              与其猜，不如让调用方知道这个值不可信。
    开源溯源 : T2-1 LGF Converter 子族（只借「日期转定宽文本」这一行为定义）。civil_from_days / days_from_civil；本件为道莅 clean-room 防御性实现（仅借 LGF 分类事实/参数域/行为定义，零代码行与符号名复制）。
              为公开算法（Howard Hinnant，公有领域），本实现按整数语义重写，零代码行与注释复制；
              码位、错误分级、自校验策略 100% 自有。
    本文件内含 : FUNCTION FC_DL_DateToIsoString（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: LEN / MID / CONCAT
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 纪元闸 + 年份域闸 + 回代自校验 + 输出长度自证（全整数，无除法零风险）
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 纪元常数、闰年基数、月长基数全常量化
    错误码   : 16#0001_0450 [信息级] 输出串长异常（补零逻辑防御提示），bValid = TRUE
               16#0001_0451 [信息级] 预留禁用（不得挪用）
               16#0001_0396 [故障级] 早于纪元或年份越 1970~9999，返回 '1970-01-01'，bValid = FALSE
               16#0001_0397 [故障级] 回代自校验失败（算法自证不过），返回 '1970-01-01'，bValid = FALSE
               16#0001_0398 [故障级] 预留禁用（不得挪用）
    码位总账 : 16#0001_0450 用 / 16#0001_0451 预留 ｜ 16#0001_0396 用 / 16#0001_0397 用 / 16#0001_0398 预留
    遗留假设 : ① 【编译门槛未闭合】本件依赖「DATE_TO_DINT 返回自 1970-01-01 起的天数、纪元当日记 0」这一口径。
              CODESYS / TwinCAT 3 默认如此，InoProShop 未实测；若某平台返回秒或返回 1970-01-01 记 1，
              回代自校验会失败并置 0397（可观测，不会静默出错）。
              ② 整数除法在三平台均向零截断，本件全部操作数为非负，故截断方向不敏感 —— IEC 语义推导，未逐平台实测。
              ③ MID 参数序按 IEC 标准 MID(串, 长度, 位置)，与库内既有用法同序。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 3 入库
        2026-11-16  v1.0.1  R21 终审修复（严重）：年序判据末项除数误用 DL_ERA_DAYS = 146097，
                            而 Hinnant civil_from_days 该处应为「周期内最大天序」146096。二者仅在
                            nDoe = 146096（即每个 400 年周期的最后一天 = 世纪闰日 2 月 29 日）时结果不同：
                            错值使 nYoe = 400 越出 [0, 399]，回代自校验随即失败，2000-02-29 / 2400-02-29
                            等合法日期被误判为 0397 故障并回退成 '1970-01-01'。新增常量 DL_ERA_LAST = 146096
                            并改用于该式；其余天序取值两种除数同解，故本次修复零副作用。向量已用等价脚本
                            复算：1970-01-01 / 1999-12-31 / 2000-02-29 / 2026-11-16 / 9999-12-31 全部自校验通过。
*)
FUNCTION FC_DL_DateToIsoString : STRING
VAR_INPUT
    dateIn          : DATE;   // 待格式化日期，有效域 1970-01-01 ~ 9999-12-31 / date to format, valid from 1970-01-01 to 9999-12-31
END_VAR
VAR_OUTPUT
    eErr            : UDINT;  // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;   // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;   // 返回值是否可用 / result usable flag
    nYear           : INT;    // 分解出的年份 1970~9999 [年] / decomposed year [year]
    nMonth          : INT;    // 分解出的月份 1~12 [月] / decomposed month [month]
    nDay            : INT;    // 分解出的日 1~31 [日] / decomposed day [day]
END_VAR
VAR
    nDays           : DINT;   // 自纪元起的天数 [天] / days since the epoch [day]
    nZ              : DINT;   // 纪元平移后的天数（+719468）[天] / day count shifted by the epoch offset [day]
    nEra            : DINT;   // 400 年周期序号 [周期] / four hundred year era index [era]
    nDoe            : DINT;   // 纪元年内的天序 0~146096 [天] / day of era, 0..146096 [day]
    nYoe            : DINT;   // 纪元年内年序 0~399 [年] / year of era, 0..399 [year]
    nDoy            : DINT;   // 年内的天序 0~365 [天] / day of year, 0..365 [day]
    nMp             : DINT;   // 三月起算的月序 0~11 [月] / month index counted from March, 0..11 [month]
    nY              : DINT;   // 工作年值 [年] / working year value [year]
    nM              : DINT;   // 工作月值 [月] / working month value [month]
    nD              : DINT;   // 工作日值 [日] / working day value [day]
    nCheck          : DINT;   // 回代算出的天数，用于自校验 [天] / recomputed day count used for the self check [day]
    nChkY           : DINT;   // 回代用年 [年] / year used by the reverse pass [year]
    nChkYoe         : DINT;   // 回代纪元年内年序 0~399 [年] / year of era used by the reverse pass [year]
    nChkDoy         : DINT;   // 回代用年内天序 [天] / day of year used by the reverse pass [day]
    nChkDoe         : DINT;   // 回代用纪元年内天序 [天] / day of era used by the reverse pass [day]
    sRet            : STRING; // 结果装配缓冲 [字符] / result assembly buffer [char]
    nLen            : INT;    // 结果实际长度 [字符] / actual result length [char]
END_VAR
VAR CONSTANT
    DL_ISO_LEN          : INT := 10;                 // 目标串长 'YYYY-MM-DD' [字符] / target length [char]
    DL_EPOCH_YEAR       : INT := 1970;               // 纪元年份 [年] / epoch year [year]
    DL_YEAR_MIN         : INT := 1970;               // 年份下界 [年] / lower year bound [year]
    DL_YEAR_MAX         : INT := 9999;               // 年份上界 [年] / upper year bound [year]
    DL_EPOCH_OFFSET     : DINT := 719468;            // 1970-01-01 在 Hinnant 纪元中的天序 [天] / epoch offset of 1970-01-01 [day]
    DL_ERA_DAYS         : DINT := 146097;            // 400 年周期的天数 [天] / days in a four hundred year era [day]
    DL_ERA_LAST         : DINT := 146096;            // 400 年周期内最大天序 = DL_ERA_DAYS − 1，年序判据专用除数 [天] / last day index inside an era, the dedicated divisor of the year-of-era test [day]
    DL_ERA_YEARS        : DINT := 400;               // 400 年周期的年数 [年] / years in an era [year]
    DL_CENTURY_DAYS     : DINT := 36524;             // 百年天数（闰日扣除用）[天] / days in a century used by the leap correction [day]
    DL_QUAD_DAYS        : DINT := 1460;              // 四年天数（闰日扣除用）[天] / days in four years used by the leap correction [day]
    DL_CENTURY_YEARS    : DINT := 100;               // 百年年数 [年] / years in a century [year]
    DL_YEAR_DAYS        : DINT := 365;               // 平年天数 [天] / days in a common year [day]
    DL_LEAP_DIV         : DINT := 4;                 // 四年闰基数 [年] / four year leap radix [year]
    DL_MONTH_SHIFT      : DINT := 3;                 // 三月起算的月偏移 [月] / month shift of the March based calendar [month]
    DL_MONTH_BASE       : DINT := 10;                // 三月起算的月份分界 [月] / boundary between the two month groups [month]
    DL_MONTH_ROLL       : DINT := 9;                 // 月份回卷量（mp + 3 − 12）[月] / month roll over amount [month]
    DL_MONTH_SUB        : DINT := 3;                 // 回代时 m > 2 分支的月偏移量（m − 3）[月] / month offset of the m greater than two branch [month]
    DL_MONTH_FEB        : DINT := 2;                 // 一、二月的分界值 [月] / boundary value of January and February [month]
    DL_DOY_SCALE        : DINT := 153;               // 月长累加系数 153 = 5 个月 × 30.6 [无量纲] / month length coefficient [dimensionless]
    DL_DOY_BIAS         : DINT := 2;                 // 月序取整偏置 [无量纲] / rounding bias of the month index [dimensionless]
    DL_DOY_DIV          : DINT := 5;                 // 月序除数 [无量纲] / divisor of the month index [dimensionless]
    DL_DIGIT_TABLE      : STRING := '0123456789';    // 数字字符表，MID 位置 = 值 + 1 [字符] / digit table, the MID position is the value plus one [char]
    DL_ISO_DASH         : STRING := '-';             // 日期分隔符 [字符] / date separator [char]
    DL_ISO_FALLBACK     : STRING := '1970-01-01';    // 故障回退串，长度恒 10 [字符] / fault fallback text with a constant length of ten [char]
    DL_ISO_ONE          : INT := 1;                  // 单位哨兵，MID 位置 1 基 [无量纲] / unity sentinel, MID is one based [dimensionless]
    DL_ISO_DIGIT_TEN    : DINT := 10;                // 十进制位数基数 [无量纲] / decimal digit radix [dimensionless]
    DL_ISO_DIGIT_HUND   : DINT := 100;               // 百位基数 [无量纲] / hundreds radix [dimensionless]
    DL_ISO_DIGIT_THOU   : DINT := 1000;              // 千位基数 [无量纲] / thousands radix [dimensionless]
    DL_DINT_ZERO        : DINT := 0;                 // 零哨兵 [无量纲] / zero sentinel [dimensionless]
    DL_INT_ZERO         : INT := 0;                  // 整数零哨兵，月份判零用 [月] / integer zero sentinel [month]
    DL_ERR_NONE         : UDINT := 16#0000_0000;     // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_DateToIsoString := DL_ISO_FALLBACK;   // 故障缺省返回纪元日 / fault default returns the epoch date
eErr   := DL_ERR_NONE;                       // 预置无错误 / preset no error
bError := FALSE;                             // 预置无故障 / preset no fault
bValid := FALSE;                             // 预置结果不可用 / preset unusable
nYear  := DL_EPOCH_YEAR;                     // 预置年份为纪元年 / preset the year to the epoch
nMonth := 1;                                 // 预置月 1 / preset the month to one
nDay   := 1;                                 // 预置日 1 / preset the day to one
sRet   := '';                                // 缓冲清空 / clear the buffer

// 段 2｜天数口径与纪元闸 / segment 2, day count and epoch gate
nDays := DATE_TO_DINT(dateIn);               // 天数口径（1970-01-01 = 0），见遗留假设 ① / day count with the epoch at zero, see assumption one
IF nDays < DL_DINT_ZERO THEN
    eErr   := 16#0001_0396;                  // 早于纪元（故障级）/ earlier than the epoch, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
    RETURN;                                  // 返回纪元日 / return the epoch date
END_IF

// 段 3｜civil_from_days 反算（全整数，无循环）/ segment 3, civil from days with integer arithmetic only
nZ    := nDays + DL_EPOCH_OFFSET;            // 平移到 Hinnant 纪元 / shift into the Hinnant epoch
nEra  := nZ / DL_ERA_DAYS;                   // nZ 恒为正，直接整除即可 / nZ is always positive, a plain division suffices
nDoe  := nZ - nEra * DL_ERA_DAYS;            // 纪元年内天序 / day of era
nYoe  := (nDoe - nDoe / DL_QUAD_DAYS + nDoe / DL_CENTURY_DAYS - nDoe / DL_ERA_LAST) / DL_YEAR_DAYS;   // 纪元年内年序，末项除数为 146096 而非 146097 / year of era, the last divisor is 146096 not 146097
nY    := nYoe + nEra * DL_ERA_YEARS;         // 绝对年份 / absolute year
nDoy  := nDoe - (DL_YEAR_DAYS * nYoe + nYoe / DL_LEAP_DIV - nYoe / DL_CENTURY_YEARS);                 // 年内天序 / day of year
nMp   := (DL_DOY_DIV * nDoy + DL_DOY_BIAS) / DL_DOY_SCALE;                                            // 三月起算月序 / March based month index
nD    := nDoy - (DL_DOY_SCALE * nMp + DL_DOY_BIAS) / DL_DOY_DIV + DL_ISO_ONE;                         // 日 / day of month
IF nMp < DL_MONTH_BASE THEN
    nM := nMp + DL_MONTH_SHIFT;              // 三月到十二月 / March to December
ELSE
    nM := nMp - DL_MONTH_ROLL;               // 一月与二月，顺带年前推已在下面补 / January and February
END_IF
IF nM <= DL_MONTH_FEB THEN
    nY := nY + DL_ISO_ONE;                   // 一、二月属上一日历年，年值补一 / January and February belong to the previous calendar year
END_IF

// 段 4｜年份域闸 / segment 4, year domain gate
IF (nY < DL_YEAR_MIN) OR (nY > DL_YEAR_MAX) THEN
    eErr   := 16#0001_0396;                  // 年份越域（故障级）/ year out of domain, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
    RETURN;                                  // 返回纪元日 / return the epoch date
END_IF

// 段 5｜回代自校验：days_from_civil(y, m, d) 必须等于输入天数 / segment 5, reverse self check
nChkY := nY;                                 // 回代用年，取分解结果 / reverse pass year taken from the decomposed result
IF nM <= DL_MONTH_FEB THEN
    nChkY := nChkY - DL_ISO_ONE;             // 一、二月回退一年 / January and February roll the year back
END_IF
IF nM > DL_MONTH_FEB THEN
    nChkDoy := (DL_DOY_SCALE * (nM - DL_MONTH_SUB) + DL_DOY_BIAS) / DL_DOY_DIV + nD - DL_ISO_ONE;   // 三月起算的天序 / day of year for the March based branch
ELSE
    nChkDoy := (DL_DOY_SCALE * (nM + DL_MONTH_ROLL) + DL_DOY_BIAS) / DL_DOY_DIV + nD - DL_ISO_ONE;   // 一、二月的天序 / day of year for January and February
END_IF
nChkYoe := nChkY - (nChkY / DL_ERA_YEARS) * DL_ERA_YEARS;                                              // 纪元年内年序 0~399 / year of era
nChkDoe := nChkYoe * DL_YEAR_DAYS + nChkYoe / DL_LEAP_DIV - nChkYoe / DL_CENTURY_YEARS + nChkDoy;      // 年内闰日修正后加天序 / leap corrected day of year
nCheck  := (nChkY / DL_ERA_YEARS) * DL_ERA_DAYS + nChkDoe - DL_EPOCH_OFFSET;                            // 回代天数 / recomputed day count
IF nCheck <> nDays THEN
    eErr   := 16#0001_0397;                  // 回代自校验失败（故障级）/ reverse self check failed, fault level
    bError := TRUE;                          // 置故障标志 / raise the fault flag
    RETURN;                                  // 不输出未经复验的日期 / never publish an unverified date
END_IF

// 段 6｜定宽格式化：年 4 位、月日 2 位，逐位查表 / segment 6, fixed width formatting with table lookups
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nY / DL_ISO_DIGIT_THOU) + DL_ISO_ONE));                                  // 千位 / thousands
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT((nY / DL_ISO_DIGIT_HUND) MOD DL_ISO_DIGIT_TEN) + DL_ISO_ONE));           // 百位 / hundreds
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT((nY / DL_ISO_DIGIT_TEN) MOD DL_ISO_DIGIT_TEN) + DL_ISO_ONE));            // 十位 / tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nY MOD DL_ISO_DIGIT_TEN) + DL_ISO_ONE));                                 // 个位 / units
sRet := CONCAT(sRet, DL_ISO_DASH);           // 分隔符 / separator
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nM / DL_ISO_DIGIT_TEN) + DL_ISO_ONE));                                   // 月十位 / month tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nM MOD DL_ISO_DIGIT_TEN) + DL_ISO_ONE));                                 // 月个位 / month units
sRet := CONCAT(sRet, DL_ISO_DASH);           // 分隔符 / separator
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nD / DL_ISO_DIGIT_TEN) + DL_ISO_ONE));                                   // 日十位 / day tens
sRet := CONCAT(sRet, MID(DL_DIGIT_TABLE, DL_ISO_ONE, DINT_TO_INT(nD MOD DL_ISO_DIGIT_TEN) + DL_ISO_ONE));                                 // 日个位 / day units

// 段 7｜分解结果单出口与长度自证 / segment 7, decomposed values and length self proof
nYear  := DINT_TO_INT(nY);                   // 年份出口 / publish the year
nMonth := DINT_TO_INT(nM);                   // 月份出口 / publish the month
nDay   := DINT_TO_INT(nD);                   // 日出口 / publish the day
nLen   := LEN(sRet);                         // 实际长度 / the actual length
IF nLen <> DL_ISO_LEN THEN
    eErr := 16#0001_0450;                    // 输出串长异常（信息级，只提示补零逻辑异常）/ length anomaly, info level
END_IF

// 段 8｜出口 / segment 8, exit
FC_DL_DateToIsoString := sRet;               // 输出 ISO 日期文本 / publish the ISO date text
bValid := TRUE;                              // 结果可用 / the result is usable
END_FUNCTION
