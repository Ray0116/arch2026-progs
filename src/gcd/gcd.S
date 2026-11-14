# gcd_u32_asm: binary GCD, hand-written RV32I.
#
# uint32_t gcd_u32_asm(uint32_t a, uint32_t b)   a in a0, b in a1, result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tgcd.c.


# a0 = a
# #a1 = b
# t0 = a | b
# t1 = shift

    .text

    .globl  gcd_u32_asm
    .type   gcd_u32_asm, @function
    .align  2
gcd_u32_asm:
    beqz a0, .Lret_b    # a = 0
    beqz a1, .Ldone   # b = 0

    or t0, a0, a1
    li t1, 0   # shift

.Lshift:
    andi t2, t0, 1
    bnez t2, .Lshift_done
    srli t0, t0, 1
    addi t1, t1, 1
    j .Lshift
.Lshift_done:
    srl a0, a0, t1
    srl a1, a1, t1

.La:
    andi t2, a0, 1
    bnez t2, .Lmain
    srli a0, a0, 1
    j .La

.Lb:
    srli a1, a1, 1
.Lmain:       # do while loop
    andi t2, a1, 1
    beqz t2, .Lb
.Lif:

    bgeu a1, a0, .Lno_swap
    mv t2, a0 # tmp = a
    mv a0, a1 # a = b
    mv a1, t2 # b = tmp

.Lno_swap:
    sub a1, a1, a0
    bnez a1, .Lb

    sll a0, a0, t1 # a<<= shift
.Ldone:
    ret

.Lret_b:
    mv a0, a1
    ret

    .size   gcd_u32_asm, .-gcd_u32_asm
