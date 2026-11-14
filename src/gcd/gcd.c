#include "gcd.h"

uint32_t gcd_u32(uint32_t a, uint32_t b)
{
    if (a == 0)
        return b;
    if (b == 0)
        return a;

    uint32_t t = a | b;
    unsigned shift = 0;
    while (!(t & 1)) {
        t >>= 1;
        shift++;
    }
    a >>= shift;
    b >>= shift;

    while (!(a & 1))
        a >>= 1;
    do {
        while (!(b & 1))
            b >>= 1;
        if (a > b) {
            uint32_t tmp = a;
            a = b;
            b = tmp;
        }
        b -= a;
    } while (b != 0);

    return a << shift;
}


/*
gcd(0, b) = b
gcd(2a, 2b) = 2 gcd(a, b)
gcd(2a, b) &= gcd(a, b)
gcd(a, b) &= gcd(a, b - a) both odd
*/
