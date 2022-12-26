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
atten:
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
notecon_freq2psg   := $C03C
notecon_midi2psg   := $C03F
psg_playfreq       := $C051
psg_setvol         := $C054
ym_set_atten       := $C057
psg_set_atten      := $C05A

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

    ; test frequency conversion routines
    ldx #<440
    ldy #>440
    jsr notecon_freq2psg
    cpx #<1181
    bne freqerror
    cpy #>1181
    bne freqerror

    ldx #<24411
    ldy #>24411
    jsr notecon_freq2psg
    cpx #<65533
    bne freqerror
    cpy #>65533
    bne freqerror
    bra soundtest
freqerror:
    phx
    tya
    jsr print_hex
    pla
    jsr print_hex

    jmp end

soundtest:
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
    
    lda atten
    ldx #0
    jsr ym_set_atten

    ; wait for some interrupts
    ldx #4
l1:
    wai
    dex
    bne l1

    ; play psg
    
    lda midinote
    tax
    ldy kf
    jsr notecon_midi2psg
    bcs error

    lda #0
    jsr psg_playfreq

    ; wait for some interrupts
    ldx #4
l2:
    wai
    dex
    cpx #0
    bne l2

    ; release fm
    lda #0
    jsr ym_release
    bcs error

    lda #0
    ldx #0
    jsr psg_setvol

    lda atten
    ldx #0

    jsr psg_set_atten

    ; wait for some interrupts
    ldx #8
l3:
    wai
    dex
    bne l3

    lda atten
    inc
    and #$7F
    sta atten

    jmp loop
error:
end:
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

print_hex:
    jsr byte_to_hex
    ldy X16::Reg::ROMBank
    phy
    stz X16::Reg::ROMBank
    phx
    jsr X16::Kernal::CHROUT
    pla
    jsr X16::Kernal::CHROUT
    pla
    sta X16::Reg::ROMBank

    rts

byte_to_hex: ; converts a number to two ASCII/PETSCII hex digits: input A = number to convert, output A = most sig nybble, X = least sig nybble, affects A,X
    pha

    and #$0f
    tax
    pla
    lsr
    lsr
    lsr
    lsr
    pha
    txa
    jsr xf_hexify
    tax
    pla
xf_hexify:
    cmp #10
    bcc @nothex
    adc #$66
@nothex:
    eor #%00110000
    rts
