//==============================================================================
// 功能块：FB_DL_EmergencyStopChainDiag ｜ 中文名称：急停回路多节点诊断聚合与断链定位
// 所属子库：DL_Device ｜ 版本：v1.0.0 ｜ 日期：2026-11-23
// 兼容：CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop（纯 IEC 61131-3 第 3 版，零方言）
// 功能描述：急停安全回路四节点（急停按钮 NC 反馈 / 双通道继电器反馈 / 回路
//           复位反馈）诊断聚合：四节点全好 → 回路完好；任一节点断 → 经去抖
//           确认后锁存断链故障并按优先级定位首个断点（按钮 > K1 > K2 > 复位），
//           复位沿且四节点恢复才解除锁存；复位沿而回路未恢复判复位时序非法
//           （信息级）。安全声明：本件只做诊断聚合与逻辑级 bSafeOut，物理
//           输出侧必须在 PRG_IoMapping 层做双保险切断（安全最高优先级拦截），
//           本件输出不得单独驱动任何安全执行器。
// 开源溯源 (Origin)：原创实现（t2-8-isa182 报警与回路诊断语义深化，零外部
//           源码行，clean-room 独立编写）
// 公开接口清单：输入 bBtnOk / bK1FbOk / bK2FbOk / bResetOk / bReset / tDebounce；
//               输出 bChainOk / bSafeOut / eBreakNode / uErrCode / bError / bValid
// 单位表：全部 BOOL / TIME 引脚，无量纲；tDebounce[ms]
// 输入契约：四节点反馈为 NC 回路完好电平（TRUE = 完好），引脚经 IO 映射层
//           注入；bReset 为操作员复位按钮沿。
// 输出契约：bSafeOut 为逻辑级安全输出（物理双保险在输出映射层）；
//           eBreakNode 锁存回放至解锁沿；uErrCode 故障级锁存、信息级每拍
//           重算；bError 仅断链故障相保持。
// 错误码表：16#0003_0760 故障级（急停回路断链，置 bError，锁存至复位沿回放）/
//           16#0003_0761 信息级（复位时序非法：复位沿而回路未恢复，不置
//           bError）/
//           16#0003_0762 预留禁用（不得挪用）
// 状态机：E_DL_EStopDiagState（本文件唯一定义，全库唯一属主）：
//           eHealthy = 0 / eBroken = 1；非法状态兜底归 eBroken（安全侧）
// 边界行为：① 断链经 tDebounce 去抖确认才锁存（反馈抖动不误报）；
//           ② 断点定位在确认瞬间按按钮→K1→K2→复位优先级单拍锁存，
//             故障期内锁存回放，不按当下输入重推断（R189）；
//           ③ 解锁条件 = 复位上升沿 AND 四节点全恢复（可达清除沿已声明）；
//           ④ TON/R_TRIG 每拍无条件刷新（不入分支，红线 R7）；
//           ⑤ 输入非有限不适用（BOOL 引脚无浮点域，域闸由组态域承担）；
//           ⑥ CASE 带 ELSE 非法态兜底归 eBroken（安全侧）。
// 修订历史：v1.0.0 2026-11-23 首版（R73 派单 · 批 1 · 序 4）
//==============================================================================

(*------------------------------------------------------------------------------
 * 枚举 1: E_DL_EStopDiagState（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 诊断状态机相位，成员与 CASE 标签双向完备。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_EStopDiagState :
(
    eHealthy := 0,   // 回路完好：四节点全恢复且锁存已解除 / Chain healthy, all nodes restored
    eBroken  := 1    // 断链锁存：故障码与断点回放中 / Broken, fault code and break node replaying
);
END_TYPE

(*------------------------------------------------------------------------------
 * 枚举 2: E_DL_EStopNode（归属本功能块，同文件发布，全库唯一属主）
 * 含义: 断链定位节点，eNone = 无断点。
 *-----------------------------------------------------------------------------*)
TYPE E_DL_EStopNode :
(
    eNone  := 0,   // 无断点 / No break point
    eBtn   := 1,   // 急停按钮节点断 / E-stop button node broken
    eK1    := 2,   // 安全继电器 K1 反馈节点断 / Safety relay K1 feedback node broken
    eK2    := 3,   // 安全继电器 K2 反馈节点断 / Safety relay K2 feedback node broken
    eReset := 4    // 回路复位反馈节点断 / Chain reset feedback node broken
);
END_TYPE

(*==============================================================================
 * 功能块: FB_DL_EmergencyStopChainDiag
 * 调用约定: 每个扫描周期无条件调用一次；实例状态全部驻留于私有变量。
 * 调用示例: eStopDiag(bBtnOk := NOT bEStopRawNc, bK1FbOk := bK1Mon,
 *                     bK2FbOk := bK2Mon, bResetOk := bResetLoopMon,
 *                     bReset := bAckBtn, tDebounce := T#50MS);
 *          断链定位读 eStopDiag.eBreakNode 送上位机诊断画面；bSafeOut 参与
 *          输出映射层双保险合取。
 * 组装说明: ① 安全组装纪律：物理切断通道必须由 PRG_IoMapping 层对本件
 *             bSafeOut 与硬件安全回路触点做双保险串联，本件输出单独不得
 *             驱动任何安全执行器（安全最高优先级拦截声明）；
 *           ② 四节点反馈引脚全部经 PRG_IoMapping 读入，本件零 %I/%Q
 *             物理地址（红线 R2）；
 *           ③ 复位按钮沿在本件内去抖无效——操作员复位须经 bResetOk
 *             反馈恢复后才可达解锁沿，双条件合取由 eBroken 相承担；
 *           ④ 本件可与任意数量下游工艺联锁件组合，bChainOk 作公共使能
 *             因子注入各工艺件的 bEn 合取项。
 *==============================================================================*)
FUNCTION_BLOCK FB_DL_EmergencyStopChainDiag
VAR_INPUT
    bBtnOk    : BOOL := FALSE;       // 急停按钮 NC 反馈（TRUE = 未按下/完好）/ E-stop button NC feedback, TRUE = intact
    bK1FbOk   : BOOL := FALSE;       // 安全继电器 K1 反馈（TRUE = 吸合正常）/ Safety relay K1 feedback, TRUE = healthy
    bK2FbOk   : BOOL := FALSE;       // 安全继电器 K2 反馈（TRUE = 吸合正常）/ Safety relay K2 feedback, TRUE = healthy
    bResetOk  : BOOL := TRUE;        // 回路复位反馈（TRUE = 复位回路完好）/ Reset loop feedback, TRUE = healthy
    bReset    : BOOL := FALSE;       // 操作员复位按钮（上升沿有效）/ Operator reset pushbutton, rising edge active
    tDebounce : TIME := T#50MS;      // 断链去抖确认延时 [ms] / Break debounce delay [ms]
END_VAR
VAR_OUTPUT
    bChainOk  : BOOL;                // 回路完好声明（去抖后）/ Chain healthy declaration after debounce
    bSafeOut  : BOOL;                // 逻辑级安全输出（物理双保险在 IO 映射层）/ Logic-level safe output, physical double cut at the IO mapping layer
    eBreakNode: E_DL_EStopNode;      // 断点定位（锁存回放）/ Break node location, latched replay
    uErrCode  : UDINT;               // 错误码，0 = 无错 / Error code, 0 = no error
    bError    : BOOL;                // 故障级标志，仅故障级错误置位 / Fault-class flag, set only on fault-level codes
    bValid    : BOOL;                // 输出可用标志 / Outputs usable flag
END_VAR
VAR
    tonBrk    : TON;                 // 断链去抖定时器，每拍无条件刷新 / Break debounce timer, refreshed every scan
    trigReset : R_TRIG;              // 复位沿检测，每拍无条件刷新 / Reset edge detector, refreshed every scan
    bChainRaw : BOOL;                // 四节点原始合取（未去抖）/ Raw four-node AND, not debounced
    bSeqBad   : BOOL;                // 复位时序非法声明 / Reset sequence violation flag
    eState    : E_DL_EStopDiagState; // 诊断状态机相位（私有驻留）/ Diagnostic state machine phase, private resident
END_VAR
VAR CONSTANT
    DL_ES_CODE_BRK : UDINT := 16#0003_0760; // 故障级：断链码 / Fault code: chain broken
    DL_ES_CODE_SEQ : UDINT := 16#0003_0761; // 信息级：复位时序非法码 / Info code: illegal reset sequence
END_VAR

// ---- 段 1｜定时/沿实例无条件刷新（红线 R7：禁入条件分支）----
bChainRaw := bBtnOk AND bK1FbOk AND bK2FbOk AND bResetOk; // 四节点原始合取 / Raw four-node AND
tonBrk(IN := NOT bChainRaw, PT := tDebounce);            // 断链去抖按断态断输入 / Break timer input per raw break state
trigReset(CLK := bReset);                                 // 复位沿每拍刷新 / Reset edge refreshed every scan

// ---- 段 2｜出口默认值：入口即赋确定值 ----
bChainOk := FALSE;                    // 回路完好默认 FALSE / Chain healthy preset FALSE
bSafeOut := FALSE;                    // 安全输出默认 FALSE（安全侧）/ Safe output preset FALSE, safe side
bSeqBad  := FALSE;                    // 时序非法声明先清零 / Sequence violation preset FALSE
uErrCode := 16#0000_0000;             // 信息码每拍重算（信息级不锁存，R189）/ Info code recomputed, never latched per R189
bError   := FALSE;                    // 故障标志先清零（故障相由锁存改写）/ Fault flag cleared, overwritten by latch in the fault phase
bValid   := TRUE;                     // 可用标志默认 TRUE / Usable flag preset TRUE

// ---- 段 3｜诊断状态机（CASE 带 ELSE；断点锁存单拍定位）----
CASE eState OF
    E_DL_EStopDiagState.eHealthy:     // 完好相：监视断链
        bChainOk := TRUE;             // 完好声明 / Healthy declared
        bSafeOut := bChainRaw;        // 安全输出随原始合取（去抖前透传，断后去抖确认才翻）/ Safe out follows raw AND
        IF tonBrk.Q THEN              // 断链去抖确认（可达进入沿）/ Break confirmed by debounce
            eState := E_DL_EStopDiagState.eBroken; // 进入断链锁存相 / Enter the broken latch phase
            IF NOT bBtnOk THEN        // 断点定位：按钮优先 / Locate: button first
                eBreakNode := E_DL_EStopNode.eBtn;
            ELSIF NOT bK1FbOk THEN    // 次优先 K1 / Then K1
                eBreakNode := E_DL_EStopNode.eK1;
            ELSIF NOT bK2FbOk THEN    // 次优先 K2 / Then K2
                eBreakNode := E_DL_EStopNode.eK2;
            ELSE                      // 余下为复位反馈节点 / Remaining: reset feedback node
                eBreakNode := E_DL_EStopNode.eReset;
            END_IF
            uErrCode := DL_ES_CODE_BRK; // 故障码锁存（回放至解锁）/ Fault code latched, replayed until release
            bError   := TRUE;           // 置故障标志（R45 配对）/ Raise the fault flag, R45 pairing
        ELSIF trigReset.Q THEN        // 完好态复位沿为无效时序 / Reset edge while healthy is a sequence violation
            bSeqBad  := TRUE;         // 信息级留痕 / Info-level trace
            uErrCode := DL_ES_CODE_SEQ; // 信息级：复位时序非法（不置 bError）/ Info: illegal reset sequence, no fault flag
        END_IF

    E_DL_EStopDiagState.eBroken:      // 断链锁存相：故障码与断点回放
        bChainOk := FALSE;            // 回路不完好声明 / Chain unhealthy declared
        bSafeOut := FALSE;            // 安全输出切断（安全侧）/ Safe output cut, safe side
        bError   := TRUE;             // 故障级锁存回放 / Fault-class latch replay
        uErrCode := DL_ES_CODE_BRK;   // 故障码回放（不在故障相重推断）/ Fault code replayed, never re-inferred
        IF trigReset.Q THEN           // 复位沿处理（锁存声明的清除沿）/ Reset edge, the declared release edge
            IF bChainRaw THEN         // 四节点全恢复才允许解锁 / All nodes restored before release
                eState := E_DL_EStopDiagState.eHealthy; // 回完好相 / Back to the healthy phase
                eBreakNode := E_DL_EStopNode.eNone;     // 断点定位清零 / Break node cleared
                uErrCode   := 16#0000_0000;             // 故障码清零 / Fault code cleared
                bError     := FALSE;                    // 故障标志解除 / Fault flag released
            ELSE
                bSeqBad  := TRUE;     // 回路未恢复时的复位判时序非法 / Reset while broken is a sequence violation
                uErrCode := DL_ES_CODE_SEQ; // 信息级留痕（故障码保持回放）/ Info trace, fault code keeps replaying
                bError   := TRUE;     // 故障级保持 / Fault class held
            END_IF
        END_IF

    ELSE                              // 非法状态兜底（R21：CASE 必带 ELSE）
        eState   := E_DL_EStopDiagState.eBroken; // 拦截非法值归断链（安全侧）/ Catch illegal value to broken, safe side
        bSafeOut := FALSE;            // 安全输出切断 / Safe output cut
        bError   := TRUE;             // 兜底相按故障级处理 / Fallback phase treated as fault class
        uErrCode := DL_ES_CODE_BRK;   // 兜底故障码 / Fallback fault code
END_CASE

bValid := TRUE;                       // 全部出口确定：输出可用 / All outlets deterministic, outputs usable
END_FUNCTION_BLOCK