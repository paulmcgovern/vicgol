;
;     ____                               __   _     _  __
;    / ___| __ _ _ __ ___   ___    ___  / _| | |   (_)/ _| ___ 
;   | |  _ / _` | '_ ` _ \ / _ \  / _ \| |_  | |   | | |_ / _ \
;   | |_| | (_| | | | | | |  __/ | (_) |  _| | |___| |  _|  __/
;    \____|\__,_|_| |_| |_|\___|  \___/|_|   |_____|_|_|  \___|
;
; For VIC-20, compile with cl65
;
; A live cell dies if it has fewer than two live neighbors.
; A live cell with two or three live neighbors lives on to the next generation.
; A live cell with more than three live neighbors dies.
; A dead cell will be brought back to life if it has exactly three live neighbors.
;
; Uses kernal RND, GETIN, and CHROUT functions.

.debuginfo +            ; Genreate label file
.macpack cbm            ; Enable scrcode macro (ASCII to PETSKII)

BORDER_REG = $900F      ; Screen background and border register
BLACK_BLUE = $0E        ; Screen: black border and blue background
CHR_ALIVE = $51         ; Solid circle
CHR_SPACE = $20         ; Space
COLOR_END = $97FA       ; End of color memory
COLOR_MEM = $9600       ; Start of color memory
COLOR_WHITE=$01         ; Color code
FAC1=$61                ; Floating Pt Acc. Used for RND() result
GAME_AREA_START = $1E16 ; Start of second row of screen
GAME_AREA_END = $1FE3   ; End of second to last row of screen
KERN_CHROUT = $FFD2     ; Kernel function to output a character
KERN_GETIN = $FFE4      ; Kernal function to get keyboard input
KERN_RND = $E094        ; Kernel random number generator
RND_SEED=$8B            ; Seed address for RND(). Floating pt value $8B-$8F
SCREEN = $1E00          ; Start of screen memory
SCREEN_END = $1FF9      ; Last address of screen memory
SCREEN_COLS = $16       ; Number of column
SCREEN_HEIGHT = $17     ; Default screen height, in bytes: 23
SCREEN_WIDTH = $16      ; Default screen width, in bytes: 22
TIMER1 = $9124          ; Timer low byte

;  *0061     97       Accum#1: Exponent
;*0062-0065  98-101   Accum#1: Mantissa
;  *0066     102      Accum#1: Sign


.segment "RODATA"

; Text strings are terminated with '@', PETSCII 0.
TXT_TITLE:   scrcode "game of life@"
TXT_ANY_KEY: scrcode "press any key@"

; Index values for looking up cell neighbours, clockwise from NW
NEIGHBOUR_IDX:  .byte 0, 1, 2, 22, 24, 44, 45, 46

; Outcomes: high four bits: alive/dead, low bits: number of neighbours
OUTCOMES: .byte %01010010           ; Alive and two neighbours
          .byte %01010011           ; Alive and three neighbours
          .byte %00100011           ; Dead and three neighbours

.segment "ZEROPAGE"

WorldPtr:   .res 2                  ; Pointer to next iteration of world
CellPtr:    .res 2                  ; Pointer to cell of interest
counter:    .res 1                  ; Byte counter
num1lo:     .res 1                  ; For 16 bit addition and subtraction
num1hi:     .res 1
num2lo:     .res 1
num2hi:     .res 1	
reslo:      .res 1
reshi:      .res 1

.segment "STARTUP"
.segment "LOWCODE"
.segment "INIT"
.segment "GRCHARS"
.segment "CODE"


main:
            lda #BLACK_BLUE         ; Setup background and border
            sta BORDER_REG

            jsr ClearScreen
            jsr TitleScreen         ; Print title screen

@any_key: 
            jsr KERN_GETIN          ; A is zero if no input read
            beq @any_key

setup:
            jsr ResetPointers       ; Set up pointers

            jsr ClearScreen

            lda #<COLOR_MEM         ; Set up for FG color fill in game area
            sta num1lo
            lda #>COLOR_MEM
            sta num1hi
            lda #<COLOR_END
            sta num2lo
            lda #>COLOR_END 
            sta num2hi
            lda #COLOR_WHITE
            jsr BlockFill           ; Set FG color on whole screen

            lda TIMER1              ; Throw some entropy into the random seed
            sta RND_SEED + 1
            sta RND_SEED + 2

            lda #$80                ; Set up RND seed $8B-$8F (exponent)
            sta RND_SEED
            lda $0
            sta RND_SEED + 1        ; Set up RND seed (mantissa)

            jsr Populate            ; Populate world with random cells
           ; jsr Glider
            jsr WrapCells

            jsr ResetPointers

            ldx #SCREEN_COLS
aaa:

            lda #$20
            lda #$0
            sta COLOR_MEM - 1, X
            sta COLOR_MEM + 483, X
            dex
            bne aaa

advance:
            jsr KERN_GETIN          ; Press any character to restart
            bne setup               ; A is zero if no input read

            ldy #$0

@updateLoopX:
            jsr CountNeighbours     ; Result saved in 'counter'

            ldy #$0
            lda counter

            lda (CellPtr), Y        ; Construct lookup flag. Get cell high bits
            and #$F0
            ora counter
            sta counter             ; resue counter

            ldx #$03                ; Three possible outocmes to test

@outcomeLoop:
            lda OUTCOMES - 1, X
            cmp counter
            beq @setAlive
            dex
            bne @outcomeLoop
            lda #CHR_SPACE
            jmp @updateWorld
@setAlive:
            lda #CHR_ALIVE
@updateWorld:
            sta (WorldPtr), Y

            lda #$01          ; Set up pointer increment
            sta num2lo
            lda #$00
            sta num2hi

            lda WorldPtr  ; Advance world pointer
            sta num1lo
            lda WorldPtr + 1
            sta num1hi
            jsr Add16
            lda reslo
            sta WorldPtr
            lda reshi
            sta WorldPtr + 1

            lda CellPtr  ; Advance cell of interest pointer
            sta num1lo
            lda CellPtr + 1
            sta num1hi
            jsr Add16
            lda reslo
            sta CellPtr
            lda reshi
            sta CellPtr + 1

            lda CellPtr + 1 ; Assess cell against end of screen memory
            cmp #>GAME_AREA_END
            bcc @updateLoopX ; ptr < end
            lda CellPtr 
            cmp #<GAME_AREA_END + 1
            bcc @updateLoopX

            jsr ResetPointers


            jsr CopyWorldToScreen     ; Copy next world iteration to screen

            jsr WrapCells

            jmp advance

;Glider:

;        lda #$51
;        sta SCREEN + 100
;        sta SCREEN + 101
;        sta SCREEN + 102
;        sta SCREEN + 102 - 22
 ;       sta SCREEN + 102 - 22 - 23
;        rts
; Copy block of memory to screen, one loop with two read/writes with offset.
CopyWorldToScreen:

            ldx #$E7 ; Half of world space
@loop:
            lda World - 1, X
            ;lda #$01
            sta GAME_AREA_START - 1, X


            lda World - 1 + $E7, X
            ;lda #$02
            sta GAME_AREA_START - 1 + $E7, X

            dex
            bne @loop
;ss:jmp ss
            rts

;;;;;;-;-;-;-;-;-;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; Calls kernal function RND() to get spacing between live cells
Populate:
            lda #<GAME_AREA_START        ; Set up start and end of screen space.
            sta num1lo            ; num1lo will be the pointer used for drawing, 
            lda #>GAME_AREA_START       ; and will be advanced unil it reaches the value
            sta num1hi            ; that is set in num2lo.
            lda #<GAME_AREA_END
            sta num2lo
            lda #>GAME_AREA_END
            sta num2hi

            ldy #$0
            lda #$0
            sta counter
@loop:
            lda counter
            bne @noop

            lda #$01              ; $1: Flag to get seed from RND_SEED
            jsr KERN_RND          ; Kernnal RND(). Result in FAC1
            lda FAC1 + 2          ; Read from within FAC1 (seems to give decent result)
            and #$07              ; Keep low bits. Adjust here for density of initial living cells

            sta counter

            lda #CHR_ALIVE
            ldy #$0
            sta (num1lo), Y

@noop:
            lda counter
            beq @incPtr
            dec counter
@incPtr:
            inc num1lo
            lda num1lo
            bne @comp

            inc num1hi

@comp:
            jsr Sub16             ; Check poiner against end value
            lda reslo
            beq @compHi
            jmp @loop
@compHi:
            lda reshi
            bne @loop

            rts

WrapCells:

;            ldx #SCREEN_COLS 
;@aaa:
;            lda #$1
;            sta GAME_AREA_START -1 , X
;          sta GAME_AREA_END, X
;          dex
;          bne @aaa
;          ldx #SCREEN_COLS 
;          lda #$02
;@bbb:
;            sta $1FCE -1, X
;           sta SCREEN -1, x
;           dex
;           bne @bbb
;ss: jmp ss
            ldx #SCREEN_COLS 
@loopFirst:
            lda GAME_AREA_START -1 , X
            sta GAME_AREA_END, X
            dex
            bne @loopFirst

            ldx #SCREEN_COLS 
@loopLast:
            lda $1FCE -1 , X
            sta SCREEN -1, x
            dex
            bne @loopLast

            rts

; Print tile screen, centered text
TitleScreen:
            lda #<TXT_TITLE         ; Pointer to text in num1lo/num1hi
            sta num1lo
            lda #>TXT_TITLE
            sta num1hi
            lda #<(SCREEN + (SCREEN_WIDTH * 4) + ((SCREEN_WIDTH - 12 ) / 2))
            sta num2lo
            lda #>(SCREEN + (SCREEN_WIDTH * 4) + ((SCREEN_WIDTH - 12) / 2))
            sta num2hi
            jsr PrintString

            lda #<TXT_ANY_KEY
            sta num1lo
            lda #>TXT_ANY_KEY
            sta num1hi
            lda #<(SCREEN + (SCREEN_WIDTH * 8) + ((SCREEN_WIDTH - 13 ) / 2))
            sta num2lo
            lda #>(SCREEN + (SCREEN_WIDTH * 8) + ((SCREEN_WIDTH - 13 ) / 2))
            sta num2hi
            jsr PrintString

; Print a zero-teminated string to screen, up to 254 characters.
; Text pointer given in num1lo, screen pointer in num2lo
PrintString:
            ldy #$0
@loopChr:
            lda (num1lo), Y
            beq @end
            sta (num2lo), Y
            iny
            jmp @loopChr
@end:
            rts


; Expect start pointer in num1lo/num1hi, end address in num2lo/num2hi.
; Value in A gets written to num2lo pointer
BlockFill:

            ldy #$0
@fillA:
            ldx num1lo
            cpx num2lo
            bne @fillB
            ldx num1hi
            cpx num2hi
            bne @fillB
            rts
@fillB:
            sta (num1lo), Y
            inc num1lo
            bne @fillA
            inc num1hi
            bne @fillA
            rts

; Clear the screen
ClearScreen:
          ;  pha
            lda #$93
            jsr KERN_CHROUT
          ;  pla
            rts


; https://codebase64.org/doku.php?id=base:16bit_addition_and_subtraction
; 16 bit add
Add16: 
            clc				; clear carry
	          lda num1lo
	          adc num2lo
	          sta reslo			; store sum of LSBs
	          lda num1hi
	          adc num2hi			; add the MSBs using carry from
	          sta reshi			; the previous calculation
	          rts

;subtracts number 2 from number 1 and writes result out
; 16 bit subtraction
Sub16:
        	  sec				; set carry for borrow purpose
        	  lda num1lo
        	  sbc num2lo			; perform subtraction on the LSBs
        	  sta reslo
        	  lda num1hi			; do the same for the MSBs, with carry
        	  sbc num2hi			; set according to the previous result
        	  sta reshi
        	  rts

; Pointers: reset them thusly
ResetPointers:
	          lda #<World             ; Pointer to start of world
            sta WorldPtr
            lda #>World
            sta WorldPtr + 1

            lda #<GAME_AREA_START
            sta CellPtr
            lda #>GAME_AREA_START
            sta CellPtr + 1

            rts

; Count the neighbours of a cell of interest.
; Find the northwest neighbour, iterte by indexes
; defined in NEIGHBOUR_IDX
; Uses A, Y, num1lo, num1hi, num2lo, num2hi, reslo, reshi
; CellPtr: Pointer to cell of interest
; counter: Sum of neighbour count 
; TODO: don't count offscreen (upper and lower), wrap the count
CountNeighbours:

            ; Find upper left (NW) neighbour: cell of interest position minus 23
            lda CellPtr
            sta num1lo
            lda CellPtr + 1
            sta num1hi

            lda #SCREEN_COLS + 1    ; Relative posn from cell of interest to NW neighbour
            sta num2lo
            lda #0
            sta num2hi
            jsr Sub16               ; New pointer in reslo is NW neighbour

            lda #0
            ldy #0
            sta counter

            ldx #$08                ; 8 neighbours to lookup

@neighbourLoop:                     ; Iterate through all neighbours
            lda NEIGHBOUR_IDX - 1, X
            tay
            lda #CHR_SPACE          ; Is neighbour occupied?
            cmp (reslo), Y          ; If yes increment counter
            beq @isEmpty
            inc counter
@isEmpty:
            dex
            bne @neighbourLoop

            rts

.segment "DATA"

World: .res 462                    ; The world is 22 x 21, or 462 bytes



