/* Host-side generator of the rubik search tables.
 *
 * Build and run from the repository root:
 *   cc -O2 -o build/gen mytests/gen.c && build/gen
 * It writes src/rubik/tables.c (C implementation) and src/rubik/tables.S
 * (assembly implementation). Both hold the same data under different names,
 * because each implementation is measured and linked on its own.
 *
 * Coordinates follow sysprog21/minirubik: the permutation rank P (Lehmer code
 * of the seven cubies, 0..5039) and the orientation rank O (base 3 of the
 * first six orientations, 0..728). Tables:
 *   perm_move[3][5040]  P after one quarter turn of face R, B or D
 *   orient_move[3][729] O after one quarter turn
 *   perm_dist[5040]     fewest moves that solve the permutation alone
 *   orient_dist[729]    fewest moves that solve the orientation alone
 *   near_off[5041]      near_ent[near_off[P] .. near_off[P + 1]) are the
 *                       states within 5 moves whose permutation rank is P
 *   near_ent[12224]     O | distance << 10, sorted by O within each P
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { NP = 5040, NO = 729, NS = NP * NO, NEAR = 5 };

static const uint8_t source[3][7] = {
    {1, 4, 2, 0, 3, 5, 6},
    {0, 1, 2, 4, 5, 6, 3},
    {0, 2, 5, 3, 1, 4, 6},
};
static const uint8_t twist[3][7] = {
    {1, 2, 0, 2, 1, 0, 0},
    {0, 0, 0, 1, 2, 1, 2},
    {0, 0, 0, 0, 0, 0, 0},
};

typedef struct {
    uint8_t p[7], o[7];
} state_t;

static state_t quarter_turn(state_t s, int face)
{
    state_t r;
    for (int i = 0; i < 7; i++) {
        int from = source[face][i];
        r.p[i] = s.p[from];
        r.o[i] = (uint8_t) ((s.o[from] + twist[face][i]) % 3);
    }
    return r;
}

static uint32_t rank_perm(const state_t *s)
{
    uint32_t p = 0;
    for (int i = 0; i < 7; i++) {
        int smaller = 0;
        for (int j = i + 1; j < 7; j++)
            smaller += s->p[j] < s->p[i];
        p = p * (uint32_t) (7 - i) + (uint32_t) smaller;
    }
    return p;
}

static uint32_t rank_orient(const state_t *s)
{
    uint32_t o = 0;
    for (int i = 0; i < 6; i++)
        o = o * 3 + s->o[i];
    return o;
}

static void unrank(uint32_t p, uint32_t o, state_t *s)
{
    uint8_t avail[7] = {0, 1, 2, 3, 4, 5, 6};
    uint32_t f = 720;
    int sum = 0;
    for (int i = 0; i < 7; i++) {
        uint32_t q = p / f;
        p %= f;
        s->p[i] = avail[q];
        for (int j = (int) q; j + 1 < 7 - i; j++)
            avail[j] = avail[j + 1];
        if (i < 5)
            f /= (uint32_t) (6 - i);
    }
    for (int i = 6; i-- > 0;) {
        s->o[i] = (uint8_t) (o % 3);
        sum += s->o[i];
        o /= 3;
    }
    s->o[6] = (uint8_t) ((3 - sum % 3) % 3);
}

static uint16_t perm_move[3][NP], orient_move[3][NO];
static uint8_t perm_dist[NP], orient_dist[NO];
static uint16_t near_off[NP + 1], near_ent[20000];

/* Value i of a table of 8-bit (width 1) or 16-bit (width 2) entries. */
static unsigned at(const void *v, int width, int i)
{
    if (width == 2)
        return ((const uint16_t *) v)[i];
    return ((const uint8_t *) v)[i];
}

static void emit_c(FILE *f,
                   const char *type,
                   const char *name,
                   const void *v,
                   int width,
                   int n)
{
    fprintf(f, "const %s %s[%d] = {", type, name, n);
    for (int i = 0; i < n; i++)
        fprintf(f, "%s%u,", i % 12 ? " " : "\n    ", at(v, width, i));
    fprintf(f, "\n};\n\n");
}

static void emit_s(FILE *f, const char *name, const void *v, int width, int n)
{
    const char *dir = width == 2 ? ".half" : ".byte";
    fprintf(f, "    .globl  %s\n    .type   %s, @object\n", name, name);
    fprintf(f, "    .align  %d\n%s:", width == 2 ? 1 : 0, name);
    for (int i = 0; i < n; i++) {
        if (i % 16 == 0)
            fprintf(f, "\n    %s   ", dir);
        else
            fprintf(f, ", ");
        fprintf(f, "%u", at(v, width, i));
    }
    fprintf(f, "\n    .size   %s, .-%s\n\n", name, name);
}

int main(void)
{
    state_t s;
    for (uint32_t r = 0; r < NP; r++) {
        unrank(r, 0, &s);
        for (int face = 0; face < 3; face++) {
            state_t n = quarter_turn(s, face);
            perm_move[face][r] = (uint16_t) rank_perm(&n);
        }
    }
    for (uint32_t r = 0; r < NO; r++) {
        unrank(0, r, &s);
        for (int face = 0; face < 3; face++) {
            state_t n = quarter_turn(s, face);
            orient_move[face][r] = (uint16_t) rank_orient(&n);
        }
    }

    /* Breadth-first search over all states for the exact distances. */
    uint8_t *dist = malloc(NS);
    uint32_t *queue = malloc(NS * sizeof *queue);
    uint32_t head = 0, tail = 1;
    memset(dist, 0xFF, NS);
    dist[0] = 0;
    queue[0] = 0;
    while (head < tail) {
        uint32_t x = queue[head++];
        uint32_t p = x / NO, o = x % NO;
        for (int face = 0; face < 3; face++) {
            uint32_t np = p, no = o;
            for (int t = 0; t < 3; t++) {
                np = perm_move[face][np];
                no = orient_move[face][no];
                uint32_t y = np * NO + no;
                if (dist[y] == 0xFF) {
                    dist[y] = (uint8_t) (dist[x] + 1);
                    queue[tail++] = y;
                }
            }
        }
    }
    if (tail != NS) {
        fputs("BFS did not reach every state\n", stderr);
        return 1;
    }

    memset(perm_dist, 0xFF, sizeof perm_dist);
    memset(orient_dist, 0xFF, sizeof orient_dist);
    int n = 0;
    for (uint32_t p = 0; p < NP; p++) {
        near_off[p] = (uint16_t) n;
        for (uint32_t o = 0; o < NO; o++) {
            uint8_t d = dist[p * NO + o];
            if (d < perm_dist[p])
                perm_dist[p] = d;
            if (d < orient_dist[o])
                orient_dist[o] = d;
            if (d <= NEAR)
                near_ent[n++] = (uint16_t) (o | (uint32_t) d << 10);
        }
    }
    near_off[NP] = (uint16_t) n;

    FILE *c = fopen("src/rubik/tables.c", "w");
    FILE *a = fopen("src/rubik/tables.S", "w");
    if (!c || !a) {
        perror("src/rubik/tables.*");
        return 1;
    }
    fprintf(c, "/* Generated by mytests/gen.c; do not edit. */\n");
    fprintf(c, "/* clang-format off */\n#include \"tables.h\"\n\n");
    emit_c(c, "uint16_t", "rk_perm_move", perm_move, 2, 3 * NP);
    emit_c(c, "uint16_t", "rk_orient_move", orient_move, 2, 3 * NO);
    emit_c(c, "uint8_t", "rk_perm_dist", perm_dist, 1, NP);
    emit_c(c, "uint8_t", "rk_orient_dist", orient_dist, 1, NO);
    emit_c(c, "uint16_t", "rk_near_off", near_off, 2, NP + 1);
    emit_c(c, "uint16_t", "rk_near_ent", near_ent, 2, n);
    fprintf(c, "/* clang-format on */\n");

    fprintf(a, "# Generated by mytests/gen.c; do not edit.\n");
    fprintf(a, "# Search tables of rubik_solve_asm; see the generator.\n\n");
    fprintf(a, "    .section .rodata\n\n");
    emit_s(a, "rks_perm_move", perm_move, 2, 3 * NP);
    emit_s(a, "rks_orient_move", orient_move, 2, 3 * NO);
    emit_s(a, "rks_perm_dist", perm_dist, 1, NP);
    emit_s(a, "rks_orient_dist", orient_dist, 1, NO);
    emit_s(a, "rks_near_off", near_off, 2, NP + 1);
    emit_s(a, "rks_near_ent", near_ent, 2, n);
    fclose(c);
    fclose(a);
    printf("%d states within %d moves\n", n, NEAR);
    return 0;
}
