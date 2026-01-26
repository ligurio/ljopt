Пропало использование #33 и проверка
0030 >  num GE     0002  #x0000000000000000

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE 1 start 0x40a64c88:3
Trace bytes: 	2340	

---- TRACE 1 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "tonumber" @8
0007 >  fun HLOAD  0006
0008 >  str SLOAD  #1    T
0009 >  fun EQ     0007  tonumber
Snapshot offset: 	0	

....        SNAP   #1   [ ---- ---- trace: 0x40096680 [0x00003cfc] tonumber|0008 ]
---- TRACE 1 stop -> stitch

---- TRACE 2 start 1/0 0x40a64c88:4
Trace bytes: 	2340581751761771	

---- TRACE 2 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "tonumber" @8
0007 >  fun HLOAD  0006
0008 >  num SLOAD  #1    T
0009 >  fun EQ     0007  tonumber
Snapshot offset: 	700	

....        SNAP   #1   [ ---- ---- 0008 ]
0010 >  p32 RETF   proto: 0x41856e50  [0x41857148]
Snapshot offset: 	17400	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0008 ]
0011 >  fun SLOAD  #2    T
0012 >  num SLOAD  #30   T
0013 >  fun EQ     0011  0x40a64c88:3
Snapshot offset: 	0	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0008 0x40a64c88:3|0012 ]
---- TRACE 2 stop -> 1

---- TRACE 3 start 2/1 0x40a64c88:4
Trace bytes: 	81781791891901911921930194121951961971980199122002011234051112131	

---- TRACE 3 IR
0001    num SLOAD  #2    PI
Snapshot offset: 	700	

....        SNAP   #0   [ ---- ---- 0001 ]
Snapshot offset: 	700	

....        SNAP   #1   [ ---- ---- 0001 ]
0003 >  p32 RETF   proto: 0x41856e50  [0x41857154]
Snapshot offset: 	17700	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 ]
0004 >  num SLOAD  #31   T
0005    num CONV   #x3ff0000000000000  num.int
0006 >  num GE     0005  #x0000000000000000
Snapshot offset: 	17900	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 0005 0004 ]
0007 >  num GT     0004  0001
Snapshot offset: 	18800	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0008    fun SLOAD  #0    R
0009    tab FLOAD  0008  func.env
0010    int FLOAD  0009  tab.hmask
0011 >  int EQ     0010  #x404f800000000000
0012    p32 FLOAD  0009  tab.node
0013 >  p32 HREFK  0012  "setmetatable" @63
0014 >  fun HLOAD  0013
0015 >  tab TNEW   #0    #0  
0016 >  tab SLOAD  #25   T
0017 >  fun EQ     0014  setmetatable
0018    tab FLOAD  0015  tab.meta
0019 >  tab EQ     0018  NULL
0020    p32 FREF   0015  tab.meta
0021    tab FSTORE 0020  0016
0022    tab TBAR   0015
Snapshot offset: 	19300	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   0015 ]
0023    tab FLOAD  0015  tab.meta
0024 >  tab NE     0023  NULL
0025    int FLOAD  0023  tab.hmask
0026 >  int EQ     0025  #x402e000000000000
0027    p32 FLOAD  0023  tab.node
0028 >  p32 HREFK  0027  "__call" @4
0029 >  fun HLOAD  0028
0030 >  fun EQ     0029  0x40a65248:16
0031    tab FLOAD  0008  func.env
0032    int FLOAD  0031  tab.hmask
0033 >  int EQ     0032  #x404f800000000000
0034    p32 FLOAD  0031  tab.node
0035 >  p32 HREFK  0034  "setmetatable" @63
0036 >  fun HLOAD  0035
0037 >  tab TNEW   #0    #0  
0038 >  fun EQ     0036  setmetatable
0039    tab FLOAD  0037  tab.meta
0040 >  tab EQ     0039  NULL
0041    p32 FREF   0037  tab.meta
0042    tab FSTORE 0041  0016
0043    tab TBAR   0037
Snapshot offset: 	19800	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0037 ]
0044    tab FLOAD  0037  tab.meta
0045 >  tab NE     0044  NULL
0046    int FLOAD  0044  tab.hmask
0047 >  int EQ     0046  #x402e000000000000
0048    p32 FLOAD  0044  tab.node
0049 >  p32 HREFK  0048  "__call" @4
0050 >  fun HLOAD  0049
0051 >  fun EQ     0050  0x40a65248:16
0052 >  num SLOAD  #30   T
0053    int FLOAD  {0x41858db0}  tab.hmask
0054 >  int EQ     0053  #x401c000000000000
0055    p32 FLOAD  {0x41858db0}  tab.node
0056 >  p32 HREFK  0055  "__index" @4
0057 >  fun HLOAD  0056
0058 >  fun EQ     0057  0x40a64f98:25
0059    tab FLOAD  0x40a64f98:25  func.env
0060    int FLOAD  0059  tab.hmask
0061 >  int EQ     0060  #x404f800000000000
0062    p32 FLOAD  0059  tab.node
0063 >  p32 HREFK  0062  "type" @60
0064 >  fun HLOAD  0063
0065 >  fun EQ     0064  type
0066 >  fun EQ     0x40a64c88:3  0x40a64c88:3
Snapshot offset: 	0	

....        SNAP   #7   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0037 ---- 0052 ---- ---- ---- [0x00001ee5] 0x40a64c88:3|"Name0" ]
---- TRACE 3 stop -> 1

---- TRACE 4 start 1/stitch 0x40a64c88:4
Trace bytes: 	578	

---- TRACE 4 IR
Snapshot offset: 	400	

....        SNAP   #0   [ ---- ]
0001 >  nil SLOAD  #2    T
0002    fun SLOAD  #0    R
0003 >  fun EQ     0002  0x40a64c88:3
0004    num CONV   #x3ff0000000000000  num.int
Snapshot offset: 	700	

....        SNAP   #1   [ 0x40a64c88:3|---- 0004 ]
---- TRACE 4 stop -> return

---- TRACE 5 start 0x40a65248:16
Trace bytes: 	2	

---- TRACE 5 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  num SLOAD  #1    T
Snapshot offset: 	100	

....        SNAP   #1   [ ---- ---- ]
---- TRACE 5 stop -> return

---- TRACE 6 start 0x41856e50:217
Trace bytes: 	1641651661691701711721731741	

---- TRACE 6 IR
Snapshot offset: 	16300	

....        SNAP   #0   [ ---- ]
0001    num SLOAD  #28   RI
0002    num SLOAD  #27   I
0003    fun SLOAD  #0    R
0004    tab FLOAD  0003  func.env
0005    int FLOAD  0004  tab.hmask
0006 >  int EQ     0005  #x404f800000000000
0007    p32 FLOAD  0004  tab.node
0008 >  p32 HREFK  0007  "counter_0" @55
0009 >  num HLOAD  0008
0010    num CONV   #x4014000000000000  num.int
Snapshot offset: 	16700	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0011 >  num UGE    0010  0009
Snapshot offset: 	16800	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0002 0001 ---- 0002 ]
0012    tab FLOAD  0003  func.env
0013    int FLOAD  0012  tab.hmask
0014 >  int EQ     0013  #x404f800000000000
0015    p32 FLOAD  0012  tab.node
0016 >  p32 HREFK  0015  "counter_0" @55
0017 >  num HLOAD  0016
0018    num CONV   #x3ff0000000000000  num.int
0019    num ADD    0017  0018
0020    tab FLOAD  0003  func.env
0021    int FLOAD  0020  tab.hmask
0022 >  int EQ     0021  #x404f800000000000
0023    p32 FLOAD  0020  tab.node
0024 >  p32 HREFK  0023  "counter_0" @55
0025    tab FLOAD  0020  tab.meta
0026 >  tab EQ     0025  NULL
0027    num HSTORE 0024  0019
0028    nil TBAR   0020
Snapshot offset: 	17100	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0002 0001 ---- 0002 0019 ]
0029 >  fun SLOAD  #2    T
0030 >  fun EQ     0029  0x40a64c88:3
Snapshot offset: 	0	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0002 0001 ---- 0002 0x40a64c88:3|+0.28125 ]
---- TRACE 6 stop -> 1

---- TRACE 7 start 3/3 0x41856e50:221
Trace bytes: 	1801811821851861871881891901911921930194121951961971980199122002011234051112131	

---- TRACE 7 IR
0001    num SLOAD  #32   PI
0002    num SLOAD  #33   PI
0003    num SLOAD  #34   PI
Snapshot offset: 	17900	

....        SNAP   #0   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 0002 0003 ]
0004    fun SLOAD  #0    R
0005    tab FLOAD  0004  func.env
0006    int FLOAD  0005  tab.hmask
0007 >  int EQ     0006  #x404f800000000000
0008    p32 FLOAD  0005  tab.node
0009 >  p32 HREFK  0008  "counter_1" @45
0010 >  num HLOAD  0009
0011    num CONV   #x4014000000000000  num.int
Snapshot offset: 	18300	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0012 >  num UGE    0011  0010
Snapshot offset: 	18400	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 0002 ---- ]
0013    tab FLOAD  0004  func.env
0014    int FLOAD  0013  tab.hmask
0015 >  int EQ     0014  #x404f800000000000
0016    p32 FLOAD  0013  tab.node
0017 >  p32 HREFK  0016  "counter_1" @45
0018 >  num HLOAD  0017
0019    num CONV   #x3ff0000000000000  num.int
0020    num ADD    0018  0019
0021    tab FLOAD  0004  func.env
0022    int FLOAD  0021  tab.hmask
0023 >  int EQ     0022  #x404f800000000000
0024    p32 FLOAD  0021  tab.node
0025 >  p32 HREFK  0024  "counter_1" @45
0026    tab FLOAD  0021  tab.meta
0027 >  tab EQ     0026  NULL
0028    num HSTORE 0025  0020
0029    nil TBAR   0021
Snapshot offset: 	18700	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 0002 ---- ---- ]
0030 >  num GE     0002  #x0000000000000000
0031    num SLOAD  #31   I
0032    num ADD    0031  0002
Snapshot offset: 	17900	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0032 0001 0002 0032 ]
0033 >  num GT     0032  0001
Snapshot offset: 	18800	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0034    tab FLOAD  0004  func.env
0035    int FLOAD  0034  tab.hmask
0036 >  int EQ     0035  #x404f800000000000
0037    p32 FLOAD  0034  tab.node
0038 >  p32 HREFK  0037  "setmetatable" @63
0039 >  fun HLOAD  0038
0040 >  tab TNEW   #0    #0  
0041 >  tab SLOAD  #25   T
0042 >  fun EQ     0039  setmetatable
0043    tab FLOAD  0040  tab.meta
0044 >  tab EQ     0043  NULL
0045    p32 FREF   0040  tab.meta
0046    tab FSTORE 0045  0041
0047    tab TBAR   0040
Snapshot offset: 	19300	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   0040 ]
0048    tab FLOAD  0040  tab.meta
0049 >  tab NE     0048  NULL
0050    int FLOAD  0048  tab.hmask
0051 >  int EQ     0050  #x402e000000000000
0052    p32 FLOAD  0048  tab.node
0053 >  p32 HREFK  0052  "__call" @4
0054 >  fun HLOAD  0053
0055 >  fun EQ     0054  0x40a65248:16
0056    tab FLOAD  0004  func.env
0057    int FLOAD  0056  tab.hmask
0058 >  int EQ     0057  #x404f800000000000
0059    p32 FLOAD  0056  tab.node
0060 >  p32 HREFK  0059  "setmetatable" @63
0061 >  fun HLOAD  0060
0062 >  tab TNEW   #0    #0  
0063 >  fun EQ     0061  setmetatable
0064    tab FLOAD  0062  tab.meta
0065 >  tab EQ     0064  NULL
0066    p32 FREF   0062  tab.meta
0067    tab FSTORE 0066  0041
0068    tab TBAR   0062
Snapshot offset: 	19800	

....        SNAP   #7   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0062 ]
0069    tab FLOAD  0062  tab.meta
0070 >  tab NE     0069  NULL
0071    int FLOAD  0069  tab.hmask
0072 >  int EQ     0071  #x402e000000000000
0073    p32 FLOAD  0069  tab.node
0074 >  p32 HREFK  0073  "__call" @4
0075 >  fun HLOAD  0074
0076 >  fun EQ     0075  0x40a65248:16
0077 >  num SLOAD  #30   T
0078    int FLOAD  {0x41858db0}  tab.hmask
0079 >  int EQ     0078  #x401c000000000000
0080    p32 FLOAD  {0x41858db0}  tab.node
0081 >  p32 HREFK  0080  "__index" @4
0082 >  fun HLOAD  0081
0083 >  fun EQ     0082  0x40a64f98:25
0084    tab FLOAD  0x40a64f98:25  func.env
0085    int FLOAD  0084  tab.hmask
0086 >  int EQ     0085  #x404f800000000000
0087    p32 FLOAD  0084  tab.node
0088 >  p32 HREFK  0087  "type" @60
0089 >  fun HLOAD  0088
0090 >  fun EQ     0089  type
0091 >  fun EQ     0x40a64c88:3  0x40a64c88:3
Snapshot offset: 	0	

....        SNAP   #8   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0062 ---- 0077 ---- ---- ---- [0x00001ee5] 0x40a64c88:3|"Name0" ]
---- TRACE 7 stop -> 1

============================================================
---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE flush

---- TRACE 1 start 0x40a7ae38:3
Trace bytes: 	2340	

---- TRACE 1 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "tonumber" @8
0007 >  fun HLOAD  0006
0008 >  str SLOAD  #1    T
0009 >  fun EQ     0007  tonumber
Snapshot offset: 	0	

....        SNAP   #1   [ ---- ---- trace: 0x40a7ece8 [0x00003cfc] tonumber|0008 ]
---- TRACE 1 stop -> stitch

---- TRACE 2 start 1/0 0x40a7ae38:4
Trace bytes: 	2340581751761771	

---- TRACE 2 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001    fun SLOAD  #0    R
0002    tab FLOAD  0001  func.env
0003    int FLOAD  0002  tab.hmask
0004 >  int EQ     0003  #x404f800000000000
0005    p32 FLOAD  0002  tab.node
0006 >  p32 HREFK  0005  "tonumber" @8
0007 >  fun HLOAD  0006
0008 >  num SLOAD  #1    T
0009 >  fun EQ     0007  tonumber
Snapshot offset: 	700	

....        SNAP   #1   [ ---- ---- 0008 ]
0010 >  p32 RETF   proto: 0x41847ea8  [0x418481a0]
Snapshot offset: 	17400	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0008 ]
0011 >  fun SLOAD  #2    T
0012 >  num SLOAD  #30   T
0013 >  fun EQ     0011  0x40a7ae38:3
Snapshot offset: 	0	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0008 0x40a7ae38:3|0012 ]
---- TRACE 2 stop -> 1

---- TRACE 3 start 2/1 0x40a7ae38:4
Trace bytes: 	81781791891901911921930194121951961971980199122002011234051112131	

---- TRACE 3 IR
0001    num SLOAD  #2    PI
Snapshot offset: 	700	

....        SNAP   #0   [ ---- ---- 0001 ]
Snapshot offset: 	700	

....        SNAP   #1   [ ---- ---- 0001 ]
0003 >  p32 RETF   proto: 0x41847ea8  [0x418481ac]
Snapshot offset: 	17700	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 ]
0004 >  num SLOAD  #31   T
Snapshot offset: 	17900	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 +1   0004 ]
0005 >  num GT     0004  0001
Snapshot offset: 	18800	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0006    fun SLOAD  #0    R
0007    tab FLOAD  0006  func.env
0008    int FLOAD  0007  tab.hmask
0009 >  int EQ     0008  #x404f800000000000
0010    p32 FLOAD  0007  tab.node
0011 >  p32 HREFK  0010  "setmetatable" @63
0012 >  fun HLOAD  0011
0013 }  tab TNEW   #0    #0  
0014 >  tab SLOAD  #25   T
0015 >  fun EQ     0012  setmetatable
0016    p32 FREF   0013  tab.meta
0017 }  tab FSTORE 0016  0014
Snapshot offset: 	19300	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   0013 ]
0018    int FLOAD  0014  tab.hmask
0019 >  int EQ     0018  #x402e000000000000
0020    p32 FLOAD  0014  tab.node
0021 >  p32 HREFK  0020  "__call" @4
0022 >  fun HLOAD  0021
0023 >  fun EQ     0022  0x40e6ac38:16
0024 >  tab TNEW   #0    #0  
0025    p32 FREF   0024  tab.meta
0026    tab FSTORE 0025  0014
Snapshot offset: 	19800	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0024 ]
0027 >  num SLOAD  #30   T
0028    int FLOAD  {0x40a6f9d8}  tab.hmask
0029 >  int EQ     0028  #x401c000000000000
0030    p32 FLOAD  {0x40a6f9d8}  tab.node
0031 >  p32 HREFK  0030  "__index" @4
0032 >  fun HLOAD  0031
0033 >  fun EQ     0032  0x40a73df0:25
0034    tab FLOAD  0x40a73df0:25  func.env
0035    int FLOAD  0034  tab.hmask
0036 >  int EQ     0035  #x404f800000000000
0037    p32 FLOAD  0034  tab.node
0038 >  p32 HREFK  0037  "type" @60
0039 >  fun HLOAD  0038
0040 >  fun EQ     0039  type
Snapshot offset: 	0	

....        SNAP   #7   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0024 ---- 0027 ---- ---- ---- [0x00001ee5] 0x40a7ae38:3|"Name0" ]
---- TRACE 3 stop -> 1

---- TRACE 4 start 1/stitch 0x40a7ae38:4
Trace bytes: 	578	

---- TRACE 4 IR
Snapshot offset: 	400	

....        SNAP   #0   [ ---- ]
0001 >  nil SLOAD  #2    T
0002    fun SLOAD  #0    R
0003 >  fun EQ     0002  0x40a7ae38:3
Snapshot offset: 	700	

....        SNAP   #1   [ 0x40a7ae38:3|---- +1   ]
---- TRACE 4 stop -> return

---- TRACE 5 start 0x41847ea8:217
Trace bytes: 	1641651661691701711721731741	

---- TRACE 5 IR
Snapshot offset: 	16300	

....        SNAP   #0   [ ---- ]
0001    num SLOAD  #28   RI
0002    num SLOAD  #27   I
0003    fun SLOAD  #0    R
0004    tab FLOAD  0003  func.env
0005    int FLOAD  0004  tab.hmask
0006 >  int EQ     0005  #x404f800000000000
0007    p32 FLOAD  0004  tab.node
0008 >  p32 HREFK  0007  "counter_0" @55
0009 >  num HLOAD  0008
Snapshot offset: 	16700	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0010 >  num ULE    0009  #x4014000000000000
0011    num ADD    0009  #x3ff0000000000000
0012    num HSTORE 0008  0011
Snapshot offset: 	17100	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0002 0001 ---- 0002 0011 ]
0013 >  fun SLOAD  #2    T
0014 >  fun EQ     0013  0x40a7ae38:3
Snapshot offset: 	0	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0002 0001 ---- 0002 0x40a7ae38:3|+0.28125 ]
---- TRACE 5 stop -> 1

---- TRACE 6 start 3/3 0x41847ea8:221
Trace bytes: 	1801811821851861871881891901911921930194121951961971980199122002011234051112131	

---- TRACE 6 IR
0001    num SLOAD  #32   PI
0002    num SLOAD  #34   PI
Snapshot offset: 	17900	

....        SNAP   #0   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0001 +1   0002 ]
0003    fun SLOAD  #0    R
0004    tab FLOAD  0003  func.env
0005    int FLOAD  0004  tab.hmask
0006 >  int EQ     0005  #x404f800000000000
0007    p32 FLOAD  0004  tab.node
0008 >  p32 HREFK  0007  "counter_1" @45
0009 >  num HLOAD  0008
Snapshot offset: 	18300	

....        SNAP   #1   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0010 >  num ULE    0009  #x4014000000000000
0011    num ADD    0009  #x3ff0000000000000
0012    num HSTORE 0008  0011
0013    num SLOAD  #31   I
0014    num ADD    0013  #x3ff0000000000000
Snapshot offset: 	17900	

....        SNAP   #2   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- 0014 0001 +1   0014 ]
0015 >  num GT     0014  0001
Snapshot offset: 	18800	

....        SNAP   #3   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ]
0016 >  p32 HREFK  0007  "setmetatable" @63
0017 >  fun HLOAD  0016
0018 }  tab TNEW   #0    #0  
0019 >  tab SLOAD  #25   T
0020 >  fun EQ     0017  setmetatable
0021    p32 FREF   0018  tab.meta
0022 }  tab FSTORE 0021  0019
Snapshot offset: 	19300	

....        SNAP   #4   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   0018 ]
0023    int FLOAD  0019  tab.hmask
0024 >  int EQ     0023  #x402e000000000000
0025    p32 FLOAD  0019  tab.node
0026 >  p32 HREFK  0025  "__call" @4
0027 >  fun HLOAD  0026
0028 >  fun EQ     0027  0x40e6ac38:16
0029 >  tab TNEW   #0    #0  
0030    p32 FREF   0029  tab.meta
0031    tab FSTORE 0030  0019
Snapshot offset: 	19800	

....        SNAP   #5   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0029 ]
0032 >  num SLOAD  #30   T
0033    int FLOAD  {0x40a6f9d8}  tab.hmask
0034 >  int EQ     0033  #x401c000000000000
0035    p32 FLOAD  {0x40a6f9d8}  tab.node
0036 >  p32 HREFK  0035  "__index" @4
0037 >  fun HLOAD  0036
0038 >  fun EQ     0037  0x40a73df0:25
0039    tab FLOAD  0x40a73df0:25  func.env
0040    int FLOAD  0039  tab.hmask
0041 >  int EQ     0040  #x404f800000000000
0042    p32 FLOAD  0039  tab.node
0043 >  p32 HREFK  0042  "type" @60
0044 >  fun HLOAD  0043
0045 >  fun EQ     0044  type
Snapshot offset: 	0	

....        SNAP   #6   [ ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ""   ---- 0029 ---- 0032 ---- ---- ---- [0x00001ee5] 0x40a7ae38:3|"Name0" ]
---- TRACE 6 stop -> 1

---- TRACE 7 start 0x40e6ac38:16
Trace bytes: 	2	

---- TRACE 7 IR
Snapshot offset: 	100	

....        SNAP   #0   [ ---- ---- ]
0001 >  num SLOAD  #1    T
Snapshot offset: 	100	

....        SNAP   #1   [ ---- ---- ]
---- TRACE 7 stop -> return

