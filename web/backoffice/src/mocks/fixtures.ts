// 계약(backoffice-bff.yaml) 모양 픽스처. 계약에 없는 필드는 넣지 않는다.
import type { ApprovalInboxView } from '../api/views';

export const approvalInbox: ApprovalInboxView = {
  sources: [
    {
      system: 'approval-service',
      asOf: { asOf: '2026-10-24T06:00:00Z', freshness: 'CURRENT' },
      confidence: 'DIRECT',
    },
    {
      system: 'order-service',
      asOf: { asOf: '2026-10-24T05:58:00Z', freshness: 'STALE' },
      confidence: 'COPY',
    },
  ],
  unavailableSources: [],
  composedAt: '2026-10-24T06:00:01Z',
  items: [
    {
      dossierId: 'dos-mock-1',
      approvalType: 'PRICE_CHANGE',
      requestState: 'SUBMITTED',
      reviewState: 'PENDING',
      executionState: 'NOT_STARTED',
      targetRef: 'price-version:E-00000001:12',
      expectedVersion: 12,
      requestedBy: 'op-mock-1',
      submittedAt: '2026-10-24T05:30:00Z',
    },
  ],
  page: { nextCursor: null, size: 50 },
};
