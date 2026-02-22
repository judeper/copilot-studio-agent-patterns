/**
 * Minimal ComponentFramework mock for unit testing.
 *
 * PCF virtual controls receive data through the ComponentFramework.PropertyTypes.DataSet
 * interface. The useCardData hook defines its own DataSet/DataSetRecord interfaces that
 * mirror this API surface. This mock creates dataset objects that satisfy those interfaces
 * without requiring the full PCF runtime.
 *
 * Why a factory: Each test gets a fresh dataset instance, avoiding shared mutable state
 * between tests. The factory accepts an array of record data and builds the sortedRecordIds
 * and records map automatically.
 */

export interface MockRecordData {
    id: string;
    values: Record<string, string | number | null>;
    formattedValues?: Record<string, string>;
}

export function createMockDataset(records: MockRecordData[]) {
    return {
        sortedRecordIds: records.map(r => r.id),
        records: Object.fromEntries(
            records.map(r => [
                r.id,
                {
                    getRecordId: () => r.id,
                    getValue: (col: string) => r.values[col] ?? null,
                    getFormattedValue: (col: string) => r.formattedValues?.[col] ?? '',
                },
            ])
        ),
    };
}
