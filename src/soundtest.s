.segment "LOADADDR"
    .word $0801
.segment "BASICSTUB"
    .word start-2
    .byte $00,$00,$9e
    .byte "2061"
    .byte $00,$00,$00
.segment "STARTUP"
start:
    jmp main
.segment "BSS"
seed:
    .res 4
midinote:
    .res 1
kf:
    .res 1
.segment "CODE"
.include "x16.inc"

ym_write           := $C000
ym_loadpatch       := $C006
ym_playnote        := $C009
ym_release         := $C012
ym_init            := $C015
psg_init           := $C018
notecon_midi2fm    := $C033
notecon_midi2psg   := $C03F

main:
    ; fiddle with RNG a bit to avoid seed state being all zero
    lda #$f7
    eor seed+3
    sta seed+2
    dec seed+3
    lda #$5a
    eor seed+2
    sta seed+1
    inc seed
    lda seed
    ora seed+1
    ora seed+2
    ora seed+3
    beq main
    ; switch to audio bank
    lda X16::Reg::ROMBank
    pha
    lda #$0a
    sta X16::Reg::ROMBank


    jsr ym_init
    jsr psg_init
    lda #0
    ldx #4
    sec
    jsr ym_loadpatch
    lda #$20
    sta midinote
loop:
    ; get a (reasonbly-pitched) note at random
    jsr rng
    lda seed
    and #$3f
    clc
    adc #$20
    sta midinote
    ; get a fractional note at random
    jsr rng
    lda seed
    and #$fc ; highest 6 bits
;    lda #0
    sta kf

    tay
    ldx midinote

    ; play fm
    jsr notecon_midi2fm
    bcs error
    lda #0
    clc
    jsr ym_playnote
    bcs error

    ; wait for some interrupts
    ldx #8
l1:
    wai
    dex
    bne l1

    ; play psg
    
    VERA_SET_ADDR Vera::VRAM_psg, 1

    lda midinote
    tax
    ldy kf
    jsr notecon_midi2psg
    bcs error
    
    stx Vera::Reg::Data0
    sty Vera::Reg::Data0
    lda #$ff ; full volume
    sta Vera::Reg::Data0
    lda #$3f ; square, 50% duty
    sta Vera::Reg::Data0

    VERA_SET_ADDR (Vera::VRAM_psg + 2), 0 ; volume register
    ; wait for some interrupts
    ldx #16
l2:
    wai
    dex
    txa
    asl
    asl
    ora #$C0
    sta Vera::Reg::Data0
    cpx #0
    bne l2

    ; release fm
    lda #0
    jsr ym_release
    bcs error

    ; release psg
    stz Vera::Reg::Data0 ; volume register from before

    ; wait for some interrupts
    ldx #8
l3:
    wai
    dex
    bne l3

    jmp loop
error:
    pla
    sta X16::Reg::ROMBank
    rts

rng:
    ; rotate the middle bytes left
    ldy seed+2 ; will move to seed+3 at the end
    lda seed+1
    sta seed+2
    ; compute seed+1 ($C5>>1 = %1100010)
    lda seed+3 ; original high byte
    lsr
    sta seed+1 ; reverse: 100011
    lsr
    lsr
    lsr
    lsr
    eor seed+1
    lsr
    eor seed+1
    eor seed+0 ; combine with original low byte
    sta seed+1
    ; compute seed+0 ($C5 = %11000101)
    lda seed+3 ; original high byte
    asl
    eor seed+3
    asl
    asl
    asl
    asl
    eor seed+3
    asl
    asl
    eor seed+3
    sty seed+3 ; finish rotating byte 2 into 3
    sta seed+0
    rts

