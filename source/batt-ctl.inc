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
        tempbuff:               rb 128
        app_limit               rq 1
        fd_batt                 rq 1
        cur_time                rq 1
        conffileprops           STAT
        cur_limit:              rb 8
        
_data
        conffile                db '/etc/batt-ctl/searchpaths.conf',0
        helpmsg                 db 'Version: %s',10
                                db 'Usage:',10,10
                                db 9,'%s -ol XX%%',10
                                db 9,'%s -ql',10
                                db 9,'%s -svc',10,10
                                db 9,'-ol',9,'-> Overrides limit to provided percentage (1%% to 100%%)',10
                                db 9,9,'   to all batteries found within config file.',10
                                db 9,'-ql',9,'-> Query current limit values for paths under config file',10
                                db 9,9,'   (only successful queries are shown).',10
                                db 9,'-svc',9,'-> Invokes service mode, which reads and applies',10
                                db 9,9,'   to batteries as declared within configuration file.',10
                                db 9,9,'   Can be used to reload configuration file parameters.',10,10,0
        readmode                db 'r',0
        writemode               db 'r+',0
        version                 db '0.1',0
        iterations              dd 0
        comments                dd 0
        limits                  dd 0
        searches                dd 0
        writecnt                dd 0
        flags:                  db 0
        
; FLAGS map:
; 
; BIT0: set if !VERSION directive has been validated;
; BIT1: set if any valid limit has been configured;
; BIT2: set if in application mode (-ol xx% command line option);
; BIT3: set if read limit mode selected;
;
