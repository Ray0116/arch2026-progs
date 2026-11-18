# Search registers:
# s0 = rks_perm_move; s1 = rks_orient_move; s2 = rks_perm_dist
# s3 = rks_orient_dist; s4 = rks_near_off; s5 = rks_near_ent
# s6 = level k; s7 = moves left for a child of level k
# s8 = face; s9 = turn; s10 = child P; s11 = child O
# a2 = perm_move row of the face; a3 = orient_move row of the face
# a4 = moves[]; a5 = bound (len); a6 = P of level k
# a7 = O of level k; t5 = face of the parent move (-1 at the root)
# t6 = return address of .Lnear

    .equ NP_BYTES, 10080
    .equ NO_BYTES, 1458
    .equ NEAR, 5
    .equ F_CUBIE, 0 # frame: cubie[7]
    .equ F_MOVES, 8 # moves[11]
    .equ F_OUT, 20
    .equ F_CAP, 24
    .equ F_LEVEL, 28 # 6 records of 24 bytes
    .equ F_SAVE, 172 # s0-s11, ra
    .equ FRAME, 224

# FACE_ROWS face, prow, orow: rows of the move tables for face 0, 1 or 2.
    .macro FACE_ROWS face, prow, orow
    mv \prow, s0
    mv \orow, s1
    beqz \face, 1f
    li t0, NP_BYTES
    li t1, NO_BYTES
    add \prow, \prow, t0
    add \orow, \orow, t1
    addi t2, \face, -1
    beqz t2, 1f
    add \prow, \prow, t0
    add \orow, \orow, t1
1:
    .endm

# QUARTER p, o, prow, orow: one quarter turn of (p, o) through the rows.
    .macro QUARTER p, o, prow, orow
    slli t0, \p, 1
    add t0, \prow, t0
    lhu \p, 0(t0)
    slli t0, \o, 1
    add t0, \orow, t0
    lhu \o, 0(t0)
    .endm

    .text

    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
    .align 2
rubik_solve_asm:
    addi sp, sp, -FRAME
    sw ra, F_SAVE+48(sp)
    sw s0, F_SAVE+0(sp)
    sw s1, F_SAVE+4(sp)
    sw s2, F_SAVE+8(sp)
    sw s3, F_SAVE+12(sp)
    sw s4, F_SAVE+16(sp)
    sw s5, F_SAVE+20(sp)
    sw s6, F_SAVE+24(sp)
    sw s7, F_SAVE+28(sp)
    sw s8, F_SAVE+32(sp)
    sw s9, F_SAVE+36(sp)
    sw s10, F_SAVE+40(sp)
    sw s11, F_SAVE+44(sp)
    sw a1, F_OUT(sp)
    sw a2, F_CAP(sp)

    # Parse the seven cubies: digits '1'..'7', no repeats.
    li t0, 0
    li t1, 0
    li t4, 7
.Lparse_p:
    add t2, a0, t0
    lbu t2, 0(t2)
    addi t2, t2, -'1'
    bgeu t2, t4, .Linvalid
    li t3, 1
    sll t3, t3, t2
    and a3, t1, t3
    bnez a3, .Linvalid
    or t1, t1, t3
    add t3, sp, t0
    sb t2, F_CUBIE(t3)
    addi t0, t0, 1
    blt t0, t4, .Lparse_p

    # Parse the seven orientations: digits '1'..'3'; O is base 3 of six.
    li a7, 0
    li t1, 0
    li t4, 3
    li t5, 13
    li t6, 14
.Lparse_o:
    add t2, a0, t0
    lbu t2, 0(t2)
    addi t2, t2, -'1'
    bgeu t2, t4, .Linvalid
    add t1, t1, t2
    beq t0, t5, 1f # the seventh does not enter O
    slli t3, a7, 1
    add a7, a7, t3
    add a7, a7, t2
1:
    addi t0, t0, 1
    blt t0, t6, .Lparse_o
    lbu t2, 14(a0)
    bnez t2, .Linvalid
    li t2, 0x1249 # bits 0, 3, 6, 9, 12: multiples of 3
    srl t2, t2, t1
    andi t2, t2, 1
    beqz t2, .Linvalid

    # P = Lehmer code: P = P * (7 - i) + #{j > i : cubie[j] < cubie[i]}.
    li a6, 0
    li t0, 0
.Lrank_i:
    add t3, sp, t0
    lbu t3, F_CUBIE(t3)
    li t2, 0
    addi t1, t0, 1
.Lrank_j:
    li t4, 7
    bge t1, t4, .Lrank_mul
    add t4, sp, t1
    lbu t4, F_CUBIE(t4)
    sltu t4, t4, t3
    add t2, t2, t4
    addi t1, t1, 1
    j .Lrank_j
.Lrank_mul:
    li t4, 7
    sub t4, t4, t0
    mv t1, a6
    li a6, 0
.Lrank_add:
    add a6, a6, t1
    addi t4, t4, -1
    bnez t4, .Lrank_add
    add a6, a6, t2
    addi t0, t0, 1
    li t4, 7
    blt t0, t4, .Lrank_i

    la s0, rks_perm_move
    la s1, rks_orient_move
    la s2, rks_perm_dist
    la s3, rks_orient_dist
    la s4, rks_near_off
    la s5, rks_near_ent
    addi a4, sp, F_MOVES

    # First bound: the heuristic of the root.
    add t0, s2, a6
    lbu a5, 0(t0)
    add t0, s3, a7
    lbu t0, 0(t0)
    bgeu a5, t0, .Lbound
    mv a5, t0

.Lbound: # one IDA* iteration with bound a5
    li t0, NEAR
    bgtu a5, t0, .Ldeep
    mv a0, a6 # bound <= 5: the table decides
    mv a1, a7
    jal t6, .Lnear
    bgtu a0, a5, .Lnext_bound
    mv s10, a6 # nothing searched: the root is the
    mv s11, a7 # state handed to the tail
    li s6, 0
    j .Ltail
.Ldeep:
    li s6, 0
    addi s7, a5, -1
    li s8, 0
    li t5, -1
.Lface:
    li t0, 3
    beq s8, t0, .Lpop
    beq s8, t5, .Lface_next # never turn the same face twice
    FACE_ROWS s8, a2, a3
    mv s10, a6
    mv s11, a7
    li s9, 0
.Lchild:
    QUARTER s10, s11, a2, a3
    add t0, a4, s6 # moves[k] = face << 2 | turn
    slli t1, s8, 2
    or t1, t1, s9
    sb t1, 0(t0)
    add t0, s2, s10 # h = max(perm_dist, orient_dist)
    lbu t0, 0(t0)
    add t1, s3, s11
    lbu t1, 0(t1)
    bgeu t0, t1, 1f
    mv t0, t1
1:
    bgtu t0, s7, .Lturn_next
    li t0, NEAR
    bgtu s7, t0, .Lpush
    mv a0, s10 # at most 5 left: exact lookup
    mv a1, s11
    jal t6, .Lnear
    bleu a0, s7, .Lfound
.Lturn_next:
    addi s9, s9, 1
    li t0, 3
    blt s9, t0, .Lchild
.Lface_next:
    addi s8, s8, 1
    j .Lface

.Lpush:
    slli t0, s6, 4 # record k at F_LEVEL + 24 k
    slli t1, s6, 3
    add t0, t0, t1
    add t0, sp, t0
    sw a6, F_LEVEL+0(t0)
    sw a7, F_LEVEL+4(t0)
    sw s8, F_LEVEL+8(t0)
    sw s9, F_LEVEL+12(t0)
    sw s10, F_LEVEL+16(t0)
    sw s11, F_LEVEL+20(t0)
    addi s6, s6, 1
    addi s7, s7, -1
    mv a6, s10
    mv a7, s11
    mv t5, s8
    li s8, 0
    j .Lface

.Lpop:
    beqz s6, .Lnext_bound
    addi s6, s6, -1
    addi s7, s7, 1
    slli t0, s6, 4
    slli t1, s6, 3
    add t0, t0, t1
    add t0, sp, t0
    lw a6, F_LEVEL+0(t0)
    lw a7, F_LEVEL+4(t0)
    lw s8, F_LEVEL+8(t0)
    lw s9, F_LEVEL+12(t0)
    lw s10, F_LEVEL+16(t0)
    lw s11, F_LEVEL+20(t0)
    li t5, -1 # parent face: record k - 1, if any
    beqz s6, 1f
    lw t5, F_LEVEL+8-24(t0)
1:
    FACE_ROWS s8, a2, a3
    j .Lturn_next

.Lnext_bound:
    addi a5, a5, 1
    j .Lbound

.Lfound:
    addi s6, s6, 1 # head = k + 1 moves are on the path

    # Tail: from (s10, s11), at distance a5 - head, pick each next move as
    # one whose child is one step closer, using the same table.
.Ltail:
    bgeu s6, a5, .Lformat
    sub s7, a5, s6
    addi s7, s7, -1
    li s8, 0
.Ltail_face:
    FACE_ROWS s8, a2, a3
    mv a6, s10
    mv a7, s11
    li s9, 0
.Ltail_turn:
    QUARTER a6, a7, a2, a3
    mv a0, a6
    mv a1, a7
    jal t6, .Lnear
    beq a0, s7, .Ltail_take
    addi s9, s9, 1
    li t0, 3
    blt s9, t0, .Ltail_turn
    addi s8, s8, 1
    j .Ltail_face
.Ltail_take:
    add t0, a4, s6
    slli t1, s8, 2
    or t1, t1, s9
    sb t1, 0(t0)
    mv s10, a6
    mv s11, a7
    addi s6, s6, 1
    j .Ltail

    # Output: each move is a face letter, then "2" or "'" for turns 1, 2.
.Lformat:
    li t0, 1
    li t1, 0
.Lneed:
    bgeu t1, a5, .Lneed_done
    add t2, a4, t1
    lbu t2, 0(t2)
    andi t2, t2, 3
    snez t2, t2
    addi t0, t0, 1
    add t0, t0, t2
    snez t3, t1
    add t0, t0, t3
    addi t1, t1, 1
    j .Lneed
.Lneed_done:
    lw t1, F_OUT(sp)
    lw t2, F_CAP(sp)
    bleu t0, t2, .Lwrite
    beqz t2, 1f
    sb zero, 0(t1)
1:
    li a0, -2
    j .Lreturn
.Lwrite:
    li t3, 0
.Lwrite_move:
    bgeu t3, a5, .Lwrite_done
    beqz t3, 1f
    li t4, ' '
    sb t4, 0(t1)
    addi t1, t1, 1
1:
    add t4, a4, t3
    lbu t4, 0(t4)
    srli t0, t4, 2
    li t2, 'R'
    beqz t0, 2f
    li t2, 'B'
    addi t0, t0, -1
    beqz t0, 2f
    li t2, 'D'
2:
    sb t2, 0(t1)
    addi t1, t1, 1
    andi t4, t4, 3
    beqz t4, 3f
    li t2, '2'
    addi t4, t4, -1
    beqz t4, 4f
    li t2, '\''
4:
    sb t2, 0(t1)
    addi t1, t1, 1
3:
    addi t3, t3, 1
    j .Lwrite_move
.Lwrite_done:
    sb zero, 0(t1)
    mv a0, a5
    j .Lreturn

.Linvalid:
    li a0, -1
.Lreturn:
    lw ra, F_SAVE+48(sp)
    lw s0, F_SAVE+0(sp)
    lw s1, F_SAVE+4(sp)
    lw s2, F_SAVE+8(sp)
    lw s3, F_SAVE+12(sp)
    lw s4, F_SAVE+16(sp)
    lw s5, F_SAVE+20(sp)
    lw s6, F_SAVE+24(sp)
    lw s7, F_SAVE+28(sp)
    lw s8, F_SAVE+32(sp)
    lw s9, F_SAVE+36(sp)
    lw s10, F_SAVE+40(sp)
    lw s11, F_SAVE+44(sp)
    addi sp, sp, FRAME
    ret

# .Lnear: a0 = P, a1 = O -> a0 = exact distance if within 5 moves, else 255.
# Returns through t6; clobbers t0-t4 only.
.Lnear:
    slli t0, a0, 1
    add t0, s4, t0
    lhu t1, 0(t0)
    lhu t2, 2(t0)
    slli t1, t1, 1
    slli t2, t2, 1
    add t1, s5, t1
    add t2, s5, t2
.Lnear_scan:
    bgeu t1, t2, .Lnear_none
    lhu t3, 0(t1)
    andi t4, t3, 0x3FF
    beq t4, a1, .Lnear_hit
    bgtu t4, a1, .Lnear_none # entries are sorted by O
    addi t1, t1, 2
    j .Lnear_scan
.Lnear_hit:
    srli a0, t3, 10
    jr t6
.Lnear_none:
    li a0, 255
    jr t6
    .size rubik_solve_asm, .-rubik_solve_asm
