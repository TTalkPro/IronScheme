#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std persistent hash-maps) —— 持久散列映射（designs/08-std-library.md D1）
;;; 词源：pfds 的 (pfds hamts)：散列数组映射字典树（HAMT），按创建时给出的散列过程与等价谓词。
;;; 也是 SRFI 146（mappings，只有 Chez 实现，不移植，D6）散列部分的替代。
;;;
;;; 与 pfds 不同（D4，iron-045 修正）。pfds 的 HAMT 有下列缺陷，原测试键少、散列值小，没有暴露；
;;; 随机散列值下约 9% 的查找出错（iron-045 用随机键与关联表对照试验发现）：
;;;   ① mask 先取低 5 位再右移，次序反了，第二层起下标恒为 0；
;;;   ② 叶子或冲突节点拆成子树后，按下一层而不是本层继续插入，层次错开；子树中的叶子与冲突节点
;;;      应按下一层处理却按本层处理；
;;;   ③ 子树的向量是压缩存储的，插入与删除时按位号而不是按位置（ctpop）改写向量；删除最后一个元素后
;;;      判断"子树已空"时检查的是旧向量。
;;;   ④ 两个键形成冲突节点时，保存的是右移到本层的散列值而不是完整散列值，之后在别的层比较时错位。
;;; 另外，pfds 假定散列值非负，负的散列值算术右移永远得不到 0，不同散列值的键
;;; 会在深层被当作散列冲突，查找随之失败。IronScheme 的 string-hash 等返回负数（且 .NET 的字符串散列每个进程
;;; 不同，所以失败时有时无）。这里取散列值后先截成 32 位非负整数（%hash）；截断造成的冲突由冲突节点按等价谓词
;;; 区分，结果不变。hamt-hash-function 仍返回用户给出的过程。
;;; 本库所有名字都是基础库没有的（D2）。
;;; 实现来自 pfds（Ian Price，new-style BSD 许可，全文见 LICENSES/pfds.txt）；原文件的说明与版权声明保留在下面。
;;;
;;; hamts.sls --- Hash Array Mapped Tries

;; Copyright (C) 2014 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

;; Documentation:
;;
;; Note: For all procedures which take a key as an argument, the key
;; must be hashable with the hamt hash function, and comparable with
;; the hamt equivalence predicate.
;;
;; make-hamt : (any -> non-negative integer) (any -> any -> boolean) -> hamt
;; returns a new empty hamt using the given hash and equivalence functions.
;;
;; hamt? : any -> boolean
;; returns #t if argument is a hamt, #f otherwise.
;;
;; hamt-size : hamt -> non-negative integer
;; returns the number of associations in the hamt.
;;
;; hamt-ref : hamt any [any] -> any
;; returns the value associated with the key in the hamt. If there is
;; no value associated with the key, it returns the default value if
;; provided, or raises an &assertion-violation if it isn't.
;;
;; hamt-contains? : hamt any -> boolean
;; returns #t if there is an association for the key in the hamt, #f
;; otherwise.
;;
;; hamt-set : hamt any any -> hamt
;; returns a new hamt with the key associated to the value. If the key
;; is already associated with a value, it is replaced.
;;
;; hamt-update : hamt any (any -> any) any -> hamt
;; returns a new hamt with the valued associated with the key updated
;; by the update procedure. If the hamt does not already have a value
;; associated with the key, then it applies the update procedure to
;; the default value, and associates the key with that.
;;
;; hamt-delete : hamt any -> hamt
;; returns a hamt with the key and its associated value removed. If
;; the key is not in the hamt, a copy of the original hamt is
;; returned.
;;
;; hamt-fold : (any any any -> any) any hamt -> hamt
;; returns the value obtained by iterating the combine procedure over
;; each key value pair in the hamt. The combine procedure takes three
;; arguments, the key and value of an association, and an accumulator,
;; and returns a new accumulator value. The initial value of the
;; accumulator is provided by the base argument. The order in which
;; the hamt is traversed is not guaranteed.
;;
;; hamt-map : (any -> any) hamt -> hamt
;; returns the hamt obtained by applying the update procedure to each
;; of the values in the hamt.
;;
;; hamt->alist : hamt -> Listof(Pairs)
;; returns the key/value associations of the hamt as a list of pairs.
;; The order of the list is not guaranteed.
;;
;; alist->hamt : Listof(Pairs) (any -> non-negative integer) (any -> any -> boolean) -> hamt
;; returns the hamt containing the associations specified by the pairs
;; in the alist. If the same key appears in the alist multiple times,
;; its leftmost value is the one that is used.
;;
;; hamt-equivalence-predicate : hamt -> (any -> any -> boolean)
;; returns the procedure used internally by the hamt to compare keys.
;;
;; hamt-hash-function : hamt -> (any -> non-negative integer)
;; returns the hash procedure used internally by the hamt.
;;
(library (ironscheme std persistent hash-maps)
  (export
    
    make-hamt
        hamt?
        hamt-size
        hamt-ref
        hamt-set
        hamt-update
        hamt-delete
        hamt-contains?
        hamt-equivalence-predicate
        hamt-hash-function
        hamt-fold
        hamt-map
        hamt->alist
        alist->hamt)
  (import
    (rnrs)
    (only (ironscheme std private pfds) vector-set vector-insert vector-remove vector-copy vector-copy! vector-fold alist-ref alist-set alist-delete alist-update bitwise-bit-set bitwise-bit-unset))

;; 散列值截成 32 位非负整数（见文件头；pfds 原样使用散列值，负数时出错）
(define (%hash hash key)
  (bitwise-and (hash key) #xFFFFFFFF))

;;; Helpers

(define cardinality 32) ; 64

;; iron-045：原为先取低 5 位再右移，第二层起下标恒为 0
(define (mask key level)
  (bitwise-and (bitwise-arithmetic-shift-right key level) (- (expt 2 5) 1)))

(define (level-up level)
  (+ level 5))

(define (ctpop key index)
  (bitwise-bit-count (bitwise-arithmetic-shift-right key (+ 1 index))))

;;; Node types

(define-record-type (subtrie %make-subtrie subtrie?)
  (fields size bitmap vector))

(define (make-subtrie bitmap vector)
  (define vecsize
    (vector-fold (lambda (val accum)
                   (+ (size val) accum))
                 0
                 vector))
  (%make-subtrie vecsize bitmap vector))

(define-record-type leaf
  (fields key value))

(define-record-type (collision %make-collision collision?)
  (fields size hash alist))

(define (make-collision hash alist)
  (%make-collision (length alist) hash alist))

;;; Main

(define (lookup vector key default hash eqv?)
  (define (handle-subtrie node level)
    (define bitmap (subtrie-bitmap node))
    (define vector (subtrie-vector node))
    (define index (mask h level))
    (if (not (bitwise-bit-set? bitmap index))
        default
        (let ((node (vector-ref vector (ctpop bitmap index))))
          (cond ((leaf? node)
                 (handle-leaf node))
                ((collision? node)
                 (handle-collision node))
                (else
                 (handle-subtrie node (level-up level)))))))

  (define (handle-leaf node)
    (if (eqv? key (leaf-key node))
        (leaf-value node)
        default))

  (define (handle-collision node)
    (alist-ref (collision-alist node) key default eqv?))

  (define h (%hash hash key))
  (define node (vector-ref vector (mask h 0)))

  (cond ((not node) default)
        ((leaf? node) (handle-leaf node))
        ((collision? node) (handle-collision node))
        (else
         (handle-subtrie node (level-up 0)))))

(define (insert hvector key update base hash eqv?)
  (define (handle-subtrie subtrie level)
    (define bitmap (subtrie-bitmap subtrie))
    (define vector (subtrie-vector subtrie))
    (define index (mask h level))
    ;; iron-045：向量是压缩存储的，按位置（ctpop）而不是位号改写；子节点在下一层
    (define (fixup node)
      (make-subtrie bitmap (vector-set vector (ctpop bitmap index) node)))
    (if (not (bitwise-bit-set? bitmap index))
        (make-subtrie (bitwise-bit-set bitmap index)
                      (vector-insert vector
                                     (ctpop bitmap index)
                                     (make-leaf key (update base))))
        (let ((node (vector-ref vector (ctpop bitmap index))))
          (cond ((leaf? node)
                 (fixup (handle-leaf node (level-up level))))
                ((collision? node)
                 (fixup (handle-collision node (level-up level))))
                (else
                 (fixup (handle-subtrie node (level-up level))))))))

  (define (handle-leaf node level)
    (define lkey  (leaf-key node))
    (define khash (bitwise-arithmetic-shift-right h level))
    (define lfull (%hash hash lkey))
    (define lhash (bitwise-arithmetic-shift-right lfull level))
    (cond ((eqv? key lkey)
           (make-leaf key (update (leaf-value node))))
          ((equal? khash lhash)
           ;; iron-045：冲突节点保存完整散列值（原为右移到本层后的值）
           (make-collision lfull
                           (list (cons lkey (leaf-value node))
                                 (cons key (update base)))))
          (else
           ;; iron-045：包成的子树就在本层（原为 (level-up level)，错开一层）
           (handle-subtrie (wrap-subtrie node lhash) level))))

  (define (handle-collision node level)
    (define khash (bitwise-arithmetic-shift-right h level))
    (define chash (bitwise-arithmetic-shift-right (collision-hash node) level))
    (if (equal? khash chash)
        (make-collision (collision-hash node)
                        (alist-update (collision-alist node) key update base eqv?))
        ;; TODO: there may be a better (more efficient) way to do this
        ;; but simple is better for now (see also handle-leaf)
        ;; iron-045：同 handle-leaf，包成的子树就在本层
        (handle-subtrie (wrap-subtrie node chash) level)))

  (define (wrap-subtrie node chash)
    (make-subtrie (bitwise-bit-set 0 (mask chash 0)) (vector node)))

  (define h (%hash hash key))
  (define idx (mask h 0))
  (define node (vector-ref hvector idx))
  (define initial-level (level-up 0))

  (cond ((not node)
         (vector-set hvector idx (make-leaf key (update base))))
        ((leaf? node)
         (vector-set hvector idx (handle-leaf node initial-level)))
        ((collision? node)
         (vector-set hvector idx (handle-collision node initial-level)))
        (else
         (vector-set hvector idx (handle-subtrie node initial-level)))))

(define (delete vector key hash eqv?)
  (define (handle-subtrie subtrie level)
    (define bitmap  (subtrie-bitmap subtrie))
    (define vector  (subtrie-vector subtrie))
    (define index   (mask h level))
    ;; iron-045：按位置（ctpop）改写压缩向量
    (define (fixup node)
      (update bitmap vector index (ctpop bitmap index) node))
    (if (not (bitwise-bit-set? bitmap index))
        subtrie
        (let ((node (vector-ref vector (ctpop bitmap index))))
          (cond ((leaf? node)
                 (fixup (handle-leaf node)))
                ((collision? node)
                 (fixup (handle-collision node)))
                (else
                 (fixup (handle-subtrie node (level-up level))))))))

  (define (update bitmap vector index position value)
    (if value
        (make-subtrie bitmap (vector-set vector position value))
        (let ((vector* (vector-remove vector position)))
          ;; iron-045：原检查的是旧向量
          (if (equal? '#() vector*)
              #f
              (make-subtrie (bitwise-bit-unset bitmap index)
                            vector*)))))

  (define (handle-leaf node)
    (if (eqv? key (leaf-key node))
        #f
        node))

  (define (handle-collision node)
    (let ((al (alist-delete (collision-alist node) key eqv?)))
      (cond ((null? (cdr al))
             (make-leaf (car (car al)) (cdr (car al))))
            (else
             (make-collision (collision-hash node) al)))))

  (define h (%hash hash key))
  (define idx (mask h 0))
  (define node (vector-ref vector idx))

  (cond ((not node) vector)
        ((leaf? node)
         (vector-set vector idx (handle-leaf node)))
        ((collision? node)
         (vector-set vector idx (handle-collision node)))
        (else
         (vector-set vector idx (handle-subtrie node (level-up 0))))))

(define (vec-map mapper vector)
  (define (handle-subtrie trie)
    (make-subtrie (subtrie-bitmap trie)
                  (vector-map dispatch (subtrie-vector trie))))

  (define (handle-leaf leaf)
    (make-leaf (leaf-key leaf)
               (mapper (leaf-value leaf))))

  (define (handle-collision collision)
    (make-collision (collision-hash collision)
                    (map (lambda (pair)
                           (cons (car pair) (mapper (cdr pair))))
                         (collision-alist collision))))

  (define (dispatch val)
    (cond ((leaf? val)
           (handle-leaf val))
          ((collision? val)
           (handle-collision val))
          (else
           (handle-subtrie val))))

  (vector-map (lambda (val)
                ;; top can have #f values
                (and val (dispatch val)))
              vector))

(define (fold combine initial vector)
  (define (handle-subtrie trie accum)
    (vector-fold dispatch accum (subtrie-vector trie)))

  (define (handle-leaf leaf accum)
    (combine (leaf-key leaf) (leaf-value leaf) accum))

  (define (handle-collision collision accum)
    (fold-right (lambda (pair acc)
                  (combine (car pair) (cdr pair) acc))
                accum
                (collision-alist collision)))

  (define (dispatch val accum)
    (cond ((leaf? val)
           (handle-leaf val accum))
          ((collision? val)
           (handle-collision val accum))
          (else
           (handle-subtrie val accum))))

  (vector-fold (lambda (val accum)
                 ;; top level can have false values
                 (if (not val) accum (dispatch val accum)))
               initial
               vector))

(define (size node)
  (cond ((not node) 0)
        ((leaf? node) 1)
        ((collision? node) (collision-size node))
        (else (subtrie-size node))))

;;; Exported Interface

(define-record-type (hamt %make-hamt hamt?)
  (fields size root hash-function equivalence-predicate))

(define (wrap-root root hamt)
  (define vecsize
    (vector-fold (lambda (val accum)
                   (+ (size val) accum))
                 0
                 root))
  (%make-hamt vecsize
              root
              (hamt-hash-function hamt)
              (hamt-equivalence-predicate hamt)))

(define (make-hamt hash eqv?)
  (%make-hamt 0 (make-vector cardinality #f) hash eqv?))

(define hamt-ref
  (case-lambda
    ((hamt key)
     (define token (cons #f #f))
     (define return-val (hamt-ref hamt key token))
     (when (eqv? token return-val)
       (assertion-violation 'hamt-ref "Key is not in the hamt" key))
     return-val)
    ((hamt key default)
     ;; assert hamt?
     (lookup (hamt-root hamt)
             key
             default
             (hamt-hash-function hamt)
             (hamt-equivalence-predicate hamt)))))

(define (hamt-set hamt key value)
  (define root
    (insert (hamt-root hamt)
            key
            (lambda (old) value)
            'dummy
            (hamt-hash-function hamt)
            (hamt-equivalence-predicate hamt)))
  (wrap-root root hamt))

(define (hamt-update hamt key proc default)
  (define root
    (insert (hamt-root hamt)
            key
            proc
            default
            (hamt-hash-function hamt)
            (hamt-equivalence-predicate hamt)))
  (wrap-root root hamt))

(define (hamt-delete hamt key)
  (define root
    (delete (hamt-root hamt)
            key
            (hamt-hash-function hamt)
            (hamt-equivalence-predicate hamt)))
  (wrap-root root hamt))

(define (hamt-contains? hamt key)
  (define token (cons #f #f))
  (if (eqv? token (hamt-ref hamt key token))
      #f
      #t))

(define (hamt-map mapper hamt)
  (%make-hamt (hamt-size hamt)
              (vec-map mapper (hamt-root hamt))
              (hamt-hash-function hamt)
              (hamt-equivalence-predicate hamt)))

(define (hamt-fold combine initial hamt)
  (fold combine initial (hamt-root hamt)))

(define (hamt->alist hamt)
  (hamt-fold (lambda (key value accumulator)
               (cons (cons key value) accumulator))
             '()
             hamt))

(define (alist->hamt alist hash eqv?)
  (fold-right (lambda (kv-pair hamt)
                (hamt-set hamt (car kv-pair) (cdr kv-pair)))
              (make-hamt hash eqv?)
              alist))
)
