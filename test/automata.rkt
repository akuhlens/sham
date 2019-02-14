#lang racket

(require rcf/ast
         sham
         sham/ast-utils
         sham/jit-utils
         (for-syntax syntax/parse racket/pretty racket/set))

(define fsa-module
  (create-empty-sham-module "module" (module-info-add-late-pass (empty-module-info) 'AlwaysInliner)))
(current-sham-module fsa-module)

(define finfo (function-info-add-attributes (empty-function-info) 'alwaysinline))

(define (ri64 i) (or^ (shl (ui64 i) (ui64 1)) (ui64 1)))

(define-syntax (define-fsa stx)
  (syntax-parse stx
    [(_ name start (end ...) [state ([evt next-state] ...)] ...)
     #:with (res ...)
     (map (lambda (e) (if (memq (syntax-e e) (syntax->datum #'(end ...))) #'1 #'0))
          (syntax->list #'(state ...)))
     #'(begin
         (define-sham-function (name (inp : i64*) (pos : i64) (len : i64) : i64)
           (return (start inp pos len)))
         (define-sham-function #:info finfo (state (inp : i64*) (pos : i64) (len : i64) : i64)
           (if^ (icmp-ult pos len)
                (switch^ (load (gep^ inp pos))
                         [(ri64 evt) (return (next-state inp (add pos (ui64 1)) len))] ...
                         (return (ui64 0)))
                (return (ui64 res)))) ...)]))

(require racket/unsafe/ops)
(define-syntax (define-racket-fsa stx)
  (syntax-parse stx
    [(_ name start (end ...) [state ([evt next-state] ...)] ...)
     #:with (res ...)
     (map (lambda (e) (if (memq (syntax-e e) (syntax->datum #'(end ...))) #'1 #'0))
          (syntax->list #'(state ...)))
     #'(begin
         (define (name inp pos len)
           (start inp pos len))
         (define (state inp pos len)
           (if (< pos len)
               (case (unsafe-vector-ref inp pos)
                 [(evt) (next-state inp (+ pos 1) len)] ...
                 [else 0])
               res)) ...)]))

(define-fsa M
  s1 (s1)
  [s1 ([0 s2]
       [1 s2]
       [2 s1])]
  [s2 ([0 s1]
       [1 s2]
       [2 s2])])

(parameterize ([compile-options (list 'pretty 'dump 'verify)])
  (compile-sham-module!
   fsa-module
   #:opt-level 3))

(require ffi/unsafe
         racket/fixnum)
(define input (for/vector ([i 10000000]) (random 3)))
(define sham-input (time (vector->cpointer input)))

(let ()
  (define-racket-fsa M
    s1 (s1)
    [s1 ([0 s2]
         [1 s2]
         [2 s1])]
    [s2 ([0 s1]
         [1 s2]
         [2 s2])])
  (time (M input 0 (vector-length input))))

(time (sham-app M sham-input 0 (vector-length input)))