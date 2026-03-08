import type { InterruptionWorkbenchModel } from "../models/messaging";

export const mockInterruptionWorkbench: InterruptionWorkbenchModel = {
  selectedItemId: "msg-unum-scope",
  items: [
    {
      id: "msg-unum-scope",
      source: "Outlook",
      senderDisplayName: "Derek D'Amore",
      title: "UNUM follow-up on scope",
      summary: "Needs confirmation of workshop scope, owners, and expected deliverables.",
      rationale: "Customer risk + meeting dependency",
      confidence: 92,
      draft: {
        id: "draft-unum-scope",
        content:
          "Hi Derek,

Thank you for the follow-up. I reviewed the current scope and recommend we confirm the workshop objectives, target audience, and expected outputs before finalizing the plan. I can send a revised outline today based on those priorities.

Best regards,
Jude",
        channel: "email",
        editable: true,
        version: 1
      },
      governance: {
        approvalRequired: true,
        approvalState: "pending",
        reviewability: "full_preview",
        interventionAllowed: true,
        auditVisible: true,
        rationaleVisible: true
      },
      sourceContext: [
        {
          id: "outlook-thread-unum-scope",
          source: "Outlook",
          label: "UNUM follow-up on scope",
          deepLink: "msteams://m365/outlook/mail/unum-scope-thread",
          previewAvailable: true
        }
      ],
      producedBy: {
        agentId: "triage-agent-01",
        agentName: "Communication Triage Agent",
        agentType: "triage",
        runId: "run-triage-1001"
      }
    },
    {
      id: "msg-manager-priority-view",
      source: "Teams",
      senderDisplayName: "Michelle Bozeman",
      title: "Latest customer priorities",
      summary: "Manager requests a concise consolidated view of current customer priorities before Monday.",
      rationale: "Manager request",
      confidence: 97,
      draft: {
        id: "draft-manager-priorities",
        content:
          "Yes. I am consolidating the open customer priorities into a single view and will share the latest summary shortly.",
        channel: "teams",
        editable: true,
        version: 1
      },
      governance: {
        approvalRequired: false,
        approvalState: "not_required",
        reviewability: "full_preview",
        interventionAllowed: true,
        auditVisible: true,
        rationaleVisible: true
      },
      sourceContext: [
        {
          id: "teams-thread-priorities",
          source: "Teams",
          label: "Latest customer priorities",
          deepLink: "https://teams.microsoft.com/l/message/priority-view-thread",
          previewAvailable: true
        }
      ],
      producedBy: {
        agentId: "triage-agent-01",
        agentName: "Communication Triage Agent",
        agentType: "triage",
        runId: "run-triage-1002"
      }
    }
  ]
};
