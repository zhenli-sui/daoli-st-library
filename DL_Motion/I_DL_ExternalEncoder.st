(*==============================================================================
 * 组件名称 (Component)  : I_DL_ExternalEncoder
 * 所属子库 (Sublibrary) : DL_Motion
 * 前缀     (Prefix)     : I_DL_
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3（第 3 版）接口语法，
 *                         无任何厂商方言、无标准库依赖（纯契约件）
 * 作者     (Author)     : 道莅代码库 · PLC编程专家（R31）
 * 开源溯源 (Origin)     : 外部编码器只读位置源公开契约语义（T1-6 外部编码器
 *                         族开族件），道莅 clean-room 防御性实现，
 *                         未复制任何外部源码行
 * 功能描述 (Function)   : 外部编码器契约接口，定义「外部编码器 = 只读位置源」
 *                         最小契约：三条只读属性回答"在哪、多快、可信吗"，
 *                         一个采样方法输出单拍一致快照（位置 + 速度 + 时戳
 *                         同拍锁定），一个复位方法。核心语义写死：外部编码器
 *                         不可被驱动，本接口无任何命令方向属性或方法。
 * 接口结构 (Contract)   : 1 属性：fPos / fVel / bValid 共 3 条，全部只读 GET；
 *                         2 方法：Sample / Reset 共 2 个（满足方法不超过 6 个
 *                         的拆分红线）；3 结构体：ST_DL_EncSnapshot 随本文件
 *                         发布，全库唯一属主为本文件。
 * 实现纪律 (Discipline) : 实现块不得在本接口后挂写方法或属性——外部编码器
 *                         不可被驱动是该族的编译期表达，任何写入型成员都
 *                         会破坏「只读位置源」契约。bValid=FALSE 的具体解释
 *                         （断线/超时/未标定）由实现块自行定义。
 * 码位     (Codes)      : 纯契约件无执行体，无错误码出口；段 16#0004_0063~0066
 *                         为本契约预留 4 槽（规格 §3 分配），实现块的错误码
 *                         不得挪用该段（段位隔离，防跨件码冲突）。
 * 边界防错 (Boundary)   : 1 接口不声明变量段（IEC 接口只允许属性与方法）；
 *                         2 Sample 的快照输出以 IN-OUT 引用传递承载规格的
 *                         OUT 语义（可移植性裁定，全平台语法一致）；
 *                         3 单拍一致快照由实现块保证：一次 Sample 调用内
 *                         位置、速度、时戳必须同拍锁定，不得跨拍拼装。
 * 修订历史 (Revision)   : 2026-11-18 v1.0.0 首版入库（R31 · 阶段三 · 序 5）
 *==============================================================================*)

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_EncSnapshot（归属本接口，同文件发布，全库唯一属主）
 * 含义: 外部编码器单拍一致快照。实现块在一次 Sample 调用内同拍锁定全部字段。
 *----------------------------------------------------------------------------*)
TYPE ST_DL_EncSnapshot :
STRUCT
    fPos    : LREAL := 0.0;   // 快照位置 [毫米] / Snapshot position [mm]
    fVel    : LREAL := 0.0;   // 快照速度 [毫米每秒] / Snapshot velocity [mm per s]
    tStamp  : TIME  := T#0MS; // 快照时戳：实现块自填的采样时标 [毫秒] / Snapshot timestamp [ms]
    bValid  : BOOL  := FALSE; // 快照有效标志：实现块解释失效原因 / Snapshot validity, reason per implementation
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 接口: I_DL_ExternalEncoder
 * 契约结构: 属性（只读 GET，3 条）+ 方法（2 个）两段式。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_ExternalEncoder

// ---- 属性段（全部只读 GET，共 3 条）----------------------------------------

PROPERTY fPos   : LREAL   // 当前位置 [毫米] / Current position [mm]
END_PROPERTY
PROPERTY fVel   : LREAL   // 当前速度 [毫米每秒] / Current velocity [mm per s]
END_PROPERTY
PROPERTY bValid : BOOL    // 当前数据可信标志 / Current data validity flag
END_PROPERTY

// ---- 方法段（共 2 个）-------------------------------------------------------

// Sample：取单拍一致快照，成功返回 TRUE 且 stSnap 各字段同拍锁定；
// 失败返回 FALSE，stSnap 内容由实现块决定（约定不清写，调用方自行保持旧值）。
METHOD Sample : BOOL
VAR_IN_OUT
    stSnap : ST_DL_EncSnapshot; // 快照出参（IN-OUT 引用承载 OUT 语义）/ Snapshot output via in-out reference
END_VAR

// Reset：复位实现块内部采样历史（首扫同步标志、失效计数等），始终返回 TRUE。
// 只清采样历史，不清物理编码器状态（清零/回零属驱动层职责，不在本契约内）。
    END_METHOD

METHOD Reset : BOOL

    END_METHOD
END_INTERFACE
