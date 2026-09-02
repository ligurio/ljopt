import ctypes
z3 = ctypes.CDLL("/home/alexey-churkin/study/diploma/z3/build/libz3.so.4.17.0.0")
z3.Z3_get_full_version.restype = ctypes.c_char_p
print(z3.Z3_get_full_version())
cfg = z3.Z3_mk_config()
ctx = z3.Z3_mk_context(cfg)
z3.Z3_del_config(cfg)
f = b'(define-fun-rec a ((n Int)) Int (ite (<= n 0) 0 (a (- n 1))))'
z3.Z3_parse_smtlib2_string(ctx, f, 0, None, None, 0, None, None)
z3.Z3_parse_smtlib2_string(ctx, f, 0, None, None, 0, None, None)  # ASSERTION VIOLATION
