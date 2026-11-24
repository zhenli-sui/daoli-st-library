// ==============================================================================
// 组件名 Component  : FB_DL_PneuCylinderDiag
// 分类   Category   : DL_Device
// 前缀   Naming     : FB_DL_ ｜ b/e/t 类型前缀制（R265）
// 版本   Version    : 1.0.0
// 复杂度 Complexity  : 中
// 功能   Purpose    : 气缸纯诊断件（不控线圈）：跟踪指令沿与到位反馈的
//                      一致性——伸出 / 缩回超时（tExtTo / tRetTo）、双传感
//                      器矛盾（bFbExt 与 bFbRet 同真，物理不可能）、中途
//                      无进展（运动相中两反馈皆无持续 tStall）三族故障
//                      锁存；bReset 上升沿解锁回 eIdle。供既有气缸控制
//                      件外挂诊断层，不替代控制件。
// 开源溯源 Origin    : 道莅原创（与 FB_DL_PneumaticCylinder 的控制 + 自检
//                      一体件分工：本件为纯诊断外挂，判据独立实现
//                      clean-room，零代码复制）
// 许可证 License    : MIT
// 参考   Reference  : IEC 61131-3:2013 §6.6 ENUM + CASE 状态机 / TON /
//                      R_TRIG 语义；气缸「指令 - 反馈」一致性监视公开
//                      工程口径（借语义，不抄文）
// 平台   Platform   : 纯 IEC 61131-3（TON / R_TRIG / ENUM+CASE），三平台通用
// 依赖   Depends    : 仅 Standard.library（TON / R_TRIG 属标准件）
// 分工声明 Split     : FB_DL_PneumaticCylinder（控制件，含线圈输出与互锁）
//                      与本件互引；本件零控制出口（不下发线圈），只做
//                      指令 - 反馈一致性诊断；控制语义归彼件（R216）。
// 归属 Ownership     : E_DL_PcdSt / E_DL_PcdErr 属主为本文件（全库唯一
//                      定义，R264）；引用件只引用不重声明。
// ------------------------------------------------------------------
// 边界 Boundary     :
//   一 TON / R_TRIG 段 0 无条件刷新（禁入分支，R7）；监视 TON 串故障锁存
//      门控（FB50-1：锁存期 IN 强制 FALSE，复位同拍不重锁）；
//   二 推进判据与超时计时不同源（R300）：推进判据 = 到位反馈电平
//      （bFbExt / bFbRet），超时计时 = 状态驻留时长（tonExtTo / tonRetTo
//      基于相而非反馈），互不共源；无进展窗 tStall 为独立第三窗
//      （判据 = 两反馈皆无），与超时窗互不共源；
//   三 同拍双窗配比约束（写死）：tStall 须 < min(tExtTo, tRetTo)——
//      双反馈皆无场景下若 tStall >= 超时窗，超时窗先到，eMidStall 永不可
//      到达（配比声明，调用方改参须维持）；反馈部分在场（如 bFbRet 恒
//      真卡滞）时无进展窗被门控让路，由超时窗接管（判据互斥分层）；
//   四 故障归因唯一（R190）：eSenConflict / eMidStall / eTimeoutExt /
//      eTimeoutRet 各有独立码位与独立触发判据，禁止共用枚举成员；
//   五 eMidStall 无独立驻留相（E_DL_PcdSt 契约定稿）：锁存后冻结当前
//      运动相驻留（bErr = TRUE + eErr = eMidStall 双通道表达），迁移被
//      锁存闸（段 6）拦截至复位沿，语义在头注与码表双声明；
//   六 失败锁存 _bFaultLatch：解除式可达自证（R152）——bReset 上升沿
//      清锁存回 eIdle（输入引脚恒可达，无「置位即永久」路径）；
//   七 失能（bEn = FALSE）语义写死（R303 离相清零）：状态回 eIdle、
//      故障锁存 / 码锁存清零、bErr / bTimeout 清零（失能不是故障）；
//   八 首拍 _bInit 全量初始化（R310）；非法枚举态兜底落 eConflict +
//      eSenConflict 合并码（R90 反证句：E_DL_PcdErr 无非法态成员，非法态
//      与传感器矛盾的出口组合同为 eConflict + bErr，现有输出不可区分，
//      故合并；数值对照码 0730 见码表）；
//   九 无浮点量、无除法；无全局、无外部变量、无物理地址。
// 错误码 Codes      :
//   16#0003_0730【故障级】非法状态拦截（ELSE 兜底，经 eSenConflict 枚举
//                通道合并表达，R90 合并反证句见边界八）
//   16#0003_0731【故障级】传感器矛盾（bFbExt 与 bFbRet 同真，物理不可能）
//                → eSenConflict，锁存至复位沿
//   16#0003_0732【故障级】伸出超时（eExtending 相驻留超 tExtTo 未到位）
//                → eTimeoutExt，锁存至复位沿
//   16#0003_0733【故障级】缩回超时（eRetracting 相驻留超 tRetTo 未到位）
//                → eTimeoutRet，锁存至复位沿
//   16#0003_0734【故障级】中途无进展（运动相两反馈皆无持续 tStall）
//                → eMidStall，锁存至复位沿（冻结当前相驻留）
//   注：eErr 为枚举出口（引脚契约按任务定稿），上述数值码位为文档级
//   对照；tExtTo / tRetTo / tStall <= 0 时对应窗禁用（诊断关闭，非故障）。
// 验收 Acceptance   :
//   算法已证（脚本）：未跑 ｜ 编译器已证（三平台）：未跑
//   V1 bCmdExt 沿 + bFbExt 3s 内到位 → eExtOk、无码
//   V2 bCmdExt 沿、bFbExt 永不到 → tExtTo 到 → eExtTo + eTimeoutExt 锁存
//   V3 运动相 bFbExt 与 bFbRet 同真 → eConflict + eSenConflict 锁存
//   V4 运动相两反馈皆无超 tStall（< 超时窗）→ eMidStall 锁存、冻结驻留
//   V5 故障态 bReset 上升沿 → 解锁回 eIdle（锁存解除可达向量）
//   V6 bEn = FALSE → eIdle + 全出口清零（R303）
//   V7 非法枚举态（强改 _eState）→ ELSE 兜底落 eConflict + 0730
//   V8 tStall = T#0S → 无进展窗禁用（仅超时窗判定）
// 修订记录 Revision  :
//   2026-11-22  v1.0.0  R65 首版（批 4 · 序号 10）
// ==============================================================================
TYPE E_DL_PcdSt :
(
    eIdle       := 0,  // 空闲：等指令 / idle, waiting for the command
    eExtending  := 10, // 伸出动作中：等伸出到位反馈 / extending, waiting for the extended feedback
    eRetracting := 20, // 缩回动作中：等缩回到位反馈 / retracting, waiting for the retracted feedback
    eExtOk      := 30, // 伸出到位确认 / the extended position confirmed
    eRetOk      := 40, // 缩回到位确认 / the retracted position confirmed
    eExtTo      := 50, // 伸出超时锁存驻留（复位沿解除）/ the extend timeout dwelling, released by the reset edge
    eRetTo      := 60, // 缩回超时锁存驻留（复位沿解除）/ the retract timeout dwelling, released by the reset edge
    eConflict   := 70  // 传感器矛盾锁存驻留（复位沿解除）/ the sensor conflict dwelling, released by the reset edge
);
END_TYPE

TYPE E_DL_PcdErr :
(
    eNone        := 0,  // 无错 / no error
    eSenConflict := 10, // 传感器矛盾（含非法态拦截合并通道，边界八）/ the sensor conflict, also the illegal state channel
    eMidStall    := 20, // 中途无进展 / the mid stroke stall
    eTimeoutExt  := 30, // 伸出超时 / the extend timeout
    eTimeoutRet  := 40  // 缩回超时 / the retract timeout
);
END_TYPE

FUNCTION_BLOCK FB_DL_PneuCylinderDiag
VAR_INPUT
    bCmdExt : BOOL := FALSE;     // 伸出指令 [-]，上升沿生效 / the extend command, rising edge effective
    bCmdRet : BOOL := FALSE;     // 缩回指令 [-]，上升沿生效 / the retract command, rising edge effective
    bFbExt  : BOOL := FALSE;     // 伸出到位反馈 [-] / the extended position feedback
    bFbRet  : BOOL := FALSE;     // 缩回到位反馈 [-] / the retracted position feedback
    bEn     : BOOL := TRUE;      // 使能 [-]，FALSE 时出口清零回 eIdle（R303）/ the enable
    tExtTo  : TIME := T#5S;      // 伸出到位超时窗 [毫秒]，T#0S = 禁用 / the extend timeout, zero disables
    tRetTo  : TIME := T#5S;      // 缩回到位超时窗 [毫秒]，T#0S = 禁用 / the retract timeout, zero disables
    tStall  : TIME := T#2S;      // 无进展窗 [毫秒]，须 < min(tExtTo, tRetTo)（边界三配比），T#0S = 禁用 / the stall window with the ratio rule
    bReset  : BOOL := FALSE;     // 故障复位电平，上升沿清锁存回 eIdle（边界六解除式）/ the fault reset level
END_VAR
VAR_OUTPUT
    eSt      : E_DL_PcdSt := E_DL_PcdSt.eIdle;  // 状态机出口 [状态] / the state outlet
    bErr     : BOOL := FALSE;    // 故障锁存中 [-]，TRUE = 需复位 / the fault latched flag
    eErr     : E_DL_PcdErr := E_DL_PcdErr.eNone; // 故障码出口 [码]（锁存回放）/ the error code outlet
    bTimeout : BOOL := FALSE;    // 超时驻留指示 [-]，eExtTo / eRetTo 相为 TRUE / the timeout dwelling indicator
END_VAR
VAR
    _bInit       : BOOL := FALSE; // 首拍初始化标志（R310）/ the first scan flag
    _eState      : E_DL_PcdSt := E_DL_PcdSt.eIdle; // 内部状态寄存器 [状态] / the internal state register
    _bFaultLatch : BOOL := FALSE; // 故障锁存副本 [-]（仅复位沿清除）/ the fault latch copy
    _eErrLatch   : E_DL_PcdErr := E_DL_PcdErr.eNone; // 故障码锁存 [码]（复位沿清除，FB33-1）/ the latched error code
    rtCmdExt     : R_TRIG;        // 伸出指令沿实例，段 0 无条件刷新（R7）/ the extend command edge refreshed unconditionally
    rtCmdRet     : R_TRIG;        // 缩回指令沿实例，段 0 无条件刷新 / the retract command edge refreshed unconditionally
    rtReset      : R_TRIG;        // 复位沿实例，段 0 无条件刷新 / the reset edge instance refreshed unconditionally
    tonExtTo     : TON;           // 伸出超时窗定时器，段 0 无条件刷新 / the extend timeout timer refreshed unconditionally
    tonRetTo     : TON;           // 缩回超时窗定时器，段 0 无条件刷新 / the retract timeout timer refreshed unconditionally
    tonStall     : TON;           // 无进展窗定时器，段 0 无条件刷新 / the stall window timer refreshed unconditionally
END_VAR
VAR CONSTANT
    DL_PCD_TIME0 : TIME := T#0S; // 时间零常量 [毫秒] / the time zero constant
END_VAR

// 段 0｜定时器与沿检测实例无条件周期刷新（禁入分支，R7；监视 TON 串锁存门控，FB50-1）/ segment 0, the unconditional refresh
rtCmdExt(CLK := bCmdExt);        // 伸出指令沿 / the extend command edge
rtCmdRet(CLK := bCmdRet);        // 缩回指令沿 / the retract command edge
rtReset(CLK := bReset);          // 复位沿 / the reset edge
tonExtTo(IN := bEn AND (_eState = E_DL_PcdSt.eExtending) AND (NOT _bFaultLatch) AND (tExtTo > DL_PCD_TIME0), PT := tExtTo); // 伸出超时计时（R300：基于相驻留，与到位反馈判据不同源；窗零禁用）/ the extend timeout, state sourced per R300
tonRetTo(IN := bEn AND (_eState = E_DL_PcdSt.eRetracting) AND (NOT _bFaultLatch) AND (tRetTo > DL_PCD_TIME0), PT := tRetTo); // 缩回超时计时（同前不同源口径）/ the retract timeout, state sourced per R300
tonStall(IN := bEn AND (NOT _bFaultLatch) AND ((_eState = E_DL_PcdSt.eExtending) OR (_eState = E_DL_PcdSt.eRetracting)) AND (NOT bFbExt) AND (NOT bFbRet) AND (tStall > DL_PCD_TIME0), PT := tStall); // 无进展计时（判据 = 两反馈皆无，R300 独立第三源；反馈部分在场让路超时窗，边界三）/ the stall window on the no feedback premise

// 段 1｜首拍初始化（R310）/ segment 1, the first scan init
IF NOT _bInit THEN               // 首拍一拍 / the first scan
    _bInit := TRUE;              // 置首拍标志 / raise the first scan flag
    _eState := E_DL_PcdSt.eIdle; // 状态显式落空闲 / place the state to idle
    _bFaultLatch := FALSE;       // 故障锁存显式清零 / clear the fault latch explicitly
    _eErrLatch := E_DL_PcdErr.eNone; // 码锁存显式清零 / clear the latched code explicitly
END_IF

// 段 2｜复位沿作用域（R311：清双锁存 + 迁空闲）/ segment 2, the reset edge scope
IF rtReset.Q THEN                // 复位沿 / the reset edge
    _bFaultLatch := FALSE;       // 清故障锁存（唯一解除路径，边界六自证可达）/ clear the fault latch
    _eErrLatch := E_DL_PcdErr.eNone; // 清码锁存 / clear the latched code
    _eState := E_DL_PcdSt.eIdle; // 迁回空闲 / back to idle
END_IF

// 段 3｜失能分支：强制 eIdle + 全出口清零，不 faults（R303 离相清零声明行）/ segment 3, the disabled branch
IF NOT bEn THEN                  // 失能 / disabled
    _eState := E_DL_PcdSt.eIdle; // 强制空闲 / force the idle
    _bFaultLatch := FALSE;       // 清故障锁存（使能断开 ≠ 气缸故障）/ clear the fault latch
    _eErrLatch := E_DL_PcdErr.eNone; // 清码锁存 / clear the latched code
    eSt := _eState;              // 状态出口 / the state outlet
    bErr := FALSE;               // 故障位复位 / the fault bit resets
    eErr := E_DL_PcdErr.eNone;   // 码出口复位 / the code outlet resets
    bTimeout := FALSE;           // 超时指示复位 / the timeout indicator resets
    RETURN;                      // 早退 / early return
END_IF

// 段 4｜传感器矛盾全局闸（最高优先级，R190 归因唯一独立码；锁存期不重置）/ segment 4, the sensor conflict gate
IF bFbExt AND bFbRet AND (NOT _bFaultLatch) THEN // 双反馈同真（物理不可能，真实可达：接线错 / 磁开失效）/ both feedbacks true
    _bFaultLatch := TRUE;        // 锁存故障 / latch the fault
    _eErrLatch := E_DL_PcdErr.eSenConflict; // 故障级 0731：传感器矛盾 / the conflict code
    _eState := E_DL_PcdSt.eConflict; // 迁入矛盾驻留相 / enter the conflict phase
END_IF

// 段 5｜主状态机（ENUM + CASE + ELSE 兜底；锁存期冻结禁迁移；本拍合法事件优先于超时，R275）/ segment 5, the main machine frozen on the latch
IF NOT _bFaultLatch THEN         // 未锁存才推进（故障态 / 冻结相驻留，边界五）/ advance only without a latch
    CASE _eState OF
        E_DL_PcdSt.eIdle:        // 空闲相 / the idle phase
            IF rtCmdExt.Q THEN   // 事件优先：伸出指令沿（同拍双指令伸出优先，声明口径）/ the extend edge first
                _eState := E_DL_PcdSt.eExtending; // 迁入伸出相 / enter the extending phase
            ELSIF rtCmdRet.Q THEN // 缩回指令沿 / the retract edge
                _eState := E_DL_PcdSt.eRetracting; // 迁入缩回相 / enter the retracting phase
            END_IF
        E_DL_PcdSt.eExtending:   // 伸出相（本拍合法事件优先：到位先消化，再消化反向沿与超时窗，R275）/ the extending phase, the event before the timeout
            IF bFbExt THEN       // 到位反馈（推进判据，R300 反馈源）/ the extended feedback, the advance criterion
                _eState := E_DL_PcdSt.eExtOk; // 迁入伸出到位确认相 / enter the extended confirmed phase
            ELSIF rtCmdRet.Q THEN // 反向指令沿（中途反向合法）/ the reverse edge
                _eState := E_DL_PcdSt.eRetracting; // 迁入缩回相 / enter the retracting phase
            ELSIF tonExtTo.Q THEN // 伸出超窗（故障级 0732）/ the extend timeout
                _bFaultLatch := TRUE; // 锁存故障 / latch the fault
                _eErrLatch := E_DL_PcdErr.eTimeoutExt; // 故障码 / the extend timeout code
                _eState := E_DL_PcdSt.eExtTo; // 迁入超时驻留相 / enter the timeout dwelling phase
            ELSIF tonStall.Q THEN // 无进展超窗（故障级 0734；冻结当前相驻留，边界五）/ the stall, frozen dwelling
                _bFaultLatch := TRUE; // 锁存故障 / latch the fault
                _eErrLatch := E_DL_PcdErr.eMidStall; // 故障码 / the stall code
            END_IF               // 状态保持 eExtending（锁存闸冻结迁移，语义双声明）
        E_DL_PcdSt.eRetracting:  // 缩回相（同拍序与伸出相一致，R275）/ the retracting phase with the same event order
            IF bFbRet THEN       // 到位反馈（推进判据，R300 反馈源）/ the retracted feedback
                _eState := E_DL_PcdSt.eRetOk; // 迁入缩回到位确认相 / enter the retracted confirmed phase
            ELSIF rtCmdExt.Q THEN // 反向指令沿 / the reverse edge
                _eState := E_DL_PcdSt.eExtending; // 迁入伸出相 / enter the extending phase
            ELSIF tonRetTo.Q THEN // 缩回超窗（故障级 0733）/ the retract timeout
                _bFaultLatch := TRUE; // 锁存故障 / latch the fault
                _eErrLatch := E_DL_PcdErr.eTimeoutRet; // 故障码 / the retract timeout code
                _eState := E_DL_PcdSt.eRetTo; // 迁入超时驻留相 / enter the timeout dwelling phase
            ELSIF tonStall.Q THEN // 无进展超窗（故障级 0734；冻结当前相驻留，边界五）/ the stall, frozen dwelling
                _bFaultLatch := TRUE; // 锁存故障 / latch the fault
                _eErrLatch := E_DL_PcdErr.eMidStall; // 故障码 / the stall code
            END_IF               // 状态保持 eRetracting（锁存闸冻结迁移，语义双声明）
        E_DL_PcdSt.eExtOk:       // 伸出到位确认相（位置随反馈电平同步）/ the extended confirmed phase
            IF bFbRet AND (NOT bFbExt) THEN // 反馈切换到缩回侧 / the feedback moved to the retracted side
                _eState := E_DL_PcdSt.eRetOk; // 同步缩回确认 / sync to the retracted confirmed
            ELSIF (NOT bFbExt) AND (NOT bFbRet) THEN // 双反馈皆失（物理中途态）/ both feedbacks lost
                _eState := E_DL_PcdSt.eIdle; // 回空闲重新同步 / back to idle for a resync
            ELSIF rtCmdRet.Q THEN // 缩回指令沿 / the retract edge
                _eState := E_DL_PcdSt.eRetracting; // 迁入缩回相 / enter the retracting phase
            END_IF
        E_DL_PcdSt.eRetOk:       // 缩回到位确认相（位置随反馈电平同步）/ the retracted confirmed phase
            IF bFbExt AND (NOT bFbRet) THEN // 反馈切换到伸出侧 / the feedback moved to the extended side
                _eState := E_DL_PcdSt.eExtOk; // 同步伸出确认 / sync to the extended confirmed
            ELSIF (NOT bFbExt) AND (NOT bFbRet) THEN // 双反馈皆失 / both feedbacks lost
                _eState := E_DL_PcdSt.eIdle; // 回空闲重新同步 / back to idle for a resync
            ELSIF rtCmdExt.Q THEN // 伸出指令沿 / the extend edge
                _eState := E_DL_PcdSt.eExtending; // 迁入伸出相 / enter the extending phase
            END_IF
        E_DL_PcdSt.eExtTo:       // 伸出超时驻留相（解除由段 2 复位沿承担）/ the extend timeout dwelling, released by the reset edge
            ;                    // 驻留语义由注释表达（禁自赋值死语句，R261）/ the dwell is expressed by this comment
        E_DL_PcdSt.eRetTo:       // 缩回超时驻留相（同前驻留口径）/ the retract timeout dwelling
            ;                    // 驻留语义由注释表达 / the dwell is expressed by this comment
        E_DL_PcdSt.eConflict:    // 传感器矛盾驻留相（同前驻留口径）/ the conflict dwelling
            ;                    // 驻留语义由注释表达 / the dwell is expressed by this comment
        ELSE                     // 非法枚举值拦截（边界八：合并 eSenConflict 通道，R90 反证句见码表）/ the illegal enumeration guard
            _bFaultLatch := TRUE; // 锁存故障 / latch the fault
            _eErrLatch := E_DL_PcdErr.eSenConflict; // 故障级 0730（合并通道，R90）/ the merged conflict channel
            _eState := E_DL_PcdSt.eConflict; // 落矛盾驻留相 / force the conflict phase
    END_CASE
END_IF

// 段 6｜统一出口（名实双出口同源，R191）/ segment 6, the unified outlet
eSt := _eState;                  // 状态出口 / the state outlet
bErr := _bFaultLatch;            // 故障位与锁存同源 / the fault bit from the latch
eErr := _eErrLatch;              // 码出口与锁存同源（锁存回放）/ the code outlet from the latch
bTimeout := (_eState = E_DL_PcdSt.eExtTo) OR (_eState = E_DL_PcdSt.eRetTo); // 超时驻留指示与状态同源 / the timeout indicator from the state
END_FUNCTION_BLOCK
