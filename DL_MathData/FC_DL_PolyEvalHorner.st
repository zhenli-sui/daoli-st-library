(*
    组件名称 : FC_DL_PolyEvalHorner
    所属子库 : DL_MathData
    当前版本 : 1.0.0
    兼 容 性 : CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop；仅依赖 Standard.library
    功能描述 : Horner 法多项式求值内核，PT100 Callendar-Van Dusen、热电偶 NIST 多项式、传感器多点拟合的公共出口。
              取舍 ①：升幂系数 a0..an + Horner 递推，n 次乘加内完成求值；相比「逐项 x^i × a_i」少一半乘法、
              少 n 次幂运算，更重要的是不产生中间大数（x^i 在高阶处会先溢出，再乘 a_i 又变回来，纯损失精度）。
              取舍 ②：前导零系数自动降阶 —— 上位机配置表常把 4 阶多项式填进 8 阶槽位，尾部全是 0.0；
              不降阶就会白做 4 次「乘 0 加 0」，把尾数误差放大并拖慢扫描。降阶后 nEffOrder 一并出口，
              调用方能看到「实际用了几阶」。
              取舍 ③：系数用 VAR_IN_OUT 免拷贝 —— 8 阶 LREAL 数组按值传参在部分平台是一次整段复制，
              本件是高频调用内核算术路径，不能付这个代价。
              取舍 ④：中间量逐阶判非有限 —— 溢出可能发生在中途而终值又被后续系数拉回有限域，
              只查终值会漏掉「中间已脏、结果恰好像样」的假值。
    开源溯源 : 原创实现。与存量 FC_DL_MultiPointLinear / FC_DL_InterpolateTable2D 的边界：那两件是分段线性/双线性，；本件为 IEC 61131-3 标准语义的道莅防御性实现（原创实现，零外部源码复制）。
              本件是单一多项式。无外部源码参考，码位与分级 100% 自有。
    本文件内含 : FUNCTION FC_DL_PolyEvalHorner（单 POU，无配套类型）
    依 赖 : 无 DL_ 内部依赖；Standard.library: 无
    红线自检 : R1 ✓ 零全局变量与外部变量 ｜ R2 ✓ 零物理 IO 地址
              R3 ✓ 纯 IEC 61131-3 ｜ R4 ✓ 阶数闸 + 非有限闸 + WHILE 守卫计数器 + 中间量逐阶复检
              R5 ✓ 全变量中英双语同行注释 ｜ R6 N/A 纯函数无顺序状态机，无 CASE 可写
              R7 N/A 无定时器、无沿检测实例 ｜ R8 ✓ 阶数上限、容差、有限域全常量化
    错误码   : 16#0001_043A [信息级] 前导零系数已降阶，nEffOrder < nOrder，bValid = TRUE
               16#0001_043B [信息级] 预留禁用（不得挪用）
               16#0001_0375 [故障级] 阶数越界（< 0 或 > DL_POLY_MAX_ORDER），返回 0，bValid = FALSE
               16#0001_0376 [故障级] fX 或参与运算的系数非有限，返回 0，bValid = FALSE
               16#0001_0377 [故障级] 中间量或结果溢出，返回 0，bValid = FALSE
    码位总账 : 16#0001_043A 用 / 16#0001_043B 预留 ｜ 16#0001_0375 用 / 16#0001_0376 用 / 16#0001_0377 用
    遗留假设 : ① FOR 循环在初值小于终值时（如 nEffOrder = 0 时的 DOWNTO）执行零次，IEC 语义保证；
              本件仍用 IF nEffOrder > 0 显式包一层，不依赖该语义。此写法为双保险，未三平台逐一实测。
              ② 无时间/日期与字符串内建依赖，编译门槛未见风险。
    修订历史 :
        2026-11-16  v1.0.0  首版，R21 批次 1 入库
*)
FUNCTION FC_DL_PolyEvalHorner : LREAL
VAR_INPUT
    nOrder          : INT := 0;                  // 阶数，0~DL_POLY_MAX_ORDER，越界即拒算 [阶] / polynomial order, rejected when out of range [order]
    fX              : LREAL := 0.0;              // 自变量，如温度 [工程单位] / independent variable, e.g. temperature [engineering unit]
END_VAR
VAR_IN_OUT
    afCoeff         : ARRAY[0..DL_POLY_MAX_ORDER] OF LREAL;   // 升幂系数 a0..an，下标即幂次；前导零自动降阶 [系数] / ascending coefficients, the index is the power [coefficient]
END_VAR
VAR_OUTPUT
    eErr            : UDINT;                     // 错误码，0=正常；16#0001_04XX 信息级 / 16#0001_03XX 故障级 / error id, 0=ok
    bError          : BOOL;                      // 故障级标志，eErr 落 16#0001_03XX 时为 TRUE / fault flag, TRUE on fault-level eErr
    bValid          : BOOL;                      // 求值结果是否可用 / evaluation usable flag
    nEffOrder       : INT;                       // 实际使用的阶数（降阶后）[阶] / effective order after the leading zero reduction [order]
END_VAR
VAR
    nEff            : INT;                       // 降阶游标 [阶] / reduction cursor [order]
    nGuard          : DINT;                      // WHILE 防死锁守卫计数 [次] / loop guard counter [count]
    nIdx            : INT;                       // Horner 递推下标 [阶] / Horner recursion index [order]
    nJ              : INT;                       // 升序循环变量（镜像下标用）[阶] / ascending loop var for mirrored index
    fAcc            : LREAL;                     // 累加工作寄存器 [工程单位] / accumulation working register [engineering unit]
    bOverflow       : BOOL;                      // 中间量溢出标志 / intermediate overflow flag
END_VAR
VAR CONSTANT
    DL_POLY_MAX_ORDER   : INT := 8;                            // 最高阶数（PT100 CVD 4 阶、热电偶 NIST ≤ 8 阶）[阶] / highest supported order [order]
    DL_POLY_GUARD_MAX   : DINT := 32;                          // 降阶 WHILE 守卫上限，远大于 8，纯防御 [次] / guard limit for the reduction loop, pure defence [count]
    DL_FLOAT_EPS        : LREAL := 1.0E-12;                    // 判零容差，系数降阶用（禁 = 0 判等）[无量纲] / zero tolerance for the reduction test [dimensionless]
    DL_LREAL_MAX_FINITE : LREAL := 1.7976931348623157E308;     // LREAL 最大有限值 [无量纲] / largest finite LREAL [dimensionless]
    DL_LREAL_ZERO       : LREAL := 0.0;                        // 零哨兵 [无量纲] / zero sentinel [dimensionless]
    DL_INT_ONE          : INT := 1;                            // 单位哨兵，避免裸 1 [无量纲] / unity sentinel [dimensionless]
    DL_ERR_NONE         : UDINT := 16#0000_0000;               // 无故障 / no error
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset the return value and the error state
FC_DL_PolyEvalHorner := DL_LREAL_ZERO;  // 故障缺省返回 0 / fault default returns zero
eErr        := DL_ERR_NONE;             // 预置无错误 / preset no error
bError      := FALSE;                   // 预置无故障 / preset no fault
bValid      := FALSE;                   // 预置结果不可用 / preset unusable
nEffOrder   := 0;                       // 预置实际阶数 0 / preset the effective order to zero
nEff        := 0;                       // 预置降阶游标 / preset the reduction cursor

// 段 2｜阶数闸：越界一律拒算，不做静默钳位 / segment 2, order gate, reject instead of silently clamping
IF (nOrder < 0) OR (nOrder > DL_POLY_MAX_ORDER) THEN
    eErr   := 16#0001_0375;             // 阶数越界（故障级）/ order out of range, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 3｜自变量有限性闸 / segment 3, independent variable finiteness gate
IF (fX <> fX) OR (ABS(fX) > DL_LREAL_MAX_FINITE) THEN
    eErr   := 16#0001_0376;             // 自变量非有限（故障级）/ non-finite independent variable, fault level
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
END_IF

// 段 4｜前导零降阶：WHILE 必带守卫计数器，超限即判故障 / segment 4, leading zero reduction with a guarded WHILE
nEff   := nOrder;                       // 从声明阶数起降 / start from the declared order
nGuard := 0;                            // 守卫计数清零 / clear the guard counter
WHILE (nEff > 0) AND (ABS(afCoeff[nEff]) < DL_FLOAT_EPS) AND (nGuard <= DL_POLY_GUARD_MAX) DO
    nEff   := nEff - 1;                 // 最高阶系数为零，降一阶 / the top coefficient is zero, drop one order
    nGuard := nGuard + 1;               // 守卫递增 / increment the guard
END_WHILE
IF nGuard > DL_POLY_GUARD_MAX THEN
    eErr   := 16#0001_0377;             // 降阶失控判溢出类故障（理论不可达，纯防御）/ reduction runaway, defensive only
    bError := TRUE;                     // 置故障标志 / raise the fault flag
    RETURN;                             // 返回 0 / return zero
END_IF
nEffOrder := nEff;                      // 出口实际阶数 / publish the effective order
IF nEff < nOrder THEN
    eErr := 16#0001_043A;               // 前导零已降阶（信息级，不置 bError）/ leading zeros reduced, info level
END_IF

// 段 5｜参与运算的系数有限性闸：只查 0..nEff，未参与的槽位不参与判据 / segment 5, finiteness of the participating coefficients only
FOR nIdx := 0 TO nEff DO
    IF (afCoeff[nIdx] <> afCoeff[nIdx]) OR (ABS(afCoeff[nIdx]) > DL_LREAL_MAX_FINITE) THEN
        eErr   := 16#0001_0376;         // 系数非有限（故障级）/ non-finite coefficient, fault level
        bError := TRUE;                 // 置故障标志 / raise the fault flag
        RETURN;                         // 返回 0，bValid 保持 FALSE / return zero, bValid stays FALSE
    END_IF
END_FOR

// 段 6｜Horner 递推：nEff 次乘加，逐阶复检中间量 / segment 6, Horner recursion with per-step re-check
fAcc       := afCoeff[nEff];            // 最高阶系数作为起值 / seed with the top coefficient
bOverflow  := FALSE;                    // 溢出标志清零 / clear the overflow flag
IF nEff > 0 THEN
    FOR nJ := 0 TO (nEff - 1) DO
        nIdx := (nEff - 1) - nJ;                                              // 镜像下标：R509 禁 DOWNTO / mirrored index, DOWNTO unsupported
        fAcc := fAcc * fX + afCoeff[nIdx];                                  // 一次乘加降一阶 / one multiply-add per order
        IF (fAcc <> fAcc) OR (ABS(fAcc) > DL_LREAL_MAX_FINITE) THEN          // 中间量非有限即溢出 / a non-finite intermediate means overflow
            bOverflow := TRUE;                                              // 锁定溢出标志 / latch the overflow flag
        END_IF
    END_FOR
END_IF

// 段 7｜出口复检：中间溢出与终值溢出同码 / segment 7, exit re-check, an intermediate or final overflow shares one code
IF bOverflow OR (ABS(fAcc) > DL_LREAL_MAX_FINITE) THEN
    FC_DL_PolyEvalHorner := DL_LREAL_ZERO;  // 溢出不给伪值 / never emit a pseudo value on overflow
    eErr   := 16#0001_0377;                 // 结果溢出（故障级）/ result overflow, fault level
    bError := TRUE;                         // 置故障标志 / raise the fault flag
    RETURN;                                 // bValid 保持 FALSE / bValid stays FALSE
END_IF

// 段 8｜出口 / segment 8, exit
FC_DL_PolyEvalHorner := fAcc;           // 输出求值结果 / publish the evaluation result
bValid := TRUE;                         // 结果可用 / the result is usable
END_FUNCTION
