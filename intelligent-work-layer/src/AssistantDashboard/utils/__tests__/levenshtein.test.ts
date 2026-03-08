import { levenshteinRatio } from "../levenshtein";

describe("levenshteinRatio", () => {
    it("returns 0 for identical strings", () => {
        expect(levenshteinRatio("hello", "hello")).toBe(0);
    });

    it("returns 100 for a complete rewrite", () => {
        expect(levenshteinRatio("abc", "xyz")).toBe(100);
    });

    it("returns correct ratio for partial edit (kitten -> sitting)", () => {
        // Edit distance is 3 (k->s, e->i, insert g), max length is 7
        // 3/7 * 100 = 42.86 -> rounds to 43
        expect(levenshteinRatio("kitten", "sitting")).toBe(43);
    });

    it("returns 0 for two empty strings", () => {
        expect(levenshteinRatio("", "")).toBe(0);
    });

    it("returns 100 when first string is empty", () => {
        expect(levenshteinRatio("", "abc")).toBe(100);
    });

    it("returns 100 when second string is empty", () => {
        expect(levenshteinRatio("abc", "")).toBe(100);
    });

    it("is case-sensitive", () => {
        // "Hello World" vs "hello world" — differs in H->h and W->w (2 substitutions)
        // Edit distance = 2, max length = 11
        // 2/11 * 100 = 18.18 -> rounds to 18
        const ratio = levenshteinRatio("Hello World", "hello world");
        expect(ratio).toBe(18);
    });

    it("returns an integer", () => {
        const ratio = levenshteinRatio("abc", "ab");
        expect(Number.isInteger(ratio)).toBe(true);
    });

    it("handles single character strings", () => {
        expect(levenshteinRatio("a", "b")).toBe(100);
        expect(levenshteinRatio("a", "a")).toBe(0);
    });
});
