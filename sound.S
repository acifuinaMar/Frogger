/*
 * sound.S
 *
 * Sistema de sonido Frogger mediante PWM.
 *
 * Arduino Due:
 * D8 -> PC22 -> PWML5
 *
 * PWM channel 5
 *
 * Reloj:
 * MCK / 1024
 *
 * 84 MHz / 1024 = 82031.25 Hz
 *
 * frecuencia = 82031 / CPRD
 */

.syntax unified
.cpu cortex-m3
.thumb


/* ============================================================
 * PIOC
 * ============================================================ */

.equ PIOC,          0x400E1200

.equ PIO_PDR,       0x004
.equ PIO_PUDR,      0x060
.equ PIO_ABSR,      0x070

/* D8 = PC22 */
.equ BUZZER_MASK,   0x00400000


/* ============================================================
 * PMC
 * ============================================================ */

.equ PMC_BASE,      0x400E0600
.equ PMC_PCER1,     0x100

/*
 * PWM = Peripheral ID 36
 * bit 4 de PCER1
 */
.equ PWM_CLK_MASK,  0x00000010


/* ============================================================
 * PWM
 * ============================================================ */

.equ PWM_BASE,      0x40094000

.equ PWM_ENA,       0x004
.equ PWM_DIS,       0x008

/* Channel 5 */
.equ PWM_CMR5,      0x2A0
.equ PWM_CDTY5,     0x2A4
.equ PWM_CPRD5,     0x2AC

/* Canal 5 = bit 5 */
.equ PWM_CH5_MASK,  0x00000020

/*
 * CPRE = 10:
 * MCK / 1024
 */
.equ PWM_CMR_VALUE, 0x0000000A


/* ============================================================
 * SECUENCIAS
 * ============================================================ */

.equ SEQ_NONE,      0
.equ SEQ_GAMEOVER,  1


/* ============================================================
 * EXPORTACIONES
 * ============================================================ */

.global sound_init
.global sound_update
.global sound_off

.global sound_start_game
.global sound_collision
.global sound_goal
.global sound_game_over

.global sound_ticks


/* ============================================================
 * ESTADO
 * ============================================================ */

.section .bss
.align 4


/*
 * Frames restantes de sonido.
 *
 * Sigue siendo pública porque loop_game_over
 * la utiliza para saber cuándo puede detener TC0.
 */

sound_ticks:
    .space 4


/*
 * 0 = sonido simple
 * 1 = secuencia GAME OVER
 */

sound_sequence:
    .space 4


/* ============================================================
 * CÓDIGO
 * ============================================================ */

.section .text
.align 2



/* ============================================================
 * sound_init
 * ============================================================ */

.type sound_init, %function
.thumb_func

sound_init:

    /* ----------------------------------------
     * PC22 -> periférico B
     * ---------------------------------------- */

    ldr r0, =PIOC
    ldr r1, =BUZZER_MASK

    /* Sin pull-up */

    str r1, [r0, #PIO_PUDR]


    /* Seleccionar periférico B */

    ldr r2, [r0, #PIO_ABSR]

    orr r2, r2, r1

    str r2, [r0, #PIO_ABSR]


    /* Quitar PC22 del control GPIO */

    str r1, [r0, #PIO_PDR]


    /* ----------------------------------------
     * Reloj PWM
     * ---------------------------------------- */

    ldr r0, =PMC_BASE

    ldr r1, =PWM_CLK_MASK

    str r1, [r0, #PMC_PCER1]


    /* ----------------------------------------
     * Canal 5
     * ---------------------------------------- */

    ldr r0, =PWM_BASE

    ldr r1, =PWM_CH5_MASK

    str r1, [r0, #PWM_DIS]


    ldr r1, =PWM_CMR_VALUE

    str r1, [r0, #PWM_CMR5]


    /* Estado inicial */

    ldr r0, =sound_ticks
    movs r1, #0
    str r1, [r0]


    ldr r0, =sound_sequence
    movs r1, #SEQ_NONE
    str r1, [r0]


    bx lr



/* ============================================================
 * sound_set_tone
 *
 * Cambia frecuencia SIN alterar duración.
 *
 * Entrada:
 *   r0 = CPRD
 * ============================================================ */

.type sound_set_tone, %function
.thumb_func

sound_set_tone:

    ldr r2, =PWM_BASE

    ldr r3, =PWM_CH5_MASK


    /* Apagar momentáneamente */

    str r3, [r2, #PWM_DIS]


    /* Periodo */

    str r0, [r2, #PWM_CPRD5]


    /* Duty = 50 % */

    lsrs r0, r0, #1

    str r0, [r2, #PWM_CDTY5]


    /* Encender */

    str r3, [r2, #PWM_ENA]


    bx lr



/* ============================================================
 * sound_disable_pwm
 *
 * Silencia momentáneamente el buzzer,
 * pero NO modifica sound_ticks.
 *
 * Esto nos permite crear pausas entre beeps.
 * ============================================================ */

.type sound_disable_pwm, %function
.thumb_func

sound_disable_pwm:

    ldr r0, =PWM_BASE

    ldr r1, =PWM_CH5_MASK

    str r1, [r0, #PWM_DIS]

    bx lr



/* ============================================================
 * sound_play
 *
 * Sonido simple.
 *
 * Entrada:
 *   r0 = CPRD
 *   r1 = duración en frames
 * ============================================================ */

.type sound_play, %function
.thumb_func

sound_play:

    /*
     * 8 bytes -> stack alineado.
     */

    push {r4, lr}


    /* Guardar periodo */

    mov r4, r0


    /* Duración */

    ldr r2, =sound_ticks

    str r1, [r2]


    /*
     * Cancelar cualquier secuencia anterior.
     */

    ldr r2, =sound_sequence

    movs r3, #SEQ_NONE

    str r3, [r2]


    /* Reproducir tono */

    mov r0, r4

    bl sound_set_tone


    pop {r4, pc}



/* ============================================================
 * sound_off
 * ============================================================ */

.type sound_off, %function
.thumb_func

sound_off:

    /* PWM OFF */

    ldr r0, =PWM_BASE

    ldr r1, =PWM_CH5_MASK

    str r1, [r0, #PWM_DIS]


    /* ticks = 0 */

    ldr r0, =sound_ticks

    movs r1, #0

    str r1, [r0]


    /* sequence = NONE */

    ldr r0, =sound_sequence

    movs r1, #SEQ_NONE

    str r1, [r0]


    bx lr



/* ============================================================
 * sound_update
 *
 * Se llama una vez por frame (30 Hz).
 *
 * Maneja:
 *
 * - sonidos simples
 * - secuencia GAME OVER
 * ============================================================ */

.type sound_update, %function
.thumb_func

sound_update:

    /*
     * 16 bytes -> alineación AAPCS.
     */

    push {r4-r6, lr}


    /* ========================================
     * Leer frames restantes
     * ======================================== */

    ldr r4, =sound_ticks

    ldr r5, [r4]


    cmp r5, #0

    beq sound_update_end


    /* Un frame menos */

    subs r5, r5, #1

    str r5, [r4]


    /* ========================================
     * ¿Tenemos una secuencia especial?
     * ======================================== */

    ldr r6, =sound_sequence

    ldr r6, [r6]


    cmp r6, #SEQ_GAMEOVER

    beq update_gameover


    /* ========================================
     * SONIDO NORMAL
     * ======================================== */

    cmp r5, #0

    bne sound_update_end


    bl sound_off

    b sound_update_end



/* ============================================================
 * SECUENCIA GAME OVER
 *
 * sound_ticks:
 *
 * 11 10 9   → BEEP 1 alto
 *  8        → silencio
 *  7  6 5   → BEEP 2 medio
 *  4        → silencio
 *  3  2 1   → BEEP 3 grave
 *  0        → fin
 *
 * Aproximadamente:
 *
 * BIP!  BIP!  BOOP!
 * ============================================================ */

/* ============================================================
 * SECUENCIA GAME OVER
 *
 * Exactamente el mismo sonido del choque:
 *
 * BEEP - BEEP - BEEP
 *
 * Cada beep:
 *   CPRD = 182
 *   ~450 Hz
 *   5 frames = ~167 ms
 *
 * Pausas:
 *   2 frames = ~67 ms
 *
 * Total:
 *
 * 5 + 2 + 5 + 2 + 5 = 19 frames
 * 19 / 30 = ~633 ms
 * ============================================================ */

update_gameover:

    /* ========================================================
     * FIN DEL PRIMER BEEP
     *
     * Inicio: 19
     * Apagamos al llegar a 14
     * ======================================================== */

    cmp r5, #14
    bne gameover_beep2

    bl sound_disable_pwm

    b sound_update_end


/* ============================================================
 * SEGUNDO BEEP
 *
 * Después de 2 frames de silencio:
 * 14 -> 13 -> 12
 * ============================================================ */

gameover_beep2:

    cmp r5, #12
    bne gameover_pause2

    /*
     * MISMO tono que sound_collision:
     * CPRD = 182
     */

    movs r0, #182

    bl sound_set_tone

    b sound_update_end


/* ============================================================
 * FIN DEL SEGUNDO BEEP
 *
 * 12 -> 7 = 5 frames
 * ============================================================ */

gameover_pause2:

    cmp r5, #7
    bne gameover_beep3

    bl sound_disable_pwm

    b sound_update_end


/* ============================================================
 * TERCER BEEP
 *
 * 2 frames de silencio:
 * 7 -> 6 -> 5
 * ============================================================ */

gameover_beep3:

    cmp r5, #5
    bne gameover_finish

    /*
     * Otra vez exactamente
     * el tono de colisión.
     */

    movs r0, #182

    bl sound_set_tone

    b sound_update_end


/* ============================================================
 * FIN
 *
 * Tercer beep:
 * 5 -> 0 = 5 frames
 * ============================================================ */

gameover_finish:

    cmp r5, #0
    bne sound_update_end

    bl sound_off

sound_update_end:

    pop {r4-r6, pc}



/* ============================================================
 * SONIDO: INICIO
 *
 * ~1200 Hz
 *
 * 82031 / 68 ≈ 1206 Hz
 *
 * 3 frames = 100 ms
 * ============================================================ */

.type sound_start_game, %function
.thumb_func

sound_start_game:

    movs r0, #68

    movs r1, #3

    b sound_play



/* ============================================================
 * SONIDO: CHOQUE
 *
 * ~450 Hz
 *
 * 82031 / 182 ≈ 451 Hz
 *
 * 5 frames = 167 ms
 * ============================================================ */

.type sound_collision, %function
.thumb_func

sound_collision:

    movs r0, #182

    movs r1, #5

    b sound_play



/* ============================================================
 * SONIDO: META
 *
 * Antes:
 *   ~2000 Hz / 4 frames
 *
 * Ahora:
 *   ~1600 Hz / 7 frames
 *
 * 82031 / 51 ≈ 1608 Hz
 *
 * 7 frames:
 *   7 / 30 ≈ 233 ms
 *
 * Más perceptible y más largo.
 * ============================================================ */

.type sound_goal, %function
.thumb_func

sound_goal:

    movs r0, #51

    movs r1, #7

    b sound_play

/* ============================================================
 * sound_game_over
 *
 * Reproduce:
 *
 * BEEP - BEEP - BEEP
 *
 * usando exactamente el mismo tono
 * que sound_collision.
 * ============================================================ */

.type sound_game_over, %function
.thumb_func

sound_game_over:

    /* Activar secuencia Game Over */

    ldr r1, =sound_sequence

    movs r2, #SEQ_GAMEOVER

    str r2, [r1]


    /*
     * Duración total:
     *
     * 5 beep
     * 2 pausa
     * 5 beep
     * 2 pausa
     * 5 beep
     *
     * = 19 frames
     */

    ldr r1, =sound_ticks

    movs r2, #19

    str r2, [r1]


    /*
     * Primer beep.
     *
     * EXACTAMENTE el mismo tono
     * que sound_collision:
     *
     * CPRD = 182
     * ~450 Hz
     */

    movs r0, #182

    b sound_set_tone