(*
 * FC_DL_SpreaderTwistLockChk | C2 | DL_Device
 * 功能：吊具四角旋锁的到位互锁判定（全锁 / 全开 / 未知 / 故障）       单位：nLockState [枚举码 0/1/2/3]、nFaultCode [INT]
 * 工况边界：仅适用于四角独立旋锁（每角一锁到位 + 一开到位双反馈）；单角双 ON、混合状态、计数越界一律判故障 9201 并置 xFault；本件为纯函数，超时由调用方 FB 计时
 * 代数值回代：四锁位全 ON 且四开位全 OFF → nLockState=1、xLockedOk=TRUE；四锁位全 OFF 且四开位全 ON → nLockState=2、xUnlockedOk=TRUE（与 spec 判定表一致）
 * 开源溯源：clean-room 自研，未复制任何第三方代码（无外部来源）
 *)
FUNCTION FC_DL_SpreaderTwistLockChk : BOOL
VAR_INPUT
    xLockFL   : BOOL;                // 左前锁到位 | front-left locked
    xLockFR   : BOOL;                // 右前锁到位 | front-right locked
    xLockRL   : BOOL;                // 左后锁到位 | rear-left locked
    xLockRR   : BOOL;                // 右后锁到位 | rear-right locked
    xUnlockFL : BOOL;                // 左前开到位 | front-left unlocked
    xUnlockFR : BOOL;                // 右前开到位 | front-right unlocked
    xUnlockRL : BOOL;                // 左后开到位 | rear-left unlocked
    xUnlockRR : BOOL;                // 右后开到位 | rear-right unlocked
END_VAR
VAR_OUTPUT
    nLockState : INT;                // 0=未知 / 1=全锁 / 2=全开 / 3=故障 | 0 unknown, 1 all locked, 2 all unlocked, 3 fault
    xLockedOk  : BOOL;               // 允许起吊（四角全锁）| lifting permitted, all four locked
    xUnlockedOk: BOOL;               // 允许脱箱（四角全开）| releasing permitted, all four unlocked
    xFault     : BOOL;               // 故障标志 | fault flag
    nFaultCode : INT;                // 故障码 0=无 / 9201=旋锁状态非法 | fault code 0=none, 9201=illegal twist lock state
    xValid     : BOOL;               // 判定结果可用（全锁或全开）| the verdict is usable, all locked or all unlocked
END_VAR
VAR
    nLockOn   : INT;                 // 锁到位计数 | count of locked positions
    nUnlockOn : INT;                 // 开到位计数 | count of unlocked positions
END_VAR

// 段1｜计数：分别统计锁到位与开到位（同角双 ON 会体现在计数总和中）
nLockOn := 0;
nUnlockOn := 0;
IF xLockFL THEN
    nLockOn := nLockOn + 1;
END_IF
IF xLockFR THEN
    nLockOn := nLockOn + 1;
END_IF
IF xLockRL THEN
    nLockOn := nLockOn + 1;
END_IF
IF xLockRR THEN
    nLockOn := nLockOn + 1;
END_IF
IF xUnlockFL THEN
    nUnlockOn := nUnlockOn + 1;
END_IF
IF xUnlockFR THEN
    nUnlockOn := nUnlockOn + 1;
END_IF
IF xUnlockRL THEN
    nUnlockOn := nUnlockOn + 1;
END_IF
IF xUnlockRR THEN
    nUnlockOn := nUnlockOn + 1;
END_IF

// 段2｜状态判定（出口先取安全侧：不允许起吊也不允许脱箱）
xLockedOk := FALSE;
xUnlockedOk := FALSE;
xFault := FALSE;
nFaultCode := 0;
IF (nLockOn = 4) AND (nUnlockOn = 0) THEN
    nLockState := 1;                 // 全锁：四锁位 ON + 四开位 OFF | all locked
    xLockedOk := TRUE;
ELSIF (nLockOn = 0) AND (nUnlockOn = 4) THEN
    nLockState := 2;                 // 全开：四开位 ON + 四锁位 OFF | all unlocked
    xUnlockedOk := TRUE;
ELSIF (nLockOn = 0) AND (nUnlockOn = 0) THEN
    nLockState := 0;                 // 未知：无任何到位反馈 | unknown, no feedback at all
ELSIF (nLockOn + nUnlockOn) > 4 THEN
    nLockState := 3;                 // 故障：同角双 ON 或计数越界 | fault, both bits of one corner are on
    xFault := TRUE;
    nFaultCode := 9201;
ELSE
    nLockState := 3;                 // 故障：混合状态（部分锁部分开）| fault, mixed state
    xFault := TRUE;
    nFaultCode := 9201;
END_IF

// 段3｜出口：只有全锁或全开才认为判定可用
xValid := xLockedOk OR xUnlockedOk;
FC_DL_SpreaderTwistLockChk := xValid;
END_FUNCTION
