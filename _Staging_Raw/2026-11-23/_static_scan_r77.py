# -*- coding: utf-8 -*-
"""One-off static redline scanner for R77 (verifier use only, no source edits)."""
import re, sys, io, json, os

FILES = [l.strip() for l in io.open(r"C:\Library\_Staging_Raw\2026-11-23\_r77_files.txt", encoding="utf-8") if l.strip()]

RESERVED = set("""PROGRAM FUNCTION_FUNCTION_BLOCK FUNCTION END_FUNCTION END_FUNCTION_BLOCK END_STRUCT END_IF END_CASE END_FOR END_WHILE END_REPEAT END_METHOD END_PROPERTY
IF THEN ELSIF ELSE CASE OF FOR TO BY DO WHILE UNTIL EXIT RETURN
AND OR XOR NOT MOD
AT INPUT OUTPUT INOUT VAR VAR_INPUT VAR_OUTPUT VAR_IN_OUT VAR_GLOBAL VAR_EXTERNAL VAR_ACCESS VAR_CONFIG CONSTANT RETAIN NON_RETAIN PERSISTENT SUPER
BOOL BYTE WORD DWORD LWORD SINT INT DINT LINT USINT UINT UDINT ULINT REAL LREAL TIME DATE TIME_OF_DAY TOD DATE_AND_TIME DT STRING WSTRING CHAR WCHAR
ARRAY POINTER REF TO AT ADDRESS OF BIT
METHOD PROPERTY ABSTRACT FINAL OVERRIDE PUBLIC PRIVATE PROTECTED INTERNAL INTERFACE IMPLEMENTS EXTENDS NAMESPACE USING
TRUE FALSE NULL EN ENO NTF ADDR SIZEOF THIS
DIRECT_ACCESS READ_ONLY READ_WRITE READ_WRITE_TASK TASK WATCHDOG SINGLE INTERVAL PRIORITY ON OFF
STRUCT ENUM UNION TYPE END_TYPE
AS TRUE FALSE""".split())
RESERVED = {r.upper() for r in RESERVED if r}

def strip_block_comments(text):
    """State-machine removal of (* *) across lines; keep line structure."""
    out, i, n = [], 0, len(text)
    in_blk = in_line = False
    line_buf = []
    while i < n:
        two = text[i:i + 2]
        if in_blk:
            if two == "*)":
                in_blk = False
                i += 2
            else:
                if text[i] == "\n":
                    out.append("".join(line_buf))
                    line_buf = []
                i += 1
        elif in_line:
            if text[i] == "\n":
                in_line = False
                out.append("".join(line_buf))
                line_buf = []
            i += 1
        else:
            if two == "(*":
                in_blk = True
                i += 2
            elif two == "//":
                in_line = True
                i += 2
            else:
                line_buf.append(text[i])
                i += 1
    out.append("".join(line_buf))
    return out

def strip_comments(line):
    # remove (* *) and // and trailing {..} pragmas
    line = re.sub(r"\{[^}]*\}", " ", line)  # pragmas
    return line

def chinese(s):
    return any('\u4e00' <= c <= '\u9fff' for c in s)

results = {}
for rel in FILES:
    p = os.path.join(r"C:\Library", rel)
    try:
        orig = io.open(p, encoding="utf-8", errors="replace").read().splitlines()
    except Exception as e:
        results[rel] = [("IO", 0, str(e))]
        continue
    # strip multi-line comments first (preserve line numbers)
    stripped = "\n".join(strip_block_comments("\n".join(orig))).split("\n")
    if len(stripped) < len(orig):
        stripped += [""] * (len(orig) - len(stripped))
    raw = stripped
    hits = []
    code = [(i + 1, strip_comments(l)) for i, l in enumerate(raw)]

    # R1 GVL / VAR_EXTERNAL (declarations in code)
    for ln, c in code:
        if re.search(r"\bVAR_EXTERNAL\b", c) or re.match(r"\s*GVL\b", c) or re.search(r"\bVAR_GLOBAL\b", c):
            hits.append(("R1", ln, "GVL/VAR_EXTERNAL/VAR_GLOBAL in code"))
    # R2 physical addressing
    for ln, c in code:
        m = re.search(r"%[IQM]\b|%[IQM]\d", c)
        if m:
            hits.append(("R2", ln, "physical address " + m.group(0)))
    # R10 constructor-style conversion: TYPE( ... ) only on RHS of assignments/expressions
    for ln, c in code:
        if ":=" in c:
            rhs = c.split(":=", 1)[1]
            m = re.search(r"\b(LREAL|REAL|DINT|INT|UINT|UDINT|WORD|DWORD|BOOL|SINT|USINT|LINT|ULINT|BYTE|TIME|STRING)\s*\(", rhs)
            if m:
                hits.append(("R10", ln, "constructor conversion " + m.group(0)))
    # R14 PROPERTY in FB
    for ln, c in code:
        if re.search(r"\bPROPERTY\b", c):
            hits.append(("R14", ln, "PROPERTY in code"))
    # R8/R9 METHOD pairing and position
    method_lines = [ln for ln, c in code if re.search(r"\bMETHOD\b", c)]
    endm_lines = [ln for ln, c in code if re.search(r"\bEND_METHOD\b", c)]
    if len(method_lines) != len(endm_lines):
        hits.append(("R8", min(method_lines or [0]), "METHOD count %d != END_METHOD %d" % (len(method_lines), len(endm_lines))))
    endvar_lines = [ln for ln, c in code if re.search(r"\bEND_VAR\b", c)]
    if method_lines and endvar_lines and min(method_lines) < max(endvar_lines):
        hits.append(("R9", min(method_lines), "METHOD declared before VAR section end"))
    # collect declared identifiers (VAR sections)
    in_var = False
    decls = []
    for ln, c in code:
        if re.match(r"\s*VAR(_INPUT|_OUTPUT|_IN_OUT)?\b", c):
            in_var = True
            continue
        if re.match(r"\s*END_VAR\b", c):
            in_var = False
            continue
        if in_var:
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*(:)", c)
            if m:
                decls.append((ln, m.group(1), c))
    # R11 semicolon on declaration lines
    for ln, name, c in decls:
        if ";" not in c:
            hits.append(("R11", ln, "missing semicolon: " + name))
    # R15 reserved word collision (case-insensitive)
    for ln, name, c in decls:
        if name.upper() in RESERVED:
            hits.append(("R15", ln, "identifier %s collides with reserved word" % name))
    # R5 bilingual comment on declaration lines
    for idx, line in enumerate(orig):
        c = strip_comments(raw[idx])
        if re.match(r"\s*[A-Za-z_][A-Za-z0-9_]*\s*:(?!=)", c) and not re.match(r"\s*(FUNCTION|METHOD|PROGRAM|TYPE|STRUCT|INTERFACE|PROPERTY|END_)\b", c) and ";" in c:
            comment = ""
            if "//" in line:
                comment = line.split("//", 1)[1]
            elif "(*" in line:
                comment = line.split("(*", 1)[1]
            elif idx + 1 < len(orig) and ("//" in orig[idx + 1] or "(*" in orig[idx + 1]):
                comment = orig[idx + 1]
            if not chinese(comment) or not re.search(r"[A-Za-z]", comment):
                hits.append(("R5", idx + 1, "declaration line lacks bilingual comment"))
    results[rel] = hits

out = io.open(r"C:\Library\_Staging_Raw\2026-11-23\_static_scan_R77.json", "w", encoding="utf-8")
json.dump(results, out, ensure_ascii=False, indent=1)
out.close()
n_files = len(results)
n_hit = sum(1 for v in results.values() if v)
print("scanned", n_files, "files,", n_hit, "with hits")
for f, h in results.items():
    if h:
        print("==", f)
        for code_, ln, msg in h:
            print("   %s L%d %s" % (code_, ln, msg))
