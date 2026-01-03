format ELF64 executable 3 at 100000h
entry Start

use AMD64, CET_IBT

include 'fastcall_v1.inc'
include 'anon_label.inc'

include 'stdio.inc'

macro struct? name
  define __ACTUAL__ name
  esc struc name
  label . : .size - .
end macro

macro ends?!
  .size:
  esc end struc
  virtual at 0
    match a, __ACTUAL__
      a a
      repeat 1, sz:.size
        display "'", `a, "'", " size: ", `sz, 10
      end repeat
    end match
  end virtual
end macro

struct STAT
  .st_dev       dq ?
  .st_ino       dq ?
  .st_nlink     dq ?
  .st_mode      dd ?
  .st_uid       dd ?
  .st_gid       dd ?
                dd ?
  .st_rdev      dq ?
  .st_size:     dq ?      ; <- Due to fgets() int parameter size and some minor optimizations,
  .st_blksize   dq ?      ; this field is declared as "no size" (offset only)
  .st_blocks    dq ?
  .st_atim      TIMESPEC
  .st_mtim      TIMESPEC
  .st_ctim      TIMESPEC
  .__glibc_reserved: rq 3
ends

struct TIMESPEC
  .tv_sec       dq ?
  .tv_nsec      dq ?
ends

proto GetExecName, qword  ; Internal function: rdi = pointer to argv[]

_bss
        tempbuff:               rb TEMPBUFF_LENGTH
        app_limit               rq 1
        fd_batt                 rq 1
        cur_time                rq 1
        conffileprops           STAT
        cur_limit:              rb LIMIT_MAX_LENGTH
        
_data
        conffile                db '/etc/batt-ctl/searchpaths.conf',0
        helpmsg                 db 'Version: %s',10
                                db 'Usage:',10,10
                                db 9,'%s -ol XX%%|disable|enable|<''any raw text''>',10
                                db 9,'%s -ql',10
                                db 9,'%s -svc',10,10
                                db 9,'-ol',9,'-> Overrides limit to provided percentage (1%% to 100%%)',10
                                db 9,9,'   to all method compatible batteries found within config file.',10
                                db 9,'-ql',9,'-> Query current limit values for paths under config file',10
                                db 9,9,'   (only successful queries are shown).',10
                                db 9,'-svc',9,'-> Invokes service mode, which reads and applies',10
                                db 9,9,'   to batteries as declared within configuration file.',10
                                db 9,9,'   Can be used to reload configuration file parameters.',10,10,0
        readmode                db 'r',0
        writemode               db 'r+',0
        enablestr               db 'enabled',0
        disablestr              db 'disabled', 0
        unknownstr              db 'unknown', 0
        version                 db '0.2',0
        
        align 4
        iterations              dd 0
        comments                dd 0
        limits                  dd 0
        searches                dd 0
        modes                   dd 0
        writecnt                dd 0
        
        flags:                  db 0
        pmode                   db 0
        
        align 16
        rawstr:                 db 'raw'
        align 16
        linearstr:              db 'linear'
        align 16
        booleanstr:             db 'boolean'
        align 16
        casemask                ddq 0DFDFDFDFDFDFDFDFDFDFDFDFDFDFDFDFh
        lfmask                  ddq  0A0A0A0A0A0A0A0A0A0A0A0A0A0A0A0Ah
        
MODE_LINEAR     = 1
MODE_BOOLEAN    = 2
MODE_RAW        = 255

FLAG_VERSION_OK     equ byte 1b     ; constants that preserve text as parameter size
FLAG_LIMIT_OK       equ byte 10b
FLAG_CLEAR_LIMIT_OK equ byte not 10b
FLAG_MODE_APP       equ byte 100b
FLAG_MODE_QUERY     equ byte 1000b
FLAG_NOT_SERVICE    equ byte 1100b
FLAG_IGNORE_WRITE   equ byte 01000000b
FLAG_CLEAR_IGNORE_WRITE equ byte 10111111b

LIMIT_MAX_LENGTH    = 1024      ; Maximum length of a LIMIT entry that will be copied to path (for raw mode)
TEMPBUFF_LENGTH     = 4096      ; Oversized to be able to handle anything, I guess

; FLAGS map:
; 
; BIT0: set if !VERSION directive has been validated;
; BIT1: set if any valid limit has been configured;
; BIT2: set if in application mode (-ol xx% command line option);
; BIT3: set if read limit mode selected;
; ...
; BIT6: ignore write flag: set when, in app mode, mode procedure has detected
;       a change in the mode that differs from app detected mode. Used to avoid
;       writes on incompatible paths.
; BIT7: (reserved for) verbose mode disable bit.
;
; 'pmode' parsing mode:
; 1 = linear (use percentage)
; 2 = boolean (use ENABLE or DISABLE)
; ...
; 255 = raw (use anything, no checks)
