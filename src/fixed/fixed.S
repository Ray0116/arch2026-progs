# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tfixed.c.

    .text

# a0 = a
# a1 = b
# a2 = n
# t0 = count
# t1 = c

    .globl op1_asm
    .type op1_asm, @function
    .align 2
op1_asm:
    li t0, 0
    beqz a1, .Lop1_done

.Lop1:
    and t1, a0, a1  # c =  a & b
    xor a0, a0, a1  # a ^= b
    slli a1, t1, 1 # b = c << 2 
    addi t0, t0, 1
    bnez a1, .Lop1

.Lop1_done:
    sw t0, 0(a2)
    ret

    .size op1_asm, .-op1_asm


    .globl op2_asm
    .type op2_asm, @function
    .align 2
op2_asm:
    sub a0, a0, a1
    ret

    .size op2_asm, .-op2_asm


# t0 = a & b
# t1 = (a ^ b) >> 1

    .globl op3_asm
    .type op3_asm, @function
    .align 2
op3_asm:
    and t0, a0, a1
    xor t1, a0, a1
    srli t1, t1, 1
    add a0, t0, t1
    ret

    .size op3_asm, .-op3_asm


# s0 = ua
# s1 = ub
# s2 = ll
# s3 = lh
# s4 = hl
# s5 = hh
# t0 = mid
# t1 = mid_carry
# t2 = lo
# t3 = hi
# t4 = lo2
# t5 = carry

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    mv s0, a0
    mv s1, a1

    srli a0, s0, 16              # hh = ah * bh
    srli a1, s1, 16
    call __mulsi3
    mv s2, a0

    slli a0, s0, 16              # lh = al * bh
    srli a0, a0, 16
    srli a1, s1, 16
    call __mulsi3
    mv s3, a0

    srli a0, s0, 16              # hl = ah * bl
    slli a1, s1, 16
    srli a1, a1, 16
    call __mulsi3
    add s3, s3, a0              # mid = lh + hl
    sltu t1, s3, a0              # mid_carry
    slli t1, t1, 16 
    add s2, s2, t1

    slli a0, s0, 16              # ll = al * bl
    srli a0, a0, 16
    slli a1, s1, 16
    srli a1, a1, 16
    call __mulsi3

    slli t2, s3, 16              # lo = ll + (mid << 16)
    add t2, a0, t2
    sltu t5, t2, a0
    srli t3, s3, 16
    add t3, t3, s2
    add t3, t3, t5

    bgez s0, .Lqa
    sub t3, t3, s1
.Lqa:
    bgez s1, .Lqb
    sub t3, t3, s0
.Lqb:
    lui t4, 0x80
    add t4, t2, t4
    sltu t5, t4, t2
    add t3, t3, t5
    srli t4, t4, 20
    slli t3, t3, 12
    or a0, t4, t3

    lw ra, 28(sp)
    lw s0, 24(sp)
    lw s1, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    addi sp, sp, 32
    ret
    .size q_mul_asm, .-q_mul_asm
