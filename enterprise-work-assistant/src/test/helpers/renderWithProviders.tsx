import * as React from 'react';
import { render, RenderOptions } from '@testing-library/react';
import { FluentProvider, webLightTheme } from '@fluentui/react-components';

/**
 * Wraps the component under test in FluentProvider with webLightTheme.
 *
 * All Fluent UI v9 components require a FluentProvider ancestor to resolve
 * design tokens (colors, spacing, typography). Tests that render Fluent
 * components without this wrapper will silently produce unstyled output.
 */
function Wrapper({ children }: { children: React.ReactNode }) {
    return (
        <FluentProvider theme={webLightTheme}>
            {children}
        </FluentProvider>
    );
}

export function renderWithProviders(
    ui: React.ReactElement,
    options?: Omit<RenderOptions, 'wrapper'>,
) {
    return render(ui, { wrapper: Wrapper, ...options });
}
