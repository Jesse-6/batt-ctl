include 'batt-ctl.inc'

_code
        Start:                  endbr64
                                __libc_start_main(&@f, [rsp+8], &rsp+16, NULL, NULL, rdx, rsp);
                                
                        align 4
                        @@      endbr64
                                push        rbx
                                push        rbp
                                push        r15
                                
                                mov         rdx, [stdout]
                                mov         rcx, [stderr]
                                mov         rdx, [rdx]
                                mov         rcx, [rcx]
                                mov         [stdout], rdx
                                mov         [stderr], rcx
                                
                                mov         r15, rsi            ; r15 = saved argv[]
                                mov         rdx, [rsi+8]
                                cmp         edi, 2
                                jb          .help
                                jne         @f2
                                cmp         [rdx], dword '-svc' ; service mode
                                jne         @f                  ;
                                cmp         [rdx+4], byte 0
                                je          .service
                        @@      cmp         [rdx], dword '-ql'
                                jne         .help
                                or          [flags], FLAG_MODE_QUERY    ; set read limit flag
                                jmp         .app_resume
                        @@      cmp         edi, 3
                                jne         .help
                                cmp         [rdx], dword '-ol'  ; override level
                                jne         .help               ; (application) mode
                .application:   call        CheckRoot
                                jc          .err0
                                mov         rdi, [rsi+16]
                                
                                mov         r11b, MODE_RAW      ; fallback, if no detection
                                xor         al, al
                                mov         ecx, LIMIT_MAX_LENGTH
                                mov         r10, rdi
                                mov         edx, ecx
                                repne       scasb
                                sub         edx, ecx
                                
                                mov         al, '%'             ; try detect linear mode (XX%)
                                mov         ecx, 4
                                mov         rdi, r10
                                repne       scasb
                                mov         sil, MODE_LINEAR
                                cmove       r11d, esi
                                je          @@f
                                
                                mov         rax, 'ENABLE'       ; try detect boolean mode
                                mov         rbx, 'DISABLE'
                                mov         rcx, [r10]
                                mov         rdx, [r10]
                                mov         r8, 000FFFFFFFFFFFFFFh
                                mov         rsi, 0DFDFDFDFDFDFDFh
                                and         rcx, rsi
                                and         rdx, rsi            ; convert to uppercase
                                and         rcx, r8
                                cmp         rdx, rbx            ; test DISABLE
                                mov         r9b, MODE_BOOLEAN
                                cmove       r11d, r9d
                                jne         @f
                                mov         [cur_limit], dword 0A30h
                                or          [flags], byte 110b  ; LIMIT_OK + MODE_APP
                                mov         [pmode], r11b
                                jmp         .app_resume
                        @@      cmp         rcx, rax            ; test ENABLE
                                cmove       r11d, r9d
                                jne         @f
                                mov         [cur_limit], dword 0A31h
                                or          [flags], byte 110b  ; LIMIT_OK + MODE_APP
                                mov         [pmode], r11b
                                jmp         .app_resume
                                
                        @@      lea         rdi, [tempbuff]     ; raw data mode fallback
                                mov         ecx, TEMPBUFF_LENGTH
                                mov         rsi, r10
                                mov         r10, rdi
                                mov         ax, 0Ah
                        @@      movsb
                                test        [rsi], byte -1
                                jz          @f
                                dec         ecx
                                jnz         @b
                        @@      stosw
                                
                        @@@     mov         [pmode], r11b
                                mov         rdi, r10
                                mov         [app_limit], r10    ; Save pointer to status message
                                or          [flags], FLAG_MODE_APP  ; set application mode flag
                                call        HandleLimit
                                jc          .err9
                                jmp         .app_resume
                                
                        @@      nop
                                
                .help:          GetExecName(*r15);
                                fprintf(*stderr, &helpmsg, &version, rdi, rdi, rdi);
                                mov         eax, 127
                                jmp         .enderr
                                
                .service:       call        CheckRoot
                                jc          .err0
                                time(&cur_time);
                                localtime(&cur_time);
                                strftime(&tempbuff, 127, \
                                        "Starting %%s in service mode at: %Y-%m-%d %H:%M:%S%n", rax);
                                GetExecName(*r15);
                                fprintf(*stderr, &tempbuff, rdi);
                                
                .app_resume:    stat(&conffile, &conffileprops);
                                test        eax, eax
                                jnz         .err1
                                
                                malloc(*conffileprops.st_size);
                                test        rax, rax
                                jz          .err2
                                mov         rbp, rax                ; rbp = buffer for config file data
                                
                                fopen(&conffile, &readmode);
                                test        rax, rax
                                jz          .err1
                                mov         rbx, rax                ; rbx = .conf file
                                
                                test        [flags], FLAG_MODE_QUERY    ; check read limit bit
                                jnz         @@f                     ; 
                                fprintf(*stderr, <"Config file size '%s' is: %u bytes",\
                                    10,0>, &conffile, *conffileprops.st_size);
                                
                        @@@     pxor        xmm2, xmm2                ; config file iteration loop
                                movdqu      [rbp], xmm2
                                movdqu      [rbp+16], xmm2
                                fgets(rbp, *conffileprops.st_size, rbx);
                                test        rax, rax
                                jz          @@f                     ; If EOF, terminate loop
                                
                                mov         ecx, [conffileprops.st_size]
                                mov         edx, [conffileprops.st_size]
                                inc         ecx
                                mov         rdi, rbp
                                xor         al, al
                                repne       scasb
                                sub         edx, ecx
                                mov         r15d, edx               ; r15 = line length
                                inc         [iterations]
                                
                                cmp         [rbp], byte '#'         ; check if it is a commented line
                                jne         @f
                                inc         [comments]
                                jmp         @@b
                                
                        @@      cmp         [rbp], word 0Ah         ; check and skip next if empty line
                                je          @@b
                                
                        @@      mov         r10, 'LIMIT='
                                mov         r11, 'SEARCH='
                                mov         rax, '!VERSION'
                                mov         rdx, [rbp]
                                mov         r8, 0#0000FFFFFFFFFFFFh
                                mov         r9, 0#00FFFFFFFFFFFFFFh
                                and         r8, rdx
                                and         r9, rdx
                                
                        @@      cmp         rdx, rax                ; check for !VERSION directive
                                jne         @f
                                cmp         [rbp+8], byte '='
                                jne         @f
                                test        [flags], FLAG_VERSION_OK    ; duplicated VERSION statement = error
                                jnz         .err4
                                ; ### !VERSION procedure
                                lea         rsi, [version]          ; only support version 0.1 so far
                                lea         rdi, [rbp+9]
                                lea         ecx, [r15d-9]
                                mov         [rdi+rcx-1], byte 0
                                repe        cmpsb
                                jne         .err3
                                or          [flags], FLAG_VERSION_OK    ; set version flag if OK.
                                jmp         @@b
                                
                        @@      cmp         r8, r10
                                jne         @f
                                ; ### LIMIT procedure
                                test        [flags], FLAG_VERSION_OK
                                jz          .err5
                                inc         [limits]                ; keep counting for cosmetic reason at ¹
                                test        [flags], FLAG_NOT_SERVICE   ; check application modes
                                jnz         @@b                     ; ignore if either AM=1 RL=1
                                call        HandleLimit
                                jc          .err6
                                fprintf(*stderr, "Line %u: Limit: %s", *iterations, &rbp+6);
                                jmp         @@b
                                
                        @@      cmp         r9, r11
                                jne         @f3                     ; CAUTION! *
                                test        [flags], FLAG_VERSION_OK    ; check valid version
                                jz          .err5
                                inc         [searches]
                                ; ### SEARCH procedure
                                test        [flags], FLAG_MODE_QUERY    ; Check read limit mode
                                jz          @f
                                ; ### Read limit mode
                                call        ReadLimit
                                jmp         @@b
                        @@      test        [flags], FLAG_LIMIT_OK  ; Check valid limit set flag
                                jz          .err7
                                test        [flags], FLAG_IGNORE_WRITE
                                jnz         @@b
                                call        HandleSearch
                                jc          .err8
                                test        eax, eax
                                jz          @f
                                mov         r15d, eax               ; recycling r15 register for error point
                                errno();
                                fprintf(*stderr, " Write unsuccessful(%u:%u): ", r15d, [rax]);
                                perror(NULL);
                        @@      jmp         @@b
                        
                        @@      cmp         edx, 'MODE'
                                jne         @f2                     ; CAUTION **
                                cmp         [rbp+4], byte '='
                                jne         @f2                     ; CAUTION **
                                movdqa      xmm7, [rawstr]
                                movdqa      xmm6, [linearstr]
                                movdqa      xmm5, [booleanstr]
                                movdqu      xmm1, [rbp+5]
                                movdqu      xmm0, [rbp+5]
                                pand        xmm7, [casemask]
                                pand        xmm6, [casemask]
                                pand        xmm5, [casemask]
                                pcmpeqb     xmm1, [lfmask]
                                pcmpeqb     xmm4, xmm4
                                pxor        xmm1, xmm4
                                pand        xmm0, xmm1
                                pcmpeqb     xmm7, xmm0
                                pcmpeqb     xmm6, xmm0
                                pcmpeqb     xmm5, xmm0
                                pmovmskb    r8d, xmm7
                                pmovmskb    r9d, xmm6
                                pmovmskb    r10d, xmm5
                                mov         al, 0
                                mov         dl, MODE_LINEAR
                                mov         cl, MODE_BOOLEAN
                                mov         r11b, MODE_RAW
                                cmp         r10w, -1
                                lea         r10, [booleanstr]
                                cmove       eax, ecx
                                cmove       rdi, r10
                                cmp         r9w, -1
                                lea         r9, [linearstr]
                                cmove       eax, edx
                                cmove       rdi, r9
                                cmp         r8w, -1
                                lea         r8, [rawstr]
                                cmove       eax, r11d
                                cmove       rdi, r8
                                test        [flags], FLAG_MODE_APP      ; skip changing write ignore flag
                                jz          @f                          ; if not app mode
                                cmp         [pmode], al         ; only allow writes to search paths under
                                setne       dl                  ; the same limit type
                                and         [flags], FLAG_CLEAR_IGNORE_WRITE
                                shl         dl, 6
                                or          [flags], dl
                                jmp         @@b
                        @@      inc         [modes]
                                mov         [pmode], al
                                and         [flags], FLAG_CLEAR_LIMIT_OK   ; set invalid limit after change mode
                                mov         [cur_limit], byte 0     ; and erase previous data
                                test        al, -1
                                jz          .err10
                                test        [flags], FLAG_NOT_SERVICE
                                jnz         @@b
                                fprintf(*stderr, <"Data mode set to: '%s'",10,0>, rdi);
                                jmp         @@b
                                
                        @@      cmp         edx, 'LOG='             ; (**) a simple directive that outputs
                                jne         @f                      ; a log line to program output
                                ; ### LOG directive procedure
                                test        [flags], FLAG_NOT_SERVICE   ; service mode only!
                                jnz         @@b
                                fputs(&rbp+4, *stderr);
                                jmp         @@b
                                
                                ; ### unrecognized configuration directive procedure
                        @@      mov         [rbp+r15-1], byte 0
                                fprintf(*stderr, <"Line %u: unrecognized directive", \
                                    ": ignoring",10,0>, *iterations);
                                jmp         @@b
                                
                        @@@     fflush(*stdout);                    ; Exit of config file loop
                                fclose(rbx);
                                free(rbp);
                                
                                test        [flags], FLAG_MODE_QUERY
                                jnz         .end
                        @@      test        [flags], FLAG_MODE_APP
                                jnz         @f
                                fprintf(*stdout,<"Total iterations: %u; ", \
                                    "limits found: %u; ", \
                                    "search paths: %u; ", \
                                    "mode changes: %u; ", \
                                    "commented lines: %u", \
                                    10, "Successful writes: %u",10,0>, \
                                    *iterations, *limits, *searches, *modes, *comments, *writecnt);
                                jmp         @f2
                                
                .batt1          db 'y',0
                .battn          db 'ie'
                .mt1            db 's'                      ; ¹
                .nullstr        db 0                        ; ¹
                        @@      lea         r8, [.batt1]
                                lea         r9, [.nullstr]
                                lea         r10, [.battn]
                                lea         r11, [.mt1]
                                cmp         [writecnt], 1
                                cmovne      r8, r10
                                jb          @f2
                                cmp         [limits], 1     ; ¹ issue 'line' or 'lines' depending on number
                                cmova       r9, r11         ; of active LIMIT directives at .conf file
                                fprintf(*stdout, <"Limit set manually at %s to %u batter%s ", \
                                    "during this session.",10,"To make it persistent, edit ", \
                                    "the 'LIMIT=' line%s at the aforementioned config file.",10,0>, \
                                    *app_limit, *writecnt, r8, r9);
                        @@      test        [writecnt], -1
                                jnz         .end
                                
                        @@      fputs(<"No changes have been made to battery charge limits. ",10, \
                                    "Check your configuration file for valid search paths, or ",10, \
                                    "if your system support battery control methods provided ",10, \
                                    "by this application.",10,0>, *stdout);
                                mov         eax, 126
                                jmp         .enderr
                                
                .end:           xor         eax, eax
                .enderr:        pop         r15
                                pop         rbp
                                pop         rbx
                                ret
                                
                .err10:         fputs(<"Invalid mode configuration. Aborted.",10,0>, *stderr);
                                mov         eax, 11
                                jmp         .enderr
                                
                .err9:          fputs(<"Invalid parameter format or limit out of range.",10,0>, \
                                    *stderr);
                                mov         eax, 10
                                jmp         .enderr
                                
                .err8:          mov         [rbp+r15-1], byte 0
                                fprintf(*stderr, <"Invalid path at line <%u>: '%s'",10,0>, \
                                    *iterations, rbp);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 9
                                jmp         .enderr
                                
                .err7:          fputs(<"Configuration error: ", \
                                    "search statement before limit set. Aborted.",10,0>, *stderr);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 8
                                jmp         .enderr
                                
                .err6:          mov         [rbp+r15-1], byte 0
                                fprintf(*stderr, <"Invalid limit at line <%u>: '%s'",10,0>, \
                                    *iterations, rbp);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 7
                                jmp         .enderr
                                
                .err5:          fputs(<"Cannot find which version to process. Aborted.",10,0>, *stderr);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 6
                                jmp         .enderr
                                
                .err4:          fputs(<"Duplicated version statement. Aborted.",10,0>, *stderr);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 5
                                jmp         .enderr
                                
                .err3:          fputs(<"Configuration file version mismatch. Aborted.",10,0>, *stderr);
                                fclose(rbx);
                                free(rbp);
                                mov         eax, 4
                                jmp         .enderr
                                
                .err2:          fputs(<"Could not allocate memory.",10,0>, *stderr);
                                mov         eax, 3
                                jmp         .enderr
                                
                .err1:          fputs(<"Configuration file corrupted or not found.",10,0>, *stderr);
                                mov         eax, 2
                                jmp         .enderr
                                
                .err0:          fputs(<"Must be run as root!",10,0>, *stderr);
                                mov         eax, 1
                                jmp         .enderr
                                
        CheckRoot:              push        rdi         ; Preserve rsi and rdi
                                push        rsi
                                clc                     ;
                                pushfq                  ; CF is bit 0 in RFLAGS register
                                geteuid();
                                test        eax, eax
                                setnz       al          ;
                                or          [rsp], al   ;
                                popfq                   ;
                                pop         rsi
                                pop         rdi
                                ret
                                
        HandleLimit:            push        r14
                                lea         r10, [rdi-6]
                                test        [flags], FLAG_MODE_APP  ; check application mode
                                cmovnz      rbp, r10
                                lea         rdi, [rbp+6]
                                test        [pmode], -1         ; Expect a valid mode
                                jz          .err
                .mod_lin:       cmp         [pmode], MODE_LINEAR
                                jne         .mod_bool
                                mov         al, '%'             ; checking percent char
                                mov         ecx, 4
                                repne       scasb
                                jne         .err
                                errno();
                                mov         r14, rax
                                mov         [r14], dword 0
                                strtoul(&rbp+6, NULL, 10);
                                test        [r14], dword -1
                                jnz         .err
                                cmp         eax, 100
                                ja          .err
                                test        eax, eax
                                jle         .err
                                lea         rsi, [rbp+6]
                                lea         rdi, [cur_limit]
                        @@      lodsb
                                cmp         al, '%'
                                je          @f
                                stosb
                                jmp         @b
                        @@      mov         [rdi], word 0Ah
                                jmp         .end
                .mod_bool:      cmp         [pmode], MODE_BOOLEAN
                                jne         .mod_raw
                                mov         r10, ("ENABLE") + (0Ah shl 48)
                                mov         r11, ("DISABLE") + (0Ah shl 56)
                                xor         eax, eax
                                cmp         [rdi], r10          ; ENABLE
                                jne         @f
                                mov         ax, 0A31h           ; '1'\n
                                nop
                                jmp         @f2
                        @@      cmp         [rdi], r11
                                jne         .err
                                cmp         [rdi+8], byte 0
                                jne         .err
                                mov         ax, 0A30h           ; '0'\n
                                nop
                        @@      test        eax, eax            ; hardening to avoid any bug
                                jz          .err
                                mov         [cur_limit], eax
                                jmp         .end
                .mod_raw:       cmp         [pmode], MODE_RAW
                                jne         .err
                                mov         ecx, LIMIT_MAX_LENGTH
                                lea         rsi, [cur_limit]
                                xchg        rsi, rdi
                        @@      movsb                           ; Copy literal LIMIT_MAX_LENGTH
                                test        [rsi], byte -1      ; bytes from line into
                                jz          @f                  ; cur_limit buffer
                                dec         ecx
                                jz          .err
                                jmp         @b
                        @@      movsb
                                ; jmp       .end
                .end:           pop         r14
                                or          [flags], FLAG_LIMIT_OK  ; set valid limit flag
                                clc
                                ret
                .err:           pop         r14
                                stc
                                ret
                                
        HandleSearch:           push        r13
                                cmp         [rbp+7], dword '/sys'
                                jne         .err
                                cmp         [rbp+11], byte '/'
                                jne         .err
                                mov         [rbp+r15-1], byte 0
                                push        r12
                                push        r14
                                fprintf(*stderr, <"Line %u: Path: '%s'",10,0>, *iterations, &rbp+7);
                                errno();
                                xor         r13, r13
                                mov         [rax], r13d
                                fopen(&rbp+7, &writemode);
                                test        rax, rax
                                mov         edx, 1              ; error opening file
                                cmovz       r13d, edx
                                jz          .end
                                mov         r12, rax            ; r12 = searched file
                                fgets(&tempbuff, TEMPBUFF_LENGTH, r12);
                                test        rax, rax
                                mov         edx, 2              ; error reading file
                                cmovz       r13d, edx
                                jnz         @f
                                fclose(r12);
                                jmp         .end
                        @@      cmp         [pmode], MODE_LINEAR
                                jne         @f3
                                strtoul(&tempbuff, NULL, 10);   ; Sanity check read value from path
                                test        eax, eax
                                jnz         @f
                                fclose(r12);
                                mov         r13b, 3             ; Sanity check error
                                jmp         .end
                        @@      cmp         eax, 100
                                jna         @f
                                fclose(r12);
                                mov         r13b, 4
                                jmp         .end
                        @@      mov         r14, 0A0A0A0A0A0A0A0Ah
                                movq        mm1, r14
                                movq        mm0, [tempbuff]
                                pcmpeqb     mm2, mm2
                                pcmpeqb     mm1, mm0
                                pxor        mm1, mm2
                                pand        mm0, mm1
                                movq        [tempbuff+64], mm0
                                emms
                                fprintf(*stderr, <" Current value: %s%%",10,0>, &tempbuff+64);
                                jmp         @f6         ; jump fseek()
                        @@      cmp         [pmode], MODE_BOOLEAN
                                jne         @f
                                xor         al, al
                                mov         ecx, 3
                                lea         rdi, [tempbuff]
                                repne       scasb
                                jne         @f2         ; jump fclose();
                                cmp         [tempbuff], word 0A31h  ; '1'\n ENABLE
                                lea         rcx, [enablestr]
                                lea         rax, [disablestr]
                                lea         rdx, [unknownstr]
                                cmove       rdx, rcx
                                cmp         [tempbuff], word 0A30h  ; '0'\n DISABLE
                                cmove       rdx, rax
                                fprintf(*stderr, <" Current state: '%s'",10,0>, rdx);
                                jmp         @f5         ; jump fseek();
                        @@      cmp         [pmode], MODE_RAW
                                je          @f2
                        @@      fclose(r12);
                                pop         r14
                                pop         r12
                                jmp         .err
                        @@      lea         rdi, [tempbuff]
                                mov         ax, 0Ah
                                mov         ecx, TEMPBUFF_LENGTH
                                repne       scasb
                                jne         @f
                                mov         [rdi-1], ah
                        @@      fprintf(*stderr, <"Current data at path: '%s'",10,0>, &tempbuff);
                                ; jmp       @f
                        @@      fflush(r12)
                                fileno(r12);
                                ftruncate(eax, 0);
                                fseek(r12, 0, SEEK_SET);        ; sysfs does not need truncation
                                test        eax, eax
                                mov         edx, 5              ; error seeking start of file
                                cmovnz      r13d, edx
                                jz          @f
                                fclose(r12);
                                jmp         .end
                        @@      clearerr(r12);
                        @@      fputs(&cur_limit, r12);
                                test        eax, eax
                                mov         edx, 6              ; error writing to file
                                cmovs       r13d, edx
                                jns         @f
                                fclose(r12);
                                jmp         .end
                        @@      fclose(r12);
                                inc         [writecnt]
                                cmp         [pmode], MODE_LINEAR
                                jne         @f
                                movq        mm4, [cur_limit]
                                movq        mm5, r14
                                pcmpeqb     mm6, mm6
                                pcmpeqb     mm5, mm4
                                pxor        mm5, mm6
                                pand        mm4, mm5
                                movq        [tempbuff+32], mm4
                                emms
                                fprintf(*stderr, <" Write successful: new value: %s%%",10,0>, &tempbuff+32);
                                jmp         .end
                        @@      cmp         [pmode], MODE_BOOLEAN
                                jne         @f
                                lea         rax, [enablestr]
                                lea         rcx, [disablestr]
                                lea         rdx, [unknownstr]
                                cmp         [cur_limit], word 0A31h
                                cmove       rdx, rax
                                cmp         [cur_limit], word 0A30h
                                cmove       rdx, rcx
                                fprintf(*stderr, <" Write successful: new state: '%s'",10,0>, rdx);
                                jmp         .end
                        @@      cmp         [pmode], MODE_RAW
                                je          @f
                                pop         r14
                                pop         r12
                                jmp         .err
                        @@      lea         rdi, [tempbuff]
                                lea         rsi, [cur_limit]
                                mov         ecx, LIMIT_MAX_LENGTH
                        @@      movsb                           ; look ahead method
                                cmp         [rsi], byte 0Ah     ;
                                je          @f                  ;
                                dec         ecx
                                jnz         @b
                        @@      mov         [rdi], byte 0
                                fprintf(*stderr, <" Write successful: new data: '%s'",10,0>, &tempbuff);
                                ; jmp       .end
                .end:           pop         r14
                                pop         r12
                                mov         eax, r13d           ; return status
                                pop         r13
                                clc
                                ret
                .err:           pop         r13
                                stc
                                ret
                                
        ; Assuming: rdi = pointer to cmdline argv[0]
        _GetExecName:           push        r11
                                mov         r11, rdi
                                xor         al, al
                                mov         ecx, 65535      ; max cmdline length to search for
                                repne       scasb
                                not         cx
                                sub         rdi, 2
                                mov         al, '/'
                                std
                                repne       scasb
                                jne         @f
                                add         rdi, 2
                                jmp         @f2
                        @@      mov         rdi, r11        ; return pointer at rdi
                        @@      cld
                                pop         r11
                                ret

        ReadLimit:              push        r12
                                mov         [rbp+r15-1], byte 0
                                test        [pmode], byte -1
                                jz          .err
                                fopen(&rbp+7, &readmode);
                                test        rax, rax
                                jz          .err
                                mov         r12, rax        ; r12 =  current search file
                                fgets(&tempbuff, TEMPBUFF_LENGTH, r12);
                                test        rax, rax
                                jnz         @f
                                fclose(r12);
                                jmp         .err
                        @@      fclose(r12);
                                cmp         [pmode], MODE_LINEAR
                                jne         @f
                                lea         rdi, [tempbuff]
                                xor         al, al
                                mov         ecx, 5          ; '100\n' string length = 5 bytes
                                repne       scasb
                                jne         .err
                                mov         [rdi-2], al
                                strtoul(&tempbuff, NULL, 10);
                                test        eax, eax
                                jz          .err
                                cmp         eax, 100
                                ja          .err
                                fprintf(*stdout, <"Path: '%s'",10," Value: %u%%",10,0>, \
                                    &rbp+7, eax);
                                jmp         .end
                        @@      cmp         [pmode], MODE_BOOLEAN
                                jne         @f              ; ###
                                lea         rax, [enablestr]
                                lea         r10, [disablestr]
                                lea         rcx, [unknownstr]
                                cmp         [tempbuff], word 0A31h
                                cmove       rcx, rax
                                cmp         [tempbuff], word 0A30h
                                cmove       rcx, r10
                                fprintf(*stdout, <"Path: '%s'",10," State: '%s'",10,0>, &rbp+7, rcx);
                                jmp         .end
                        @@      cmp         [pmode], MODE_RAW
                                jne         .err
                                lea         rdi, [tempbuff]
                                mov         ax, 0Ah
                                mov         ecx, TEMPBUFF_LENGTH
                                repne       scasb
                                jne         @f
                                mov         [rdi-1], ah
                        @@      fprintf(*stdout, <"Path: '%s'",10," Data: '%s'",10,0>, &rbp+7, &tempbuff);
                                ; jmp       .end
                .end:           pop         r12
                                clc
                                ret
                .err:           stc
                                pop         r12
                                ret
                                
