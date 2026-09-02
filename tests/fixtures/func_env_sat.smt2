(set-option :print-success false)
(set-option :produce-models true)
(define-fun lsb ((x (_ BitVec 500))) (_ BitVec 500) (ite (not (= x (_ bv0 500))) (_ bv1 500) (_ bv0 500)))

(declare-datatypes ((MemCell 0))
  (((int-val (get-bv (_ BitVec 64)))
    (fp-val (get-fp (_ FloatingPoint 11 53)))
    (str-val (get-str String))
    (tab-val (get-tab Int))
    (p32-val (get-p32-tab Int) (get-p32-idx MemCell)))))
(define-sort MemPtr () (Array Int (Array Int (Array MemCell MemCell))))

(define-const zero_pointer (Array MemCell MemCell)
  ((as const (Array MemCell MemCell)) (int-val #x0000000000000000)))
(define-const zero_pointer_i_1d (Array Int Int)
  ((as const (Array Int Int)) 0))
; Uninterpreted functions for TOSTR/STRTO conversions.
(declare-fun tostr_num ((_ FloatingPoint 11 53)) String)
(declare-fun strto_num (String) (_ FloatingPoint 11 53))
; Uninterpreted functions for math library calls.
(declare-fun math_sin ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_cos ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_tan ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_asin ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_acos ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_atan ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_sinh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_cosh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_tanh ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_exp ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_log ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(declare-fun math_log10 ((_ FloatingPoint 11 53)) (_ FloatingPoint 11 53))
(define-fun-rec str_reverse ((s String)) String
  (ite (= (str.len s) 0)
       ""
       (str.++ (str_reverse (str.substr s 1 (- (str.len s) 1)))
               (str.substr s 0 1))))
(declare-fun shared_mem_stackc809d6fc_cfc63790 () MemPtr)
(declare-fun mem_ver_shared_mem_stackc809d6fc_cfc63790 () (Array Int (Array Int Int)))

(assert (= (select mem_ver_shared_mem_stackc809d6fc_cfc63790 0) zero_pointer_i_1d))(declare-fun vm_c809d6fc_cfc63790 () (Array Int (Array Int (MemCell))))
(declare-fun mem_unoptc809d6fc_cfc63790 () MemPtr)
(declare-fun mem_ver_mem_unoptc809d6fc_cfc63790 () (Array Int (Array Int Int)))

(assert (= (select mem_ver_mem_unoptc809d6fc_cfc63790 0) zero_pointer_i_1d))
(declare-fun op_unoptc809d6fc_cfc63790 () (Array Int MemCell))

(declare-fun te_unoptc809d6fc_cfc63790 () (Array Int Bool))
(declare-fun snap_unoptc809d6fc_cfc63790 () (Array Int (Array Int (MemCell))))
; 500 is arbitrary constant for maximum number of trace exits per snapshot
(declare-fun snap_unoptc809d6fc_cfc63790_te () (_ BitVec 500))

 ; 1   1   fun SLOADdummy #0 R
 ; 2   2   tab FLOADdummy 0001 func.env
 ; 3   3   p32 HREFdummy 0002 "v88"
 ; 4   4   p32 EQdummy 0003 [0x4088e4e8]
 ; 5   5   tab FLOADdummy 0002 tab.meta
 ; 6   6   tab NEdummy 0005 NULL
 ; 7   7   p32 HREFdummy 0005 "__newindex"
 ; 8   8   p32 EQdummy 0007 [0x4088e4e8]
 ; 9   9   p32 NEWREFdummy 0002 "v88"
 ; 10   10   tru HSTOREdummy 0009 true
 ; 11   11   tab FLOADdummy 0001 func.env
 ; 12   12   p32 HREFdummy 0011 "v86"
 ; 13   13   p32 EQdummy 0012 [0x4088e4e8]
 ; 14   14   tab FLOADdummy 0011 tab.meta
 ; 15   15   tab NEdummy 0014 NULL
 ; 16   16   p32 HREFdummy 0014 "__newindex"
 ; 17   17   p32 EQdummy 0016 [0x4088e4e8]
 ; 18   18   p32 NEWREFdummy 0011 "v86"
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #xffffffffffffffa2)))))) (= (select op_unoptc809d6fc_cfc63790 19) a!1))) ; 19   19    num CONV #xc057800000000000 num.int
 ; 20   20   num HSTOREdummy 0018 0019
 ; 21   21   tab FLOADdummy 0001 func.env
 ; 22   22   p32 HREFdummy 0021 "v84"
 ; 23   23   p32 EQdummy 0022 [0x4088e4e8]
 ; 24   24   tab FLOADdummy 0021 tab.meta
 ; 25   25   tab NEdummy 0024 NULL
 ; 26   26   p32 HREFdummy 0024 "__newindex"
 ; 27   27   p32 EQdummy 0026 [0x4088e4e8]
 ; 28   28   p32 NEWREFdummy 0021 "v84"
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #xfffffffffffffff1)))))) (= (select op_unoptc809d6fc_cfc63790 29) a!1))) ; 29   29    num CONV #xc02e000000000000 num.int
 ; 30   30   num HSTOREdummy 0028 0029
(assert (let ((a!1 true)) (= (select te_unoptc809d6fc_cfc63790 31) a!1)))
(assert (let ((a!1 (int-val #xFFFFFFFE00000000))) (= (select op_unoptc809d6fc_cfc63790 31) a!1))) ; 31   31 >  fal SLOAD #3 T
 ; 32   32   tab FLOADdummy 0001 func.env
 ; 33   33   p32 HREFdummy 0032 "v92"
 ; 34   34   p32 EQdummy 0033 [0x4088e4e8]
 ; 35   35   tab FLOADdummy 0032 tab.meta
 ; 36   36   tab NEdummy 0035 NULL
 ; 37   37   p32 HREFdummy 0035 "__newindex"
 ; 38   38   p32 EQdummy 0037 [0x4088e4e8]
 ; 39   39   p32 NEWREFdummy 0032 "v92"
 ; 40   40   str HSTOREdummy 0039 "esse consequat"
 ; 41   41   nil TBARdummy 0032 <nil>
 ; 42   42   tab FLOADdummy 0001 func.env
 ; 43   43   p32 HREFdummy 0042 "v90"
 ; 44   44   p32 EQdummy 0043 [0x4088e4e8]
 ; 45   45   tab FLOADdummy 0042 tab.meta
 ; 46   46   tab NEdummy 0045 NULL
 ; 47   47   p32 HREFdummy 0045 "__newindex"
 ; 48   48   p32 EQdummy 0047 [0x4088e4e8]
 ; 49   49   p32 NEWREFdummy 0042 "v90"
 ; 50   50   fal HSTOREdummy 0049 false
 ; 51   51   tab FLOADdummy 0001 func.env
 ; 52   52   int FLOADdummy 0051 tab.hmask
 ; 53   53   int EQdummy 0052 #x402e000000000000
 ; 54   54   p32 FLOADdummy 0051 tab.node
 ; 55   55   p32 HREFKdummy 0054 "v86" @8
 ; 56   56   num HLOADdummy 0055 <nil>
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #x0000000000000001)))))) (= (select op_unoptc809d6fc_cfc63790 57) a!1))) ; 57   57    num CONV #x3ff0000000000000 num.int
 ; 58   58   num HSTOREdummy 0055 0057
 ; 59   59   nil TBARdummy 0051 <nil>
 ; 60   60   tab FLOADdummy 0001 func.env
 ; 61   61   p32 HREFdummy 0060 "ipairs"
 ; 62   62   p32 EQdummy 0061 [0x4088e4e8]
 ; 63   63   tab FLOADdummy 0060 tab.meta
 ; 64   64   tab NEdummy 0063 NULL
 ; 65   65   int FLOADdummy 0063 tab.hmask
 ; 66   66   int EQdummy 0065 #x3ff0000000000000
 ; 67   67   p32 FLOADdummy 0063 tab.node
 ; 68   68   p32 HREFKdummy 0067 "__index" @1
 ; 69   69   tab HLOADdummy 0068 <nil>
 ; 70   70   int FLOADdummy 0069 tab.hmask
 ; 71   71   int EQdummy 0070 #x404f800000000000
 ; 72   72   p32 FLOADdummy 0069 tab.node
 ; 73   73   p32 HREFKdummy 0072 "ipairs" @18
 ; 74   74   fun HLOADdummy 0073 <nil>
 ; 75   75   p32 UREFOdummy 0001 #0
 ; 76   76   p32 SUBdummy 0075 0000
 ; 77   77   p32 UGTdummy 0076 #x4050000000000000
 ; 78   78   tab ULOADdummy 0075 <nil>
 ; 79   79   fun EQdummy 0074 ipairs
 ; 80   80   fun EQdummy ipairs_aux ipairs_aux
(assert (let ((a!1 (int-val (bvadd #x0000000000000000 #x0000000000000001)))) (= (select op_unoptc809d6fc_cfc63790 81) a!1))) ; 81   81    int ADD #x0000000000000000 #x3ff0000000000000
 ; 82   82   int FLOADdummy 0078 tab.asize
 ; 83   83   int ULEdummy 0082 0081
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) (get-bv (select op_unoptc809d6fc_cfc63790 81)))))))) (= (select op_unoptc809d6fc_cfc63790 84) a!1))) ; 84   84    num CONV 0081 num.int
 ; 85   85   p32 HREFdummy 0078 0084
 ; 86   86   p32 EQdummy 0085 [0x4088e4e8]
 ; 87   87   tab FLOADdummy 0001 func.env
 ; 88   88   p32 HREFdummy 0087 "math"
 ; 89   89   p32 EQdummy 0088 [0x4088e4e8]
 ; 90   90   tab FLOADdummy 0087 tab.meta
 ; 91   91   tab NEdummy 0090 NULL
 ; 92   92   int FLOADdummy 0090 tab.hmask
 ; 93   93   int EQdummy 0092 #x3ff0000000000000
 ; 94   94   p32 FLOADdummy 0090 tab.node
 ; 95   95   p32 HREFKdummy 0094 "__index" @1
 ; 96   96   tab HLOADdummy 0095 <nil>
 ; 97   97   int FLOADdummy 0096 tab.hmask
 ; 98   98   int EQdummy 0097 #x404f800000000000
 ; 99   99   p32 FLOADdummy 0096 tab.node
 ; 100   100   p32 HREFKdummy 0099 "math" @54
 ; 101   101   tab HLOADdummy 0100 <nil>
 ; 102   102   int FLOADdummy 0101 tab.hmask
 ; 103   103   int EQdummy 0102 #x403f000000000000
 ; 104   104   p32 FLOADdummy 0101 tab.node
 ; 105   105   p32 HREFKdummy 0104 "abs" @21
 ; 106   106   fun HLOADdummy 0105 <nil>
 ; 107   107   fun EQdummy 0106 math.abs
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #xffffffffffffffad)))))) (= (select op_unoptc809d6fc_cfc63790 108) a!1))) ; 108   108    num CONV #xc054c00000000000 num.int
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x7fffffffffffffff)))) (= (select op_unoptc809d6fc_cfc63790 109) a!1))) ; 109   109    num FLOAD nil #222
(assert (let ((a!1 (fp-val (fp.abs (get-fp (select op_unoptc809d6fc_cfc63790 108)))))) (= (select op_unoptc809d6fc_cfc63790 110) a!1))) ; 110   110    num ABS 0108 0109
 ; 111   111   tab FLOADdummy 0001 func.env
 ; 112   112   p32 HREFdummy 0111 "math"
 ; 113   113   p32 EQdummy 0112 [0x4088e4e8]
 ; 114   114   tab FLOADdummy 0111 tab.meta
 ; 115   115   tab NEdummy 0114 NULL
 ; 116   116   int FLOADdummy 0114 tab.hmask
 ; 117   117   int EQdummy 0116 #x3ff0000000000000
 ; 118   118   p32 FLOADdummy 0114 tab.node
 ; 119   119   p32 HREFKdummy 0118 "__index" @1
 ; 120   120   tab HLOADdummy 0119 <nil>
 ; 121   121   int FLOADdummy 0120 tab.hmask
 ; 122   122   int EQdummy 0121 #x404f800000000000
 ; 123   123   p32 FLOADdummy 0120 tab.node
 ; 124   124   p32 HREFKdummy 0123 "math" @54
 ; 125   125   tab HLOADdummy 0124 <nil>
 ; 126   126   int FLOADdummy 0125 tab.hmask
 ; 127   127   int EQdummy 0126 #x403f000000000000
 ; 128   128   p32 FLOADdummy 0125 tab.node
 ; 129   129   p32 HREFKdummy 0128 "cos" @6
 ; 130   130   fun HLOADdummy 0129 <nil>
(assert (let ((a!1 true)) (= (select te_unoptc809d6fc_cfc63790 131) a!1)))
(assert (let ((a!1 (fp-val (get-fp (select (select vm_c809d6fc_cfc63790 0) 4))))) (= (select op_unoptc809d6fc_cfc63790 131) a!1))) ; 131   131 >  num SLOAD #4 T
 ; 132   132   fun EQdummy 0130 math.cos
(assert (let ((a!1 (fp-val (math_cos (get-fp (select op_unoptc809d6fc_cfc63790 131)))))) (= (select op_unoptc809d6fc_cfc63790 133) a!1))) ; 133   133    num CALLN 0131 cos
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x8000000000000000)))) (= (select op_unoptc809d6fc_cfc63790 134) a!1))) ; 134   134    num FLOAD nil #226
(assert (let ((a!1 (fp-val (fp.neg (get-fp (select op_unoptc809d6fc_cfc63790 133)))))) (= (select op_unoptc809d6fc_cfc63790 135) a!1))) ; 135   135    num NEG 0133 0134
(assert (let ((a!1 (fp-val (fp.add RNE (get-fp (select op_unoptc809d6fc_cfc63790 110)) (get-fp (select op_unoptc809d6fc_cfc63790 135)))))) (= (select op_unoptc809d6fc_cfc63790 136) a!1))) ; 136   136    num ADD 0110 0135
 ; 137   137   tab FLOADdummy 0001 func.env
 ; 138   138   int FLOADdummy 0137 tab.hmask
 ; 139   139   int EQdummy 0138 #x402e000000000000
 ; 140   140   p32 FLOADdummy 0137 tab.node
 ; 141   141   p32 HREFKdummy 0140 "v86" @8
 ; 142   142   num HLOADdummy 0141 <nil>
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #x0000000000000052)))))) (= (select op_unoptc809d6fc_cfc63790 143) a!1))) ; 143   143    num CONV #x4054800000000000 num.int
 ; 144   144   num ADDdummy 0142 0143
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #x000000000000000c)))))) (= (select op_unoptc809d6fc_cfc63790 145) a!1))) ; 145   145    num CONV #x4028000000000000 num.int
 ; 146   146   num ADDdummy 0144 0145
 ; 147   147   tab FLOADdummy 0001 func.env
 ; 148   148   p32 HREFdummy 0147 "math"
 ; 149   149   p32 EQdummy 0148 [0x4088e4e8]
 ; 150   150   tab FLOADdummy 0147 tab.meta
 ; 151   151   tab NEdummy 0150 NULL
 ; 152   152   int FLOADdummy 0150 tab.hmask
 ; 153   153   int EQdummy 0152 #x3ff0000000000000
 ; 154   154   p32 FLOADdummy 0150 tab.node
 ; 155   155   p32 HREFKdummy 0154 "__index" @1
 ; 156   156   tab HLOADdummy 0155 <nil>
 ; 157   157   int FLOADdummy 0156 tab.hmask
 ; 158   158   int EQdummy 0157 #x404f800000000000
 ; 159   159   p32 FLOADdummy 0156 tab.node
 ; 160   160   p32 HREFKdummy 0159 "math" @54
 ; 161   161   tab HLOADdummy 0160 <nil>
 ; 162   162   int FLOADdummy 0161 tab.hmask
 ; 163   163   int EQdummy 0162 #x403f000000000000
 ; 164   164   p32 FLOADdummy 0161 tab.node
 ; 165   165   p32 HREFKdummy 0164 "tan" @1
 ; 166   166   fun HLOADdummy 0165 <nil>
 ; 167   167   fun EQdummy 0166 math.tan
 ; 168   168   num CALLNdummy 0146 tan
 ; 169   169   tab FLOADdummy 0001 func.env
 ; 170   170   p32 HREFdummy 0169 "math"
 ; 171   171   p32 EQdummy 0170 [0x4088e4e8]
 ; 172   172   tab FLOADdummy 0169 tab.meta
 ; 173   173   tab NEdummy 0172 NULL
 ; 174   174   int FLOADdummy 0172 tab.hmask
 ; 175   175   int EQdummy 0174 #x3ff0000000000000
 ; 176   176   p32 FLOADdummy 0172 tab.node
 ; 177   177   p32 HREFKdummy 0176 "__index" @1
 ; 178   178   tab HLOADdummy 0177 <nil>
 ; 179   179   int FLOADdummy 0178 tab.hmask
 ; 180   180   int EQdummy 0179 #x404f800000000000
 ; 181   181   p32 FLOADdummy 0178 tab.node
 ; 182   182   p32 HREFKdummy 0181 "math" @54
 ; 183   183   tab HLOADdummy 0182 <nil>
 ; 184   184   int FLOADdummy 0183 tab.hmask
 ; 185   185   int EQdummy 0184 #x403f000000000000
 ; 186   186   p32 FLOADdummy 0183 tab.node
 ; 187   187   p32 HREFKdummy 0186 "abs" @21
 ; 188   188   fun HLOADdummy 0187 <nil>
 ; 189   189   fun EQdummy 0188 math.abs
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) RTZ ((_ sign_extend 32) ((_ extract 31 0) #xffffffffffffffda)))))) (= (select op_unoptc809d6fc_cfc63790 190) a!1))) ; 190   190    num CONV #xc043000000000000 num.int
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x7fffffffffffffff)))) (= (select op_unoptc809d6fc_cfc63790 191) a!1))) ; 191   191    num FLOAD nil #222
(assert (let ((a!1 (fp-val (fp.abs (get-fp (select op_unoptc809d6fc_cfc63790 190)))))) (= (select op_unoptc809d6fc_cfc63790 192) a!1))) ; 192   192    num ABS 0190 0191
 ; 193   193   num SUBdummy 0168 0192
 ; 194   194   tab FLOADdummy 0001 func.env
 ; 195   195   p32 HREFdummy 0194 "math"
 ; 196   196   p32 EQdummy 0195 [0x4088e4e8]
 ; 197   197   tab FLOADdummy 0194 tab.meta
 ; 198   198   tab NEdummy 0197 NULL
 ; 199   199   int FLOADdummy 0197 tab.hmask
 ; 200   200   int EQdummy 0199 #x3ff0000000000000
 ; 201   201   p32 FLOADdummy 0197 tab.node
 ; 202   202   p32 HREFKdummy 0201 "__index" @1
 ; 203   203   tab HLOADdummy 0202 <nil>
 ; 204   204   int FLOADdummy 0203 tab.hmask
 ; 205   205   int EQdummy 0204 #x404f800000000000
 ; 206   206   p32 FLOADdummy 0203 tab.node
 ; 207   207   p32 HREFKdummy 0206 "math" @54
 ; 208   208   tab HLOADdummy 0207 <nil>
 ; 209   209   int FLOADdummy 0208 tab.hmask
 ; 210   210   int EQdummy 0209 #x403f000000000000
 ; 211   211   p32 FLOADdummy 0208 tab.node
 ; 212   212   p32 HREFKdummy 0211 "sin" @23
 ; 213   213   fun HLOADdummy 0212 <nil>
 ; 214   214   fun EQdummy 0213 math.sin
(assert (let ((a!1 (fp-val (math_sin (get-fp (select op_unoptc809d6fc_cfc63790 136)))))) (= (select op_unoptc809d6fc_cfc63790 215) a!1))) ; 215   215    num CALLN 0136 sin
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x8000000000000000)))) (= (select op_unoptc809d6fc_cfc63790 216) a!1))) ; 216   216    num FLOAD nil #226
(assert (let ((a!1 (fp-val (fp.neg (get-fp (select op_unoptc809d6fc_cfc63790 215)))))) (= (select op_unoptc809d6fc_cfc63790 217) a!1))) ; 217   217    num NEG 0215 0216
 ; 218   218   num ADDdummy 0193 0217
(assert (let ((a!1 true)) (= (select te_unoptc809d6fc_cfc63790 219) a!1)))

(assert (= (select (select mem_unoptc809d6fc_cfc63790 0) 0) zero_pointer))
(assert (= (select mem_ver_mem_unoptc809d6fc_cfc63790 1) (store (select mem_ver_mem_unoptc809d6fc_cfc63790 0) 0 (+ (select (select mem_ver_mem_unoptc809d6fc_cfc63790 0) 0) 1))))
(assert (let (
    (old_version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 0) 0))
    (new_version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 1) 0))
    (index (str-val "```tab.asize"))
    (data (int-val #x0000000000000003))
    (version_array (select mem_unoptc809d6fc_cfc63790 0))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array))))
(assert (= (select mem_ver_mem_unoptc809d6fc_cfc63790 2) (store (select mem_ver_mem_unoptc809d6fc_cfc63790 1) 0 (+ (select (select mem_ver_mem_unoptc809d6fc_cfc63790 1) 0) 1))))
(assert (let (
    (old_version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 1) 0))
    (new_version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 2) 0))
    (index (str-val "```tab.hmask"))
    (data (int-val #x0000000000000000))
    (version_array (select mem_unoptc809d6fc_cfc63790 0))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array))))
(assert (let ((a!1 (tab-val 0))) (= (select op_unoptc809d6fc_cfc63790 219) a!1))) ; 219   219 >  tab TNEW #3 #0
 ; 220   220   int FLOADdummy 0219 tab.asize
 ; 221   221   int ABCdummy 0220 #x3ff0000000000000
(assert (let ((a!1 (tab-val (get-tab (select op_unoptc809d6fc_cfc63790 219))))) (= (select op_unoptc809d6fc_cfc63790 222) a!1))) ; 222   222    p32 FLOAD 0219 tab.array
(assert (let ((a!1 true)) (= (select te_unoptc809d6fc_cfc63790 223) a!1)))
(assert (let ((a!1 (p32-val (get-tab (select op_unoptc809d6fc_cfc63790 222)) (ite ((_ is fp-val) (fp-val ((_ to_fp 11 53) #x3ff0000000000000))) (ite (fp.isZero (get-fp (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))) (fp-val ((_ to_fp 11 53) #x0000000000000000)) (fp-val ((_ to_fp 11 53) #x3ff0000000000000))) (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))))) (= (select op_unoptc809d6fc_cfc63790 223) a!1))) ; 223   223    p32 AREF 0222 #x3ff0000000000000
(assert (let ((a!1 (tab-val (get-tab (select (let (
    (ptr (get-tab (select op_unoptc809d6fc_cfc63790 219)))
    (version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 2) (get-tab (select op_unoptc809d6fc_cfc63790 219))))
) (select (select mem_unoptc809d6fc_cfc63790 ptr) version)) (str-val "```tab.meta")))))) (= (select op_unoptc809d6fc_cfc63790 224) a!1))) ; 224   224    tab FLOAD 0219 tab.meta
 ; 225   225   tab EQdummy 0224 NULL
 ; 226   226   num ASTOREdummy 0223 0146
 ; 227   227    nil NOP <nil> <nil>

(assert (= (select snap_unoptc809d6fc_cfc63790 2) (store (select snap_unoptc809d6fc_cfc63790 2) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 2) (store (select snap_unoptc809d6fc_cfc63790 2) 8 (fp-val ((_ to_fp 11 53) #xc057800000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 3) (store (select snap_unoptc809d6fc_cfc63790 3) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 4) (store (select snap_unoptc809d6fc_cfc63790 4) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 5) (store (select snap_unoptc809d6fc_cfc63790 5) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 5) (store (select snap_unoptc809d6fc_cfc63790 5) 7 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 6) (store (select snap_unoptc809d6fc_cfc63790 6) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 6) (store (select snap_unoptc809d6fc_cfc63790 6) 7 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 7) (store (select snap_unoptc809d6fc_cfc63790 7) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_unoptc809d6fc_cfc63790 7) (store (select snap_unoptc809d6fc_cfc63790 7) 7 (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))))
; Table, use directly
(assert (= snap_unoptc809d6fc_cfc63790_te (bvor (bvor (_ bv0 500)
    (ite (not (select te_unoptc809d6fc_cfc63790 31)) (bvshl (_ bv1 500) (_ bv0 500)) (_ bv0 500)))
    (ite (not (and (select te_unoptc809d6fc_cfc63790 219) (select te_unoptc809d6fc_cfc63790 131))) (bvshl (_ bv1 500) (_ bv1 500)) (_ bv0 500)))))
(declare-fun mem_optc809d6fc_cfc63790 () MemPtr)
(declare-fun mem_ver_mem_optc809d6fc_cfc63790 () (Array Int (Array Int Int)))

(assert (= (select mem_ver_mem_optc809d6fc_cfc63790 0) zero_pointer_i_1d))
(declare-fun op_optc809d6fc_cfc63790 () (Array Int MemCell))

(declare-fun te_optc809d6fc_cfc63790 () (Array Int Bool))
(declare-fun snap_optc809d6fc_cfc63790 () (Array Int (Array Int (MemCell))))
; 500 is arbitrary constant for maximum number of trace exits per snapshot
(declare-fun snap_optc809d6fc_cfc63790_te () (_ BitVec 500))

 ; 1   1   fun SLOADdummy #0 R
 ; 2   2   tab FLOADdummy 0001 func.env
 ; 3   3   p32 HREFdummy 0002 "v88"
 ; 4   4   p32 EQdummy 0003 [0x4088e4e8]
 ; 5   5   tab FLOADdummy 0002 tab.meta
 ; 6   6   tab NEdummy 0005 NULL
 ; 7   7   p32 HREFdummy 0005 "__newindex"
 ; 8   8   p32 EQdummy 0007 [0x4088e4e8]
 ; 9   9   p32 NEWREFdummy 0002 "v88"
 ; 10   10   tru HSTOREdummy 0009 true
 ; 11   11   p32 HREFdummy 0002 "v86"
 ; 12   12   p32 EQdummy 0011 [0x4088e4e8]
 ; 13   13   p32 HREFdummy 0005 "__newindex"
 ; 14   14   p32 EQdummy 0013 [0x4088e4e8]
 ; 15   15   p32 NEWREFdummy 0002 "v86"
 ; 16   16   num HSTOREdummy 0015 #xc057800000000000
 ; 17   17   p32 HREFdummy 0002 "v84"
 ; 18   18   p32 EQdummy 0017 [0x4088e4e8]
 ; 19   19   p32 HREFdummy 0005 "__newindex"
 ; 20   20   p32 EQdummy 0019 [0x4088e4e8]
 ; 21   21   p32 NEWREFdummy 0002 "v84"
 ; 22   22   num HSTOREdummy 0021 #xc02e000000000000
(assert (let ((a!1 true)) (= (select te_optc809d6fc_cfc63790 23) a!1)))
(assert (let ((a!1 (int-val #xFFFFFFFE00000000))) (= (select op_optc809d6fc_cfc63790 23) a!1))) ; 23   23 >  fal SLOAD #3 T
 ; 24   24   p32 HREFdummy 0002 "v92"
 ; 25   25   p32 EQdummy 0024 [0x4088e4e8]
 ; 26   26   p32 HREFdummy 0005 "__newindex"
 ; 27   27   p32 EQdummy 0026 [0x4088e4e8]
 ; 28   28   p32 NEWREFdummy 0002 "v92"
 ; 29   29   str HSTOREdummy 0028 "esse consequat"
 ; 30   30   nil TBARdummy 0002 <nil>
 ; 31   31   p32 HREFdummy 0002 "v90"
 ; 32   32   p32 EQdummy 0031 [0x4088e4e8]
 ; 33   33   p32 HREFdummy 0005 "__newindex"
 ; 34   34   p32 EQdummy 0033 [0x4088e4e8]
 ; 35   35   p32 NEWREFdummy 0002 "v90"
 ; 36   36   fal HSTOREdummy 0035 false
 ; 37   37   int FLOADdummy 0002 tab.hmask
 ; 38   38   int EQdummy 0037 #x402e000000000000
 ; 39   39   p32 FLOADdummy 0002 tab.node
 ; 40   40   p32 HREFKdummy 0039 "v86" @8
 ; 41   41   num HLOADdummy 0040 <nil>
 ; 42   42   num HSTOREdummy 0040 #x3ff0000000000000
 ; 43   43   p32 HREFdummy 0002 "ipairs"
 ; 44   44   p32 EQdummy 0043 [0x4088e4e8]
 ; 45   45   int FLOADdummy 0005 tab.hmask
 ; 46   46   int EQdummy 0045 #x3ff0000000000000
 ; 47   47   p32 FLOADdummy 0005 tab.node
 ; 48   48   p32 HREFKdummy 0047 "__index" @1
 ; 49   49   tab HLOADdummy 0048 <nil>
 ; 50   50   int FLOADdummy 0049 tab.hmask
 ; 51   51   int EQdummy 0050 #x404f800000000000
 ; 52   52   p32 FLOADdummy 0049 tab.node
 ; 53   53   p32 HREFKdummy 0052 "ipairs" @18
 ; 54   54   fun HLOADdummy 0053 <nil>
 ; 55   55   p32 UREFOdummy 0001 #0
 ; 56   56   p32 SUBdummy 0055 0000
 ; 57   57   p32 UGTdummy 0056 #x4050000000000000
 ; 58   58   tab ULOADdummy 0055 <nil>
 ; 59   59   fun EQdummy 0054 ipairs
 ; 60   60   int FLOADdummy 0058 tab.asize
 ; 61   61   int ULEdummy 0060 #x3ff0000000000000
 ; 62   62   p32 HREFdummy 0058 #x3ff0000000000000
 ; 63   63   p32 EQdummy 0062 [0x4088e4e8]
 ; 64   64   p32 HREFdummy 0002 "math"
 ; 65   65   p32 EQdummy 0064 [0x4088e4e8]
 ; 66   66   p32 HREFKdummy 0052 "math" @54
 ; 67   67   tab HLOADdummy 0066 <nil>
 ; 68   68   int FLOADdummy 0067 tab.hmask
 ; 69   69   int EQdummy 0068 #x403f000000000000
 ; 70   70   p32 FLOADdummy 0067 tab.node
 ; 71   71   p32 HREFKdummy 0070 "abs" @21
 ; 72   72   fun HLOADdummy 0071 <nil>
 ; 73   73   fun EQdummy 0072 math.abs
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x7fffffffffffffff)))) (= (select op_optc809d6fc_cfc63790 74) a!1))) ; 74   74    num FLOAD nil #222
 ; 75   75   p32 HREFKdummy 0070 "cos" @6
 ; 76   76   fun HLOADdummy 0075 <nil>
(assert (let ((a!1 true)) (= (select te_optc809d6fc_cfc63790 77) a!1)))
(assert (let ((a!1 (fp-val (get-fp (select (select vm_c809d6fc_cfc63790 0) 4))))) (= (select op_optc809d6fc_cfc63790 77) a!1))) ; 77   77 >  num SLOAD #4 T
 ; 78   78   fun EQdummy 0076 math.cos
(assert (let ((a!1 (fp-val (math_cos (get-fp (select op_optc809d6fc_cfc63790 77)))))) (= (select op_optc809d6fc_cfc63790 79) a!1))) ; 79   79    num CALLN 0077 cos
(assert (let ((a!1 (fp-val ((_ to_fp 11 53) #x8000000000000000)))) (= (select op_optc809d6fc_cfc63790 80) a!1))) ; 80   80    num FLOAD nil #226
(assert (let ((a!1 (fp-val (fp.neg (get-fp (select op_optc809d6fc_cfc63790 79)))))) (= (select op_optc809d6fc_cfc63790 81) a!1))) ; 81   81    num NEG 0079 0080
(assert (let ((a!1 (fp-val (fp.sub RNE ((_ to_fp 11 53) #x4054c00000000000) (get-fp (select op_optc809d6fc_cfc63790 79)))))) (= (select op_optc809d6fc_cfc63790 82) a!1))) ; 82   82    num SUB #x4054c00000000000 0079
 ; 83   83   p32 HREFKdummy 0070 "tan" @1
 ; 84   84   fun HLOADdummy 0083 <nil>
 ; 85   85   fun EQdummy 0084 math.tan
 ; 86   86   p32 HREFKdummy 0070 "sin" @23
 ; 87   87   fun HLOADdummy 0086 <nil>
 ; 88   88   fun EQdummy 0087 math.sin
(assert (let ((a!1 (fp-val (math_sin (get-fp (select op_optc809d6fc_cfc63790 82)))))) (= (select op_optc809d6fc_cfc63790 89) a!1))) ; 89   89    num CALLN 0082 sin
(assert (let ((a!1 (fp-val (fp.neg (get-fp (select op_optc809d6fc_cfc63790 89)))))) (= (select op_optc809d6fc_cfc63790 90) a!1))) ; 90   90    num NEG 0089 0080
(assert (let ((a!1 (fp-val (fp.sub RNE ((_ to_fp 11 53) #xc04288394353ab2a) (get-fp (select op_optc809d6fc_cfc63790 89)))))) (= (select op_optc809d6fc_cfc63790 91) a!1))) ; 91   91    num SUB #xc04288394353ab2a 0089
(assert (let ((a!1 true)) (= (select te_optc809d6fc_cfc63790 92) a!1)))

(assert (= (select (select mem_optc809d6fc_cfc63790 0) 0) zero_pointer))
(assert (= (select mem_ver_mem_optc809d6fc_cfc63790 1) (store (select mem_ver_mem_optc809d6fc_cfc63790 0) 0 (+ (select (select mem_ver_mem_optc809d6fc_cfc63790 0) 0) 1))))
(assert (let (
    (old_version (select (select mem_ver_mem_optc809d6fc_cfc63790 0) 0))
    (new_version (select (select mem_ver_mem_optc809d6fc_cfc63790 1) 0))
    (index (str-val "```tab.asize"))
    (data (int-val #x0000000000000003))
    (version_array (select mem_optc809d6fc_cfc63790 0))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array))))
(assert (= (select mem_ver_mem_optc809d6fc_cfc63790 2) (store (select mem_ver_mem_optc809d6fc_cfc63790 1) 0 (+ (select (select mem_ver_mem_optc809d6fc_cfc63790 1) 0) 1))))
(assert (let (
    (old_version (select (select mem_ver_mem_optc809d6fc_cfc63790 1) 0))
    (new_version (select (select mem_ver_mem_optc809d6fc_cfc63790 2) 0))
    (index (str-val "```tab.hmask"))
    (data (int-val #x0000000000000000))
    (version_array (select mem_optc809d6fc_cfc63790 0))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array))))
(assert (let ((a!1 (tab-val 0))) (= (select op_optc809d6fc_cfc63790 92) a!1))) ; 92   92 >  tab TNEW #3 #0
(assert (let ((a!1 (tab-val (get-tab (select op_optc809d6fc_cfc63790 92))))) (= (select op_optc809d6fc_cfc63790 93) a!1))) ; 93   93    p32 FLOAD 0092 tab.array
(assert (let ((a!1 true)) (= (select te_optc809d6fc_cfc63790 94) a!1)))
(assert (let ((a!1 (p32-val (get-tab (select op_optc809d6fc_cfc63790 93)) (ite ((_ is fp-val) (fp-val ((_ to_fp 11 53) #x3ff0000000000000))) (ite (fp.isZero (get-fp (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))) (fp-val ((_ to_fp 11 53) #x0000000000000000)) (fp-val ((_ to_fp 11 53) #x3ff0000000000000))) (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))))) (= (select op_optc809d6fc_cfc63790 94) a!1))) ; 94   94    p32 AREF 0093 #x3ff0000000000000
(assert (= (select mem_ver_mem_optc809d6fc_cfc63790 3) (store (select mem_ver_mem_optc809d6fc_cfc63790 2) (get-p32-tab (select op_optc809d6fc_cfc63790 94)) (+ (select (select mem_ver_mem_optc809d6fc_cfc63790 2) (get-p32-tab (select op_optc809d6fc_cfc63790 94))) 1))))
(assert (let (
    (old_version (select (select mem_ver_mem_optc809d6fc_cfc63790 2) (get-p32-tab (select op_optc809d6fc_cfc63790 94))))
    (new_version (select (select mem_ver_mem_optc809d6fc_cfc63790 3) (get-p32-tab (select op_optc809d6fc_cfc63790 94))))
    (index (get-p32-idx (select op_optc809d6fc_cfc63790 94)))
    (data (fp-val ((_ to_fp 11 53) #x4057c00000000000)))
    (version_array (select mem_optc809d6fc_cfc63790 (get-p32-tab (select op_optc809d6fc_cfc63790 94))))
) (let (
        (updated_array (store (select version_array old_version) index data))
        (new_array (select version_array new_version))
) (= new_array updated_array)))) ; 95   95    num ASTORE 0094 #x4057c00000000000
 ; 96   96    nil NOP <nil> <nil>

(assert (= (select snap_optc809d6fc_cfc63790 2) (store (select snap_optc809d6fc_cfc63790 2) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 2) (store (select snap_optc809d6fc_cfc63790 2) 8 (fp-val ((_ to_fp 11 53) #xc057800000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 3) (store (select snap_optc809d6fc_cfc63790 3) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 4) (store (select snap_optc809d6fc_cfc63790 4) 7 (fp-val ((_ to_fp 11 53) #xc02e000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 5) (store (select snap_optc809d6fc_cfc63790 5) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 5) (store (select snap_optc809d6fc_cfc63790 5) 7 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 6) (store (select snap_optc809d6fc_cfc63790 6) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 6) (store (select snap_optc809d6fc_cfc63790 6) 7 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 7) (store (select snap_optc809d6fc_cfc63790 7) 3 (fp-val ((_ to_fp 11 53) #x0000000000000000)))))
(assert (= (select snap_optc809d6fc_cfc63790 7) (store (select snap_optc809d6fc_cfc63790 7) 7 (fp-val ((_ to_fp 11 53) #x3ff0000000000000)))))
; Table, use directly
(assert (= snap_optc809d6fc_cfc63790_te (bvor (bvor (_ bv0 500)
    (ite (not (select te_optc809d6fc_cfc63790 23)) (bvshl (_ bv1 500) (_ bv2 500)) (_ bv0 500)))
    (ite (not (and (select te_optc809d6fc_cfc63790 92) (select te_optc809d6fc_cfc63790 77))) (bvshl (_ bv1 500) (_ bv3 500)) (_ bv0 500)))))
(assert (or (not (= (lsb snap_unoptc809d6fc_cfc63790_te) (lsb snap_optc809d6fc_cfc63790_te)))
    (not (= (let (
    (ptr (get-tab (select op_unoptc809d6fc_cfc63790 219)))
    (version (select (select mem_ver_mem_unoptc809d6fc_cfc63790 2) (get-tab (select op_unoptc809d6fc_cfc63790 219))))
) (select (select mem_unoptc809d6fc_cfc63790 ptr) version)) (let (
    (ptr (get-tab (select op_optc809d6fc_cfc63790 92)))
    (version (select (select mem_ver_mem_optc809d6fc_cfc63790 3) (get-tab (select op_optc809d6fc_cfc63790 92))))
) (select (select mem_optc809d6fc_cfc63790 ptr) version))))
    (not (= (get-fp (select (select snap_unoptc809d6fc_cfc63790 7) 7)) (get-fp (select (select snap_optc809d6fc_cfc63790 7) 7))))
    (not (= (get-fp (select (select snap_unoptc809d6fc_cfc63790 7) 3)) (get-fp (select (select snap_optc809d6fc_cfc63790 7) 3))))
    ; Memory part
))

(check-sat)
(reset)