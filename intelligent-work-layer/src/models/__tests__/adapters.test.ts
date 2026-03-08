/**
 * Validation tests for Work OS adapter functions.
 * Verifies that AssistantCard → Work OS model mapping is correct
 * using realistic fixtures from the test suite.
 */
import {
  toWorkQueueItem,
  toAgentActivityItem,
  toShellState,
  toDraftArtifact,
} from "../adapters";
import {
  tier1SkipItem,
  tier2LightItem,
  tier3FullItem,
  calendarBriefingItem,
} from "../../test/fixtures/cardFixtures";
import type { AssistantCard, CommandSideEffect } from "../../AssistantDashboard/components/types";

// ── Helper: clone a fixture and override fields ─────────────────────
function cardWith(
  base: AssistantCard,
  overrides: Partial<AssistantCard>,
): AssistantCard {
  return { ...base, ...overrides };
}

// =====================================================================
// toWorkQueueItem
// =====================================================================
describe("toWorkQueueItem", () => {
  it("converts a FULL-tier email card with high confidence (≥90) to Ready state", () => {
    const card = cardWith(tier3FullItem, { confidence_score: 95 });
    const item = toWorkQueueItem(card);
    expect(item.state).toBe("Ready");
    expect(item.id).toBe(card.id);
    expect(item.itemType).toBe("draft_reply");
    expect(item.source).toBe("Outlook");
  });

  it("converts a FULL-tier card with low confidence (<90) to NeedsApproval state", () => {
    const item = toWorkQueueItem(tier3FullItem); // confidence_score = 87
    expect(item.state).toBe("NeedsApproval");
  });

  it('maps Priority "N/A" to "Low"', () => {
    const card = cardWith(tier2LightItem, { priority: "N/A" });
    const item = toWorkQueueItem(card);
    expect(item.priority).toBe("Low");
  });

  it('maps null priority to "Low"', () => {
    const item = toWorkQueueItem(tier1SkipItem); // priority is null
    expect(item.priority).toBe("Low");
  });

  it("handles cards where draft_payload is a string (JSON) gracefully", () => {
    const item = toWorkQueueItem(calendarBriefingItem); // draft_payload is a string
    // String draft_payload is NOT a DraftPayload object, so isDraftPayload returns false
    expect(item.itemType).toBe("briefing_pack");
    expect(item.state).toBeDefined();
  });

  it("handles cards where draft_payload is null", () => {
    const item = toWorkQueueItem(tier1SkipItem); // draft_payload is null
    expect(item.itemType).toBe("review_task");
  });

  it('maps SENT_AS_IS outcome to "Sent" state', () => {
    const card = cardWith(tier3FullItem, { card_outcome: "SENT_AS_IS" });
    const item = toWorkQueueItem(card);
    expect(item.state).toBe("Sent");
  });

  it('maps DISMISSED outcome to "Completed" state', () => {
    const card = cardWith(tier3FullItem, { card_outcome: "DISMISSED" });
    const item = toWorkQueueItem(card);
    expect(item.state).toBe("Completed");
  });

  it('maps EMAIL trigger to "Outlook" source', () => {
    const item = toWorkQueueItem(tier3FullItem);
    expect(item.source).toBe("Outlook");
  });

  it('maps TEAMS_MESSAGE trigger to "Teams" source', () => {
    const item = toWorkQueueItem(tier2LightItem);
    expect(item.source).toBe("Teams");
  });

  it('maps CALENDAR_SCAN trigger to "Calendar" source', () => {
    const item = toWorkQueueItem(calendarBriefingItem);
    expect(item.source).toBe("Calendar");
  });

  it('maps heartbeat triggers (PREP_REQUIRED etc.) to "Internal" source', () => {
    const card = cardWith(tier1SkipItem, {
      trigger_type: "PREP_REQUIRED",
    });
    const item = toWorkQueueItem(card);
    expect(item.source).toBe("Internal");
  });

  it('produces itemType "draft_reply" for EMAIL with draft', () => {
    const item = toWorkQueueItem(tier3FullItem); // EMAIL + DraftPayload
    expect(item.itemType).toBe("draft_reply");
  });

  it('produces itemType "quick_reply" for TEAMS_MESSAGE with draft', () => {
    const card = cardWith(tier2LightItem, {
      draft_payload: {
        draft_type: "TEAMS_MESSAGE",
        raw_draft: "Hey, looks good!",
        research_summary: "",
        recipient_relationship: "Internal colleague",
        inferred_tone: "collaborative",
        confidence_score: 95,
        user_context: "",
      },
    });
    const item = toWorkQueueItem(card);
    expect(item.itemType).toBe("quick_reply");
  });

  it('produces itemType "briefing_pack" for CALENDAR_SCAN', () => {
    const item = toWorkQueueItem(calendarBriefingItem);
    expect(item.itemType).toBe("briefing_pack");
  });

  it("sets governance.approvalRequired=true when confidence < 90", () => {
    const item = toWorkQueueItem(tier3FullItem); // confidence_score = 87
    expect(item.governance.approvalRequired).toBe(true);
  });

  it("sets governance.approvalRequired=false when confidence >= 90", () => {
    const card = cardWith(tier3FullItem, { confidence_score: 95 });
    const item = toWorkQueueItem(card);
    expect(item.governance.approvalRequired).toBe(false);
  });

  it("includes sourceContext when original_sender_email exists", () => {
    const item = toWorkQueueItem(tier3FullItem);
    expect(item.sourceContext).toBeDefined();
    expect(item.sourceContext).toHaveLength(1);
    expect(item.sourceContext![0].source).toBe("Outlook");
    expect(item.sourceContext![0].label).toBe(tier3FullItem.original_subject);
  });

  it("excludes sourceContext when original_sender_email is null", () => {
    const card = cardWith(tier1SkipItem, { original_sender_email: null });
    const item = toWorkQueueItem(card);
    expect(item.sourceContext).toBeUndefined();
  });
});

// =====================================================================
// toAgentActivityItem
// =====================================================================
describe("toAgentActivityItem", () => {
  const updateEffect: CommandSideEffect = {
    action: "UPDATE_CARD",
    description: "Updated card status to READY",
  };

  const createEffect: CommandSideEffect = {
    action: "CREATE_CARD",
    description: "Created new follow-up card",
  };

  it("converts UPDATE_CARD side effect to info tone", () => {
    const item = toAgentActivityItem(updateEffect);
    expect(item.tone).toBe("info");
  });

  it("converts CREATE_CARD side effect to success tone", () => {
    const item = toAgentActivityItem(createEffect);
    expect(item.tone).toBe("success");
  });

  it("formats timeLabel as HH:MM AM/PM", () => {
    const timestamp = new Date(2026, 1, 21, 14, 35, 0); // 2:35 PM
    const item = toAgentActivityItem(updateEffect, timestamp);
    expect(item.timeLabel).toBe("2:35 PM");
  });

  it('sets taskState to "completed"', () => {
    const item = toAgentActivityItem(updateEffect);
    expect(item.taskState).toBe("completed");
  });

  it("generates a non-empty id", () => {
    const item = toAgentActivityItem(updateEffect);
    expect(item.id).toBeTruthy();
    expect(item.id.length).toBeGreaterThan(0);
  });
});

// =====================================================================
// toShellState
// =====================================================================
describe("toShellState", () => {
  it('maps quietMode=true to allowedInterruptions="critical_only"', () => {
    const state = toShellState(true, 5);
    expect(state.allowedInterruptions).toBe("critical_only");
    expect(state.quietMode).toBe(true);
  });

  it('maps quietMode=false to allowedInterruptions="all"', () => {
    const state = toShellState(false, 3);
    expect(state.allowedInterruptions).toBe("all");
    expect(state.quietMode).toBe(false);
  });
});

// =====================================================================
// toDraftArtifact
// =====================================================================
describe("toDraftArtifact", () => {
  it("prefers humanized_draft over raw_draft when available", () => {
    const artifact = toDraftArtifact(tier3FullItem);
    expect(artifact).toBeDefined();
    expect(artifact!.content).toBe(tier3FullItem.humanized_draft);
  });

  it("falls back to raw_draft when humanized_draft is null", () => {
    const card = cardWith(tier3FullItem, { humanized_draft: null });
    const artifact = toDraftArtifact(card);
    expect(artifact).toBeDefined();
    expect(artifact!.content).toBe(
      (tier3FullItem.draft_payload as { raw_draft: string }).raw_draft,
    );
  });

  it('maps EMAIL draft_type to "email" channel', () => {
    const artifact = toDraftArtifact(tier3FullItem);
    expect(artifact).toBeDefined();
    expect(artifact!.channel).toBe("email");
  });

  it('maps TEAMS_MESSAGE draft_type to "teams" channel', () => {
    const card = cardWith(tier3FullItem, {
      draft_payload: {
        draft_type: "TEAMS_MESSAGE",
        raw_draft: "Quick update on the project",
        research_summary: "",
        recipient_relationship: "Internal colleague",
        inferred_tone: "collaborative",
        confidence_score: 90,
        user_context: "",
      },
    });
    const artifact = toDraftArtifact(card);
    expect(artifact).toBeDefined();
    expect(artifact!.channel).toBe("teams");
  });

  it("returns undefined when draft_payload is null", () => {
    const artifact = toDraftArtifact(tier1SkipItem);
    expect(artifact).toBeUndefined();
  });

  it("returns undefined when draft_payload is a plain string", () => {
    const artifact = toDraftArtifact(calendarBriefingItem);
    expect(artifact).toBeUndefined();
  });
});
