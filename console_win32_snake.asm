extern ExitProcess
extern WriteConsoleA
extern ReadConsoleInputA
extern SetConsoleTitleA
extern SetConsoleCursorInfo
extern SetConsoleWindowInfo
extern SetCurrentConsoleFontEx
extern SetConsoleCursorPosition
extern SetConsoleScreenBufferSize
extern GetStdHandle
extern GetCurrentConsoleFontEx
extern GetTickCount
extern GetNumberOfConsoleInputEvents

; win32 console input/output
STD_OUTPUT_HANDLE       equ -11
STD_INPUT_HANDLE        equ -10

; key code
KEY_EVENT               equ 0x0001
VK_LEFT                 equ 0x25
VK_UP                   equ 0x26
VK_RIGHT                equ 0x27
VK_DOWN                 equ 0x28
VK_ESCAPE               equ 0x1B

KEY_CODE                equ PINPUT_RECORD + INPUT_RECORD.Event + KEY_EVENT_RECORD.wVirtualKeyCode
KEY_DOWN                equ PINPUT_RECORD + INPUT_RECORD.Event + KEY_EVENT_RECORD.bKeyDown

; border constants
; window_length - border_length
BORDER_WIDTH            equ 150
BORDER_HEIGHT           equ 60
BORDER_RIGHT_DOWN       equ border + RECT.RightDown

SIZE_COORD              equ 4  ; 16bit + 16bit = 32bit = 4B
FRAME_TIME              equ 17 ; 1_000/60 = 16.666666(7) milliseconds
SIZE_FONT               equ 10

; snake consts
TAIL_LENGTH             equ 128
DEAD_TAIL_LENGTH        equ 64

; xxxxxxxxxxxoooooooo
; ^         ^
; begin     DEAD_TAIL_LENGTH + begin

SPAWN_TAIL              equ 4
STATE_LEFT              equ 0
STATE_UP                equ 1
STATE_RIGHT             equ 2
STATE_DOWN              equ 3
SPAWN_Y                 equ 4

; ooooooooooooo       H
; ^            ^      ^
; begin        end    head

BEGIN_SNAKE_TAIL        equ snake + SNAKE.tail
END_SNAKE_TAIL          equ BEGIN_SNAKE_TAIL + TAIL_LENGTH * SIZE_COORD
SNAKE_STATE             equ snake + SNAKE.state
HEAD                    equ snake + SNAKE.head

; eat constants
EAT_LENGTH              equ 100
BEGIN_EAT               equ ECOORD
END_EAT                 equ ECOORD + EAT_LENGTH * SIZE_COORD

; rand constants "MMIX by Donald Knuth"
A                       equ 6364136223846793005
C                       equ 1442695040888963407

global start

section .bss
        struc KEY_EVENT_RECORD
          .bKeyDown           resd 1     ; win32 BOOL 32 bit
          .wRepeatCount       resw 1
          .wVirtualKeyCode    resw 1
          .wVirtualScanCode   resw 1
          .uChar              resb 1
          .dwControlKeyState  resd 1
        endstruc

        struc INPUT_RECORD
          .EventType resw 1
          .Padding   resw 1      ; Padding
          .Event     reso 1      ; MOUSE_EVENT_RECORD 128 bit
        endstruc

        struc COORD
          .X resw 1
          .Y resw 1
        endstruc

        struc RECT
          .LeftUp      resd 1
          .RightDown   resd 1
        endstruc

        struc SNAKE
          .state  resb 1
          .head   resd 1
          .tail   resd TAIL_LENGTH
        endstruc

        struc CONSOLE_FONT_INFOEX
          .cbSize                      resd 1
          .nFont                       resd 1
          .dwFontSize                  resd 1
          .FontFamily                  resd 1
          .FontWeight                  resd 1
          .FaceName           times 32 resw 1  ; LF_FACESIZE = 32
        endstruc

section .data
        head               db 254, 0
        empty              db 176, 0
        eat                db 35, 0
        title              db 'Snake!', 0
        stdOut             dq 0
        stdIn              dq 0
        buffer             dq 0
        next_rand          dq 1
        offset_dead_tail   dq DEAD_TAIL_LENGTH * SIZE_COORD           ; len_dead_tail * SIZE_COORD < TAIL_LENGTH

        PINPUT_RECORD istruc INPUT_RECORD
          at INPUT_RECORD.EventType,  dw 0
          at INPUT_RECORD.Padding,    dw 0
          at INPUT_RECORD.Event,      dw 0
        iend

        ECOORD      times EAT_LENGTH dd 0

        snake istruc SNAKE
          at SNAKE.state,                  db STATE_RIGHT
          at SNAKE.head,                   dw TAIL_LENGTH - DEAD_TAIL_LENGTH + 1, SPAWN_Y
          at SNAKE.tail, times TAIL_LENGTH dd 0
        iend

        border istruc RECT
          at RECT.LeftUp,      dw 0, 0
          at RECT.RightDown,   dw BORDER_WIDTH, BORDER_HEIGHT
        iend

        border_buffer          dw BORDER_WIDTH + 1, BORDER_HEIGHT + 1

section text USE64
start:
        %define shadow_space 28h
        sub     rsp,    shadow_space                      ; Microsoft x64 calling convention "shadow space"

        mov     rcx,    STD_OUTPUT_HANDLE
        call    GetStdHandle
        mov     [stdOut],    rax                          ; get console output handle

        mov     rcx,    STD_INPUT_HANDLE                  ; get console input handle
        call    GetStdHandle
        mov     [stdIn],    rax

        mov     rcx,    title
        call    SetConsoleTitleA                          ; set title

        sub     rsp,    84
        mov     dword [rsp + CONSOLE_FONT_INFOEX.cbSize],    84 ; sizeof(CONSOLE_FONT_INFOEX)
        mov     rcx,    [stdOut]
        mov     rdx,    0                                 ; false, font information is retrieved for the current window size
        mov     r8,     rsp
        call    GetCurrentConsoleFontEx                   ; get current font

        mov     word [rsp + CONSOLE_FONT_INFOEX.dwFontSize + COORD.X],    SIZE_FONT  ; set font size
        mov     word [rsp + CONSOLE_FONT_INFOEX.dwFontSize + COORD.Y],    SIZE_FONT  ; set font size

        mov     rcx,    [stdOut]
        mov     rdx,    0
        mov     r8,     rsp
        call    SetCurrentConsoleFontEx                   ; set font
        add     rsp,    84

        mov     rcx,    [stdOut]
        mov     rdx,    [border_buffer]
        call    SetConsoleScreenBufferSize                ; set screen buffer >= BORDER_RIGHT_DOWN coord
        ; cmp     rax,    0
        ; je      quit

        mov     rcx,    [stdOut]
        mov     edx,    1                                 ; true - coordinates specify the new upper-left and lower-right corners
        mov     r8,     border
        call    SetConsoleWindowInfo                      ; BOOL SetConsoleWindowInfo(HANDLE hConsoleOutput, BOOL bAbsolute, const SMALL_RECT *lpConsoleWindow);
        ; cmp     rax,    0
        ; je      quit

        push    dword 0                                   ; push CONSOLE_CURSOR_INFO visible = false
        push    dword 64                                  ; push size CONSOLE_CURSOR_INFO
        mov     rcx,    [stdOut]
        mov     rdx,    rsp
        call    SetConsoleCursorInfo                      ; BOOL SetConsoleCursorInfo(HANDLE hConsoleOutput, const CONSOLE_CURSOR_INFO *lpConsoleCursorInfo);
        add     rsp,    8

        call    time
        mov     rcx,    rax
        call    srand

        call    init_eat
        call    init_snake

        ; stack:
        ;   start_t
        ;   t
        call    time
        push    rax     ; start_t
        push    qword 0 ; t
    .app_loop:
        call    time    ; end_t in rax
        pop     rdx     ; t
        pop     rcx     ; start_t
        mov     r8,     rax

        cmp     rax,    rcx
        jl      quit

        sub     rax,    rcx
        add     rdx,    rax
        push    r8      ; start_t = end_t
        push    rdx     ; t

        call    input
      .inner_app_loop:
        mov     rax,    [rsp]
        cmp     rax,    FRAME_TIME
        jl      .end_inner_app_loop
        pop     rax
        sub     rax,    FRAME_TIME
        push    rax

        call    update_eat
        call    update_tail
        call    update_head
        jmp     .inner_app_loop
      .end_inner_app_loop:

        jmp     .app_loop

    quit:
        xor     rcx,    rcx         ; UINT uExitCode = 0
        call    ExitProcess         ; ExitProcess(uExitCode)

input: ; void -> pollute: rcx, rdx, r8, r9
        sub     rsp,    shadow_space           ; Microsoft x64 calling convention "shadow space"

        mov     rcx,    [stdIn]
        mov     rdx,    buffer
        call    GetNumberOfConsoleInputEvents

        cmp     qword [buffer],    0           ; ReadConsoleInputA waiting function -> if input buffer clear ignore ReadConsoleInputA
        je      .end

        mov     rcx,    [stdIn]
        mov     rdx,    PINPUT_RECORD
        mov     r8,     1
        mov     r9,     buffer
        call    ReadConsoleInputA              ; waiting function
        cmp     word [PINPUT_RECORD + INPUT_RECORD.EventType], KEY_EVENT
        jne      .end

    .key_input:
        cmp     dword [KEY_DOWN],    1
        jne     .end
        cmp     word [KEY_CODE],    VK_LEFT
        je      .left_key_input
        cmp     word [KEY_CODE],    VK_UP
        je      .up_key_input
        cmp     word [KEY_CODE],    VK_RIGHT
        je      .right_key_input
        cmp     word [KEY_CODE],    VK_DOWN
        je      .down_key_input
        cmp     word [KEY_CODE],    VK_ESCAPE
        je      quit
        jmp     .end

    .left_key_input:
        cmp     byte [SNAKE_STATE],    STATE_RIGHT
        je      .end
        mov     byte [SNAKE_STATE],    STATE_LEFT
        jmp     .end
    .up_key_input:
        cmp     byte [SNAKE_STATE],    STATE_DOWN
        je      .end
        mov     byte [SNAKE_STATE],    STATE_UP
        jmp     .end
    .right_key_input:
        cmp     byte [SNAKE_STATE],    STATE_LEFT
        je      .end
        mov     byte [SNAKE_STATE],    STATE_RIGHT
        jmp     .end
    .down_key_input:
        cmp     byte [SNAKE_STATE],    STATE_UP
        je      .end
        mov     byte [SNAKE_STATE],    STATE_DOWN
        jmp     .end

    .end:
        add     rsp,    shadow_space           ; Microsoft x64 calling convention "shadow space"
        ret

update_head: ; void -> pollute: rcx, rdx
        ; draw head
        mov     r8,    HEAD
        mov     r9,    head
        call    put_char

        xor     rcx,    rcx
        xor     rdx,    rdx
        cmp     byte [SNAKE_STATE],    STATE_LEFT
        je      .state_left
        cmp     byte [SNAKE_STATE],    STATE_UP
        je      .state_up
        cmp     byte [SNAKE_STATE],    STATE_RIGHT
        je      .state_right
        cmp     byte [SNAKE_STATE],    STATE_DOWN
        je      .state_down

    .state_left:
        mov     cx,    [HEAD + COORD.X]
        mov     dx,    [border + RECT.LeftUp + COORD.X]
        cmp     dx,    cx
        jge     .to_right_side
        dec     word [HEAD + COORD.X]
        jmp     .end
      .to_right_side:
        mov     cx,    word [BORDER_RIGHT_DOWN + COORD.X]
        mov     word [HEAD + COORD.X],    cx
        jmp     .end

    .state_up:
        mov     cx,    [HEAD + COORD.Y]
        mov     dx,    [border + RECT.LeftUp + COORD.Y]
        cmp     dx,    cx
        jge     .to_down_side
        dec     word [HEAD + COORD.Y]
        jmp     .end
      .to_down_side:
        mov     cx,    word [BORDER_RIGHT_DOWN + COORD.Y]
        mov     word [HEAD + COORD.Y],    cx
        jmp     .end

    .state_right:
        mov     cx,    [HEAD + COORD.X]
        mov     dx,    [BORDER_RIGHT_DOWN + COORD.X]
        cmp     dx,    cx
        jle     .to_left_side
        inc     word [HEAD + COORD.X]
        jmp     .end
      .to_left_side:
        mov     cx,    word [border + RECT.LeftUp + COORD.X]
        mov     word [HEAD + COORD.X],    cx
        jmp     .end

    .state_down:
        mov     cx,    [HEAD + COORD.Y]
        mov     dx,    [BORDER_RIGHT_DOWN + COORD.Y]
        cmp     dx,    cx
        jle     .to_up_side
        inc     word [HEAD + COORD.Y]
        jmp     .end
      .to_up_side:
        mov     cx,    word [border + RECT.LeftUp + COORD.Y]
        mov     word [HEAD + COORD.Y],    cx
        jmp     .end
    .end:
        ret

update_tail: ; void -> pollute: rcx, rdx, r8, r9 + pollute intersect_tail, put_char
        ; draw snake trace
        mov     r8,    BEGIN_SNAKE_TAIL
        add     r8,    [offset_dead_tail]
        mov     r9,    empty
        call    put_char

        call    intersect_tail ; rax: true/false, rcx: address intersect block
        cmp     rax,    0
        je      .update
        mov     rdx,    BEGIN_SNAKE_TAIL
        mov     rax,    rcx
        sub     rax,    rdx
        add     rdx,    [offset_dead_tail]
        mov     [offset_dead_tail],    rax
    .delete:
        cmp     rcx,    rdx
        je      .update

        ; draw snake trace where dead snake
        push    rcx
        push    rdx
        mov     r8,    rdx
        mov     r9,    empty
        call    put_char
        pop     rdx
        pop     rcx

        add     rdx,    SIZE_COORD
        jmp     .delete
    .update:
        mov    rcx,    BEGIN_SNAKE_TAIL
    .loop:
        cmp    rcx,    END_SNAKE_TAIL - SIZE_COORD
        je     .end
        mov    rdx,    [rcx + SIZE_COORD]
        mov    [rcx],    rdx
        add    rcx,    SIZE_COORD
        jmp    .loop
    .end:
        mov    edx,    [HEAD]
        mov    [rcx],    edx
        ret

update_eat: ; void -> pollute: rcx, rdx, r8, r9 + pollute generate_eat
        mov    r8,     BEGIN_EAT
    .loop:
        cmp    r8,     END_EAT
        je     .end
        mov    r9,     r8
        add    r8,     SIZE_COORD
        xor    rcx,    rcx
        mov    ecx,    [r9]
        cmp    ecx,    [HEAD]
        jne    .loop
        mov    rdx,    r9
        push   r8
        call   generate_eat
        pop    r8
        mov    rax,    [offset_dead_tail]
        cmp    rax,    SPAWN_TAIL * SIZE_COORD
        jle     .loop
        sub    rax,    SPAWN_TAIL * SIZE_COORD
        mov    [offset_dead_tail],    rax
        jmp    .loop
    .end:
        ret

put_char: ; r8: &COORD, r9: &char -> pollute: rcx, rdx, r8, r9 + ?pollute SetConsoleCursorPosition, WriteConsoleA
        push    r9
        mov     rcx,    [stdOut]
        mov     rdx,    [r8]
        call    SetConsoleCursorPosition
        pop     r9
        mov     rcx,    [stdOut]
        mov     rdx,    r9
        mov     r8,     1
        mov     r9,     buffer
        call    WriteConsoleA
        ret

intersect_tail: ; void -> rax: bool, rcx: &intersect_block
        mov    rcx,    BEGIN_SNAKE_TAIL
        add    rcx,    [offset_dead_tail]
    .loop:
        cmp    rcx,    END_SNAKE_TAIL
        je     .end
        mov    rax,    [rcx]
        cmp    eax,    [HEAD]
        je     .intersect
        add    rcx,    SIZE_COORD
        jmp    .loop
    .intersect:
        mov    rax,    1
        ret
    .end:
        mov    rax,    0
        ret

generate_eat: ; rdx: &ECOORD -> pollute: rcx, r8, r9 + pollute rand, put_char
        ; random x
        xor    rcx,    rcx
        mov    cx,     [BORDER_RIGHT_DOWN + COORD.X]
        sub    cx,     [border + RECT.LeftUp + COORD.X]
        push   rdx
        call   rand
        pop    rdx
        add    ax,     [border + RECT.LeftUp + COORD.X]
        mov    word [rdx + COORD.X],    ax
        ; random y
        xor    rcx,    rcx
        mov    cx,     [BORDER_RIGHT_DOWN + COORD.Y]
        sub    cx,     [border + RECT.LeftUp + COORD.Y]
        push   rdx
        call   rand
        pop    rdx
        add    ax,     [border + RECT.LeftUp + COORD.Y]
        mov    word [rdx + COORD.Y],    ax
        ; draw eat
        mov    r8,     rdx
        mov    r9,     eat
        call   put_char
        ret

srand: ; rcx: u64
        mov    qword [next_rand],    rcx
        ret

rand: ; rcx: mod -> rax: random; pollute: rdx, r8
        mov    rax,    [next_rand]    ; rax = next_rand
        mov    r8,     A
        mul    r8                     ; rax = next_rand * A
        mov    r8,     C
        add    rax,    r8             ; rax = next_rand * A + C
        mov    [next_rand],    rax    ; next_rand = next_rand * A + C
        xor    rdx,    rdx
        div    rcx                    ; rax = rax / rcx, rdx = rax % rcx
        mov    rax,    rdx            ; rax = rax % rcx
        ret

time: ; void -> rax: time in milliseconds; pollute: ?pollute GetTickCount
        call    GetTickCount
        ret

init_snake: ; void -> pollute: rax, rcx
        movsxd  rcx,    [border + RECT.LeftUp + COORD.X]
        mov     rax,    BEGIN_SNAKE_TAIL
        add     rax,    [offset_dead_tail]
    .loop:
        cmp     rax,    END_SNAKE_TAIL
        je      .end
        mov     word [rax + COORD.X],    cx
        mov     word [rax + COORD.Y],    SPAWN_Y

        push    rcx
        push    rax
        mov     r8,    rax
        mov     r9,    head
        call    put_char
        pop     rax
        pop     rcx

        add     rax,    SIZE_COORD
        inc     rcx
        jmp     .loop
    .end:
        ret

init_eat:  ; void -> pollute: rdx + pollute generate_eat
        mov    rdx,     BEGIN_EAT
    .loop:
        cmp    rdx,     END_EAT
        je     .end
        push   rdx
        call   generate_eat
        pop    rdx
        add    rdx,     SIZE_COORD
        jmp    .loop
    .end:
        ret