#include "rubik.h"

#include "tables.h"

#define NEAR 5
#define MAX_MOVES 11
#define NO_ENTRY 0xFF

/* Exact distance of (p, o) if it is within NEAR moves, else NO_ENTRY. */
static unsigned near_dist(unsigned p, unsigned o)
{
    for (unsigned i = rk_near_off[p]; i < rk_near_off[p + 1]; i++) {
        unsigned e = rk_near_ent[i], eo = e & 0x3FF;
        if (eo == o)
            return e >> 10;
        if (eo > o)
            break;
    }
    return NO_ENTRY;
}

static unsigned max2(unsigned a, unsigned b)
{
    return a > b ? a : b;
}

/* Depth-first search with budget left; moves[] receives the path. */
static int search(unsigned p,
                  unsigned o,
                  unsigned left,
                  int last_face,
                  uint8_t *moves)
{
    if (max2(rk_perm_dist[p], rk_orient_dist[o]) > left)
        return 0;
    if (left <= NEAR)
        return near_dist(p, o) <= left;
    for (int face = 0; face < 3; face++) {
        if (face == last_face)
            continue;
        unsigned np = p, no = o;
        for (int turn = 0; turn < 3; turn++) {
            np = rk_perm_move[face * RK_NP + np];
            no = rk_orient_move[face * RK_NO + no];
            moves[0] = (uint8_t) (face << 2 | turn);
            if (search(np, no, left - 1, face, moves + 1))
                return 1;
        }
    }
    return 0;
}

/* Apply move m = face << 2 | (quarter turns - 1) to (*p, *o). Moves are
 * encoded this way because RV32I has no divider: the face and the turn count
 * come out with a shift and a mask instead of / 3 and % 3.
 */
static void apply(unsigned m, unsigned *p, unsigned *o)
{
    unsigned face = m >> 2, turns = (m & 3) + 1;
    for (unsigned t = 0; t < turns; t++) {
        *p = rk_perm_move[face * RK_NP + *p];
        *o = rk_orient_move[face * RK_NO + *o];
    }
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    unsigned cubie[7], seen = 0, osum = 0, o = 0, p = 0;

    for (int i = 0; i < RUBIK_STATE_LEN; i++) {
        unsigned c = (unsigned char) state[i] - '1';
        if (c >= (i < 7 ? 7u : 3u))
            return -1; /* also catches an early NUL */
        if (i < 7) {
            if (seen & (1u << c))
                return -1; /* repeated cubie */
            seen |= 1u << c;
            cubie[i] = c;
        } else {
            osum += c;
            if (i < 13)
                o = o * 3 + c;
        }
    }
    /* osum is at most 14; bits 0, 3, 6, 9 and 12 mark the multiples of 3. */
    if (state[RUBIK_STATE_LEN] != '\0' || !((0x1249u >> osum) & 1))
        return -1;

    /* Lehmer code of the permutation. */
    for (int i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (int j = i + 1; j < 7; j++)
            smaller += cubie[j] < cubie[i];
        p = p * (unsigned) (7 - i) + smaller;
    }

    uint8_t moves[MAX_MOVES];
    unsigned len = max2(rk_perm_dist[p], rk_orient_dist[o]);
    while (!search(p, o, len, -1, moves))
        len++;

    /* The search path covers len - d moves; the table supplies the rest. */
    unsigned head = len > NEAR ? len - NEAR : 0;
    for (unsigned i = 0; i < head; i++)
        apply(moves[i], &p, &o);
    unsigned d = near_dist(p, o);
    head = len - d;
    for (unsigned i = head; i < len; i++) {
        for (unsigned m = 0; m < 11; m++) {
            if ((m & 3) == 3)
                continue; /* not a move */
            unsigned np = p, no = o;
            apply(m, &np, &no);
            if (near_dist(np, no) == len - 1 - i) {
                moves[i] = (uint8_t) m;
                p = np;
                o = no;
                break;
            }
        }
    }

    /* Each move is a face letter plus an optional "2" or "'". */
    size_t need = 1;
    for (unsigned i = 0; i < len; i++)
        need += (i ? 1 : 0) + 1 + ((moves[i] & 3) != 0);
    if (need > cap) {
        if (cap)
            out[0] = '\0';
        return -2;
    }
    char *w = out;
    for (unsigned i = 0; i < len; i++) {
        if (i)
            *w++ = ' ';
        *w++ = "RBD"[moves[i] >> 2];
        if ((moves[i] & 3) == 1)
            *w++ = '2';
        else if ((moves[i] & 3) == 2)
            *w++ = '\'';
    }
    *w = '\0';
    return (int) len;
}
