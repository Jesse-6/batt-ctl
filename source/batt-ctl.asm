include 'batt-ctl.inc'

; for instance:
; ext proto geteuid, none

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


_code align 64
        Start:                  endbr64
                                __libc_start_main(&@f, [rsp+8], &rsp+16, NULL, NULL, rdx, rsp);
                                
                        align 16
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
                                or          [flags], byte 1000b ; set read limit flag
                                jmp         .app_resume
                        @@      cmp         edi, 3
                                jne         .help
                                cmp         [rdx], dword '-ol'  ; override level
                                jne         @f                  ; (application) mode
                .application:   call        CheckRoot
                                jc          .err0
                                mov         rdi, [rsi+16]
                                mov         [app_limit], rdi    ; Save pointer to status message
                                or          [flags], byte 100b  ; set application mode flag
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
                                
                                test        [flags], byte 1000b     ; check read limit bit
                                jnz         @@f                     ; 
                                fprintf(*stderr, <"Config file size '%s' is: %u bytes",\
                                    10,0>, &conffile, *conffileprops.st_size);
                                
                        @@@     xor         r15, r15                ; config file iteration loop
                                mov         [rbp], r15
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
                                test        [flags], byte 1         ; duplicated VERSION statement = error
                                jnz         .err4
                                ; ### !VERSION procedure
                                lea         rsi, [version]          ; only support version 0.1 so far
                                lea         rdi, [rbp+9]
                                lea         ecx, [r15d-9]
                                mov         [rdi+rcx-1], byte 0
                                repe        cmpsb
                                jne         .err3
                                or          [flags], byte 1         ; set version flag if OK.
                                jmp         @@b
                                
                        @@      cmp         r8, r10
                                jne         @f
                                ; ### LIMIT procedure
                                test        [flags], byte 1
                                jz          .err5
                                inc         [limits]                ; keep counting for cosmetic reason at ¹
                                test        [flags], byte 1100b     ; check application modes
                                jnz         @@b                     ; ignore if either AM=1 RL=1
                                call        HandleLimit
                                jc          .err6
                                fprintf(*stderr, "Line %u: Limit at: %s", *iterations, &rbp+6);
                                jmp         @@b
                                
                        @@      cmp         r9, r11
                                jne         @f3                     ; CAUTION! *
                                test        [flags], byte 1         ; check valid version
                                jz          .err5
                                inc         [searches]
                                ; ### SEARCH procedure
                                test        [flags], byte 1000b     ; Check read limit mode
                                jz          @f
                                ; ### Read limit mode
                                call        ReadLimit
                                jmp         @@b
                        @@      test        [flags], byte 10b       ; Check valid limit set flag
                                jz          .err7
                                call        HandleSearch
                                jc          .err8
                                test        eax, eax
                                jz          @f
                                mov         r15d, eax               ; recycling r15 register for error point
                                errno();
                                fprintf(*stderr, " Write unsuccessful(%u:%u): ", r15d, [rax]);
                                perror(NULL);
                        @@      jmp         @@b
                                
                                ; ### unrecognized configuration directive procedure
                        @@      mov         [rbp+r15-1], byte 0     ; CAUTION! * must jump here!!!
                                fprintf(*stderr, <"Configuration error at line <%u>: unrecognized: '%s'", \
                                    ": ignoring",10,0>, *iterations, rbp);
                                jmp         @@b
                                
                        @@@     fflush(*stdout);                    ; Exit of config file loop
                                fclose(rbx);
                                free(rbp);
                                
                                test        [flags], byte 1000b
                                jnz         .end
                        @@      test        [flags], byte 100b
                                jnz         @f
                                fprintf(*stdout,<"Total iterations: %u; ", \
                                    "limits found: %u; ", \
                                    "search paths: %u; ", \
                                    "commented lines: %u", \
                                    10, "Successful writes: %u",10,0>, \
                                    *iterations, *limits, *searches, *comments, *writecnt);
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
                                cmova       r8, r10
                                cmp         [limits], 1     ; ¹ issue 'limit' or 'limits' depending
                                cmova       r9, r11         ; on number of active lines at .conf file
                                fprintf(*stdout, <"Limit set manually at %s to %u batter%s ", \
                                    "during this session.",10,"To make it persistent, edit ", \
                                    "the 'LIMIT=' line%s at the aforementioned config file.",10,0>, \
                                    *app_limit, *writecnt, r8, r9);
                        @@      nop
                                
                                test        [writecnt], -1
                                jnz         .end
                                fputs(<"No changes have been made to battery charge limits. ",10, \
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
                                test        [flags], byte 100b  ; check application mode
                                cmovnz      rbp, r10
                                lea         rdi, [rbp+6]
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
                                pop         r14
                                or          [flags], byte 10b   ; set valid limit flag
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
                                fgets(&tempbuff, 127, r12);
                                test        rax, rax
                                mov         edx, 2              ; error reading file
                                cmovz       r13d, edx
                                jnz         @f
                                fclose(r12);
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
                                fseek(r12, 0, SEEK_SET);
                                test        eax, eax
                                mov         edx, 3              ; error seeking start of file
                                cmovnz      r13d, edx
                                jz          @f
                                fclose(r12);
                                jmp         .end
                        @@      fputs(&cur_limit, r12);
                                test        eax, eax
                                mov         edx, 4              ; error writing to file
                                cmovs       r13d, edx
                                jns         @f
                                fclose(r12);
                                jmp         .end
                        @@      fclose(r12);
                                movq        mm4, [cur_limit]
                                movq        mm5, r14
                                pcmpeqb     mm6, mm6
                                pcmpeqb     mm5, mm4
                                pxor        mm5, mm6
                                pand        mm4, mm5
                                movq        [tempbuff+32], mm4
                                emms
                                fprintf(*stderr, <" Write successful: new value: %s%%",10,0>, &tempbuff+32);
                                inc         [writecnt]
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
                                fopen(&rbp+7, &readmode);
                                test        rax, rax
                                jz          .err
                                mov         r12, rax        ; r12 =  current search file
                                fgets(&tempbuff, 127, r12);
                                test        rax, rax
                                jnz         @f
                                fclose(r12);
                                jmp         .err
                        @@      fclose(r12);
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
                                pop         r12
                                clc
                                ret
                .err:           stc
                                pop         r12
                                ret
                                
