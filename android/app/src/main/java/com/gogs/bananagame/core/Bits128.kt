package com.gogs.bananagame.core

/**
 * A 128-bit bitmask (Swift's `UInt128`) as two longs, for the bitmask BFS solvers
 * (boards up to 128 cells). Immutable; equality and hashing are structural.
 */
data class Bits128(val lo: Long, val hi: Long) {
    infix fun or(o: Bits128) = Bits128(lo or o.lo, hi or o.hi)
    infix fun and(o: Bits128) = Bits128(lo and o.lo, hi and o.hi)
    fun inv() = Bits128(lo.inv(), hi.inv())
    infix fun andNot(o: Bits128) = Bits128(lo and o.lo.inv(), hi and o.hi.inv())
    val isZero get() = lo == 0L && hi == 0L
    val nonZero get() = !isZero

    fun has(i: Int): Boolean = if (i < 64) (lo ushr i) and 1L != 0L else (hi ushr (i - 64)) and 1L != 0L
    fun set(i: Int) = if (i < 64) Bits128(lo or (1L shl i), hi) else Bits128(lo, hi or (1L shl (i - 64)))
    fun clear(i: Int) = if (i < 64) Bits128(lo and (1L shl i).inv(), hi) else Bits128(lo, hi and (1L shl (i - 64)).inv())

    infix fun shl(n: Int): Bits128 = when {
        n <= 0 -> if (n == 0) this else shr(-n)
        n >= 128 -> ZERO
        n >= 64 -> Bits128(0L, lo shl (n - 64))
        else -> Bits128(lo shl n, (hi shl n) or (lo ushr (64 - n)))
    }

    infix fun shr(n: Int): Bits128 = when {
        n <= 0 -> if (n == 0) this else shl(-n)
        n >= 128 -> ZERO
        n >= 64 -> Bits128(hi ushr (n - 64), 0L)
        else -> Bits128((lo ushr n) or (hi shl (64 - n)), hi ushr n)
    }

    /** Index of the lowest set bit (128 if none). */
    fun trailingZeros(): Int = if (lo != 0L) java.lang.Long.numberOfTrailingZeros(lo)
    else if (hi != 0L) 64 + java.lang.Long.numberOfTrailingZeros(hi) else 128

    /** `x & (x - 1)`: drops the lowest set bit. */
    fun dropLowest(): Bits128 = if (lo != 0L) Bits128(lo and (lo - 1), hi) else Bits128(0L, hi and (hi - 1))

    fun popCount() = java.lang.Long.bitCount(lo) + java.lang.Long.bitCount(hi)

    companion object {
        val ZERO = Bits128(0L, 0L)
        fun bit(i: Int) = ZERO.set(i)
        /** The lowest `n` bits set. */
        fun ones(n: Int): Bits128 = when {
            n <= 0 -> ZERO
            n >= 128 -> Bits128(-1L, -1L)
            n >= 64 -> Bits128(-1L, if (n == 64) 0L else (1L shl (n - 64)) - 1)
            else -> Bits128((1L shl n) - 1, 0L)
        }
    }
}
