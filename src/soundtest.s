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
patch:
    .res 1
tmp:
    .res 2
.segment "CODE"
testpat:
    .byte "TEST.PAT"
strstruct:
    .byte 84
    .word playstring
playstring:
    .byte "S0O3CDEFKGAB"
    .byte "P2KC4.C8F4S1"
    .byte ">RC4.C8F4GAG"
    .byte "V63CV58CV40C"
    .byte ">RC4.C8F4GAG"
    .byte "S1C4.C8F4GAG"
    .byte "S0C4.C8F4GAG"
    

.include "x16.inc"

.include "../../x16-rom/inc/audio.inc"

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
stp
    ; test frequency conversion routines
    ldx #<440
    ldy #>440
    jsr notecon_freq2psg
    cpx #<1181
    bne freqerror
    cpy #>1181
    bne freqerror
stp
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

convtest:
    ; convert some values back and forth
    stz midinote
    stz kf
convloop:
    lda midinote
    jsr print_hex
    jsr print_space
    lda kf
    jsr print_hex
    jsr print_space

    ldx midinote
    ldy kf
    jsr notecon_midi2psg

    phy
    phx
    tya
    jsr print_hex
    pla
    pha
    jsr print_hex
    jsr print_space

    plx
    ply
    jsr notecon_psg2midi

    phy
    txa
    jsr print_hex
    jsr print_space
    pla
    jsr print_hex
    jsr print_newline
    
    lda kf
    clc
    adc #128
    sta kf
    bne convloop
    inc midinote
    lda midinote
    bpl convloop

soundtest:
    jsr ym_init
    jsr psg_init
    stz patch
    lda #0
    ldx patch
    sec
    jsr ym_loadpatch
    lda #$18
    sta midinote
    lda #0
    ldx #1
    jsr ym_setpan
    lda #1
    ldx #2
    jsr ym_setpan
    lda #2
    ldx #8
    ldy #2
    jsr X16::Kernal::SETLFS

    lda #8
    ldx #<testpat
    ldy #>testpat
    jsr X16::Kernal::SETNAM

    jsr X16::Kernal::OPEN

;    lda #2
;    ldx #2
;    jsr ym_loadpatchlfn

    lda #2
    jsr X16::Kernal::CLOSE

    lda #0
    jsr bas_playstringvoice

    lda #84
    ldx #<playstring
    ldy #>playstring

    jsr bas_psgplaystring

    stp
    lda #0
    ldx #1
    jsr ym_setpan
    lda #1
    ldx #2
    jsr ym_setpan

loop:
    ; get a (reasonbly-pitched) note at random
;    jsr rng
;    lda seed
;    and #$3f
;    clc
;    adc #$20
    lda midinote
    inc
    cmp #88
    bcc :+
    lda #24
:
    sta midinote
    ; get a fractional note at random
    jsr rng
    lda seed
    and #$fc ; highest 6 bits
    lda #0
    sta kf

    lda midinote
    jsr print_hex
    jsr print_space


    tay
    ldx midinote

    ; play fm
;    jsr notecon_midi2fm
;    bcs error
    clc
    lda midinote
    and #1
    jsr ym_playdrum
    bcs error
    
    ldx atten
    lda #0
    jsr ym_setatten

    ldx atten
    lda #1
    jsr ym_setatten

    ; wait for some interrupts
    ldx #4
l1:
    wai
    dex
    bne l1

    ; play psg
    
    lda midinote
    and #3
    bne :+
    lda #3
:   tax
    lda #0
    jsr psg_setpan

    ldx midinote
    ldy kf
    jsr notecon_midi2psg
    bcs error

    lda #0
    jsr psg_playfreq

    stz $9F25
    lda #$01
    sta $9F22
    lda #$F9
    sta $9F21

    jsr rng
    lda seed
    ldx #0
    jsr psg_write

    ; wait for some interrupts
    ldx #4
l2:
    wai
    dex
    cpx #0
    bne l2

    ; release fm
    lda #0
;    jsr ym_release
;    bcs error

    lda #0
    ldx #0
    jsr psg_setvol

    ldx atten
    lda #0

    jsr psg_setatten

    ; wait for some interrupts
    ldx #4
l3:
    wai
    dex
    bne l3

    lda atten
    inc
    and #$1F
    sta atten

    lda atten
    bne goloop
    
;    inc patch
;    lda #0
;    ldx patch
;    sec
;    jsr ym_loadpatch
goloop:
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

print_space:
    lda #' '
    jmp X16::Kernal::CHROUT

print_newline:
    lda #$0D
    jmp X16::Kernal::CHROUT


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
