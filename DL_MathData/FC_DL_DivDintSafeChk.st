(*==============================================================================
 * 组件名称 (Component)  : FC_DL_DivDintSafeChk
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 分类/来源标签         : 函数（FUNCTION）· 纯函数 · DINT 安全除
 *                         iec-std-wrapper / math-safe
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用 IEC 标准 DINT 除法与 MOD 语义
 * 溯源声明 (Provenance) : IEC 61131-3 标准语义的道莅防御性实现——内部委托平台标准库语义，
 *                         外围统一错误码 / 钳位 / 双语注释，严禁重实现数学内核。
 * 功能一句话 (Summary)  : DINT 安全除：除零返回哨兵零并置故障，负最小值除 -1
 *                         的整数溢出显式钳位到 DINT 上限，商余同出可观测。
 *
 * 功能描述 (Function)   : 除零闸先行（除数为零返回哨兵 0 + 故障码）；溢出闸
 *                         拦截 DINT 负最小值除以 -1 的唯一上溢情形，按保守方向
 *                         钳到 DINT 上限；合法路径一次算出商与余数（MOD），
 *                         商余配对输出便于调用方做可逆校验。
 * 与既有件边界 (Boundary): 与 FC_DL_DivLrealSafe 构成整数域/实数域对偶；
 *                         本件哨兵零与「真实商为零」区分靠 bError 与事件码，
 *                         哨兵只出现在故障路径。
 * 码位说明 (Codes)      : 信息 16#0002_304C 整除无余数（余数为零）
 *                         故障 16#0002_304D 除数为零，商返回哨兵零
 *                         故障 16#0002_304E 商溢出（负最小值除 -1），已钳上限
 *                         段 16#02_3_4C~4F 首槽信息级、次槽起故障级。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 IEC 标准 DINT 除法 / MOD / 常量。
 * 红线自检 (Redline)    : 零全局依赖 ｜ 零 VAR_EXTERNAL ｜ 零 %I/%Q ｜ 纯 IEC 标准库
 *                         除法前强制判零 ｜ 全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-18  v1.0.0  首版入库（R32 · 批 2）
 *============================================================================*)

FUNCTION FC_DL_DivDintSafeChk : BOOL
VAR_INPUT
    iDividend : DINT;                   // 被除数 [整数域] / Dividend
    iDivisor  : DINT;                   // 除数 [整数域]，零即触发除零闸 / Divisor, zero triggers the gate
END_VAR
VAR_OUTPUT
    iQuot   : DINT;                     // 商 [整数]，故障路径为哨兵零 / Quotient, sentinel zero on fault
    iRem    : DINT;                     // 余数 [整数]，故障路径为零 / Remainder, zero on fault
    bError  : BOOL;                     // 故障标志，与故障码 304D/304E 配对 / Fault flag paired with codes
    uErrorId: UDINT;                    // 事件码，0 表示无事件 / Event code, zero means none
END_VAR
VAR
    uCode : UDINT;   // 码位暂存，出口单点写入 [码] / Code staging
END_VAR
VAR CONSTANT
    DL_DDS_IMIN : DINT := -2147483648;  // DINT 负最小值 [整数] / DINT most negative value
    DL_DDS_IMAX : DINT := 2147483647;   // DINT 正最大值 [整数] / DINT most positive value
END_VAR

(* 段 1｜输出预置 / Pre-set *)
FC_DL_DivDintSafeChk := FALSE;
iQuot    := 0;
iRem     := 0;
bError   := FALSE;
uErrorId := 16#0000_0000;
uCode    := 16#0000_0000;

(* 段 2｜除零闸：哨兵零 + 故障配对（R45），绝不放行平台异常 / Divide-by-zero gate with sentinel and fault pairing *)
IF iDivisor = 0 THEN
    iQuot    := 0;               // 哨兵零，与真实零商靠 bError 区分 / Sentinel zero, distinguished by bError
    iRem     := 0;
    bError   := TRUE;            // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_304D;    // 故障级：除数为零 / Fault: divisor is zero
    RETURN;
END_IF

(* 段 3｜溢出闸：DINT 负最小值除以 -1 是唯一上溢点，钳到上限 / Overflow gate: the only DINT overflow, clamp to the max *)
IF (iDividend = DL_DDS_IMIN) AND (iDivisor = -1) THEN
    iQuot    := DL_DDS_IMAX;     // 保守方向钳位 / Conservative clamp upward
    iRem     := 0;               // 溢出情形余数无意义，置零 / Remainder meaningless here
    bError   := TRUE;            // 故障级码配对置位 / Fault flag paired
    uErrorId := 16#0002_304E;    // 故障级：商溢出已钳 / Fault: quotient overflow clamped
    FC_DL_DivDintSafeChk := TRUE;
    RETURN;
END_IF

(* 段 4｜合法路径：商余一次算出，余数只判一次 / Legal path: quotient and remainder in one pass *)
iQuot := iDividend / iDivisor;   // 整数除法向零截断（标准语义）/ Integer division truncates toward zero
iRem  := iDividend MOD iDivisor; // 标准取余，符号随被除数 / Standard remainder, sign follows the dividend
IF iRem = 0 THEN
    uCode := 16#0002_304C;       // 信息级：整除无余数 / Info: exact division
END_IF
uErrorId := uCode;               // 码位单点写入 / Single write point
FC_DL_DivDintSafeChk := TRUE;
END_FUNCTION
