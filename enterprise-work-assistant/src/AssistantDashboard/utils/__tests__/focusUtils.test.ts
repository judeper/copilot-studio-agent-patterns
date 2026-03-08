import { focusAfterRender } from "../focusUtils";

describe("focusAfterRender", () => {
    const originalRAF = window.requestAnimationFrame;

    afterEach(() => {
        window.requestAnimationFrame = originalRAF;
    });

    it("uses requestAnimationFrame when available", () => {
        const rafMock = jest.fn();
        window.requestAnimationFrame = rafMock;
        const callback = jest.fn();

        focusAfterRender(callback);

        expect(rafMock).toHaveBeenCalledWith(callback);
        expect(callback).not.toHaveBeenCalled();
    });

    it("falls back to setTimeout when rAF is unavailable", () => {
        jest.useFakeTimers();
        // Remove rAF to trigger fallback
        (window as unknown as Record<string, unknown>).requestAnimationFrame = undefined;
        const callback = jest.fn();

        focusAfterRender(callback);

        expect(callback).not.toHaveBeenCalled();
        jest.runAllTimers();
        expect(callback).toHaveBeenCalledTimes(1);
        jest.useRealTimers();
    });
});
