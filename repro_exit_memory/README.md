# ljopt misses a miscompile around a trace exit (no loop involved)

ljopt compares table memory only at its **final version**, and never
conditions a store on whether the trace already exited. Snapshot
*slots* are compared per snapshot; memory is not. So a store that is
overwritten later, but observable at an exit in between, can be
deleted without ljopt noticing.

This is not loop-specific. The trace here is straight-line
(`stop -> return`), so `last_iter_ref` is nil and the guard pinning
in `ir_smtlib.lua` never runs.

## The shape

`trace.lua` records:

    0009    num ASTORE 0006  0001   ; store A into t[1]
    0010 >  num SLOAD  #3           ; guards that can exit ...
    0011 >  int CONV   0010  index
    0012 >  int ABC    0003  0011
    0014 >  num ALOAD  0013
    0016    num ASTORE 0006  0015   ; store B, overwrites A

`lj_opt_dse_ahstore` refuses to drop store A precisely because of the
guards at 10..14. Remove that check (`dse_across_guard.patch`) and it
drops it.

## Result

    clean  luajit: ljopt -> unsat   (correct, traces equivalent)
    faulty luajit: ljopt -> unsat   (WRONG -- miscompile missed)

`runtime_check.lua` shows the miscompile is real, not just an IR
difference. It warms the trace, writes a marker, then forces an exit
between the two stores:

    clean  luajit: t[1] == 12345   (store A ran before the exit)
    faulty luajit: t[1] == -1      (store A was eliminated)

## Fix direction

Compare memory at each snapshot, at the version current at that
snapshot, the way slots already are. The snapshot machinery to hang
it on already exists (`enrich_snapshots_with_exits`, snap_te).
