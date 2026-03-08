import type { CloseOfDayReviewModel } from "../models/review";

export const mockCloseOfDayReview: CloseOfDayReviewModel = {
  metrics: [
    {
      id: "review-completed",
      label: "Completed",
      value: "7 actions",
      note: "Customer reply sent, meeting pack reviewed, and one work packet created."
    },
    {
      id: "review-deferred",
      label: "Deferred",
      value: "2 items",
      note: "Both have been placed into tomorrow’s protected focus lane with context preserved."
    },
    {
      id: "review-focus",
      label: "Protected focus",
      value: "3.5 hours",
      note: "Only two critical interruptions were allowed through."
    }
  ],
  carryForward: [
    {
      id: "carry-first-focus-block",
      label: "First focus block",
      value: "Refine Work OS product blueprint trust model"
    },
    {
      id: "carry-held-for-tomorrow",
      label: "Held for tomorrow",
      value: "Manager summary draft and one planning refinement"
    },
    {
      id: "carry-risk-watch",
      label: "Risk watch",
      value: "Approval-routing decision still needs team alignment"
    },
    {
      id: "carry-morning-setup",
      label: "Morning setup",
      value: "Start tomorrow with quiet mode on and the review summary pinned"
    }
  ],
  primaryAction: {
    id: "act-finalize-review",
    label: "Finalize review",
    actionType: "generate_review",
    requiresApproval: false,
    reversible: true
  },
  secondaryActions: [
    {
      id: "act-rebuild-tomorrow-lane",
      label: "Rebuild tomorrow lane",
      actionType: "rebuild_lane"
    }
  ]
};
