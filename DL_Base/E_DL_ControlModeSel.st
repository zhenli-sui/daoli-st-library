// E_DL_ControlModeSel v1.0.0
// 开源溯源：AixOCAT / URL https://github.com/AixOCAT / 许可证 MIT / 借鉴 CONTROL_MODE 枚举语义（手/自动/停止三态），clean-room 重写
(*
  道莅工业代码库 | DL_Base | E_DL_ControlModeSel
  版本: 1.0.0 | 日期: 2026-11-23 | 轮次: R75
  功能: 手动/自动/停止三态控制模式枚举（strict 口径，配 MANUAL 覆写件族）
  邻件关系: 与 E_SMStatus 语义相邻（状态机状态 vs 操作模式选择），本件为
            模式选择属主；引用方（覆写/手自动切换族）只引用不重声明（R12）
  使用约定: 全库唯一属主，其他件引用时由 L2 闸按类型名自动回溯本文件；
            成员值固定步进 10，禁止中途插值改序（防历史引用漂移）
*)
TYPE E_DL_ControlModeSel :
(
    eManual := 0,    // 手动模式（操作员直控，联锁保留）/ Manual mode, operator direct with interlocks
    eAuto   := 10,   // 自动模式（程序/上位调度）/ Auto mode, program or supervisory driven
    eStop   := 20    // 停止模式（受控停机，输出回安全位）/ Stop mode, controlled stop to safe outputs
);
END_TYPE
