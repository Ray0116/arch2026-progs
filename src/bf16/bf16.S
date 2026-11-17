# bf16_from_f32, bf16_mul and bf16_sqrt: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only. All three are leaf functions: the small products are
# formed by an inline shift-and-add loop, so no __mulsi3 call and no stack.
# Tests: tests/tbf16.c.

    .text

# a0 = f32bits
# t0 = exp bit, and rounding bit
# t1 = 0x7F800000, and 0x7FFF

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    lui t1, 0x7F800
    and t0, a0, t1
    beq t0, t1, .Lf32_keep

    srli t0, a0, 16
    andi t0, t0, 1
    add a0, a0, t0
    lui t1, 8
    addi t1, t1, -1
    add a0, a0, t1

.Lf32_keep:
    srli a0, a0, 16
    ret

    .size   bf16_from_f32_asm, .-bf16_from_f32_asm


# t0 = exp_a
# t1 = exp_b
# t2 = mant_a
# t3 = mant_b
# t4 = sign
# t5 = exp_adjust
# t6 = 0xFF
# a2 = product
# a3 = tmp

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2
bf16_mul_asm:
    srli t0, a0, 7
    andi t0, t0, 0xFF
    srli t1, a1, 7
    andi t1, t1, 0xFF
    andi t2, a0, 0x7F
    andi t3, a1, 0x7F
    xor t4, a0, a1
    srli t4, t4, 15
    slli t4, t4, 15
    li t6, 0xFF

    bne t0, t6, .Lmul_b_spec
    bnez t2, .Lmul_ret_a
    or a3, t1, t3
    beqz a3, .Lmul_nan
    j .Lmul_inf
.Lmul_b_spec:   # b is NaN or inf
    bne t1, t6, .Lmul_zero
    bnez t3, .Lmul_ret_b
    or a3, t0, t2
    beqz a3, .Lmul_nan
    j .Lmul_inf

.Lmul_zero:    # one of them is 0
    or a3, t0, t2
    beqz a3, .Lmul_ret_sign
    or a3, t1, t3
    beqz a3, .Lmul_ret_sign

    li t5, 0

    bnez t0, .Lmul_na_norm
.Lmul_na:   # normarize
    andi a3, t2, 0x80
    bnez a3, .Lmul_na_done
    slli t2, t2, 1
    addi t5, t5, -1
    j .Lmul_na
.Lmul_na_done:
    li t0, 1
    j .Lmul_nb_start
.Lmul_na_norm:
    ori t2, t2, 0x80

.Lmul_nb_start:
    bnez t1, .Lmul_nb_norm
.Lmul_nb:
    andi a3, t3, 0x80
    bnez a3, .Lmul_nb_done
    slli t3, t3, 1
    addi t5, t5, -1
    j .Lmul_nb
.Lmul_nb_done:
    li t1, 1
    j .Lmul_prod
.Lmul_nb_norm:
    ori t3, t3, 0x80

.Lmul_prod:   # mul
    li a2, 0
.Lmul_loop:
    andi a3, t3, 1
    beqz a3, .Lmul_skip
    add a2, a2, t2
.Lmul_skip:
    slli t2, t2, 1
    srli t3, t3, 1
    bnez t3, .Lmul_loop

    add t0, t0, t1
    addi t0, t0, -127
    add t0, t0, t5

    srli a3, a2, 15
    beqz a3, .Lmul_no_carry
    srli t2, a2, 8
    andi t2, t2, 0x7F
    addi t0, t0, 1
    j .Lmul_range
.Lmul_no_carry:
    srli t2, a2, 7
    andi t2, t2, 0x7F

.Lmul_range:
    bge t0, t6, .Lmul_inf
    bgtz t0, .Lmul_pack
    li a3, -6
    blt t0, a3, .Lmul_ret_sign
    li a3, 1
    sub a3, a3, t0
    srl t2, t2, a3
    li t0, 0

.Lmul_pack:
    slli t0, t0, 7
    or a0, t4, t0
    or a0, a0, t2
    ret

.Lmul_ret_sign:
    mv a0, t4
    ret
.Lmul_inf:
    li a0, 0x7F80
    or a0, a0, t4
    ret
.Lmul_nan:
    li a0, 0x7FC0
    ret
.Lmul_ret_b:
    mv a0, a1
.Lmul_ret_a:
    ret

    .size   bf16_mul_asm, .-bf16_mul_asm


# t0 = exp
# t1 = mant
# t2 = new_exp
# t3 = low
# t4 = high
# t5 = result
# t6 = mid
# a2 = mid * mid
# a3 = multiplicand
# a4 = multiplier
# a5 = tmp

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli t0, a0, 7
    andi t0, t0, 0xFF
    andi t1, a0, 0x7F

    li a3, 0xFF
    bne t0, a3, .Lsq_zero
    bnez t1, .Lsq_ret
    srli a3, a0, 15
    bnez a3, .Lsq_nan
    ret

.Lsq_zero:
    or a3, t0, t1
    beqz a3, .Lsq_ret0
    srli a3, a0, 15
    bnez a3, .Lsq_nan
    beqz t0, .Lsq_ret0

    addi t0, t0, -127
    ori t1, t1, 0x80
    andi a3, t0, 1
    beqz a3, .Lsq_even
    
    slli t1, t1, 1
    addi t2, t0, -1
    srai t2, t2, 1
    addi t2, t2, 127
    j .Lsq_init
.Lsq_even:
    srai t2, t0, 1
    addi t2, t2, 127

.Lsq_init:
    li t3, 90
    li t4, 256
    li t5, 128
.Lsq_loop:
    bgtu t3, t4, .Lsq_done
    add t6, t3, t4
    srli t6, t6, 1

    li a2, 0
    mv a3, t6
    mv a4, t6
.Lsq_mul:
    andi a5, a4, 1
    beqz a5, .Lsq_skip
    add a2, a2, a3
.Lsq_skip:
    slli a3, a3, 1
    srli a4, a4, 1
    bnez a4, .Lsq_mul
    srli a2, a2, 7

    bgtu a2, t1, .Lsq_high
    mv t5, t6
    addi t3, t6, 1
    j .Lsq_loop
.Lsq_high:
    addi t4, t6, -1
    j .Lsq_loop

.Lsq_done:
    slli t2, t2, 7
    andi t5, t5, 0x7F
    or a0, t2, t5
.Lsq_ret:
    ret
.Lsq_ret0:
    li a0, 0
    ret
.Lsq_nan:
    li a0, 0x7FC0
    ret

    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
