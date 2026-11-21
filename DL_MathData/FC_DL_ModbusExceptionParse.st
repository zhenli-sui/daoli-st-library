(*==============================================================================
 * 组件名称 (Component)  : FC_DL_ModbusExceptionParse
 * 所属子库 (Sublibrary) : DL_MathData
 * 归属目录 (Directory)  : C:\Library\DL_MathData
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 函数（FUNCTION）· 纯函数 · 协议诊断帧解析
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / 施耐德
 *                         Machine Expert；仅用标准位运算与枚举，无实例依赖
 * 功能一句话 (Summary)  : 解析从站异常响应帧（功能码最高位置位加异常码），输出原始
 *                         功能码、异常码中文名、严重度分级与可重试标志。
 * 功能描述 (Function)   : 从站回非法数据地址与回从站设备忙，在通讯层都只表现为
 *                         「事务失败」；前者是组态错必须改程序，后者重试即可。
 *                         现场一律当「通讯不稳」处理，反复重启总线。本件把两者
 *                         分开定性，让上层重试策略按严重度分级动作。
 * 与既有件边界 (Boundary): FB_DL_ModbusPollMaster 负责组帧、发送、超时与重试编排；
 *                         本件只解析不决策，是否重试、重试几次由调用方的重试上限
 *                         决定。二者是「判读」与「执行」的分工，本件不持有任何状态。
 * 设计要点 (Key notes)  : ① 功能码先去最高位得原始码，原始码为零视为帧不可解释；
 *                         ② 非异常帧也走完整出口，返回「正常响应」文字与信息码，
 *                           便于 HMI 用同一字段显示两种帧；
 *                         ③ 未定义异常码不算解析成功：文字照给，但有效性置假，
 *                           让上层既能显示又能区分「看不懂」与「看懂且是故障」；
 *                         ④ 严重度分级是本件的核心输出，重试判据与分级绑定，
 *                           避免上层拿「故障」去无脑重试；
 *                         ⑤ 纯函数：无算术、无除法、无循环、无内部状态。
 * 开源溯源 (Origin)     : 来源标签 oscat-network。OSCAT 为公开发布的第三方函数库，
 *                         本件仅借鉴其把「协议帧解析 / 校验 / 诊断」分成独立函数族
 *                         的分类方式，以及「功能码 + 异常码」两入参的参数域；许可证
 *                         按其发布方条款仅作分类参考，本件零代码行、零注释引用。
 *                         异常码语义取自 Modbus 应用协议规范的公开定义（该规范为公开
 *                         技术文档），中文名、分级与可重试判据为本库自有设计，
 *                         整体属 clean-room 独立实现。
 * 码位说明 (Codes)      : 本件独占信息级码段 16#0001_0138 到 16#0001_0139，纯函数
 *                         无锁存面故不占故障级码；与同族 0134 到 013C 各件相邻不重叠。
 *                         0138 功能码非法或异常码未定义 ｜ 0139 本帧非异常帧。
 * 依赖说明 (Depends)    : 无 DL_ 内部依赖；仅 Standard.library 的位运算与
 *                         USINT_TO_INT 显式转换。
 * 红线自检 (Redline)    : 零全局变量表依赖 ｜ 零外部变量声明 ｜ 零物理地址
 *                         纯 IEC 61131-3 ｜ 无算术无除法 ｜ 分支带兜底
 *                         全变量双语同行注释 ｜ 无定时器实例
 * 修订历史 (Revision)   : 2026-11-15  v1.0.0  首版入库（Round 12 · 协议诊断族）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ModbusExcSeverity（归属 DL_MathData，与本件同文件）
 * 含义: 异常码的处置严重度。编号 0 起跳、段间隔 10。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ModbusExcSeverity :
(
    eInfo  := 0,     // 提示级：可忽略，不改变重试策略 / Informational, no retry impact
    eWarn  := 10,    // 告警级：可原样重试，短退避后再发 / Warning, safe to retry after a short back off
    eFault := 20     // 故障级：须人工介入，重试无意义或有害 / Fault, manual intervention required
);
END_TYPE

(*==============================================================================
 * 判读示意 (Interpretation picture)：
 *   功能码 16#83 表示读保持寄存器出错，去掉最高位得原始码 3
 *   异常码 16#02 语义为非法数据地址，属组态错，故障级，不可重试
 *   功能码 16#86 表示写单寄存器出错，原始码 6，异常码 16#06 从站忙
 *   从站忙属告警级，可原样重试，短退避后再发即可，不必重启总线
 *   异常码 16#07 落在规范定义的编号空隙里，按未定义处理，故障级且有效性为假
 *============================================================================*)

FUNCTION FC_DL_ModbusExceptionParse : BOOL
VAR_INPUT
    uFuncCode : USINT;        // 响应功能码原值，最高位置位表示异常帧 [位串] / Raw response function code, top bit set means exception
    uExcCode  : USINT;        // 异常码，仅在异常帧有效 [代码] / Exception code, valid only on exception frames
END_VAR
VAR_OUTPUT
    bIsException : BOOL;                  // 是异常帧为真 / Exception frame detected
    nOrigFunc    : INT;                   // 原始功能码，去掉最高位后的值，0 表示非法 [代码] / Original function code without the top bit
    sExcName     : STRING(40);            // 异常码中文名，未定义码给「未定义异常码」 [文本] / Chinese name of the exception code
    eSeverity    : E_DL_ModbusExcSeverity; // 严重度分级，驱动上层重试策略 / Severity class driving the retry policy
    bRetryable   : BOOL;                  // 可原样重试为真 / Safe to retry unchanged
    uErrorId     : UDINT;                 // 事件码，0 表示无事件 / Event code, zero means none
    bValid       : BOOL;                  // 帧结构可解释为真 / Frame interpretable
END_VAR
VAR
    uFunc : USINT;            // 功能码快照，便于统一取位 [位串] / Function code snapshot
    uExc  : USINT;            // 异常码快照，便于分支判读 [代码] / Exception code snapshot
    nOrig : INT;              // 原始功能码中间量，先算后判 [代码] / Original code temporary
END_VAR
VAR CONSTANT
    DL_MB_EXC_BIT  : USINT := 16#80;   // 异常帧标志位，功能码最高位 [位串] / Exception flag bit, the top bit of the function code
    DL_MB_FUNC_MASK : USINT := 16#7F;  // 功能码掩码，去掉异常帧标志 [位串] / Function code mask removing the flag bit
    DL_MB_EXC_MAX  : USINT := 16#0B;   // 规范定义的异常码上限，超出即视为不可解释帧 [代码] / Highest code defined by the specification
END_VAR

(*------------------------------------------------------------------------------
 * 段 1｜输出预置：任何路径下输出确定
 *      Pre-set outputs so that every path is deterministic
 *-----------------------------------------------------------------------------*)
FC_DL_ModbusExceptionParse := FALSE;
bIsException               := FALSE;
nOrigFunc                  := 0;
sExcName                   := '';
eSeverity                  := E_DL_ModbusExcSeverity.eInfo;
bRetryable                 := FALSE;
uErrorId                   := 16#0000_0000;
bValid                     := FALSE;

(*------------------------------------------------------------------------------
 * 段 2｜取快照与异常帧判定（边界 B1）：最高位为异常标志
 *      Snapshot the inputs and detect the exception flag in the top bit
 *-----------------------------------------------------------------------------*)
uFunc        := uFuncCode;
uExc         := uExcCode;
bIsException := (uFunc AND DL_MB_EXC_BIT) <> 0;

(*------------------------------------------------------------------------------
 * 段 3｜原始功能码解出（边界 B2）：掩掉标志位，为零视为帧不可解释
 *      Strip the flag bit, a zero result means the frame cannot be interpreted
 *-----------------------------------------------------------------------------*)
nOrig     := USINT_TO_INT(uFunc AND DL_MB_FUNC_MASK);
nOrigFunc := nOrig;
IF nOrig = 0 THEN
    uErrorId := 16#0001_0138;   // 功能码非法，无原始语义可判
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 4｜正常响应出口（边界 B3）：非异常帧给正常文字与信息码后返回
 *      Normal response exit: report the healthy frame and return
 *-----------------------------------------------------------------------------*)
IF NOT bIsException THEN
    sExcName                  := '正常响应';
    eSeverity                 := E_DL_ModbusExcSeverity.eInfo;
    bRetryable                := FALSE;
    bValid                    := TRUE;
    uErrorId                  := 16#0001_0139;   // 本帧不是异常帧，属提示
    FC_DL_ModbusExceptionParse := TRUE;
    RETURN;
END_IF

(*------------------------------------------------------------------------------
 * 段 5｜异常码映射（边界 B4）：逐码定性，未定义码走兜底分支
 *      Exception code mapping, undefined codes fall through to the fallback branch
 *      分级口径：组态类与校验类为故障级不可重试；忙与网关类为告警级可重试
 *-----------------------------------------------------------------------------*)
CASE uExc OF

    16#01:
        sExcName    := '非法功能';
        eSeverity   := E_DL_ModbusExcSeverity.eFault;
        bRetryable  := FALSE;

    16#02:
        sExcName    := '非法数据地址';
        eSeverity   := E_DL_ModbusExcSeverity.eFault;
        bRetryable  := FALSE;

    16#03:
        sExcName    := '非法数据值';
        eSeverity   := E_DL_ModbusExcSeverity.eFault;
        bRetryable  := FALSE;

    16#04:
        sExcName    := '从站设备故障';
        eSeverity   := E_DL_ModbusExcSeverity.eFault;
        bRetryable  := TRUE;

    16#05:
        sExcName    := '确认处理中';
        eSeverity   := E_DL_ModbusExcSeverity.eWarn;
        bRetryable  := TRUE;

    16#06:
        sExcName    := '从站设备忙';
        eSeverity   := E_DL_ModbusExcSeverity.eWarn;
        bRetryable  := TRUE;

    16#08:
        sExcName    := '存储奇偶校验错';
        eSeverity   := E_DL_ModbusExcSeverity.eFault;
        bRetryable  := FALSE;

    16#0A:
        sExcName    := '网关路径不可用';
        eSeverity   := E_DL_ModbusExcSeverity.eWarn;
        bRetryable  := TRUE;

    16#0B:
        sExcName    := '网关目标设备无响应';
        eSeverity   := E_DL_ModbusExcSeverity.eWarn;
        bRetryable  := TRUE;

    ELSE
        (* 未定义码兜底：文字照给便于 HMI 显示，但有效性置假，不算解析成功 *)
        (* Undefined code fallback: still name it for the HMI, but never mark it valid *)
        IF uExc > DL_MB_EXC_MAX THEN
            sExcName := '未定义异常码（超出规范上限）';
        ELSE
            sExcName := '未定义异常码';
        END_IF
        eSeverity  := E_DL_ModbusExcSeverity.eFault;
        bRetryable := FALSE;
        uErrorId   := 16#0001_0138;   // 未定义异常码，不可解释

END_CASE

(*------------------------------------------------------------------------------
 * 段 6｜收口：无事件即解析成功，事件码为未定义码时保持无效
 *      Close out: only event free calls count as a successful interpretation
 *-----------------------------------------------------------------------------*)
IF uErrorId = 16#0000_0000 THEN
    bValid                     := TRUE;
    FC_DL_ModbusExceptionParse := TRUE;
END_IF
END_FUNCTION
