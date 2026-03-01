import * as React from "react";
import { Button } from "@fluentui/react-components";

interface ErrorBoundaryState {
    hasError: boolean;
    error: Error | null;
}

/**
 * React error boundary for the AssistantDashboard content area.
 *
 * Catches render crashes from malformed card data or unexpected component errors
 * and displays a recovery UI instead of crashing the entire dashboard.
 * Implemented as a class component because React 16 does not support
 * error boundaries via hooks.
 */
export class ErrorBoundary extends React.Component<
    { children: React.ReactNode },
    ErrorBoundaryState
> {
    constructor(props: { children: React.ReactNode }) {
        super(props);
        this.state = { hasError: false, error: null };
    }

    static getDerivedStateFromError(error: Error): ErrorBoundaryState {
        return { hasError: true, error };
    }

    componentDidCatch(error: Error, errorInfo: React.ErrorInfo): void {
        console.error("AssistantDashboard error:", error, errorInfo);
    }

    render(): React.ReactNode {
        if (this.state.hasError) {
            return (
                <div style={{ padding: "20px", textAlign: "center" }}>
                    <h3>Something went wrong</h3>
                    <p>The dashboard encountered an error. Please refresh the page.</p>
                    <Button
                        appearance="primary"
                        onClick={() => this.setState({ hasError: false, error: null })}
                    >
                        Try Again
                    </Button>
                </div>
            );
        }
        return this.props.children;
    }
}
