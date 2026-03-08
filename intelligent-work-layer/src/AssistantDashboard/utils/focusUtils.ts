/**
 * Schedule a focus callback after the next animation frame,
 * falling back to setTimeout for environments without rAF.
 */
export function focusAfterRender(callback: () => void): void {
    if (typeof window !== "undefined" && typeof window.requestAnimationFrame === "function") {
        window.requestAnimationFrame(callback);
        return;
    }
    setTimeout(callback, 0);
}
