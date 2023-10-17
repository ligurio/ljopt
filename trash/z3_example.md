
[0] ~/sources/MRG/tarantool$ luajit -jdump=-m -O+loop -Ohotloop=1 -e 'local b; for i = 1, 3 do b = 20 end'
---- TRACE 1 start (command line):1
0006  KSHORT   0  20
0007  FORL     1 => 0006
---- TRACE 1 IR
0001    int SLOAD  #2    CI
0002  + int ADD    0001  +1
0003 >  int LE     0002  +3
0004 ------ LOOP ------------
0005  + int ADD    0002  +1
0006 >  int LE     0005  +3
0007    int PHI    0002  0005
---- TRACE 1 stop -> loop

[0] ~/sources/MRG/tarantool$ luajit -bl -e "local a = 10; for i = 1, 20 do a = 30 end"
-- BYTECODE -- 0x4034a150:0-1
0001    KSHORT   0  10
0002    KSHORT   1   1
0003    KSHORT   2  20
0004    KSHORT   3   1
0005    FORI     1 => 0008
0006 => KSHORT   0  30
0007    FORL     1 => 0006
0008 => RET0     0   1
$
