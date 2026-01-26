Здесь 
0019 >  int LE     0018  #x4026000000000000
в оптимизированной попадает в снэпшот с оффсетом 18700
В неоптимизированной в снэпшот с оффсетом 800
0053 >  int LE     0052  #x4026000000000000

Аналогично в
../ljopt-tests/samples/14300902197835653140.lua



---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE 1 start 0x41947778:7
Trace bytes: 	24910	

---- TRACE 1 IR
Snapshot offseet: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  num SLOAD  #1    T
Snapshot offseet: 	500	

....        SNAP   #1   [ ---- ---- ]
0002 >  num EQ     0001  0001
Snapshot offseet: 	900	

....        SNAP   #2   [ ---- ---- 0001 ]
---- TRACE 1 stop -> return

---- TRACE 2 start 0x41947ac0:16
Trace bytes: 	2	

---- TRACE 2 IR
Snapshot offseet: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  tab SLOAD  #1    T
Snapshot offseet: 	100	

....        SNAP   #1   [ ---- ---- ]
---- TRACE 2 stop -> return

---- TRACE 3 start 0x403919c8:217
Trace bytes: 	180181182185186187188156157158159160161124910162163164165166167124910168169170171017212173174175017612177179	

---- TRACE 3 IR
Snapshot offseet: 	17900	

....        SNAP   #0   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "counter_0" @55
0007 >  num HLOAD  0006
0008    num CONV   #x4014000000000000  num.int
Snapshot offseet: 	18300	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0009 >  num UGE    0008  0007
Snapshot offseet: 	18400	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0010    tab FLOAD  0001  func.env
0011    int FLOAD  0010  tab.hmask
0012 >  int EQ     0011  #x404f800000000000
0013    p32 FLOAD  0010  tab.node
0014 >  p32 HREFK  0013  "counter_0" @55
0015 >  num HLOAD  0014
0016    num CONV   #x3ff0000000000000  num.int
0017    num ADD    0015  0016
0018    tab FLOAD  0001  func.env
0019    int FLOAD  0018  tab.hmask
0020 >  int EQ     0019  #x404f800000000000
0021    p32 FLOAD  0018  tab.node
0022 >  p32 HREFK  0021  "counter_0" @55
0023    tab FLOAD  0018  tab.meta
0024 >  tab EQ     0023  NULL
0025    num HSTORE 0022  0017
0026    nil TBAR   0018
Snapshot offseet: 	18700	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0027    tab FLOAD  0001  func.env
0028    int FLOAD  0027  tab.hmask
0029 >  int EQ     0028  #x404f800000000000
0030    p32 FLOAD  0027  tab.node
0031 >  p32 HREFK  0030  "setmetatable" @63
0032 >  fun HLOAD  0031
0033 >  tab TDUP   {0x4039e450}
0034 >  fun SLOAD  #3    T
0035    num CONV   #x0000000000000000  num.int
0036    num FLOAD  nil  #226
0037    num NEG    0035  0036
0038 >  fun EQ     0034  0x41947778:7
Snapshot offseet: 	500	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0x41947778:7|0037 ]
0039 >  num EQ     0037  0037
Snapshot offseet: 	800	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0x41947778:7|0037 ]
0040    tab FLOAD  0001  func.env
0041    int FLOAD  0040  tab.hmask
0042 >  int EQ     0041  #x404f800000000000
0043    p32 FLOAD  0040  tab.node
0044 >  p32 HREFK  0043  "setmetatable" @63
0045 >  fun HLOAD  0044
0046 >  tab TNEW   #0    #1  
0047    num CONV   #x0000000000000000  num.int
0048    num FLOAD  nil  #226
0049    num NEG    0047  0048
0050 >  fun EQ     0034  0x41947778:7
Snapshot offseet: 	500	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0037 0045 0046 0x41947778:7|0049 ]
0051 >  num EQ     0049  0049
Snapshot offseet: 	800	

....        SNAP   #7   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0037 0045 0046 0x41947778:7|0049 ]
0052    int SLOAD  #0    FR
0053 >  int LE     0052  #x4026000000000000
0054 >  int CONV   0049  int.num index
0055    int FLOAD  0046  tab.asize
0056 >  int ULE    0055  0054
0057    p32 HREF   0046  0049
0058 >  p32 EQ     0057  [0x4138a4e8]
0059    tab FLOAD  0046  tab.meta
0060 >  tab EQ     0059  NULL
0061 >  num EQ     0049  0049
0062    p32 NEWREF 0046  0049
0063    nil HSTORE 0062  nil
Snapshot offseet: 	16900	

....        SNAP   #8   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0037 0045 0046 ---- ---- ]
0064 >  tab SLOAD  #25   T
0065 >  fun EQ     0045  setmetatable
0066    tab FLOAD  0046  tab.meta
0067 >  tab EQ     0066  NULL
0068    p32 FREF   0046  tab.meta
0069    tab FSTORE 0068  0064
0070    tab TBAR   0046
Snapshot offseet: 	17100	

....        SNAP   #9   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 0037 0046 ]
0071    tab FLOAD  0046  tab.meta
0072 >  tab NE     0071  NULL
0073    int FLOAD  0071  tab.hmask
0074 >  int EQ     0073  #x402e000000000000
0075    p32 FLOAD  0071  tab.node
0076 >  p32 HREFK  0075  "__call" @4
0077 >  fun HLOAD  0076
0078 >  fun EQ     0077  0x41947ac0:16
0079 >  int CONV   0037  int.num index
0080    int FLOAD  0033  tab.asize
0081 >  int ULE    0080  0079
0082    p32 HREF   0033  0037
0083 >  p32 EQ     0082  [0x4138a4e8]
0084    tab FLOAD  0033  tab.meta
0085 >  tab EQ     0084  NULL
0086 >  num EQ     0037  0037
0087    p32 NEWREF 0033  0037
0088    tab HSTORE 0087  0046
0089    nil TBAR   0033
Snapshot offseet: 	17300	

....        SNAP   #10  [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0033 ---- ---- ]
0090 >  fun EQ     0032  setmetatable
0091    tab FLOAD  0033  tab.meta
0092 >  tab EQ     0091  NULL
0093    p32 FREF   0033  tab.meta
0094    tab FSTORE 0093  0064
0095    tab TBAR   0033
Snapshot offseet: 	17500	

....        SNAP   #11  [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0033 ]
0096    tab FLOAD  0033  tab.meta
0097 >  tab NE     0096  NULL
0098    int FLOAD  0096  tab.hmask
0099 >  int EQ     0098  #x402e000000000000
0100    p32 FLOAD  0096  tab.node
0101 >  p32 HREFK  0100  "__call" @4
0102 >  fun HLOAD  0101
0103 >  fun EQ     0102  0x41947ac0:16
Snapshot offseet: 	17900	

....        SNAP   #12  [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
---- TRACE 3 stop -> loop

---- TRACE 4 start 3/1 0x403919c8:218
Trace bytes: 	184189	

---- TRACE 4 abort 0x403919c8:221 -- NYI: bytecode UCLO  

============================================================
---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE 1 start 0x4027ee58:7
Trace bytes: 	24910	

---- TRACE 1 IR
Snapshot offseet: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  num SLOAD  #1    T
Snapshot offseet: 	500	

....        SNAP   #1   [ ---- ---- ]
0002 >  num EQ     0001  0001
Snapshot offseet: 	900	

....        SNAP   #2   [ ---- ---- 0001 ]
---- TRACE 1 stop -> return

---- TRACE 2 start 0x4027ea60:16
Trace bytes: 	2	

---- TRACE 2 IR
Snapshot offseet: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  tab SLOAD  #1    T
Snapshot offseet: 	100	

....        SNAP   #1   [ ---- ---- ]
---- TRACE 2 stop -> return

---- TRACE 3 start 0x403a47a0:217
Trace bytes: 	180181182185186187188156157158159160161124910162163164165166167124910168169170171017212173174175017612177179	

---- TRACE 3 IR
Snapshot offseet: 	17900	

....        SNAP   #0   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "counter_0" @55
0007 >  num HLOAD  0006
Snapshot offseet: 	18300	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0008 >  num ULE    0007  #x4014000000000000
0009  + num ADD    0007  #x3ff0000000000000
0010    num HSTORE 0006  0009
Snapshot offseet: 	18700	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0011 >  p32 HREFK  0005  "setmetatable" @63
0012 >  fun HLOAD  0011
0013 }  tab TDUP   {0x403a2350}
0014 >  fun SLOAD  #3    T
0016 >  fun EQ     0014  0x4027ee58:7
0017 >  tab TNEW   #0    #1  
0018    int SLOAD  #0    FR
0019 >  int LE     0018  #x4026000000000000
0020    p32 NEWREF 0017  #x0000000000000000
0021    nil HSTORE 0020  nil
Snapshot offseet: 	16900	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0012 0013 -0   0012 0017 ---- ---- ]
0022 >  tab SLOAD  #25   T
0023 >  fun EQ     0012  setmetatable
0024    p32 FREF   0017  tab.meta
0025    tab FSTORE 0024  0022
Snapshot offseet: 	17100	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0012 0013 -0   0017 ]
0026    int FLOAD  0022  tab.hmask
0027 >  int EQ     0026  #x402e000000000000
0028    p32 FLOAD  0022  tab.node
0029 >  p32 HREFK  0028  "__call" @4
0030 >  fun HLOAD  0029
0031 >  fun EQ     0030  0x4027ea60:16
0032 }  p32 NEWREF 0013  #x0000000000000000
0033 }  tab HSTORE 0032  0017
0034    p32 FREF   0013  tab.meta
0035 }  tab FSTORE 0034  0022
Snapshot offseet: 	17900	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0036 ------ LOOP ------------
Snapshot offseet: 	18300	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0037 >  num ULE    0009  #x4014000000000000
0038  + num ADD    0009  #x3ff0000000000000
0039    num HSTORE 0006  0038
Snapshot offseet: 	18700	

....        SNAP   #7   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0040 }  tab TDUP   {0x403a2350}
0041 >  tab TNEW   #0    #1  
0042    p32 NEWREF 0041  #x0000000000000000
0043    nil HSTORE 0042  nil
0044    p32 FREF   0041  tab.meta
0045    tab FSTORE 0044  0022
0046 }  p32 NEWREF 0040  #x0000000000000000
0047 }  tab HSTORE 0046  0041
0048    p32 FREF   0040  tab.meta
0049 }  tab FSTORE 0048  0022
0050    num PHI    0009  0038
---- TRACE 3 stop -> loop

