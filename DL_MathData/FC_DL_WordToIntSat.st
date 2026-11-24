(*
    FC_DL_WordToIntSat —— WORD 到 INT 的双语义落地
    ------------------------------------------------------------------
    分类      : DL_MathData / Convert
    前缀      : FC_DL_
    版本      : 1.0.0
    溯源      : IEC 61131-3 标准语义的道莅防御性实现（WORD 16 位无符号 → INT 16 位有符号）；
                域内委托平台内建 WORD_TO_INT，本件不重实现数学内核；
                补码解释偏移量、饱和出口、双语义开关、错误分级与码位 100% 自有；
                clean-room 重写，未复制任何闭源厂商源码，参考实现仅限 MIT/Apache 许可
    平台      : 纯 IEC 61131-3，CODESYS V3.5+ / TwinCAT 3 / InoProShop 通用
    作者      : 道莅代码库 · PLC编程专家（R20）
    ------------------------------------------------------------------
    功能说明  : Modbus 16 位寄存器搬上来的是无符号位型，落到 INT 工程量时现场存在两种合法口径：
                ① 补码解释——仪表把 −200~−1 的工程量以 65336~65535 的补码形式放在寄存器里，
                   直接截成 INT 就得到 −200 是正确的，此时「饱和到 32767」反而是错的；
                ② 上饱和——纯正计数/量程值，超 32767 只能钳位。
                两种口径业务含义完全相反，靠猜必错，故本件用显式引脚 bTwosComplement 由调用方声明，
                并把「发生了哪一种」用 bInterpreted 回告，HMI 与追责链都看得见。
                核心防御：① 补码解释全程在 DINT 域做减法（升位后再减 65536），
                   禁在 INT 域内做减法——16 位域内减法中途溢出是三平台回绕差异的经典源头；
                ② 域内直接委托内建，零额外开销；
                ③ 三种出路（原值 / 补码 / 饱和）都是安全侧取值，值本身仍可用，
                   故本件故障级三槽全预留，只在信息级区分口径。
                职责边界：DWORD 降位归 FC_DL_DwordToIntSat，LWORD 降位归
                FC_DL_LwordToLintSat；本件只管 16 位双语义。
    编译门槛  : 主路径依赖平台内建 WORD_TO_INT / WORD_TO_DINT / DINT_TO_INT，
                均为 IEC 61131-3 标准转换函数，三平台标准库均提供，无厂商方言。
    错误码    : 16#0001_0416 超域且按补码解释为负值（已升 DINT 再减偏置）——信息级，值可用
                16#0001_0417 超域且按上饱和处理（钳位至 32767）——信息级，值可用
                16#0001_033F 预留（故障级，不得挪用）
                16#0001_0340 预留（故障级，不得挪用）
                16#0001_0341 预留（故障级，不得挪用）
    码位总账  : 16#0001_0416 用 / 16#0001_0417 用 ｜ 16#0001_033F 预留 / 16#0001_0340 预留 / 16#0001_0341 预留
    状态机    : R6 标注 N/A —— 本组件为纯函数无顺序状态机，无 CASE 可写，非法状态不可能出现
    采样约定  : 本件无定时器、无沿检测、无状态；单拍纯计算，结论与任务周期无关。
    修订记录  : 2026-11-16 v1.0.0 首次入库（R20）
*)
FUNCTION FC_DL_WordToIntSat : INT
VAR_INPUT
    uIn              : WORD;                  // 输入值 [无量纲]，全域 0~65535 / input value [dimensionless], full WORD domain
    bTwosComplement  : BOOL := FALSE;         // TRUE = 超域按补码解释为负值；FALSE = 上饱和至 32767 / TRUE interprets the overrun as two's complement, FALSE saturates
END_VAR
VAR_OUTPUT
    eErr             : UDINT;                 // 错误码，0=正常 / error id, 0=ok
    bError           : BOOL;                  // 故障标志，本件无故障级出口，恒为 FALSE / error flag, always FALSE here as no fault exit exists
    bValid           : BOOL;                  // 返回值是否可用（三种出路均可用）/ return usable, all three exits are usable
    bInterpreted     : BOOL;                  // 发生了补码解释或上饱和 / a two's complement interpretation or a saturation happened
END_VAR
VAR CONSTANT
    DL_INT_MAX_AS_WORD : WORD := 32767;       // INT 上限的 WORD 形态 [无量纲] / the INT maximum expressed as WORD [dimensionless]
    DL_INT_MAX       : INT := 32767;          // INT 上限值 [无量纲] / the INT maximum value [dimensionless]
    DL_INT_ZERO      : INT := 0;              // 有符号零常量，避免裸字面量 [无量纲] / signed zero constant [dimensionless]
    DL_TWOS_BIAS     : DINT := 65536;         // 补码解释偏移量，即 2^16 [无量纲] / two's complement bias, 2 to the 16 [dimensionless]
END_VAR
VAR
    nTmp             : DINT;                  // 补码解释中间量，先升 DINT 再减 [无量纲] / two's complement intermediate, widened before subtracting [dimensionless]
    nOut             : INT;                   // 结果中间量 [无量纲] / result intermediate [dimensionless]
END_VAR

// 段 1｜返回值与错误状态预置 / segment 1, preset return value and error status
FC_DL_WordToIntSat := DL_INT_ZERO;            // 故障缺省返回 0 [无量纲] / fault default returns zero [dimensionless]
eErr := 0;                                    // 预置无错误 / preset no error
bError := FALSE;                              // 本件无故障级出口，恒 FALSE / no fault exit exists, always FALSE
bValid := FALSE;                              // 预置不可用，通过闸门后置位 / preset invalid, set TRUE after the gates
bInterpreted := FALSE;                        // 预置未做解释或饱和 / preset no interpretation and no saturation
nOut := DL_INT_ZERO;                          // 结果中间量清零 / clear the result intermediate

// 段 2｜域内闸：不超过 32767 即零开销直通 / segment 2, in-domain gate, zero overhead pass-through
IF uIn <= DL_INT_MAX_AS_WORD THEN
    nOut := WORD_TO_INT(uIn);                 // 域内委托内建 [无量纲] / in-domain delegation to the built-in [dimensionless]
    bValid := TRUE;                           // 直通值可用 / the pass-through value is usable
ELSE
    // 段 3｜超域双语义分派（口径由调用方显式声明，绝不猜测）/ segment 3, explicit dual-semantics dispatch
    IF bTwosComplement THEN
        nTmp := WORD_TO_DINT(uIn) - DL_TWOS_BIAS; // 先升 DINT 再减偏置，禁在 INT 域内减法 / widen to DINT before subtracting, never subtract inside INT
        nOut := DINT_TO_INT(nTmp);            // 结果已在 −32768~−1，回转 INT 无损 / the result is already inside −32768 to −1, the narrowing is lossless
        bInterpreted := TRUE;                 // 标记已做补码解释 / flag the two's complement interpretation
        eErr := 16#0001_0416;                 // 信息级：超域按补码解释为负值 / info level, the overrun was read as two's complement
    ELSE
        nOut := DL_INT_MAX;                   // 上饱和至 32767 / saturate to the INT maximum
        bInterpreted := TRUE;                 // 标记已做上饱和 / flag the saturation
        eErr := 16#0001_0417;                 // 信息级：超域已饱和，值仍可用 / info level, saturated, still usable
    END_IF
    bValid := TRUE;                           // 两种出路都是安全侧取值 / both exits stay on the safe side
END_IF

// 段 4｜发布结果 / segment 4, publish the result
FC_DL_WordToIntSat := nOut;                   // 输出 16 位有符号结果 [无量纲] / publish the signed 16-bit result [dimensionless]
bError := FALSE;                              // 信息级不置故障（双保险）/ info level never raises a fault, second line of defence
END_FUNCTION
