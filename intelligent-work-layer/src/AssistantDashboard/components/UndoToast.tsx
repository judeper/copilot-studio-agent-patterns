import * as React from "react";
import { Button, Text } from "@fluentui/react-components";
import { ArrowUndoRegular } from "@fluentui/react-icons";

const UNDO_TIMEOUT_MS = 10_000;

interface UndoToastProps {
    message: string;
    onUndo: () => void;
    onExpire: () => void;
}

export const UndoToast: React.FC<UndoToastProps> = ({ message, onUndo, onExpire }) => {
    const [remaining, setRemaining] = React.useState(UNDO_TIMEOUT_MS);
    const startTimeRef = React.useRef(Date.now());

    React.useEffect(() => {
        const interval = setInterval(() => {
            const elapsed = Date.now() - startTimeRef.current;
            const left = Math.max(0, UNDO_TIMEOUT_MS - elapsed);
            setRemaining(left);
            if (left === 0) {
                clearInterval(interval);
                onExpire();
            }
        }, 100);
        return () => clearInterval(interval);
    }, [onExpire]);

    const progress = remaining / UNDO_TIMEOUT_MS;

    return (
        <div className="undo-toast" role="alert" aria-live="polite">
            <div
                className="undo-toast-progress"
                style={{ width: `${progress * 100}%` }}
            />
            <Text size={300}>{message}</Text>
            <Button
                appearance="transparent"
                icon={<ArrowUndoRegular />}
                onClick={onUndo}
                size="small"
            >
                Undo
            </Button>
        </div>
    );
};

/** Hook to manage a single undo-able action with deferred execution. */
export function useUndoAction() {
    const [pending, setPending] = React.useState<{
        message: string;
        execute: () => void;
        rollback: () => void;
    } | null>(null);

    const startAction = React.useCallback(
        (message: string, execute: () => void, rollback: () => void) => {
            setPending({ message, execute, rollback });
        },
        [],
    );

    const handleUndo = React.useCallback(() => {
        if (pending) {
            pending.rollback();
            setPending(null);
        }
    }, [pending]);

    const handleExpire = React.useCallback(() => {
        if (pending) {
            pending.execute();
            setPending(null);
        }
    }, [pending]);

    return { pending, startAction, handleUndo, handleExpire };
}
