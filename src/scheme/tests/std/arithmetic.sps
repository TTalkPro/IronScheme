;;; (ironscheme std arithmetic) 的测试（designs/08-std-library.md D8）。两部分均为 SRFI 64 形式，经
;;; tests/std/srfi64-shim.ss 接到 check 计数：
;;;   SRFI 151：chez-srfi 的 tests/bitwise-operations.sps（Copyright © 2017 John Cowan, © 2020 Amirouche
;;;     Boubekki，MIT）；
;;;   SRFI 143：chez-srfi 的 tests/fixnums.sps（同上）。
;;; 另补 SRFI 141 与 SRFI 60 独有名字的测试（原测试没有）。
(import (rnrs) (only (ironscheme) include) (ironscheme std arithmetic))
(include "tests/std/check.ss")
(include "tests/std/srfi64-shim.ss")

;;; ———————————————— SRFI 151（bitwise-operations.sps）————————————————
(test-begin "bitwise-operations")

(define check-001
  (test-equal -1 (bitwise-not 0)))

(define check-002
  (test-equal 0 (bitwise-not -1)))

(define check-003
  (test-equal -11 (bitwise-not 10)))

(define check-004
  (test-equal 36 (bitwise-not -37)))

(define check-005
  (test-equal 0 (bitwise-and #b0 #b1)))

(define check-006
  (test-equal 1680869008 (bitwise-and -193073517 1689392892)))

(define check-007
  (test-equal 3769478 (bitwise-and 1694076839 -4290775858)))

(define check-008
  (test-equal 6 (bitwise-and 14 6)))

(define check-009
  (test-equal 10 (bitwise-and 11 26)))

(define check-010
  (test-equal 4 (bitwise-and 37 12)))

(define check-011
  (test-equal 1 (bitwise-and #b1 #b1)))

(define check-012
  (test-equal 0 (bitwise-and #b1 #b10)))

(define check-013
  (test-equal #b10 (bitwise-and #b11 #b10)))

(define check-014
  (test-equal #b101 (bitwise-and #b101 #b111)))

(define check-015
  (test-equal #b111 (bitwise-and -1 #b111)))

(define check-016
  (test-equal #b110 (bitwise-and -2 #b111)))

(define check-017
  (test-equal 3769478 (bitwise-and -4290775858 1694076839)))

(define check-018
  (test-equal -4294967295 (bitwise-ior 1 (- -1 #xffffffff))))

(define check-019
  (test-equal -18446744073709551615 (bitwise-ior 1 (- -1 #xffffffffffffffff))))

(define check-020
  (test-equal 14 (bitwise-ior 10 12)))

(define check-021
  (test-equal 11 (bitwise-ior 3  10)))

(define check-022
  (test-equal -4294967126 (bitwise-xor #b10101010 (- -1 #xffffffff))))

(define check-023
  (test-equal -18446744073709551446 (bitwise-xor #b10101010 (- -1 #xffffffffffffffff))))

(define check-024
  (test-equal -2600468497 (bitwise-ior 1694076839 -4290775858)))

(define check-025
  (test-equal -184549633 (bitwise-ior -193073517 1689392892)))

(define check-026
  (test-equal -2604237975 (bitwise-xor 1694076839 -4290775858)))

(define check-027
  (test-equal -1865418641 (bitwise-xor -193073517 1689392892)))

(define check-028
  (test-equal 6 (bitwise-xor 10 12)))

(define check-029
  (test-equal 9 (bitwise-xor 3 10)))

(define check-030
  (test-equal (bitwise-not -4294967126) (bitwise-eqv #b10101010 (- -1 #xffffffff))))

(define check-031
  (test-equal -42 (bitwise-eqv 37 12)))

(define check-032
  (test-equal -1 (bitwise-nand 0 0)))

(define check-033
  (test-equal -1 (bitwise-nand 0 -1)))

(define check-034
  (test-equal -124 (bitwise-nand -1 123)))

(define check-035
  (test-equal -11 (bitwise-nand 11 26)))

(define check-036
  (test-equal -28 (bitwise-nor  11 26)))

(define check-037
  (test-equal 0 (bitwise-nor -1 123)))

(define check-038
  (test-equal 16 (bitwise-andc1 11 26)))

(define check-039
  (test-equal 1 (bitwise-andc2 11 26)))

(define check-040
  (test-equal -2 (bitwise-orc1 11 26)))

(define check-041
  (test-equal -1 (bitwise-nor 0 0)))

(define check-042
  (test-equal 0 (bitwise-nor 0 -1)))

(define check-043
  (test-equal 0 (bitwise-andc1 0 0)))

(define check-044
  (test-equal -1 (bitwise-andc1 0 -1)))

(define check-045
  (test-equal 123 (bitwise-andc1 0 123)))

(define check-046
  (test-equal 0 (bitwise-andc2 0 0)))

(define check-047
  (test-equal -1 (bitwise-andc2 -1 0)))

(define check-048
  (test-equal -1 (bitwise-orc1 0 0)))

(define check-049
  (test-equal -1 (bitwise-orc1 0 -1)))

(define check-050
  (test-equal 0 (bitwise-orc1 -1 0)))

(define check-051
  (test-equal -124 (bitwise-orc1 123 0)))

(define check-052
  (test-equal -1 (bitwise-orc2 0 0)))

(define check-053
  (test-equal -1 (bitwise-orc2 -1 0)))

(define check-054
  (test-equal 0 (bitwise-orc2 0 -1)))

(define check-055
  (test-equal -124 (bitwise-orc2 0 123)))

;; bitwise/integer

(define check-056
  (test-equal #x1000000000000000100000000000000000000000000000000
              (arithmetic-shift #x100000000000000010000000000000000 64)))

(define check-057
  (test-equal #x8e73b0f7da0e6452c810f32b809079e5
              (arithmetic-shift #x8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b -64)))

(define check-058
  (test-equal 2 (arithmetic-shift 1 1)))

(define check-059
  (test-equal 0 (arithmetic-shift 1 -1)))

(define check-060
  (test-equal 1 (arithmetic-shift 1 0)))

(define check-061
  (test-equal 4 (arithmetic-shift 1 2)))

(define check-062
  (test-equal 8 (arithmetic-shift 1 3)))

(define check-063
  (test-equal 16 (arithmetic-shift 1 4)))

(define check-064
  (test-equal (expt 2 31) (arithmetic-shift 1 31)))

(define check-065
  (test-equal (expt 2 32) (arithmetic-shift 1 32)))

(define check-066
  (test-equal (expt 2 33) (arithmetic-shift 1 33)))

(define check-067
  (test-equal (expt 2 63) (arithmetic-shift 1 63)))

(define check-068
  (test-equal (expt 2 64) (arithmetic-shift 1 64)))

(define check-069
  (test-equal (expt 2 65) (arithmetic-shift 1 65)))

(define check-070
  (test-equal (expt 2 127) (arithmetic-shift 1 127)))

(define check-071
  (test-equal (expt 2 128) (arithmetic-shift 1 128)))

(define check-072
  (test-equal (expt 2 129) (arithmetic-shift 1 129)))

(define check-073
  (test-equal 3028397001194014464 (arithmetic-shift 11829675785914119 8)))

(define check-074
  (test-equal -1 (arithmetic-shift -1 0)))

(define check-075
  (test-equal -2 (arithmetic-shift -1 1)))

(define check-076
  (test-equal -4 (arithmetic-shift -1 2)))

(define check-077
  (test-equal -8 (arithmetic-shift -1 3)))

(define check-078
  (test-equal -16 (arithmetic-shift -1 4)))

(define check-079
  (test-equal (- (expt 2 31)) (arithmetic-shift -1 31)))

(define check-080
  (test-equal (- (expt 2 32)) (arithmetic-shift -1 32)))

(define check-081
  (test-equal (- (expt 2 33)) (arithmetic-shift -1 33)))

(define check-082
  (test-equal (- (expt 2 63)) (arithmetic-shift -1 63)))

(define check-083
  (test-equal (- (expt 2 64)) (arithmetic-shift -1 64)))

(define check-084
  (test-equal (- (expt 2 65)) (arithmetic-shift -1 65)))

(define check-085
  (test-equal (- (expt 2 127)) (arithmetic-shift -1 127)))

(define check-086
  (test-equal (- (expt 2 128)) (arithmetic-shift -1 128)))

(define check-087
  (test-equal (- (expt 2 129)) (arithmetic-shift -1 129)))

(define check-088
  (test-equal 0 (arithmetic-shift 1 -63)))

(define check-089
  (test-equal 0 (arithmetic-shift 1 -64)))

(define check-090
  (test-equal 0 (arithmetic-shift 1 -65)))

(define check-091
  (test-equal 32 (arithmetic-shift 8 2)))

(define check-092
  (test-equal 4 (arithmetic-shift 4 0)))

(define check-093
  (test-equal 4 (arithmetic-shift 8 -1)))

(define check-094
  (test-equal -79 (arithmetic-shift -100000000000000000000000000000000 -100)))

(define check-095
  (test-equal 2 (bit-count 12)))

(define check-096
  (test-equal 0 (integer-length  0)))

(define check-097
  (test-equal 1 (integer-length  1)))

(define check-098
  (test-equal 0 (integer-length -1)))

(define check-099
  (test-equal 3 (integer-length  7)))

(define check-100
  (test-equal 3 (integer-length -7)))

(define check-101
  (test-equal 4 (integer-length  8)))

(define check-102
  (test-equal 3 (integer-length -8)))

(define check-103
  (test-equal 9 (bitwise-if 3 1 8)))

(define check-104
  (test-equal 0 (bitwise-if 3 8 1)))

(define check-105
  (test-equal 3 (bitwise-if 1 1 2)))

(define check-106
  (test-equal #b00110011 (bitwise-if #b00111100 #b11110000 #b00001111)))

;; bitwise/single

(define check-107
  (test-equal #t (bit-set? 0 1)))

(define check-108
  (test-equal #f (bit-set? 1 1)))

(define check-109
  (test-equal #f (bit-set? 1 8)))

(define check-110
  (test-equal #t (bit-set? 10000 -1)))

(define check-111
  (test-equal #t (bit-set? 1000 -1)))

(define check-112
  (test-equal #t (bit-set? 64 #x10000000000000000)))

(define check-113
  (test-equal #f (bit-set? 64 1)))

(define check-114
  (test-equal #t (bit-set? 3 10)))

(define check-115
  (test-equal #t (bit-set? 2 6)))

(define check-116
  (test-equal #f (bit-set? 0 6)))

(define check-117
  (test-equal 0 (copy-bit 0 0 #f)))

(define check-118
  (test-equal 0 (copy-bit 30 0 #f)))

(define check-119
  (test-equal 0 (copy-bit 31 0 #f)))

(define check-120
  (test-equal 0 (copy-bit 62 0 #f)))

(define check-121
  (test-equal 0 (copy-bit 63 0 #f)))

(define check-122
  (test-equal 0 (copy-bit 128 0 #f)))

(define check-123
  (test-equal -1 (copy-bit 0 -1 #t)))

(define check-124
  (test-equal -1 (copy-bit 30 -1 #t)))

(define check-125
  (test-equal -1 (copy-bit 31 -1 #t)))

(define check-126
  (test-equal -1 (copy-bit 62 -1 #t)))

(define check-127
  (test-equal -1 (copy-bit 63 -1 #t)))

(define check-128
  (test-equal -1 (copy-bit 128 -1 #t)))

(define check-129
  (test-equal 1 (copy-bit 0 0 #t)))

(define check-130
  (test-equal #x106 (copy-bit 8 6 #t)))

(define check-131
  (test-equal 6 (copy-bit 8 6 #f)))

(define check-132
  (test-equal -2 (copy-bit 0 -1 #f)))

(define check-133
  (test-equal 0 (copy-bit 128 #x100000000000000000000000000000000 #f)))

(define check-134
  (test-equal #x100000000000000000000000000000000
              (copy-bit 128 #x100000000000000000000000000000000 #t)))

(define check-135
  (test-equal #x100000000000000000000000000000000
              (copy-bit 64 #x100000000000000000000000000000000 #f)))

(define check-136
  (test-equal #x-100000000000000000000000000000000
              (copy-bit 64 #x-100000000000000000000000000000000 #f)))

(define check-137
  (test-equal #x-100000000000000000000000000000000
              (copy-bit 256 #x-100000000000000000000000000000000 #t)))

(define check-138
  (test-equal #b100 (copy-bit 2 0 #t)))

(define check-139
  (test-equal #b1011 (copy-bit 2 #b1111 #f)))

(define check-140
  (test-equal #b1 (copy-bit 0 0 #t)))

(define check-141
  (test-equal #b1011 (bit-swap 1 2 #b1101)))

(define check-142
  (test-equal #b1011 (bit-swap 2 1 #b1101)))

(define check-143
  (test-equal #b1110 (bit-swap 0 1 #b1101)))

(define check-144
  (test-equal #b10000000101 (bit-swap 3 10 #b1101)))

(define check-145
  (test-equal 1 (bit-swap 0 2 4)))

(define check-146
  (test-equal #t (any-bit-set? 3 6)))

(define check-147
  (test-equal #f (any-bit-set? 3 12)))

(define check-148
  (test-equal #t (every-bit-set? 4 6)))

(define check-149
  (test-equal #f (every-bit-set? 7 6)))

(define check-150
  (test-equal -1 (first-set-bit 0)))

(define check-151
  (test-equal 0 (first-set-bit 1)))

(define check-152
  (test-equal 0 (first-set-bit 3)))

(define check-153
  (test-equal 2 (first-set-bit 4)))

(define check-154
  (test-equal 1 (first-set-bit 6)))

(define check-155
  (test-equal 0 (first-set-bit -1)))

(define check-156
  (test-equal 1 (first-set-bit -2)))

(define check-157
  (test-equal 0 (first-set-bit -3)))

(define check-158
  (test-equal 2 (first-set-bit -4)))

(define check-159
  (test-equal 128 (first-set-bit #x100000000000000000000000000000000)))

(define check-160
  (test-equal 1 (first-set-bit 2)))

(define check-161
  (test-equal 3 (first-set-bit 40)))

(define check-162
  (test-equal 2 (first-set-bit -28)))

(define check-163
  (test-equal 99 (first-set-bit (expt  2 99))))

(define check-164
  (test-equal 99 (first-set-bit (expt -2 99))))

;; bitwise/field

(define check-165
  (test-equal 0 (bit-field 6 0 1)))

(define check-166
  (test-equal 3 (bit-field 6 1 3)))

(define check-167
  (test-equal 1 (bit-field 6 2 999)))

(define check-168
  (test-equal 1 (bit-field #x100000000000000000000000000000000 128 129)))

(define check-169
  (test-equal #b1010 (bit-field #b1101101010 0 4)))

(define check-170
  (test-equal #b101101 (bit-field #b1101101010 3 9)))

(define check-171
  (test-equal #b10110 (bit-field #b1101101010 4 9)))

(define check-172
  (test-equal #b110110 (bit-field #b1101101010 4 10)))

(define check-173
  (test-equal #t (bit-field-any? #b101101 0 2)))

(define check-174
  (test-equal #t (bit-field-any? #b101101 2 4)))

(define check-175
  (test-equal #f (bit-field-any? #b101101 1 2)))

(define check-176
  (test-equal #f (bit-field-every? #b101101 0 2)))

(define check-177
  (test-equal #t (bit-field-every? #b101101 2 4)))

(define check-178
  (test-equal #t (bit-field-every? #b101101 0 1)))

(define check-179
  (test-equal #b100000 (bit-field-clear #b101010 1 4)))

(define check-180
  (test-equal #b101110 (bit-field-set #b101010 1 4)))

(define check-181
  (test-equal #b111 (bit-field-replace #b110 1 0 1)))

(define check-182
  (test-equal #b110 (bit-field-replace #b110 1 1 2)))

(define check-183
  (test-equal #b010 (bit-field-replace #b110 1 1 3)))

(define check-184
  (test-equal #b100100 (bit-field-replace #b101010 #b010 1 4)))

(define check-185
  (test-equal #b1001 (bit-field-replace-same #b1111 #b0000 1 3)))

(define check-186
  (test-equal #b110  (bit-field-rotate #b110 1 1 2)))

(define check-187
  (test-equal #b1010 (bit-field-rotate #b110 1 2 4)))

(define check-188
  (test-equal #b1011 (bit-field-rotate #b0111 -1 1 4)))

(define check-188-bis
  (test-equal #b1011 (bit-field-rotate #b1101 -1 1 3)))

(define check-188-ter
  (test-equal #b1011 (bit-field-rotate #b1101 1 1 3)))

(define check-189
  (test-equal #b0 (bit-field-rotate #b0 128 0 256)))

(define check-190
  (test-equal #b1 (bit-field-rotate #b1 128 1 256)))

(define check-191
  (test-equal #x100000000000000000000000000000000
              (bit-field-rotate #x100000000000000000000000000000000 128 0 64)))

(define check-192
  (test-equal #x100000000000000000000000000000008
              (bit-field-rotate #x100000000000000000000000000000001 3 0 64)))

(define check-193
  (test-equal #x100000000000000002000000000000000
              (bit-field-rotate #x100000000000000000000000000000001 -3 0 64)))

(define check-194
  (test-equal #b110 (bit-field-rotate #b110 0 0 10)))

(define check-195
  (test-equal #b110 (bit-field-rotate #b110 0 0 256)))

(define check-196
  (test-equal 1 (bit-field-rotate #x100000000000000000000000000000000 1 0 129)))

(define check-197
  (test-equal 6 (bit-field-reverse 6 1 3)))

(define check-198
  (test-equal 12 (bit-field-reverse 6 1 4)))

(define check-199
  (test-equal #x80000000 (bit-field-reverse 1 0 32)))

(define check-200
  (test-equal #x40000000 (bit-field-reverse 1 0 31)))

(define check-201
  (test-equal #x20000000 (bit-field-reverse 1 0 30)))

(define check-202
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #xFBFFFFFF)
              (bit-field-reverse -2 0 27)))

(define check-203
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #xF7FFFFFF)
              (bit-field-reverse -2 0 28)))

(define check-204
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #xEFFFFFFF)
              (bit-field-reverse -2 0 29)))

(define check-205
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #xDFFFFFFF)
              (bit-field-reverse -2 0 30)))

(define check-206
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #xBFFFFFFF)
              (bit-field-reverse -2 0 31)))

(define check-207
  (test-equal (bitwise-ior (arithmetic-shift -1 32) #x7FFFFFFF)
              (bit-field-reverse -2 0 32)))

(define check-208
  (test-equal 5 (bit-field-reverse #x140000000000000000000000000000000 0 129)))

;; bitwise/conversion

(define check-209
  (test-equal '(#t #f #t #f #t #t #t) (bits->list #b1110101)))

(define check-210
  (test-equal '(#f #t #f #t) (bits->list #b111010 4)))

(define check-211
  (test-equal #b1110101 (list->bits '(#t #f #t #f #t #t #t))))

(define check-212
  (test-equal #b111010100 (list->bits '(#f #f #t #f #t #f #t #t #t))))

(define check-213
  (test-equal '(#t #t) (bits->list 3)))

(define check-214
  (test-equal '(#f #t #t #f) (bits->list 6 4)))

(define check-215
  (test-equal '(#f #t) (bits->list 6 2)))

(define check-216
  (test-equal '(#t #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                   #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f)
              (bits->list 1 128)))

(define check-217
  (test-equal '(#f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #t)
              (bits->list #x100000000000000000000000000000000)))

(define check-218
  (test-equal 6 (list->bits '(#f #t #t))))

(define check-219
  (test-equal 12 (list->bits '(#f #f #t #t))))

(define check-220
  (test-equal 6 (list->bits '(#f #t #t #f))))

(define check-221
  (test-equal 2 (list->bits '(#f #t))))

(define check-222
  (test-equal 1 (list->bits
                 '(#t #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                      #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f))))

(define check-223
  (test-equal #x100000000000000000000000000000000
              (list->bits
               '(#f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f
                 #f #f #f #f #f #f #f #f #f #f #f #f #f #f #f #t))))

(define check-224
  (test-equal #x03FFFFFF (list->bits '(#t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-225
  (test-equal #x07FFFFFF (list->bits '(#t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-226
  (test-equal #x0FFFFFFF (list->bits '(#t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-227
  (test-equal #x1FFFFFFF (list->bits '(#t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-228
  (test-equal #x3FFFFFFF (list->bits '(#t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-229
  (test-equal #x7FFFFFFF (list->bits '(#t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))
(define check-230
  (test-equal #xFFFFFFFF (list->bits '(#t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t
                                          #t #t #t #t #t #t #t #t))))

(define check-231
  (test-equal #x1FFFFFFFF (list->bits '(#t
                                        #t #t #t #t #t #t #t #t
                                        #t #t #t #t #t #t #t #t
                                        #t #t #t #t #t #t #t #t
                                        #t #t #t #t #t #t #t #t))))

(define check-232
  (test-equal 1 (list->bits '(#t #f))))

(define check-233
  (test-equal #b1110101 (vector->bits '#(#t #f #t #f #t #t #t))))

(define check-234
  (test-equal #b00011010100 (vector->bits '#(#f #f #t #f #t #f #t #t))))

(define check-235
  (test-equal '#(#t #t #t #f #t #f #t #f #f) (bits->vector #b1010111 9)))

(define check-236
  (test-equal '#(#t #t #t #f #t #f #t #f #f) (bits->vector #b1010111 9)))

(define check-237
  (test-equal #b1110101 (bits #t #f #t #f #t #t #t)))

(define check-238
  (test-equal 0 (bits)))

(define check-239
  (test-equal #b111010100 (bits #f #f #t #f #t #f #t #t #t)))

;; bitwise/fold

(define check-240
  (test-equal '(#t #f #t #f #t #t #t) (bitwise-fold cons '() #b1010111)))

(define check-241
  (test-equal 5
              (let ((count 0))
                (bitwise-for-each (lambda (b) (if b (set! count (+ count 1))))
                                  #b1010111)
                count)))

(define check-242
  (test-equal #b101010101
              (bitwise-unfold (lambda (i) (= i 10)) even? (lambda (i) (+ i 1)) 0)))

(define check-243
  (test-equal #t
              (let ((g (make-bitwise-generator #b110)))
                (and
                 (equal? #f (g))
                 (equal? #t (g))
                 (equal? #t (g))
                 (equal? #f (g))))))

(test-end "bitwise-operations")

;;; ———————————————— SRFI 143（fixnums.sps）————————————————
(test-begin "fixnums")
;; D2：本库不导出 SRFI 143 的 fxbit-set? / fxcopy-bit（与基础库同名、参数次序相反），下面的
;; fixnum-074 ~ 082 按对照表改为基础库的写法：(fxbit-set? 下标 i) → (fxbit-set? i 下标)，
;; (fxcopy-bit 下标 i 布尔) → (fxcopy-bit i 下标 0或1)

(define fx-check-00
  (test-equal "fixnum-000" #t (fixnum? 32767)))

(define fx-check-01
  (test-equal "fixnum-001" #f (fixnum? 1.1)))

(define fx-check-02
  (test-equal "fixnum-002" #t (fx=? 1 1 1)))

(define fx-check-03
  (test-equal "fixnum-003" #f (fx=? 1 2 2)))

(define fx-check-04
  (test-equal "fixnum-004" #f (fx=? 1 1 2)))

(define fx-check-05
  (test-equal "fixnum-005" #f (fx=? 1 2 3)))

(define fx-check-06
  (test-equal "fixnum-006" #t (fx<? 1 2 3)))

(define fx-check-07
  (test-equal "fixnum-007" #f (fx<? 1 1 2)))

(define fx-check-08
  (test-equal "fixnum-008" #t (fx>? 3 2 1)))

(define fx-check-09
  (test-equal "fixnum-009" #f (fx>? 2 1 1)))

(define fx-check-10
  (test-equal "fixnum-010" #t (fx<=? 1 1 2)))

(define fx-check-11
  (test-equal "fixnum-011" #f (fx<=? 1 2 1)))

(define fx-check-12
  (test-equal "fixnum-012" #t (fx>=? 2 1 1)))

(define fx-check-13
  (test-equal "fixnum-013" #f (fx>=? 1 2 1)))

(define fx-check-14
  (test-equal "fixnum-014" '(#t #f) (list (fx<=? 1 1 2) (fx<=? 2 1 3))))

(define fx-check-15
  (test-equal "fixnum-015" #t (fxzero? 0)))

(define fx-check-16
  (test-equal "fixnum-016" #f (fxzero? 1)))

(define fx-check-17
  (test-equal "fixnum-017" #f (fxpositive? 0)))

(define fx-check-18
  (test-equal "fixnum-018" #t (fxpositive? 1)))

(define fx-check-19
  (test-equal "fixnum-019" #f (fxpositive? -1)))

(define fx-check-20
  (test-equal "fixnum-020" #f (fxnegative? 0)))

(define fx-check-21
  (test-equal "fixnum-021" #f (fxnegative? 1)))

(define fx-check-22
  (test-equal "fixnum-022" #t (fxnegative? -1)))

(define fx-check-23
  (test-equal "fixnum-023" #f (fxodd? 0)))

(define fx-check-24
  (test-equal "fixnum-024" #t (fxodd? 1)))

(define fx-check-25
  (test-equal "fixnum-025" #t (fxodd? -1)))

(define fx-check-26
  (test-equal "fixnum-026" #f (fxodd? 102)))

(define fx-check-27
  (test-equal "fixnum-027" #t (fxeven? 0)))

(define fx-check-28
  (test-equal "fixnum-028" #f (fxeven? 1)))

(define fx-check-29
  (test-equal "fixnum-029" #t (fxeven? -2)))

(define fx-check-30
  (test-equal "fixnum-030" #t (fxeven? 102)))

(define fx-check-31
  (test-equal "fixnum-031" 4 (fxmax 3 4)))

(define fx-check-32
  (test-equal "fixnum-032" 5 (fxmax 3 5 4)))

(define fx-check-33
  (test-equal "fixnum-033" 3 (fxmin 3 4)))

(define fx-check-34
  (test-equal "fixnum-034" 3 (fxmin 3 5 4)))

(define fx-check-35
  (test-equal "fixnum-035" 7 (fx+ 3 4)))

(define fx-check-36
  (test-equal "fixnum-036" 12 (fx* 4 3)))

(define fx-check-37
  (test-equal "fixnum-037" -1 (fx- 3 4)))

(define fx-check-38
  (test-equal "fixnum-038" -3 (fxneg 3)))

(define fx-check-39
  (test-equal "fixnum-039" 7 (fxabs -7)))

(define fx-check-40
  (test-equal "fixnum-040" 7 (fxabs 7)))

(define fx-check-41
  (test-equal "fixnum-041" 1764 (fxsquare 42)))

(define fx-check-42
  (test-equal "fixnum-042" 4 (fxsquare 2)))

(define fx-check-43
  (test-equal "fixnum-043" 2 (fxquotient 5 2)))

(define fx-check-44
  (test-equal "fixnum-044" -2 (fxquotient -5 2)))

(define fx-check-45
  (test-equal "fixnum-045" -2 (fxquotient 5 -2)))

(define fx-check-46
  (test-equal "fixnum-046" 2 (fxquotient -5 -2)))

(define fx-check-47
  (test-equal "fixnum-047" 1 (fxremainder 13 4)))

(define fx-check-48
  (test-equal "fixnum-048" -1 (fxremainder -13 4)))

(define fx-check-49
  (test-equal "fixnum-049" 1 (fxremainder 13 -4)))

(define fx-check-50
  (test-equal "fixnum-050" -1 (fxremainder -13 -4)))

(define fx-check-51
  (test-equal "fixnum-051" 35 (let*-values (((root rem) (fxsqrt 32)))
              (* root rem))))
(define fx-check-52
  (test-equal "fixnum-052" -1 (fxnot 0)))

(define fx-check-53
  (test-equal "fixnum-053"  0 (fxand #b0 #b1)))

(define fx-check-54
  (test-equal "fixnum-054"  6 (fxand 14 6)))

(define fx-check-55
  (test-equal "fixnum-055"  14 (fxior 10 12)))

(define fx-check-56
  (test-equal "fixnum-056"  6 (fxxor 10 12)))

(define fx-check-57
  (test-equal "fixnum-057" 0 (fxnot -1)))

(define fx-check-58
  (test-equal "fixnum-058" 9 (fxif 3 1 8)))

(define fx-check-59
  (test-equal "fixnum-059" 0 (fxif 3 8 1)))

(define fx-check-60
  (test-equal "fixnum-060" 2 (fxbit-count 12)))

(define fx-check-61
  (test-equal "fixnum-061" 0 (fxlength 0)))

(define fx-check-62
  (test-equal "fixnum-062" 8 (fxlength 128)))

(define fx-check-63
  (test-equal "fixnum-063" 8 (fxlength 255)))

(define fx-check-64
  (test-equal "fixnum-064" 9 (fxlength 256)))

(define fx-check-65
  (test-equal "fixnum-065" -1 (fxfirst-set-bit 0)))

(define fx-check-66
  (test-equal "fixnum-066" 0 (fxfirst-set-bit 1)))

(define fx-check-67
  (test-equal "fixnum-067" 0 (fxfirst-set-bit 3)))

(define fx-check-68
  (test-equal "fixnum-068" 2 (fxfirst-set-bit 4)))

(define fx-check-69
  (test-equal "fixnum-069" 1 (fxfirst-set-bit 6)))

(define fx-check-70
  (test-equal "fixnum-070" 0 (fxfirst-set-bit -1)))

(define fx-check-71
  (test-equal "fixnum-071" 1 (fxfirst-set-bit -2)))

(define fx-check-72
  (test-equal "fixnum-072" 0 (fxfirst-set-bit -3)))

(define fx-check-73
  (test-equal "fixnum-073" 2 (fxfirst-set-bit -4)))

(define fx-check-74
  (test-equal "fixnum-074" #t (fxbit-set? 1 0)))

(define fx-check-75
  (test-equal "fixnum-075" #f (fxbit-set? 1 1)))

(define fx-check-76
  (test-equal "fixnum-076" #f (fxbit-set? 8 1)))

(define fx-check-77
  (test-equal "fixnum-077" #t (fxbit-set? -1 10000)))

(define fx-check-78
  (test-equal "fixnum-078" #t (fxbit-set? -1 1000)))

(define fx-check-79
  (test-equal "fixnum-079" 0 (fxcopy-bit 0 0 0)))

(define fx-check-80
  (test-equal "fixnum-080" -1 (fxcopy-bit -1 0 1)))

(define fx-check-81
  (test-equal "fixnum-081" 1 (fxcopy-bit 0 0 1)))

(define fx-check-82
  (test-equal "fixnum-082" #x106 (fxcopy-bit 6 8 1)))

(define fx-check-83
  (test-equal "fixnum-083" 6 (fxcopy-bit 6 8 0)))

(define fx-check-84
  (test-equal "fixnum-084" -2 (fxcopy-bit -1 0 0)))

(define fx-check-85
  (test-equal "fixnum-085" 0 (fxbit-field 6 0 1)))

(define fx-check-86
  (test-equal "fixnum-086" 3 (fxbit-field 6 1 3)))

(define fx-check-87
  (test-equal "fixnum-087" 2 (fxarithmetic-shift 1 1)))

(define fx-check-88
  (test-equal "fixnum-088" 0 (fxarithmetic-shift 1 -1)))

(define fx-check-89
  (test-equal "fixnum-089" #b110  (fxbit-field-rotate #b110 1 1 2)))

(define fx-check-90
  (test-equal "fixnum-090" #b1010 (fxbit-field-rotate #b110 1 2 4)))

(define fx-check-91
  (test-equal "fixnum-091" #b1011 (fxbit-field-rotate #b0111 -1 1 4)))

(define fx-check-92
  (test-equal "fixnum-092" #b110 (fxbit-field-rotate #b110 0 0 10)))

(define fx-check-93
  (test-equal "fixnum-093" 6 (fxbit-field-reverse 6 1 3)))

(define fx-check-94
  (test-equal "fixnum-094" 12 (fxbit-field-reverse 6 1 4)))

(define fx-check-95
  (test-equal "fixnum-095" -11 (fxnot 10)))

(define fx-check-96
  (test-equal "fixnum-096" 36 (fxnot -37)))

(define fx-check-97
  (test-equal "fixnum-097" 11 (fxior 3  10)))

(define fx-check-98
  (test-equal "fixnum-098" 10 (fxand 11 26)))

(define fx-check-99
  (test-equal "fixnum-099" 9 (fxxor 3 10)))

(define fx-check-100
  (test-equal "fixnum-100" 4 (fxand 37 12)))

(define fx-check-101
  (test-equal "fixnum-101" 32 (fxarithmetic-shift 8 2)))

(define fx-check-102
  (test-equal "fixnum-102" 4 (fxarithmetic-shift 4 0)))

(define fx-check-103
  (test-equal "fixnum-103" 4 (fxarithmetic-shift 8 -1)))

(define fx-check-104
  (test-equal "fixnum-104" 0 (fxlength  0)))

(define fx-check-105
  (test-equal "fixnum-105" 1 (fxlength  1)))

(define fx-check-106
  (test-equal "fixnum-106" 0 (fxlength -1)))

(define fx-check-107
  (test-equal "fixnum-107" 3 (fxlength  7)))

(define fx-check-108
  (test-equal "fixnum-108" 3 (fxlength -7)))

(define fx-check-109
  (test-equal "fixnum-109" 4 (fxlength  8)))

(define fx-check-110
  (test-equal "fixnum-110" 3 (fxlength -8)))

(define fx-check-111
  ;; TODO: investigate
  (test-equal "fixnum-111" #t (fxbit-set? 10 3)))

(define fx-check-112
  ;; TODO: investigate
  (test-equal "fixnum-112" #t (fxbit-set? 6 2)))

(define fx-check-113
  (test-equal "fixnum-113" #f (fxbit-set? 6 0)))

(define fx-check-114
  (test-equal "fixnum-114" #b100 (fxcopy-bit 0 2 1)))

(define fx-check-115
  (test-equal "fixnum-115" #b1011 (fxcopy-bit #b1111 2 0)))

(define fx-check-116
  (test-equal "fixnum-116" 1 (fxfirst-set-bit 2)))

(define fx-check-117
  (test-equal "fixnum-117" 3 (fxfirst-set-bit 40)))

(define fx-check-118
  (test-equal "fixnum-118" 2 (fxfirst-set-bit -28)))

(define fx-check-119
  (test-equal "fixnum-119" 1 (fxand #b1 #b1)))

(define fx-check-120
  (test-equal "fixnum-120" 0 (fxand #b1 #b10)))

(define fx-check-121
  (test-equal "fixnum-121" #b10 (fxand #b11 #b10)))

(define fx-check-122
  (test-equal "fixnum-122" #b101 (fxand #b101 #b111)))

(define fx-check-123
  (test-equal "fixnum-123" #b111 (fxand -1 #b111)))

(define fx-check-124
  (test-equal "fixnum-124" #b110 (fxand -2 #b111)))

(define fx-check-125
  (test-equal "fixnum-125" 1 (fxarithmetic-shift 1 0)))

(define fx-check-126
  (test-equal "fixnum-126" 4 (fxarithmetic-shift 1 2)))

(define fx-check-127
  (test-equal "fixnum-127" 8 (fxarithmetic-shift 1 3)))

(define fx-check-128
  (test-equal "fixnum-128" 16 (fxarithmetic-shift 1 4)))

(define fx-check-129
  (test-equal "fixnum-129" -1 (fxarithmetic-shift -1 0)))

(define fx-check-130
  (test-equal "fixnum-130" -2 (fxarithmetic-shift -1 1)))

(define fx-check-131
  (test-equal "fixnum-131" -4 (fxarithmetic-shift -1 2)))

(define fx-check-132
  (test-equal "fixnum-132" -8 (fxarithmetic-shift -1 3)))

(define fx-check-133
  (test-equal "fixnum-133" -16 (fxarithmetic-shift -1 4)))

(define fx-check-134
  (test-equal "fixnum-134" #b1010 (fxbit-field #b1101101010 0 4)))

(define fx-check-135
  (test-equal "fixnum-135" #b101101 (fxbit-field #b1101101010 3 9)))

(define fx-check-136
  (test-equal "fixnum-136" #b10110 (fxbit-field #b1101101010 4 9)))

(define fx-check-137
  (test-equal "fixnum-137" #b110110 (fxbit-field #b1101101010 4 10)))

(define fx-check-138
  (test-equal "fixnum-138" 3 (fxif 1 1 2)))

(define fx-check-139
  (test-equal "fixnum-139" #b00110011 (fxif #b00111100 #b11110000 #b00001111)))

(define fx-check-140
  (test-equal "fixnum-140" #b1 (fxcopy-bit 0 0 1)))

(test-end "fixnums")

;;; ———————————————— SRFI 141（原测试没有；按 SRFI 141 文本的定义） ————————————————
(define (qr f n d) (call-with-values (lambda () (f n d)) list))
(check (qr floor/ 7 2) => '(3 1))
(check (qr floor/ -7 2) => '(-4 1))
(check (qr floor/ 7 -2) => '(-4 -1))
(check (list (floor-quotient -7 2) (floor-remainder -7 2)) => '(-4 1))
(check (qr truncate/ -7 2) => '(-3 -1))
(check (list (truncate-quotient -7 2) (truncate-remainder -7 2)) => '(-3 -1))
(check (qr ceiling/ 7 2) => '(4 -1))
(check (list (ceiling-quotient 7 2) (ceiling-remainder 7 2)) => '(4 -1))
(check (qr round/ 7 2) => '(4 -1))                          ; 3.5 舍入到偶数 4
(check (qr round/ 5 2) => '(2 1))                           ; 2.5 舍入到偶数 2
(check (list (round-quotient 7 2) (round-remainder 7 2)) => '(4 -1))
(check (qr euclidean/ -7 2) => '(-4 1))
(check (qr euclidean/ -7 -2) => '(4 1))                     ; 余数总是非负
(check (list (euclidean-quotient 7 -2) (euclidean-remainder 7 -2)) => '(-3 1))
(check (qr balanced/ 7 4) => '(2 -1))                       ; 余数在 [-d/2, d/2)
(check (list (balanced-quotient 5 4) (balanced-remainder 5 4)) => '(1 1))

;;; ———————————————— SRFI 60 独有（原测试没有；按 SRFI 60 文本） ————————————————
(check (logand #b1100 #b1010) => #b1000)
(check (logior #b1100 #b1010) => #b1110)
(check (logxor #b1100 #b1010) => #b0110)
(check (lognot 0) => -1)
(check (logtest #b0100 #b0110) => #t)
(check (logtest #b0001 #b0110) => #f)
(check (logbit? 2 #b0100) => #t)
(check (logcount #b10101) => 3)
(check (ash 1 4) => 16)
(check (ash 16 -2) => 4)
(check (any-bits-set? #b0100 #b0110) => #t)
(check (bitwise-merge #b1100 #b1010 #b0101) => #b1001)     ; 掩码为 1 的位取第二个
(check (log2-binary-factors 12) => 2)
(check (copy-bit-field #b1101101010 0 0 4) => #b1101100000)
(check (rotate-bit-field #b0100 3 0 4) => #b0010)
(check (reverse-bit-field #xa7 0 8) => #xe5)
(check (integer->list 6) => '(#t #t #f))
(check (integer->list 6 4) => '(#f #t #t #f))
(check (list->integer '(#t #t #f)) => 6)
(check (booleans->integer #t #f #t) => 5)

;;; ———————————————— SRFI 143 的常量（原测试没有） ————————————————
(check fx-width => (fixnum-width))
(check fx-greatest => (greatest-fixnum))
(check fx-least => (least-fixnum))

(check-report "std arithmetic")
