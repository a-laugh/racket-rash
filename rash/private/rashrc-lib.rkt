#lang racket/base

(provide current-prompt-function)
(provide current-result-print-default-function)

(require racket/date)
(require shell/mixed-pipeline)
(require (prefix-in sp- shell/pipeline))
(require "rashrc-git-stuff.rkt")
(require racket/exn)


(define (print-ret-maybe last-ret ret-number)
  (define (pre)
    (printf "Result ~a:~n" ret-number))
  (cond [(exn? last-ret)
         (begin (pre)
                (eprintf "~a~n" last-ret)
                ;; let any filtering output finish
                (sleep 0.01))]
        [(and (pipeline? last-ret)
              (pipeline-running? last-ret))
         (pre)
         (printf "~a~n" last-ret)]
        [(and (pipeline? last-ret)
              (not (pipeline-success? last-ret)))
         (pre)
         (let ([err (pipeline-return last-ret)])
           (eprintf "~a~n" (format "~a" (if (exn? err)
                                            (exn->string err)
                                            err)))
           (sleep 0.01))]
        [(and (pipeline? last-ret)
              (pipeline-ends-with-unix-segment? last-ret))
         ;; successful unix pipes just have a boring status code
         (void)]
        [(pipeline? last-ret)
         (print-ret-maybe (pipeline-return last-ret) ret-number)]
        [(void? last-ret)
         (void)]
        [else (pre)
              ({current-result-print-default-function} last-ret)]))


;; TODO - use a library for these functions?
;;        Or do I not want another dependency?
(define (mstyle n)
  (λ (s) (format "\033[~am~a" n s)))
(define (mstyle2 n1 n2)
  (λ (s) (format "\033[~a;~am~a" n1 n2 s)))
(define default-style (mstyle 0))
(define cyan (mstyle 36))
(define red (mstyle 31))
(define green (mstyle 32))
(define bblue (mstyle2 1 34))

(define windows? (equal? (system-type 'os) 'windows))

(define (git-info-with-style)
  #|
  TODO - getting git info may be slow depending on file system.
  Eg. network mounts or busy file systems may make git info queries
  unusably slow, or huge git histories may slow this down.  I should
  add some sort of timeout, or only give information that comes out
  quickly.
  |#
  (define info (get-git-info))
  (if info
      (string-append
       (default-style "[")
       (hash-ref info 'branch) " "
       (if (< 0 (hash-ref info 'ahead))
           (format "~a~a" (default-style "▲") (cyan (hash-ref info 'ahead)))
           "")
       (if (< 0 (hash-ref info 'behind))
           (format "~a~a" (default-style "▼") (cyan (hash-ref info 'behind)))
           "")
       (if (hash-ref info 'dirty?) (red " D") "")
       (if (hash-ref info 'submodule-dirty?) (red " S") "")
       (if (hash-ref info 'untracked?) (red " U") "")
       (default-style "] "))
      ""))

;; TODO - add path coloring like in megaprompt, maybe with some more info and color options
;; TODO - add path shortening to a maximum length, or more generally finding the
;; max length a prompt string should be and adjusting all parts to it...

(define (basic-prompt #:last-return-value [last-ret #f]
                      #:last-return-index [last-ret-n 0])
  (when (> last-ret-n 0)
    (print-ret-maybe last-ret last-ret-n))
  (let* ([cdate (current-date)]
         [chour (date-hour cdate)]
         [cmin (date-minute cdate)]
         [padded-min (if (< cmin 10)
                         (string-append "0" (number->string cmin))
                         cmin)])
    (printf "~a:~a ~a~a~n~a "
            (cyan chour) padded-min
            (with-handlers ([(λ _ #t) (λ (e) (default-style "[git-info-error] "))])
              (git-info-with-style))
            (bblue (path->string (current-directory)))
            (default-style "➤"))))

(define (lame-prompt #:last-return-value [last-ret #f]
                     #:last-return-index [last-ret-n #f])
  (print-ret-maybe last-ret last-ret-n)
  (printf ">"))

(define current-prompt-function (make-parameter (if windows?
                                                    lame-prompt
                                                    basic-prompt)))
(define current-result-print-default-function
  (make-parameter (λ (result) (printf "~s~n" result))))