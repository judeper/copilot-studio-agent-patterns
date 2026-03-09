import { vi } from 'vitest';
import { focusAfterRender } from "../focusUtils";

describe("focusAfterRender", () => {
    const originalRAF = window.requestAnimationFrame;

    afterEach(() => {
        window.requestAnimationFrame = originalRAF;
    });

    it("uses requestAnimationFrame when available", () => {
        const rafMock = vi.fn();
        window.requestAnimationFrame = rafMock;
        const callback = vi.fn();

        focusAfterRender(callback);

        expect(rafMock).toHaveBeenCalledWith(callback);
        expect(callback).not.toHaveBeenCalled();
    });

    it("falls back to setTimeout when rAF is unavailable", () => {
        vi.useFakeTimers();
        // Remove rAF to trigger fallback
        (window as unknown as Record<string, unknown>).requestAnimationFrame = undefined;
        const callback = vi.fn();

        focusAfterRender(callback);

        expect(callback).not.toHaveBeenCalled();
        vi.runAllTimers();
        expect(callback).toHaveBeenCalledTimes(1);
        vi.useRealTimers();
    });
});
