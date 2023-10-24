; Запустить: z3 z3_example.smt

; тело функции без оптимизации
(declare-const b1 Int)
(declare-const b2 Int)
; разворачиваем цикл (loop unroll)
(assert (= b1 20))  ; итерация 1
(assert (= b2 20))  ; итерация 2

; тело функции с оптимизацией
(declare-const b3 Int)
(assert (= b3 20))

; проверяем равенство значений, возвращаемых из функции
(assert (not (= b3 b2)))
(check-sat)
; (get-model)
