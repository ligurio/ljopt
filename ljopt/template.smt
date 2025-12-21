(define-fun bswap16 ((x (_ BitVec 16))) (_ BitVec 16)
    (concat ((_ extract 7 0) x)   ; Lower byte becomes upper byte
            ((_ extract 15 8) x)) ; Upper byte becomes lower byte
)

(define-fun bswap32 ((x (_ BitVec 32))) (_ BitVec 32)
    (concat ((_ extract 7 0) x)    ; Byte 0 -> Byte 3
            ((_ extract 15 8) x)   ; Byte 1 -> Byte 2
            ((_ extract 23 16) x)  ; Byte 2 -> Byte 1
            ((_ extract 31 24) x)) ; Byte 3 -> Byte 0
)

(define-fun bswap64 ((x (_ BitVec 64))) (_ BitVec 64)
    (concat ((_ extract 7 0) x)     ; Byte 0 -> Byte 7
            ((_ extract 15 8) x)    ; Byte 1 -> Byte 6
            ((_ extract 23 16) x)   ; Byte 2 -> Byte 5
            ((_ extract 31 24) x)   ; Byte 3 -> Byte 4
            ((_ extract 39 32) x)   ; Byte 4 -> Byte 3
            ((_ extract 47 40) x)   ; Byte 5 -> Byte 2
            ((_ extract 55 48) x)   ; Byte 6 -> Byte 1
            ((_ extract 63 56) x)) ; Byte 7 -> Byte 0
)

(define-fun bvabs ((x (_ BitVec 32))) (_ BitVec 32)
    (ite (bvslt x (_ bv0 32))     ; if x < 0 (signed)
         (bvneg x)                ; then -x
         x))                      ; else x

; Minimum for unsigned integers
(define-fun bvumin ((x (_ BitVec 32)) (y (_ BitVec 32))) (_ BitVec 32)
    (ite (bvule x y)  ; if x <= y (unsigned)
         x            ; then x
         y))          ; else y

; Maximum for unsigned integers  
(define-fun bvumax ((x (_ BitVec 32)) (y (_ BitVec 32))) (_ BitVec 32)
    (ite (bvuge x y)  ; if x >= y (unsigned)
         x            ; then x
         y))          ; else y

; For signed integers
(define-fun bvsmin ((x (_ BitVec 32)) (y (_ BitVec 32))) (_ BitVec 32)
    (ite (bvsle x y)  ; if x <= y (signed)
         x            ; then x
         y))          ; else y

(define-fun bvsmax ((x (_ BitVec 32)) (y (_ BitVec 32))) (_ BitVec 32)
    (ite (bvsge x y)  ; if x >= y (signed)
         x            ; then x
         y))          ; else y