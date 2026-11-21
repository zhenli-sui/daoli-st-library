# -*- coding: utf-8 -*-
"""R25 手册增量：从 .st 源码提取本轮 20 件的 VAR_INPUT/VAR_OUTPUT 接口表并追加到对应 MANUAL（追加式，不重写正文）。"""
import re, os, json

os.chdir("C:/Library")
SET = {
 "DL_MathData": ["FC_DL_Affine2DInvert"],
 "DL_Algo": ["FB_DL_ParticleCounterStat", "FB_DL_CoolingTowerApproachCalc", "FB_DL_DuctStaticReset", "FB_DL_DewpointReset"],
 "DL_Device": ["FB_DL_InverterGridSync", "FB_DL_HeatPumpDefrost", "FB_DL_VavBoxCtrl", "FB_DL_WaferMapping"],
 "DL_Motion": ["FB_DL_StackingAlignCtrl", "FB_DL_LabelApplySync"],
 "DL_Process": ["FB_DL_RoomClimateCtrl", "FB_DL_WeightCheckReject", "FB_DL_CasePackerPattern",
                "FB_DL_BatteryTestCycler", "FB_DL_PalletizerLayerSeq", "FB_DL_SplicerAutoJoint",
                "FB_DL_ChillerSeqMgr", "FB_DL_FormationChannelMgr", "FB_DL_SolarStringGroundFault"],
}


def cn(cmt):
    c = cmt.strip().lstrip('/').strip()
    return c.split('/')[0].strip().rstrip('，,；;')


def parse(path):
    src = open(path, encoding='utf-8', newline='').read()
    ver = re.search(r'版本：(v[\d.]+)', src).group(1)
    title = re.search(r'中文名称：([^\s｜]+)', src)
    title = title.group(1) if title else ''
    out = {}
    for sec in ("VAR_INPUT", "VAR_OUTPUT"):
        m = re.search(sec + r'(.*?)\nEND_VAR', src, re.S)
        pins = []
        for line in m.group(1).splitlines():
            mm = re.match(r'\s*(\w+)\s*:\s*([^;]+);\s*//?\s*(.*)$', line)
            if not mm:
                continue
            nm, ty, cmt = mm.group(1), mm.group(2).strip(), mm.group(3)
            dflt = ''
            dm = re.search(r'\s*:=\s*([^;]+)$', ty)
            if dm:
                dflt = dm.group(1).strip()
                ty = ty[:dm.start()].strip()
            pins.append((nm, ty, dflt, cn(cmt)))
        out[sec] = pins
    codes = []
    for m in re.finditer(r'(DL_\w*CODE\w*)\s*:\s*UDINT\s*:=\s*16#([0-9A-Fa-f_]+)', src):
        if '预留' in src[m.start():m.start() + 200].splitlines()[0]:
            continue
        codes.append(m.group(2).replace('_', '_'))
    seg = re.search(r'16#000\d_', src).group(0)
    return ver, title, out, codes, seg


def fmt_pins(pins):
    parts = []
    for nm, ty, dflt, cmt in pins:
        s = '`%s`（%s' % (nm, ty)
        if dflt:
            s += ' 缺省 %s' % dflt
        s += '）'
        parts.append(s)
    return '、'.join(parts)


for cat, names in SET.items():
    man = "%s/MANUAL_%s.md" % (cat, cat)
    body = open(man, encoding='utf-8', newline='').read()
    add = ["", "---", "", "## 附录 · R25 批次接口表（2026-11-17，共 %d 件）" % len(names), "",
           "> 引脚名与类型均由 `.st` 源码 VAR_INPUT / VAR_OUTPUT 段机读提取（不凭记忆）；单位与工程量纲见各件头注释「单位表」。", ""]
    for n in names:
        p = "%s/%s.st" % (cat, n)
        ver, title, io, codes, seg = parse(p)
        add.append("### %s ｜ %s（%s %s）" % (n, title, cat, ver))
        add.append("- **输入引脚**：%s" % fmt_pins(io["VAR_INPUT"]))
        add.append("- **输出引脚**：%s" % fmt_pins(io["VAR_OUTPUT"]))
        add.append("- **码位**：%s" % ' ｜ '.join('`16#%s`' % c for c in codes))
        add.append("")
    add.append("*Last updated: 2026-11-17（R25 追加接口表 20 件）｜ 道莅工控代码库产品总监*")
    open(man, 'w', encoding='utf-8', newline='').write(body.rstrip('\n') + '\n' + '\n'.join(add) + '\n')
    print("appended", man, len(names))
