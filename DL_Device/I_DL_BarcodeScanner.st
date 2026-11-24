(*==============================================================================
 * 组件名称 (Component)  : I_DL_BarcodeScanner
 * 所属子库 (Sublibrary) : DL_Device
 * 当前版本 (Version)    : 1.0.0
 * 兼容性   (Platform)   : CODESYS 3.5 / TwinCAT 3 / 汇川 InoProShop / Machine Expert
 *                         纯 IEC 61131-3（第3版）接口语法，零厂商方言
 * 分类     (Category)   : 设备抽象接口（Interface）+ 配套状态枚举（DUT）
 * 功能简述 (Function)   : 工业固定式扫码枪标准抽象契约。路由分拣、批次追
 *                         溯、上下料校验等 DL_Process 模板的依赖注入件。
 *                         定义状态读取属性组（GET）与触发/应答/复位方法组；
 *                         串口/总线收发与数据本体由实现块（如
 *                         FB_DL_SerialScanner）经 IN_OUT 引脚注入，接口层
 *                         不做任何串口/总线收发与过程映像读写。
 * 契约结构 (Structure)  : 公约 0.11 接口三段式——状态枚举（本文件承载）+
 *                         属性（PROPERTY GET）+ 方法（METHOD）；方法共 3 个
 *                         （≤6 红线内）。故障态一律拒绝方法（红线：接口方
 *                         法拒绝语义），返回 FALSE 不静默成功。
 * 开源溯源 (Origin)     : 来源标签 tcopen-component / scanner-handshake
 *                         （RAW_NOTES_R7 S-2/S-3：TcOpen 组件接口分层思想
 *                         ——属性/方法分离契约与命令-应答握手语义，Apache
 *                         -2.0 公开资料，仅借鉴分层思想；接口命名、枚举编
 *                         号、方法签名 100% 本库独立设计，clean-room 未复
 *                         制源码）。
 * 归属说明 (Ownership)  : 本文件同时承载 E_DL_ScannerState 枚举定义，该枚
 *                         归属接口 I_DL_BarcodeScanner，与其同文件发布
 *                         （公约 0.11；禁止异文件同名异型重复定义）。
 * 红线自检 (Redline)    : R1 零全局变量表/外部变量引用 ✓｜R2 零物理 IO 地址 ✓
 *                         R3 纯 IEC 61131-3 ✓｜R4 N/A（契约件无运算）
 *                         R5 全成员中英双语同行注释 ✓｜R6 N/A（接口无状态机）
 *                         R7 N/A（无实例调用）｜R18 INTERFACE/END_INTERFACE
 *                         成对终结 ✓
 * 修订历史 (Revision)   :
 *   2026-11-15  v1.0.0  首版入库（Round 07 · DL_Device 扫码枪族接口件）
 *============================================================================*)

(*-----------------------------------------------------------------------------
 * 枚举: E_DL_ScannerState（归属接口 I_DL_BarcodeScanner，与其同文件）
 * 含义: 扫码枪握手状态机离散状态。编号步长 10 留空位便于后续插态而不破坏
 *       已有工程；eFault 取 99 保证排序末位（全库枚举编号惯例）。
 *----------------------------------------------------------------------------*)
TYPE E_DL_ScannerState :
(
    eIdle      := 0,    // 空闲待机：可受理解码触发 / Idle, ready to accept a decode trigger
    eTriggered := 10,   // 已触发：触发单拍输出已发出，等待下一拍进入读码 / Triggered, one-shot trigger output emitted
    eReading   := 20,   // 读码等待：结果窗口期内等待扫码枪回数 / Reading, waiting for the scanner reply inside the result window
    eOk        := 30,   // 解码成功：条码已锁存，等待应答消费 / Read OK, barcode latched, awaiting acknowledge
    eNoRead    := 40,   // 未读到：重试耗尽后的 NoRead 结果保持态 / NoRead, result hold state after retries exhausted
    eFault     := 99    // 故障锁存：连续 NoRead 超限/非法状态等，复位可尝试恢复 / Latched fault, reset may recover
) UINT;
END_TYPE

(*-----------------------------------------------------------------------------
 * 接口: I_DL_BarcodeScanner
 * 边界防错: 故障态一律拒绝方法；接口层不做任何串口/总线收发（数据本体经
 *           实现块 IN_OUT 引脚注入）；实现块负责握手编排与结果校验。
 *----------------------------------------------------------------------------*)
INTERFACE I_DL_BarcodeScanner

// ---- 属性段（全部只读 GET，实现块一一落地）----------------------------------

PROPERTY eState    : E_DL_ScannerState // 当前握手状态（Current handshake state），枚举见 E_DL_ScannerState
PROPERTY bReady    : BOOL              // 就绪可触发（Scanner ready），TRUE=处于可受理触发的状态 / TRUE = trigger acceptable
PROPERTY bReadOk   : BOOL              // 解码成功且结果有效（Read OK），TRUE=sBarcode 有效待消费 / TRUE = barcode valid and pending
PROPERTY bNoRead   : BOOL              // 未读到（NoRead），TRUE=重试耗尽未获得有效条码 / TRUE = no valid barcode after retries
PROPERTY sBarcode  : STRING(255)       // 最近有效条码字符串（Last valid barcode），长度 ≤255，bReadOk=TRUE 时有效 / Last valid barcode, valid when bReadOk
PROPERTY nReadCount: UDINT             // 累计成功解码次数（Total successful reads），复位不清零（追溯口径）/ Cumulative reads, preserved over reset
PROPERTY bFault    : BOOL              // 故障锁存中（Fault latched），显式排除信息级码（R21）/ TRUE = latched fault, info codes excluded
PROPERTY uErrorId  : UDINT             // 末次故障码（Last error code），0=无故障，段位 16#0003_xxxx / Last error code, family 16#0003_xxxx

// ---- 方法段（单发指令，返回受理/合法性结果）----------------------------------

METHOD CmdTrigger : BOOL // 触发一次解码（Trigger one decode），仅空闲态受理；非空闲/故障态拒绝返回 FALSE / Trigger one decode, accepted only in idle, rejected otherwise
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdAck : BOOL // 应答清除结果保持位（Acknowledge clears the result hold），eOk/eNoRead 态受理，为下一次解码前提 / Ack accepted in eOk/eNoRead
VAR_INPUT
END_VAR

    END_METHOD

METHOD CmdReset : BOOL // 复位故障（Reset fault），仅故障态受理返回 TRUE / Reset accepted only in fault state
VAR_INPUT
END_VAR

    END_METHOD
END_INTERFACE
