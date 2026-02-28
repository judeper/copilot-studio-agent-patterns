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
    card_outcome: 'PENDING',
    original_sender_email: 'newsletter@contoso.com',
    original_sender_display: 'Contoso Weekly',
    original_subject: 'Contoso Weekly Newsletter — February 2026',
    conversation_cluster_id: 'conv-newsletter-001',
    source_signal_id: 'msgid-skip-001@contoso.com',
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
    card_outcome: 'PENDING',
    original_sender_email: 'alee@contoso.com',
    original_sender_display: 'Alex Lee',
    original_subject: null,
    conversation_cluster_id: 'thread-teams-001',
    source_signal_id: 'msg-light-001',
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
    card_outcome: 'PENDING',
    original_sender_email: 'legal@fabrikam.com',
    original_sender_display: 'Fabrikam Legal',
    original_subject: 'Contract Renewal — Contoso Agreement #2024-1847',
    conversation_cluster_id: 'conv-fabrikam-renewal',
    source_signal_id: 'msgid-full-001@fabrikam.com',
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
    card_outcome: 'PENDING',
    original_sender_email: 'unknown@external.com',
    original_sender_display: null,
    original_subject: 'Re: Project Timeline Inquiry',
    conversation_cluster_id: 'conv-woodgrove-timeline',
    source_signal_id: 'msgid-lowconf-001@woodgrove.com',
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
    card_outcome: 'PENDING',
    original_sender_email: 'jsmith@northwindtraders.com',
    original_sender_display: 'Janet Smith',
    original_subject: 'Quarterly Business Review',
    conversation_cluster_id: 'series-qbr-master-001',
    source_signal_id: 'event-cal-001',
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
        cr_originalsenderemail: null,
        cr_originalsenderdisplay: null,
        cr_originalsubject: null,
        cr_conversationclusterid: null,
        cr_sourcesignalid: null,
    },
    formattedValues: {
        createdon: '2/21/2026 11:00 AM',
        cr_cardoutcome: 'PENDING',
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
        cr_originalsenderemail: 'legal@fabrikam.com',
        cr_originalsenderdisplay: 'Fabrikam Legal',
        cr_originalsubject: 'Contract Renewal — Contoso Agreement #2024-1847',
        cr_conversationclusterid: 'conv-fabrikam-renewal',
        cr_sourcesignalid: 'msgid-full-001@fabrikam.com',
    },
    formattedValues: {
        createdon: '2/21/2026 9:15 AM',
        cr_cardoutcome: 'PENDING',
    },
};

// ---------------------------------------------------------------------------
// Edge case: Empty dataset (no records)
// ---------------------------------------------------------------------------
export const emptyDataset = {
    sortedRecordIds: [] as string[],
    records: {} as Record<string, never>,
};

// ---------------------------------------------------------------------------
// Sprint 2: DAILY_BRIEFING card with full briefing JSON in draft_payload
// ---------------------------------------------------------------------------
export const dailyBriefingItem: AssistantCard = {
    id: 'briefing-001',
    trigger_type: 'DAILY_BRIEFING',
    triage_tier: 'FULL',
    item_summary: 'You have 8 open items with 3 needing action today. The most urgent is Sarah Chen\'s budget revision — 36 hours pending with your 2 PM call approaching.',
    priority: 'High',
    temporal_horizon: null,
    research_log: null,
    key_findings: null,
    verified_sources: null,
    confidence_score: 100,
    card_status: 'READY',
    draft_payload: JSON.stringify({
        briefing_type: 'DAILY',
        briefing_date: '2026-02-28',
        total_open_items: 8,
        day_shape: 'You have 8 open items with 3 needing action today. The most urgent is Sarah Chen\'s budget revision — 36 hours pending with your 2 PM call approaching.',
        action_items: [
            {
                rank: 1,
                card_ids: ['full-001'],
                thread_summary: 'Contract renewal from Fabrikam legal — deadline March 1',
                recommended_action: 'Review proposed terms and confirm before deadline',
                urgency_reason: '28 hours pending, High priority, March 1 deadline',
                related_calendar: null,
            },
            {
                rank: 2,
                card_ids: ['full-002', 'full-003'],
                thread_summary: 'Budget revision from Sarah Chen — 2 emails in thread',
                recommended_action: 'Reply with updated figures before 2 PM call',
                urgency_reason: '36 hours pending, typically respond to Sarah within 2 hours',
                related_calendar: 'Q3 Budget Review — 2:00 PM today',
            },
        ],
        fyi_items: [
            {
                card_ids: ['cal-001'],
                summary: 'QBR with Northwind Traders at 2 PM — prep notes ready',
                category: 'MEETING_PREP',
            },
        ],
        stale_alerts: [
            {
                card_id: 'stale-001',
                summary: 'US Bank compliance review — 5 days without action',
                hours_pending: 120,
                recommended_action: 'DELEGATE',
            },
        ],
    }),
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/28/2026 7:00 AM',
    card_outcome: 'PENDING',
    original_sender_email: null,
    original_sender_display: null,
    original_subject: null,
    conversation_cluster_id: null,
    source_signal_id: null,
};

// ---------------------------------------------------------------------------
// Sprint 2: NUDGE card — staleness reminder for an overdue item
// ---------------------------------------------------------------------------
export const nudgeItem: AssistantCard = {
    id: 'nudge-001',
    trigger_type: 'EMAIL',
    triage_tier: 'LIGHT',
    item_summary: 'Reminder: Contract renewal request from Fabrikam legal team — 48h without action',
    priority: 'High',
    temporal_horizon: null,
    research_log: null,
    key_findings: null,
    verified_sources: null,
    confidence_score: null,
    card_status: 'NUDGE',
    draft_payload: null,
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/23/2026 12:00 PM',
    card_outcome: 'PENDING',
    original_sender_email: 'legal@fabrikam.com',
    original_sender_display: 'Fabrikam Legal',
    original_subject: 'Contract Renewal — Contoso Agreement #2024-1847',
    conversation_cluster_id: 'conv-fabrikam-renewal',
    source_signal_id: 'msgid-full-001@fabrikam.com',
};

// ---------------------------------------------------------------------------
// Sprint 2: DAILY_BRIEFING card — synthesized daily action plan
// ---------------------------------------------------------------------------
export const briefingCardItem: AssistantCard = {
    id: 'briefing-001',
    trigger_type: 'DAILY_BRIEFING',
    triage_tier: 'FULL',
    item_summary: 'You have 8 open items with 3 needing action today.',
    priority: null,
    temporal_horizon: null,
    research_log: null,
    key_findings: null,
    verified_sources: null,
    confidence_score: 100,
    card_status: 'READY',
    draft_payload: JSON.stringify({
        briefing_type: 'DAILY',
        briefing_date: '2026-02-28',
        total_open_items: 8,
        day_shape: 'You have 8 open items with 3 needing action today. The most urgent is Sarah Chen\'s budget revision request.',
        action_items: [
            {
                rank: 1,
                card_ids: ['full-001'],
                thread_summary: 'Q3 budget revision request from Sarah Chen',
                recommended_action: 'Reply to Sarah with updated figures before your 2 PM call',
                urgency_reason: '36 hours pending',
                related_calendar: 'Q3 Budget Review — 2:00 PM today',
            },
        ],
        fyi_items: [
            {
                card_ids: ['light-001'],
                summary: 'IT maintenance window this Saturday',
                category: 'INFO_UPDATE',
            },
        ],
        stale_alerts: [
            {
                card_id: 'full-003',
                summary: 'US Bank compliance doc — 5 days with no action',
                hours_pending: 120,
                recommended_action: 'DELEGATE',
            },
        ],
    }),
    low_confidence_note: null,
    humanized_draft: null,
    created_on: '2/28/2026 7:00 AM',
    card_outcome: 'PENDING',
    original_sender_email: null,
    original_sender_display: null,
    original_subject: null,
    conversation_cluster_id: null,
    source_signal_id: null,
};
