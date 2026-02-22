/**
 * Shared test fixtures mirroring actual Copilot Studio JSON output.
 *
 * Each fixture is a typed AssistantCard representing a specific triage tier
 * or edge case. Named exports make edge cases discoverable across test files.
 * All data is realistic — field values match what the Copilot Studio agent
 * produces and what useCardData parses from cr_fulljson.
 */
import type { AssistantCard } from '../../AssistantDashboard/components/types';
import type { MockRecordData } from '../mocks/componentFramework';

// ---------------------------------------------------------------------------
// Tier 1: SKIP — minimal card with summary only
// ---------------------------------------------------------------------------
export const tier1SkipItem: AssistantCard = {
    id: 'skip-001',
    trigger_type: 'EMAIL',
    triage_tier: 'SKIP',
    item_summary: 'Marketing newsletter from Contoso Weekly — no action needed.',
    priority: null,
    temporal_horizon: null,
    research_log: null,
    key_findings: null,
    verified_sources: null,
    confidence_score: null,
    card_status: 'SUMMARY_ONLY',
    draft_payload: null,
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/21/2026 10:30 AM',
};

// ---------------------------------------------------------------------------
// Tier 2: LIGHT — priority and temporal horizon, simple key_findings
// ---------------------------------------------------------------------------
export const tier2LightItem: AssistantCard = {
    id: 'light-001',
    trigger_type: 'TEAMS_MESSAGE',
    triage_tier: 'LIGHT',
    item_summary: 'Project status update from engineering lead.',
    priority: 'Medium',
    temporal_horizon: 'THIS_WEEK',
    research_log: null,
    key_findings: '- Sprint velocity on track\n- Two blockers flagged for review',
    verified_sources: null,
    confidence_score: null,
    card_status: 'SUMMARY_ONLY',
    draft_payload: null,
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/21/2026 9:45 AM',
};

// ---------------------------------------------------------------------------
// Tier 3: FULL — all fields populated including draft
// ---------------------------------------------------------------------------
export const tier3FullItem: AssistantCard = {
    id: 'full-001',
    trigger_type: 'EMAIL',
    triage_tier: 'FULL',
    item_summary: 'Contract renewal request from Fabrikam legal team.',
    priority: 'High',
    temporal_horizon: 'TODAY',
    research_log: 'Searched: contract renewal Fabrikam. Found active agreement expiring March 1. Checked SharePoint for latest terms.',
    key_findings: '- Contract expires March 1\n- Auto-renewal clause present\n- Legal review required before signing',
    verified_sources: [
        { title: 'Fabrikam Contract Portal', url: 'https://fabrikam.example.com/contracts', tier: 1 },
    ],
    confidence_score: 87,
    card_status: 'READY',
    draft_payload: {
        draft_type: 'EMAIL',
        raw_draft: 'Dear Fabrikam team,\n\nThank you for the contract renewal notice. We have reviewed the terms and would like to proceed with the following amendments...',
        research_summary: 'Contract analysis complete. Auto-renewal clause identified. Legal review recommended before March 1 deadline.',
        recipient_relationship: 'External client',
        inferred_tone: 'formal',
        confidence_score: 87,
        user_context: 'Renewal discussion initiated by Fabrikam legal department',
    },
    low_confidence_note: null,
    humanized_draft: 'Dear Fabrikam team, regarding the upcoming contract renewal, we have reviewed the terms and would like to discuss a few amendments before the March 1 deadline.',
    created_on: '2/21/2026 9:15 AM',
};

// ---------------------------------------------------------------------------
// LOW_CONFIDENCE — card with low confidence note
// ---------------------------------------------------------------------------
export const lowConfidenceItem: AssistantCard = {
    id: 'low-conf-001',
    trigger_type: 'EMAIL',
    triage_tier: 'FULL',
    item_summary: 'Ambiguous request from unknown sender regarding project timeline.',
    priority: 'Low',
    temporal_horizon: 'NEXT_WEEK',
    research_log: 'Searched: sender identity, project timeline references. Insufficient context found.',
    key_findings: '- Sender not in organization directory\n- Project name not matched to known projects',
    verified_sources: null,
    confidence_score: 32,
    card_status: 'LOW_CONFIDENCE',
    draft_payload: null,
    low_confidence_note: 'Unable to determine sender identity or project context. Manual review recommended before responding.',
    humanized_draft: null,
    created_on: '2/21/2026 8:00 AM',
};

// ---------------------------------------------------------------------------
// CALENDAR_SCAN — briefing text as plain string draft_payload
// ---------------------------------------------------------------------------
export const calendarBriefingItem: AssistantCard = {
    id: 'cal-001',
    trigger_type: 'CALENDAR_SCAN',
    triage_tier: 'LIGHT',
    item_summary: 'Quarterly business review with Northwind Traders at 2:00 PM.',
    priority: 'High',
    temporal_horizon: 'TODAY',
    research_log: null,
    key_findings: '- Q4 revenue figures prepared\n- Three open action items from last QBR',
    verified_sources: null,
    confidence_score: null,
    card_status: 'SUMMARY_ONLY',
    draft_payload: 'Meeting briefing: Quarterly business review with Northwind Traders. Key topics include Q4 revenue performance, outstanding action items from previous QBR, and partnership expansion discussion.',
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/21/2026 7:30 AM',
};

// ---------------------------------------------------------------------------
// Edge case: MockRecordData with malformed JSON in cr_fulljson
// ---------------------------------------------------------------------------
export const malformedJsonRecord: MockRecordData = {
    id: 'bad-001',
    values: {
        cr_fulljson: 'not valid json{',
        cr_humanizeddraft: null,
        createdon: null,
    },
    formattedValues: {
        createdon: '2/21/2026 11:00 AM',
    },
};

// ---------------------------------------------------------------------------
// Edge case: MockRecordData with valid full-tier JSON
// ---------------------------------------------------------------------------
export const validJsonRecord: MockRecordData = {
    id: 'valid-001',
    values: {
        cr_fulljson: JSON.stringify({
            trigger_type: 'EMAIL',
            triage_tier: 'FULL',
            item_summary: 'Contract renewal request from Fabrikam legal team.',
            priority: 'High',
            temporal_horizon: 'TODAY',
            research_log: 'Searched: contract renewal Fabrikam.',
            key_findings: '- Contract expires March 1',
            verified_sources: [
                { title: 'Fabrikam Portal', url: 'https://fabrikam.example.com', tier: 1 },
            ],
            confidence_score: 87,
            card_status: 'READY',
            draft_payload: {
                draft_type: 'EMAIL',
                raw_draft: 'Dear Fabrikam team...',
                research_summary: 'Contract analysis complete',
                recipient_relationship: 'External client',
                inferred_tone: 'formal',
                confidence_score: 87,
                user_context: 'Renewal discussion',
            },
            low_confidence_note: null,
        }),
        cr_humanizeddraft: 'Dear Fabrikam team, regarding the upcoming contract renewal...',
        createdon: null,
    },
    formattedValues: {
        createdon: '2/21/2026 9:15 AM',
    },
};

// ---------------------------------------------------------------------------
// Edge case: Empty dataset (no records)
// ---------------------------------------------------------------------------
export const emptyDataset = {
    sortedRecordIds: [] as string[],
    records: {} as Record<string, never>,
};
