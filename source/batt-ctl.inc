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
  .st_size:     dq ?
  .st_blksize   dq ?
  .st_blocks    dq ?
  .st_atim       TIMESPEC
  .st_mtim       TIMESPEC
  .st_ctim       TIMESPEC
  .__glibc_reserved: rq 3
ends

struct TIMESPEC
  .tv_sec       dq ?
  .tv_nsec      dq ?
ends

struct TIMEVAL
  .tv_sec       dq ?
  .tv_usec      dq ?
ends


proto GetExecName, qword
