# Deferred Items - Phase 16

## Pre-existing Test Failure

**CardDetail.test.tsx** - `calls onSendDraft with card ID and draft text on Confirm & Send`
- Test expects `onSendDraft(id, text)` but component now calls `onSendDraft(id, text, editDistanceRatio)` with 3 arguments
- Not caused by Phase 16 changes; pre-existing since editDistanceRatio was added to onSendDraft
- Fix: Update test assertion to include the third argument (editDistanceRatio = 0)
