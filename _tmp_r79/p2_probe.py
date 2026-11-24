MAX=0xFFFFFFFF
def pow_algo(base,exp):
    """mirror FC_DL_IntPowSatUdint v1.0.1"""
    if exp==0: return 1,False,0
    bu,eu,res,it=base,exp,1,0
    while eu>0 and it<32:
        it+=1
        if eu%2==1:
            if bu!=0 and res>(MAX//bu):
                res=MAX; ovf=True
            else:
                res=res*bu
        eu//=2
        if eu>0:
            if bu!=0 and bu>(MAX//bu): bu=MAX
            else: bu=bu*bu
    ovf=False
    # recompute flag honestly
    return res, None, it

def pow_flag(base,exp):
    if exp==0: return 1,False,0
    bu,eu,res,it,flag=base,exp,1,0,False
    while eu>0 and it<32:
        it+=1
        if eu%2==1:
            if bu!=0 and res>(MAX//bu):
                res=MAX; flag=True
            else: res=res*bu
        eu//=2
        if eu>0:
            if bu!=0 and bu>(MAX//bu): bu=MAX
            else: bu=bu*bu
    if it>=32: flag=True   # v1.0.1 P2 patch
    return res,flag,it

def truth(base,exp):
    v=base**exp
    return v if v<=MAX else None  # None=overflow

cases=[(2,32),(3,32),(1,2**31),(0,2**31),(2,2**31),(65536,2),(2,31),(10,9),(7,10),(2,63),(1,100),(0,0),(5,0),(65535,2),(65536,1),(4294967295,1),(2**16,3)]
print(f"{'base':>12} {'exp':>12} {'res':>12} {'flag':>6} {'iter':>4} {'truth':>12}  verdict")
bad=[]
for b,e in cases:
    r,f,it=pow_flag(b,e)
    t=truth(b,e)
    if t is None:
        ok = (r==MAX and f is True); want="SATURATED"
    else:
        ok = (r==t and f is False); want=str(t)
    if not ok: bad.append((b,e,r,f,it,want))
    print(f"{b:>12} {e:>12} {r:>12} {str(f):>6} {it:>4} {want:>12}  {'OK' if ok else '**MISMATCH**'}")
print("\nMISMATCH count:",len(bad))
for x in bad: print("  ",x)
