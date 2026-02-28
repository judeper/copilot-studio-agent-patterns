import { renderHook } from '@testing-library/react';
import { useCardData } from '../useCardData';
import { createMockDataset, MockRecordData } from '../../../test/mocks/componentFramework';
import {
    validJsonRecord,
    malformedJsonRecord,
    emptyDataset,
} from '../../../test/fixtures/cardFixtures';

describe('useCardData', () => {
    it('parses valid JSON records into AssistantCard array', () => {
        const dataset = createMockDataset([validJsonRecord]);

        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(1);
        expect(result.current[0].trigger_type).toBe('EMAIL');
        expect(result.current[0].triage_tier).toBe('FULL');
        expect(result.current[0].item_summary).toBe('Contract renewal request from Fabrikam legal team.');
        expect(result.current[0].priority).toBe('High');
        expect(result.current[0].confidence_score).toBe(87);
    });

    it('parses multiple records across tiers', () => {
        const skipRecord: MockRecordData = {
            id: 'skip-rec',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'EMAIL',
                    triage_tier: 'SKIP',
                    item_summary: 'Newsletter',
                    priority: null,
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
            },
            formattedValues: { createdon: '2/21/2026 10:00 AM' },
        };

        const lightRecord: MockRecordData = {
            id: 'light-rec',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'TEAMS_MESSAGE',
                    triage_tier: 'LIGHT',
                    item_summary: 'Status update',
                    priority: 'Medium',
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
            },
            formattedValues: { createdon: '2/21/2026 9:00 AM' },
        };

        const dataset = createMockDataset([skipRecord, lightRecord, validJsonRecord]);

        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(3);
        expect(result.current[0].triage_tier).toBe('SKIP');
        expect(result.current[1].triage_tier).toBe('LIGHT');
        expect(result.current[2].triage_tier).toBe('FULL');
    });

    it('returns empty array for undefined dataset', () => {
        const { result } = renderHook(() => useCardData(undefined, 1));
        expect(result.current).toEqual([]);
    });

    it('returns empty array for empty dataset', () => {
        const { result } = renderHook(() => useCardData(emptyDataset, 1));
        expect(result.current).toEqual([]);
    });

    it('skips records with malformed JSON', () => {
        const dataset = createMockDataset([malformedJsonRecord, validJsonRecord]);

        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(1);
        expect(result.current[0].id).toBe('valid-001');
    });

    it('skips records where cr_fulljson is null', () => {
        const nullJsonRecord: MockRecordData = {
            id: 'null-json-001',
            values: {
                cr_fulljson: null,
                cr_humanizeddraft: null,
            },
            formattedValues: { createdon: '2/21/2026 11:00 AM' },
        };

        const dataset = createMockDataset([nullJsonRecord]);

        const { result } = renderHook(() => useCardData(dataset, 1));
        expect(result.current).toEqual([]);
    });

    it('returns null priority and confidence_score for SKIP tier', () => {
        const skipRecord: MockRecordData = {
            id: 'skip-tier',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'EMAIL',
                    triage_tier: 'SKIP',
                    item_summary: 'Marketing newsletter',
                    priority: null,
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
            },
            formattedValues: { createdon: '2/21/2026 10:30 AM' },
        };

        const dataset = createMockDataset([skipRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(1);
        expect(result.current[0].priority).toBeNull();
        expect(result.current[0].confidence_score).toBeNull();
    });

    it('returns all fields for FULL tier including verified_sources array', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(1);
        const card = result.current[0];
        expect(card.verified_sources).toBeInstanceOf(Array);
        expect(card.verified_sources).toHaveLength(1);
        expect(card.verified_sources![0].title).toBe('Fabrikam Portal');
        expect(card.confidence_score).toBe(87);
        expect(typeof card.confidence_score).toBe('number');
    });

    it('converts N/A priority to null (ingestion boundary)', () => {
        const naRecord: MockRecordData = {
            id: 'na-priority',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'EMAIL',
                    triage_tier: 'LIGHT',
                    item_summary: 'Item with N/A priority',
                    priority: 'N/A',
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
            },
            formattedValues: { createdon: '2/21/2026 8:00 AM' },
        };

        const dataset = createMockDataset([naRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current).toHaveLength(1);
        expect(result.current[0].priority).toBeNull();
    });

    it('populates humanized_draft from cr_humanizeddraft column', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].humanized_draft).toBe(
            'Dear Fabrikam team, regarding the upcoming contract renewal...'
        );
    });

    it('populates created_on from getFormattedValue("createdon")', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].created_on).toBe('2/21/2026 9:15 AM');
    });

    // ── Sprint 1A: Outcome tracking and sender context ──

    it('reads card_outcome from cr_cardoutcome formatted value', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].card_outcome).toBe('PENDING');
    });

    it('reads original_sender_email from cr_originalsenderemail', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].original_sender_email).toBe('legal@fabrikam.com');
    });

    it('reads original_sender_display from cr_originalsenderdisplay', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].original_sender_display).toBe('Fabrikam Legal');
    });

    it('reads original_subject from cr_originalsubject', () => {
        const dataset = createMockDataset([validJsonRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].original_subject).toBe(
            'Contract Renewal — Contoso Agreement #2024-1847'
        );
    });

    it('defaults card_outcome to PENDING when column is empty', () => {
        const noOutcomeRecord: MockRecordData = {
            id: 'no-outcome',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'EMAIL',
                    triage_tier: 'LIGHT',
                    item_summary: 'Test',
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
                cr_originalsenderemail: null,
                cr_originalsenderdisplay: null,
                cr_originalsubject: null,
            },
            formattedValues: {
                createdon: '2/21/2026 10:00 AM',
                // cr_cardoutcome intentionally omitted
            },
        };

        const dataset = createMockDataset([noOutcomeRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].card_outcome).toBe('PENDING');
    });

    it('parses SENT_AS_IS outcome correctly', () => {
        const sentRecord: MockRecordData = {
            ...validJsonRecord,
            id: 'sent-test',
            formattedValues: {
                ...validJsonRecord.formattedValues,
                cr_cardoutcome: 'SENT_AS_IS',
            },
        };

        const dataset = createMockDataset([sentRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].card_outcome).toBe('SENT_AS_IS');
    });

    it('parses DISMISSED outcome correctly', () => {
        const dismissedRecord: MockRecordData = {
            ...validJsonRecord,
            id: 'dismissed-test',
            formattedValues: {
                ...validJsonRecord.formattedValues,
                cr_cardoutcome: 'DISMISSED',
            },
        };

        const dataset = createMockDataset([dismissedRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].card_outcome).toBe('DISMISSED');
    });

    it('returns null for sender fields when not populated', () => {
        const noSenderRecord: MockRecordData = {
            id: 'no-sender',
            values: {
                cr_fulljson: JSON.stringify({
                    trigger_type: 'TEAMS_MESSAGE',
                    triage_tier: 'LIGHT',
                    item_summary: 'Teams message',
                    card_status: 'SUMMARY_ONLY',
                }),
                cr_humanizeddraft: null,
                cr_originalsenderemail: null,
                cr_originalsenderdisplay: null,
                cr_originalsubject: null,
            },
            formattedValues: {
                createdon: '2/21/2026 10:00 AM',
                cr_cardoutcome: 'PENDING',
            },
        };

        const dataset = createMockDataset([noSenderRecord]);
        const { result } = renderHook(() => useCardData(dataset, 1));

        expect(result.current[0].original_sender_email).toBeNull();
        expect(result.current[0].original_sender_display).toBeNull();
        expect(result.current[0].original_subject).toBeNull();
    });
});
