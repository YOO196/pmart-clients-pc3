// 목 핸들러 공통: Problem 응답, 토큰 클레임, 멱등 재생, 기대 버전.
import { HttpResponse } from 'msw';

import { parseOperatorToken, type OperatorSession } from '@pmart/web-core';
import { db } from './db';

export function problem(
  status: number,
  code: string,
  details: ReadonlyArray<{ field?: string; reason?: string }> = [],
): HttpResponse<Record<string, unknown>> {
  return HttpResponse.json(
    { type: 'about:blank', title: code, status, code, traceId: 'mock-trace', details },
    { status, headers: { 'content-type': 'application/problem+json', 'x-request-id': `mock-${status}-${code}` } },
  );
}

/** 게이트웨이처럼 access token 을 확인한다: 만료(exp)·폐기된 세션(sid)이면 null(→ 401). */
export function operator(request: Request): OperatorSession | null {
  const auth = request.headers.get('Authorization');
  const who = auth?.startsWith('Bearer ') ? parseOperatorToken(auth.slice(7)) : null;
  if (!who) return null;
  if (who.expiresAtSeconds !== undefined && who.expiresAtSeconds * 1000 <= Date.now()) return null;
  if (who.sessionId && db.sessions.get(who.sessionId)?.revoked) return null;
  return who;
}

export const unauthorized = () => new HttpResponse(null, { status: 401 });

export const keyOf = (request: Request) => request.headers.get('Idempotency-Key') ?? '';

export function expectedVersion(request: Request): number | undefined {
  const v = request.headers.get('X-Expected-Version');
  return v === null ? undefined : Number(v);
}

type Reply = { status: number; body: unknown } | HttpResponse<Record<string, unknown>>;

/** 같은 키 = 저장된 응답 재생(서버 멱등 규칙). */
export function idempotent(request: Request, run: () => Reply) {
  const id = `${request.method} ${new URL(request.url).pathname} ${keyOf(request)}`;
  const saved = db.idempotent.get(id);
  if (saved) return HttpResponse.json(saved.body as Record<string, unknown>, { status: saved.status });
  const result = run();
  if (result instanceof Response) return result;
  db.idempotent.set(id, result);
  return HttpResponse.json(result.body as Record<string, unknown>, { status: result.status });
}

/**
 * 본사 승인 필요(AP-1, VERIFY 모드 흉내) — 422 APPROVAL_REQUIRED. details: threshold(걸린 기준 문장), approvalRequest(approval-service 본문 JSON 문자열).
 * 넣은 번호가 안 되면 field=approvalRef reason. 목 규칙: 승인 번호 'AP-PENDING' = 아직 승인 안 됨(NOT_APPROVED), 'AP-USED' = 이미 씀(ALREADY_USED).
 */
export function approvalProblem(targetRef: string, threshold: string, approvalRef?: string | null) {
  const ref = approvalRef?.trim() ?? '';
  if (ref === 'AP-PENDING') return problem(422, 'APPROVAL_REQUIRED', [{ field: 'approvalRef', reason: 'NOT_APPROVED' }]);
  if (ref === 'AP-USED') return problem(422, 'APPROVAL_REQUIRED', [{ field: 'approvalRef', reason: 'ALREADY_USED' }]);
  // 목 승인 서비스가 발급한 번호: 아직 승인 전(조회 2번 미만)이면 NOT_APPROVED, 다른 대상이면 TARGET_MISMATCH, 이미 썼으면 ALREADY_USED
  const issued = db.approvals.get(ref);
  if (issued) {
    if (issued.targetRef !== targetRef) return problem(422, 'APPROVAL_REQUIRED', [{ field: 'approvalRef', reason: 'TARGET_MISMATCH' }]);
    if (issued.checks < 2) return problem(422, 'APPROVAL_REQUIRED', [{ field: 'approvalRef', reason: 'NOT_APPROVED' }]);
    if (issued.used) return problem(422, 'APPROVAL_REQUIRED', [{ field: 'approvalRef', reason: 'ALREADY_USED' }]);
    issued.used = true;
    return null;
  }
  if (ref) return null;
  return problem(422, 'APPROVAL_REQUIRED', [
    { field: 'threshold', reason: threshold },
    {
      field: 'approvalRequest',
      reason: JSON.stringify({
        type: targetRef.includes(':RESTRICTION_LIFT:') ? 'MFC_OPERATION_RESTRICTION' : 'MFC_STOCK_ADJUSTMENT',
        targetService: targetRef.includes(':RESTRICTION_LIFT:') ? 'mfc-capacity-service' : 'mfc-inventory-service',
        targetRef,
        allowedActions: ['EXECUTE'],
        summary: threshold,
      }),
    },
  ]);
}
