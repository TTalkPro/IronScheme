#| License
Copyright (c) 2026 the IronScheme contributors
All rights reserved.
This source code is subject to terms and conditions of the BSD License.
See docs/license.txt. |#

;;; (ironscheme std system) —— 环境变量与实现信息（designs/08-std-library.md）
;;; 词源：SRFI 98（Derick Eddington）环境变量；SRFI 112（John Cowan）实现与运行环境信息。
;;; 实现：环境变量取自 (ironscheme environment)（get-environment-variables 由散列表转为关联表，
;;; 同 chez-srfi 的 IronScheme 适配，Derick Eddington，MIT 许可，见 LICENSES/chez-srfi.txt）；
;;; SRFI 112 的各项按 IronScheme 的实际运行环境取值（.NET 的 RuntimeInformation / Environment）：
;;;   implementation-name     "IronScheme"
;;;   implementation-version  (ironscheme-version)，如 "0.1.0"
;;;   cpu-architecture        进程的体系结构，名字与 (ironscheme std syntax) 的 cond-expand 特性一致：
;;;                           "x86-64" "i386" "arm64" "arm"…（其余为 .NET 名字的小写）
;;;   machine-name            Environment.MachineName
;;;   os-name                 "Windows" "Linux" "macOS" "FreeBSD"，否则为 RuntimeInformation.OSDescription
;;;   os-version              RuntimeInformation.OSDescription（如 "Debian GNU/Linux 13 (trixie)"、
;;;                           "Microsoft Windows 10.0.22631"），取不到时为 #f
;;;
;;; 与 SRFI 文本不同的取舍（D4）：chez-srfi 的 IronScheme 适配把 cpu-architecture 写死为 "x86"/"amd64"、
;;; os-name 取 PlatformID（"Unix"/"Win32NT"），这里改为上面的实际值。
;;; 本库所有名字都是基础库没有的（D2）。
(library (ironscheme std system)
  (export
    cpu-architecture get-environment-variable get-environment-variables implementation-name
    implementation-version machine-name os-name os-version)
  (import
    (rnrs)
    (only (ironscheme) ironscheme-version)
    (only (ironscheme clr) clr-static-prop-get clr-static-call)
    (only (ironscheme environment) get-environment-variable)
    (rename (only (ironscheme environment) get-environment-variables) (get-environment-variables get-env-vars)))

;; ———————————————— SRFI 98 ————————————————
(define (get-environment-variables)
  (let-values (((k v) (hashtable-entries (get-env-vars))))
    (map cons (vector->list k) (vector->list v))))

;; ———————————————— SRFI 112 ————————————————
(define (implementation-name) "IronScheme")

(define (implementation-version) (ironscheme-version))

(define (clr->string x) (call-with-string-output-port (lambda (p) (display x p))))

(define (cpu-architecture)
  (let ((a (string-downcase
             (clr->string
               (clr-static-prop-get System.Runtime.InteropServices.RuntimeInformation ProcessArchitecture)))))
    (cond ((string=? a "x64") "x86-64")
          ((string=? a "x86") "i386")
          (else a))))

(define (machine-name)
  (clr-static-prop-get System.Environment MachineName))

(define (os-description)
  (clr-static-prop-get System.Runtime.InteropServices.RuntimeInformation OSDescription))

(define (os-name)
  (cond ((clr-static-call System.OperatingSystem IsWindows) "Windows")
        ((clr-static-call System.OperatingSystem IsLinux) "Linux")
        ((clr-static-call System.OperatingSystem IsMacOS) "macOS")
        ((clr-static-call System.OperatingSystem IsFreeBSD) "FreeBSD")
        (else (os-description))))

(define (os-version)
  (let ((d (os-description)))
    (and (string? d) (> (string-length d) 0) d)))
)
