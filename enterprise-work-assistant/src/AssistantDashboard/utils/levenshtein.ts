/**
 * Computes the normalized Levenshtein edit distance ratio between two strings.
 *
 * @returns Integer 0-100 where 0 = identical and 100 = complete rewrite.
 *          Uses two-row iterative algorithm for O(min(m,n)) space.
 */
export function levenshteinRatio(a: string, b: string): number {
    if (a === b) return 0;
    if (a.length === 0 || b.length === 0) return 100;

    // Ensure b is the shorter string for space optimization
    if (a.length < b.length) {
        [a, b] = [b, a];
    }

    const m = a.length;
    const n = b.length;

    // Two-row iterative Levenshtein distance
    let prev = new Array<number>(n + 1);
    let curr = new Array<number>(n + 1);

    for (let j = 0; j <= n; j++) {
        prev[j] = j;
    }

    for (let i = 1; i <= m; i++) {
        curr[0] = i;
        for (let j = 1; j <= n; j++) {
            const cost = a[i - 1] === b[j - 1] ? 0 : 1;
            curr[j] = Math.min(
                prev[j] + 1,      // deletion
                curr[j - 1] + 1,  // insertion
                prev[j - 1] + cost // substitution
            );
        }
        [prev, curr] = [curr, prev];
    }

    const distance = prev[n];
    return Math.round((distance / Math.max(m, n)) * 100);
}
