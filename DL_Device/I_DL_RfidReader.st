(*==============================================================================
 * 组件名称 (Component)  : I_DL_RfidReader
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 组件分类 (Category)   : 接口（INTERFACE）+ 配套结构体与枚举（同文件发布）
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Schneider
 *                         Machine Expert；纯 IEC 61131-3 第 3 版接口语法，
 *                         零厂商方言，零标准库依赖
 * 功能描述 (Function)   : 载具与托盘 RFID 读写头的标准抽象契约。按本库接口
 *                         三段式组织（结构体 + 只读属性 + 单发方法），上层工站
 *                         只依赖本接口引用，即可用同一套代码适配串口读写头、
 *                         工业以太网读写头、IO-Link 读写头与仿真器。
 * 参数分段 (Segments)   : 借 AOI 的参数分段范式把接口切为四段：
 *                         In 段（指令）= 四个单发方法；
 *                         Out 段（状态）= 三个只读属性；
 *                         InOut 段（诊断与组态）= ST_DL_RfidDiag 与 ST_DL_RfidCfg
 *                         经属性与方法参数整体吞吐；
 *                         Local 段（内部中间量）= 留给实现块，接口不出现。
 *                         只借分段组织与访问等级思想，未接触任何厂商的 UDT
 *                         布局、参数命名与内部逻辑。
 * 与既有件边界 (Boundary): I_DL_BarcodeScanner 是一维码扫描（触发应答握手、
 *                         单向只读）；本接口是读写双向加载具数据区（分页与
 *                         字块）加防重复读，方法语义与数据模型都不同，
 *                         不做继承合并。
 * 方法数红线 (Budget)   : 方法 4 个（Init / ReadTag / WriteTag / Reset），
 *                         属性 3 个（State / Tag / Diag），属性不计入方法预算
 *                         （与 I_DL_MotionAxis 同一口径），故满足接口方法数
 *                         不超过 6 的红线。
 * 语义约定 (Semantics)  :
 *   1 未 Init 或 Init 失败时，除 Reset 与三个只读属性外全部方法返回 FALSE 并
 *     给出非零码，且不改变任何内部状态；
 *   2 全部方法为非阻塞单发：方法内只登记请求并置内部标志，跨周期动作由实现块
 *     主体状态机执行，方法内不得出现等待循环；
 *   3 忙态（内部指令执行中）再调用 ReadTag 或 WriteTag 一律返回 FALSE 并给码，
 *     不排队不缓存（读头硬件本身互斥，排队只会让上层误以为指令已生效）；
 *   4 视野内无标签是业务态不是故障：不置故障位、不进故障态、不计入重试次数；
 *   5 所有失败必须区分「组态或使用类」与「工艺类」两类码段，HMI 据此决定是
 *     叫工程师改参数还是叫维修换硬件。
 * 开源溯源 (Origin)     : tcopen-component / rockwell-aoi。参考 TcOpen 公开组件
 *                         库的契约与实现分离范式（接口只定义成员签名，状态经
 *                         只读属性暴露），以及 Rockwell AOI 公开手册所述的参数
 *                         分段与外部访问等级思想（Instruction / Status /
 *                         InOut / Local 四段，Input 与 Output 只读、InOut 与
 *                         Local 对外不可见）。仅借分段组织与访问等级，结构体
 *                         布局、成员命名、码位与状态机 100% 自有 clean-room，
 *                         不构成衍生作品。
 * 依赖     (Depends)    : 无 DL_ 内部依赖；无标准库功能块依赖
 * 归属声明 (Ownership)  : 本文件同时承载 E_DL_RfidState、ST_DL_RfidTag、
 *                         ST_DL_RfidDiag、ST_DL_RfidCfg 四个类型定义，均归属
 *                         本接口并与其同文件发布（库内公约 0.18）。
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 10 · T2-6 Rockwell AOI 开组）
 *============================================================================*)

(*------------------------------------------------------------------------------
 * 枚举: E_DL_RfidState
 * 含义: 对外可观测的读写头状态。区间 0 到 20 为常规态，90 以上为异常与业务态，
 *       数值步长 10 留空位，新增状态不破坏已有 HMI 的数值映射
 *-----------------------------------------------------------------------------*)
TYPE E_DL_RfidState :
(
    eOffline := 0,     // 未初始化或未上电：除复位与只读属性外全部拒绝 / Offline, only reset and read-only members are served
    eReady   := 10,    // 就绪，可受理指令 / Ready, accepts commands
    eBusy    := 20,    // 指令执行中，互斥，禁止重入 / Busy, mutually exclusive, re-entry rejected
    eError   := 90,    // 故障，需复位清除 / Fault, cleared only by reset
    eNoTag   := 95     // 视野内无标签，业务态非故障 / No tag in field, a business state rather than a fault
);
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_RfidTag
 * 含义: 一次读写的标签快照。读到后保持（R27），直到下次成功读取覆盖
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_RfidTag :
STRUCT
    sTagId  : STRING(64);   // 标签唯一号，空串表示无标签 [ASCII] / Tag unique identifier, empty means no tag
    sData   : STRING(64);   // 标签数据区内容，编码由组态决定 [ASCII 或十六进制] / Tag data area content
    uPage   : UINT;         // 数据页号，0 表示连续区 [页] / Data page number, zero means the contiguous area
    nRssi   : INT;          // 信号强度，域零下 90 到 0 [分贝毫瓦] / Signal strength, -90 to 0 dBm
    bValid  : BOOL;         // 本次读取有效 [-] / TRUE when this snapshot holds a valid read
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_RfidDiag
 * 含义: 诊断与统计。整体经只读属性回读，等价于 AOI 的 InOut 段对外封装
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_RfidDiag :
STRUCT
    uLastErrorId : UDINT;   // 末次故障码，段位由实现块按子库公约自定 [代码] / Last error code, family defined by the implementer
    nCommRetry   : INT;     // 本次指令累计通信重试次数 [次] / Retry count of the current command
    nReadTotal   : DINT;    // 累计读成功次数，跨班不清零 [次] / Total successful reads, never cleared per shift
    nWriteTotal  : DINT;    // 累计写成功次数，跨班不清零 [次] / Total successful writes, never cleared per shift
    bAntennaOk   : BOOL;    // 天线自检通过 [-] / TRUE when the antenna self-test passed
    tLastComm    : TIME;    // 末次成功通信距今时长 [毫秒] / Elapsed time since the last successful communication
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 结构体: ST_DL_RfidCfg
 * 含义: 组态参数，调用方持有并经 Init 方法的 VAR_IN_OUT 注入，接口侧只读使用
 *-----------------------------------------------------------------------------*)
TYPE ST_DL_RfidCfg :
STRUCT
    sAntennaNo   : STRING(8);          // 天线号，多天线读头用于选天线 [ASCII] / Antenna selector for multi-antenna readers
    nPowerDbm    : INT;                // 发射功率，域 0 到 30 [分贝毫瓦] / Transmit power, 0 to 30 dBm
    tTimeout     : TIME;               // 单次指令超时，域 50 毫秒到 5 秒 [毫秒] / Per-command timeout, 50 ms to 5 s
    nMaxRetry    : INT;                // 重试次数，域 0 到 5 [次] / Retry count, 0 to 5
    bDupFilterEn : BOOL;               // 同标签重复读抑制使能 [-] / Duplicate-read suppression enable
    tDupWindow   : TIME;               // 重复读抑制窗，域 100 毫秒到 60 秒 [毫秒] / Duplicate suppression window
END_STRUCT
END_TYPE

(*------------------------------------------------------------------------------
 * 接口: I_DL_RfidReader
 * 契约结构: 属性段（只读 GET，Out 段）+ 方法段（单发，In 段）
 *-----------------------------------------------------------------------------*)
INTERFACE I_DL_RfidReader

// ---- 属性段（Out 段，全部只读，实现块以同名 PROPERTY GET 落地） -----------

PROPERTY State : E_DL_RfidState      // 当前状态，映射规则由实现块逐条写死（Current state, mapping fixed by the implementer）
PROPERTY Tag   : ST_DL_RfidTag       // 当前标签快照，读到后保持（Current tag snapshot, held after a successful read）
PROPERTY Diag  : ST_DL_RfidDiag      // 诊断结构整体回读（Whole diagnostic structure, read back at once）

// ---- 方法段（In 段，全部非阻塞单发，返回 FALSE 时必须给出非零码） --------

METHOD Init : BOOL                   // 初始化，组态经 VAR_IN_OUT 注入，只登记不阻塞（Initialise; configuration injected by reference）
VAR_IN_OUT
    stCfg : ST_DL_RfidCfg;           // 组态结构，调用方持有，接口侧只读 [结构] / Configuration structure owned by the caller, read-only here
END_VAR

    END_METHOD

METHOD ReadTag : BOOL                // 发起读标签（唯一号与数据区），忙时拒绝（Start a tag read, rejected while busy）
VAR_INPUT
END_VAR

    END_METHOD

METHOD WriteTag : BOOL               // 发起写数据区，内容经 VAR_IN_OUT 注入，忙时拒绝（Start a data write, rejected while busy）
VAR_IN_OUT
    stTagIn : ST_DL_RfidTag;         // 待写内容，实现块须锁存副本防调用方中途改动 [结构] / Payload to write; the implementer must latch a copy
END_VAR

    END_METHOD

METHOD Reset : BOOL                  // 清故障回就绪态，是故障态下唯一受理的方法（Clear the fault and return to ready）
VAR_INPUT
END_VAR

(*==============================================================================
 * 调用示例 (Instance guide)：
 *   VAR fbReader : FB_DL_RfidTagHandler;    // 具体实现块
 *       stCfg    : ST_DL_RfidCfg;           // 组态，调用方持有
 *       stTag    : ST_DL_RfidTag;           // 标签快照
 *       iReader  : I_DL_RfidReader;         // 接口引用，注入实现块
 *   END_VAR
 *   fbReader(stCfg := stCfg, bHwReady := bReaderReady);
 *   iReader := fbReader;                     // 依赖注入，上层只依赖接口
 *   IF iReader.State = E_DL_RfidState.eReady THEN
 *       bOk := iReader.ReadTag();
 *   END_IF
 *   IF iReader.Tag.bValid THEN
 *       sPalletId := iReader.Tag.sTagId;     // 保持型，读到后立即可用
 *   END_IF
 *   上层工站不得直接引用实现块类型，只能持有接口引用，替换硬件时只改注入点。
 *============================================================================*)

    END_METHOD
END_INTERFACE
