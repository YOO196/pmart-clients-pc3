// ⚠ 화면 개발·시험용 목 — 본사 승인(approval-service) 변경 요청 만들기·제출·승인 조회. 실제 서버 동작이 아니다.
// 규칙(계약 흉내): 초안 201 → 제출 202(resultId = approvalId, X-Expected-Version = 초안 버전). 같은 대상의 열린 승인이 있으면 409 DUPLICATE_APPROVAL.
// 승인 조회: 첫 조회는 REVIEW_PENDING, 두 번째부터 APPROVED(본사가 그 사이 승인했다고 흉내). 그 뒤 그 번호로 집행하면 받는다(support.approvalProblem).
import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { db, nextSeq } from './db';
import { expectedVersion, idempotent, operator, problem, unauthorized } from './support';

export const approvalHandlers = [
  http.post(`${API_BASE}/change-requests`, async ({ request }) => {
    if (!operator(request)) return unauthorized();
    const body = (await request.json()) as Record<string, unknown>;
    return idempotent(request, () => {
      if (typeof body.targetRef !== 'string' || !body.type) return problem(400, 'VALIDATION_FAILED');
      const id = `CR-${nextSeq()}`;
      db.changeRequests.set(id, { changeRequestId: id, version: 1, body, approvalId: null });
      return { status: 201, body: { ...body, changeRequestId: id, version: 1, requestState: 'DRAFT', approvalId: null } };
    });
  }),

  http.post(`${API_BASE}/change-requests/:id/submissions`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const cr = db.changeRequests.get(String(params.id));
    if (!cr) return problem(404, 'NOT_FOUND');
    return idempotent(request, () => {
      if (expectedVersion(request) !== undefined && expectedVersion(request) !== cr.version) return problem(409, 'VERSION_CONFLICT');
      const targetRef = String(cr.body.targetRef);
      if ([...db.approvals.values()].some((a) => a.targetRef === targetRef && !a.used)) return problem(409, 'DUPLICATE_APPROVAL');
      const approvalId = `APV-${nextSeq()}`;
      db.approvals.set(approvalId, { approvalId, targetRef, checks: 0, used: false });
      cr.approvalId = approvalId;
      return { status: 202, body: { status: 'ACCEPTED', requestId: request.headers.get('Idempotency-Key') ?? '', resultId: approvalId } };
    });
  }),

  http.get(`${API_BASE}/approvals/:approvalId`, ({ request, params }) => {
    if (!operator(request)) return unauthorized();
    const a = db.approvals.get(String(params.approvalId));
    if (!a) return problem(404, 'NOT_FOUND');
    a.checks += 1;
    return HttpResponse.json({ approvalId: a.approvalId, targetRef: a.targetRef, reviewState: a.checks >= 2 ? 'APPROVED' : 'REVIEW_PENDING', requestState: 'SUBMITTED' });
  }),
];
