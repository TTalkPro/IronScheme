#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std persistent queues) —— 持久（纯函数式）队列（designs/08-std-library.md D1）
;;; 词源：pfds 的 (pfds queues)，Okasaki 的银行家队列：enqueue / dequeue 均摊 O(1)，旧版本保持不变。
;;; 与 (ironscheme std queues)（SRFI 117，可变的表队列）不同：本库的 enqueue 返回新队列。
;;; 对空队列 dequeue 引发 &assertion 的子类型条件，用 queue-empty-condition? 判断。
;;; 本库所有名字都是基础库没有的（D2）。
;;; 实现来自 pfds（Ian Price，new-style BSD 许可，全文见 LICENSES/pfds.txt）；原文件的说明与版权声明保留在下面。
;;;
;;; queues.sls --- Purely functional queues

;; Copyright (C) 2011,2012 Ian Price <ianprice90@googlemail.com>

;; Author: Ian Price <ianprice90@googlemail.com>

;; This program is free software, you can redistribute it and/or
;; modify it under the terms of the new-style BSD license.

;; You should have received a copy of the BSD license along with this
;; program. If not, see <http://www.debian.org/misc/bsd.license>.

;;; Commentary:
;;
;; A scheme translation of "Simple and Efficient Purely Functional
;; Queues and Deques" by Chris Okazaki
;;
;;
;;; Documentation:
;;
;; make-queue : () -> queue
;; returns a queue containing no items
;;
;; queue? : any -> boolean
;; tests if an object is a queue
;;
;; queue-length : queue -> non-negative integer
;; returns the number of items in the queue
;;
;; queue-empty? : queue -> boolean
;; returns true if there are no items in the queue, false otherwise
;;
;; enqueue : queue any -> queue
;; returns a new queue with the enqueued item at the end
;;
;; dequeue : queue -> value queue
;; returns two values, the item at the front of the queue, and a new
;; queue containing the all the other items
;; raises a &queue-empty condition if the queue is empty
;;
;; queue-empty-condition? : object -> boolean
;; tests if an object is a &queue-empty condition
;;
;; queue->list : queue -> listof(any)
;; returns a queue containing all the items in the list. The order of
;; the elements in the queue is the same as the order of the elements
;; in the list.
;;
;; list->queue : listof(any) -> queue
;; returns a list containing all the items in the queue. The order of
;; the items in the list is the same as the order in the queue.
;; For any list l, (equal? (queue->list (list->queue l)) l) is #t.
;;
(library (ironscheme std persistent queues)
  (export
    
    make-queue
        queue?
        queue-length
        queue-empty?
        enqueue
        dequeue
        queue-empty-condition?
        list->queue
        queue->list)
  (import
    (except (rnrs) cons*)
    (rnrs r5rs)
    (only (ironscheme std private pfds) cons* tail head empty? take drop rev append*))

;; 原 (pfds queues private condition)
(define-condition-type &queue-empty
  &assertion
  make-queue-empty-condition
  queue-empty-condition?)

(define (rotate l r a)
  (if (empty? l)
      (cons* (head r) a)
      (cons* (head l)
             (rotate (tail l)
                     (tail r)
                     (cons* (head r) a)))))


;;; Implementation

(define-record-type (queue %make-queue queue?)
  (fields
   (immutable length)
   (immutable l)
   (immutable r)
   (immutable l^)))


(define (make-queue)
  (%make-queue 0 '() '() '()))

(define (enqueue queue item)
  (let ((len (queue-length queue))
        (l (queue-l queue))
        (r (queue-r queue))
        (l^ (queue-l^ queue)))
    (makeq (+ len 1) l (cons* item r) l^)))

(define (dequeue queue)
  (when (queue-empty? queue)
    ;; (error 'dequeue  "Can't dequeue empty queue")
    (raise (condition
            (make-queue-empty-condition)
            (make-who-condition 'dequeue)
            (make-message-condition "There are no elements to dequeue")
            (make-irritants-condition (list queue)))))
  (let ((len (queue-length queue))
        (l (queue-l queue))
        (r (queue-r queue))
        (l^ (queue-l^ queue)))
    (values (head l)
            (makeq (- len 1) (tail l) r l^))))

(define (makeq length l r l^)
  (if (empty? l^)
      (let ((l* (rotate l r '())))
        (%make-queue length l* '() l*))
      (%make-queue length l r (tail l^))))

(define (queue-empty? queue)
  (zero? (queue-length queue)))

(define (list->queue list)
  (fold-left enqueue (make-queue) list))

(define (queue->list queue)
  (let loop ((rev-list '()) (queue queue))
    (if (queue-empty? queue)
        (reverse rev-list)
        (let-values (((val queue) (dequeue queue)))
          (loop (cons val rev-list)
                 queue)))))
)
