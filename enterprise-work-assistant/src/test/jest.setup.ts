import '@testing-library/jest-dom';

// jsdom does not implement matchMedia. The App component's usePrefersDarkMode
// hook calls window.matchMedia, which would throw without this mock.
Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: jest.fn().mockImplementation(query => ({
        matches: false,
        media: query,
        onchange: null,
        addListener: jest.fn(),
        removeListener: jest.fn(),
        addEventListener: jest.fn(),
        removeEventListener: jest.fn(),
        dispatchEvent: jest.fn(),
    })),
});

// jsdom does not implement ResizeObserver. Fluent UI v9 MessageBar uses
// ResizeObserver internally for reflow detection.
class ResizeObserverMock {
    observe() { /* no-op */ }
    unobserve() { /* no-op */ }
    disconnect() { /* no-op */ }
}
window.ResizeObserver = ResizeObserverMock as unknown as typeof ResizeObserver;
