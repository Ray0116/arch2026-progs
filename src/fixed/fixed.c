#include "fixed.h"

uint32_t op1(uint32_t a, uint32_t b, int *n)
{
    int count = 0;
    while (b != 0) {
        uint32_t c = (a & b) << 1;
        a ^= b;
        b = c;
        count++;
    }
    *n = count;
    return a;
}

uint32_t op2(uint32_t a, uint32_t b)
{
    return a - b;
}


uint32_t op3(uint32_t a, uint32_t b)
{
    return (a & b) + ((a ^ b) >> 1);
}



int32_t q_mul(int32_t a, int32_t b)
{
    uint32_t ua = (uint32_t) a, ub = (uint32_t) b;
    uint32_t al = ua & 0xFFFF, ah = ua >> 16;
    uint32_t bl = ub & 0xFFFF, bh = ub >> 16;

    uint32_t ll = al * bl, lh = al * bh, hl = ah * bl, hh = ah * bh;
    uint32_t mid = lh + hl;
    uint32_t mid_carry = (mid < lh) ? 0x10000u : 0;
    uint32_t lo = ll + (mid << 16);
    uint32_t hi = hh + (mid >> 16) + mid_carry + (lo < ll);

    if (a < 0)
        hi -= ub;
    if (b < 0)
        hi -= ua;

    hi += lo >= 0xFFF80000u; /* lo + 2^19 carries out */
    uint32_t lo2 = lo + (1u << 19);
    return (int32_t) ((lo2 >> 20) | (hi << 12));
}
