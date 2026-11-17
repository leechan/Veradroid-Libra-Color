// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.ime;

/** Key edges of a row (plain Java: KeyRow uses it, the JVM tests check it at every panel width). */
final class KeyGrid {
    private KeyGrid() { }

    /**
     * Key i of a row of width w spans [e[i], e[i+1]): e[i] = round(w * (weights before i) / sum), e[n] = w.
     * The leftover pixels are spread over the row (no key is more than 1 px wider than another of the same
     * weight), and rows with the same weights before a key share that key's edge exactly.
     */
    static int[] edges(int w, float[] weights) {
        double sum = 0;
        for (float x : weights) sum += x;
        int[] e = new int[weights.length + 1];
        double acc = 0;
        for (int i = 0; i < weights.length; i++) { e[i] = (int) Math.round(w * acc / sum); acc += weights[i]; }
        e[weights.length] = w;
        return e;
    }
}
