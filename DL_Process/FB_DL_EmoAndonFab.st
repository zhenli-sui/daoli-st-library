// =====================================================================
// FB_DL_EmoAndonFab.st
// 洁净室 EMO-安灯联动呼叫（EMO 急停优先仲裁 + 门审计联动 + 应答/复位管理）
// Cleanroom EMO andon linkage with priority arbitration and door audit
// 所属子库: DL_Process    版本: v1.0.0    兼容: CODESYS V3.5+ / TwinCAT 3 / 汇川 InoProShop
// 码位: 16#0005_047B ~ 16#0005_047F (本件独占 5 槽, 勿复用)
// 溯源: 道莅 clean-room 防御性实现
//       来源组标签: semiconductor, andon, emo, safety-linkage
// 枚举属主: E_DL_AndonLevel —— 全库唯一属主为 DL_Process 安灯呼叫系统件,
//           本件只引用不重声明
// 修改记录: R30 初版 (ROUND_PLAN_R30 序 10)
// 分层声明: 本件为联动编排件, 四级仲裁律全部消费库内安灯呼叫系统件的
//           E_DL_AndonLevel 契约, 不重写普通呼叫仲裁; EMO 触发不唯一属主,
//           首出定位到按钮号; 门审计事件经门开位掩码引脚注入
// =====================================================================
FUNCTION_BLOCK FB_DL_EmoAndonFab
VAR_INPUT
    abEmo        : ARRAY[1..6] OF BOOL;  // EMO 急停按钮阵列 / EMO button array
    bDoorOpenMask: WORD := 0;        // 安全门开位掩码注入, 位 0..5 对应门 1..6 / Door-open mask injected, bit0..5 = door 1..6
    bAck         : BOOL := FALSE;    // 呼叫应答命令 / Call acknowledge command
    bReset       : BOOL := FALSE;    // 事件复位命令 / Event reset command
END_VAR
VAR_OUTPUT
    eAndonLevel  : E_DL_AndonLevel := E_DL_AndonLevel.eNone;  // 联动安灯级别 / Linked andon level
    bLampRed     : BOOL := FALSE;    // 红灯输出 / Red lamp output
    bBuzzer      : BOOL := FALSE;    // 蜂鸣输出（应答后静音）/ Buzzer output, muted after ack
    uFirstEmo    : USINT := 0;       // 首出 EMO 按钮号 1~6, 0 = 无 / First-out EMO button, 0 = none
    eErr         : UDINT := 16#0005_047B;  // 错误码 / Error code
END_VAR
VAR
    rtrAck       : R_TRIG;           // 应答沿检测, 每拍无条件刷新 / Ack edge, refreshed every cycle
    rtrReset     : R_TRIG;           // 复位沿检测, 每拍无条件刷新 / Reset edge, refreshed every cycle
    bEmoAny      : BOOL := FALSE;    // 任一 EMO 有效标记 / Any EMO active flag
    uFirstThis   : USINT := 0;       // 本拍首出候选按钮号 / First-out candidate this cycle
    uFirstLatch  : USINT := 0;       // 首出锁存按钮号 / First-out latched button
    bAckLatch    : BOOL := FALSE;    // 应答静音锁存 / Acknowledge mute latch
    uZi          : INT   := 1;       // 1..6 数组下标 / Array subscript 1..6
END_VAR

// ---------------------------------------------------------------------
// 代码位表（本件独占, 勿复用）:
//   16#0005_047B 信息 无 EMO 无门审计事件
//   16#0005_047C 故障 EMO 急停触发（任一按钮有效, 优先级高于门审计）,
//                解除式 = 全部按钮释放 且 bReset 上升沿
//   16#0005_047D 故障 安全门审计联动（门开掩码非零）, 解除式 = 门掩码归零
//   16#0005_047E 信息 应答沿确认（事件存续期间的应答统计拍,
//                未应答解除不计入应答统计, 沿用安灯呼叫系统语义）
//   16#0005_047F 信息 复位确认（事件已解除后的复位拍, 清应答锁存）
// ---------------------------------------------------------------------

// ---- EMO 首出候选扫描（升序取最小按钮号）/ EMO first-out candidate scan ----
bEmoAny := FALSE;                   // 标记复位 / Reset flag
uFirstThis := 0;                    // 候选清零 / Clear candidate
FOR uZi := 1 TO 6 DO
    IF abEmo[uZi] THEN
        bEmoAny := TRUE;            // 任一按钮有效 / Any button active
        IF uFirstThis = 0 THEN
            uFirstThis := INT_TO_USINT(uZi);    // 升序首出候选 / Ascending first candidate
        END_IF
    END_IF
END_FOR

// ---- 应答与复位沿实例无条件刷新 / Unconditional ack and reset edge refresh ----
rtrAck(CLK := bAck);
rtrReset(CLK := bReset);

// ---- 首出锁存与解除 / First-out latch and release ----
IF (uFirstLatch = 0) AND bEmoAny THEN
    uFirstLatch := uFirstThis;      // 未锁存才仲裁, 同拍取最小按钮号 / Arbitrate only if unlatched, min button
END_IF
IF NOT bEmoAny THEN
    uFirstLatch := 0;               // 全部释放解除首出锁存 / Release when all clear
END_IF
uFirstEmo := uFirstLatch;           // 输出首出按钮号 / Output first-out button

// ---- 应答锁存管理（未应答解除不计入应答统计: 解除拍自动清锁存）
//      Ack latch management, un-acked release clears latch ----
IF rtrAck.Q AND (bEmoAny OR (bDoorOpenMask <> 0)) THEN
    bAckLatch := TRUE;              // 事件存续期间应答生效 / Ack effective while event present
END_IF
IF (NOT bEmoAny) AND (bDoorOpenMask = 0) THEN
    bAckLatch := FALSE;             // 事件消失清应答锁存 / Clear latch on event clear
END_IF

// ---- 联动级别仲裁: EMO 优先于门审计, 同拍取高者 / Level arbitration: EMO over door ----
IF bEmoAny THEN
    eAndonLevel := E_DL_AndonLevel.eMaint;      // EMO 映射最高优先级维修级 / EMO maps to highest level
ELSIF bDoorOpenMask <> 0 THEN
    eAndonLevel := E_DL_AndonLevel.eDevice;     // 门审计映射设备级 / Door audit maps device level
ELSE
    eAndonLevel := E_DL_AndonLevel.eNone;       // 无事件 / No event
END_IF

// ---- 灯与蜂鸣输出（蜂鸣按级别 CASE 判定, 含 ELSE 兜底）/ Lamp and buzzer with CASE fallback ----
bLampRed := bEmoAny OR (bDoorOpenMask <> 0);    // 红灯: 任一事件点亮 / Lamp on any event
CASE eAndonLevel OF
    E_DL_AndonLevel.eNone:     bBuzzer := FALSE;                        // 无事件不鸣响 / No event, silent
    E_DL_AndonLevel.eMaterial: bBuzzer := FALSE;                        // 本件不消费普通缺料级 / Material level not consumed here
    E_DL_AndonLevel.eQuality:  bBuzzer := FALSE;                        // 本件不消费普通品质级 / Quality level not consumed here
    E_DL_AndonLevel.eDevice:   bBuzzer := bLampRed AND (NOT bAckLatch); // 设备级: 未应答鸣响 / Device level: buzzer until ack
    E_DL_AndonLevel.eMaint:    bBuzzer := bLampRed AND (NOT bAckLatch); // 维修级: 未应答鸣响 / Maint level: buzzer until ack
    ELSE                       bBuzzer := bLampRed;                     // 兜底: 未知级别按最响处理 / Fallback: loudest
END_CASE

// ---- 错误码仲裁 / Error arbitration ----
IF bEmoAny THEN
    eErr := 16#0005_047C;           // EMO 触发（最高优先级）/ EMO active, highest priority
ELSIF rtrAck.Q AND bLampRed THEN
    eErr := 16#0005_047E;           // 应答沿确认拍 / Ack edge cycle
ELSIF bDoorOpenMask <> 0 THEN
    eErr := 16#0005_047D;           // 门审计联动 / Door audit linkage
ELSIF rtrReset.Q AND (NOT bEmoAny) THEN
    eErr := 16#0005_047F;           // 复位确认拍 / Reset confirm cycle
ELSE
    eErr := 16#0005_047B;           // 无事件 / No event
END_IF

END_FUNCTION_BLOCK
