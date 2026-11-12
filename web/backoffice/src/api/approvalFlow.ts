// 승인 요청: 정본 서비스가 돌려준 approvalRequest → approval-service 변경 요청 생성 → 제출(approvalId 발급).
// 백엔드 handoff 2026-10-30 §3 ③④. 승인 결정과 정본 반영은 다른 사람·다른 시점의 일이라 여기서 기다리지 않는다.
import type { Api } from './client';
import { commandParams, IdempotencyKey } from './command';
import { CommandRejectedFailure, UnknownResultFailure } from '@pmart/web-core';
import type { ApprovalRequestBody } from './models';
import { request } from '@pmart/web-core';
import { pollUntil } from '@pmart/web-core';

export interface ApprovalRequested {
  readonly changeRequestId: string;
  /** null 이면 제출은 됐지만 승인 ID 발급을 아직 확인하지 못했다(결과 불명). */
  readonly approvalId: string | null;
}

/**
 * 사용자 행위 1회 = 키 1개. 두 단계 요청 키는 그 키에서 만든다(재전송하면 두 단계 모두 같은 키).
 * 제출 결과가 불명이면 변경 요청 조회(짝 조회)로 approvalId 를 확인한다.
 */
export async function requestApproval(
  api: Api,
  body: ApprovalRequestBody,
  key: IdempotencyKey,
): Promise<ApprovalRequested> {
  const created = await request(
    'POST',
    api.approval.POST('/change-requests', {
      ...commandParams(new IdempotencyKey(`${key.value}:cr`)),
      body,
    }),
  );
  const changeRequestId = created.changeRequestId;
  if (!changeRequestId) throw new UnknownResultFailure('changeRequestId 없음');

  const findApprovalId = async () => {
    const outcome = await pollUntil(
      () => request('GET', api.approval.GET('/change-requests/{changeRequestId}', { params: { path: { changeRequestId } } })),
      (cr) => typeof cr.approvalId === 'string' && cr.approvalId.length > 0,
    );
    return outcome.kind === 'done' ? (outcome.value.approvalId ?? null) : null;
  };

  let submitted;
  try {
    submitted = await request(
      'POST',
      api.approval.POST('/change-requests/{changeRequestId}/submissions', {
        ...commandParams(new IdempotencyKey(`${key.value}:submit`), { path: { changeRequestId }, version: created.version }),
      }),
    );
  } catch (e) {
    if (e instanceof UnknownResultFailure) return { changeRequestId, approvalId: await findApprovalId() };
    throw e;
  }
  if (submitted.status === 'REJECTED') throw new CommandRejectedFailure(submitted.nextAction, submitted.requestId);
  if (submitted.status === 'UNKNOWN_RESULT') return { changeRequestId, approvalId: await findApprovalId() };
  if (submitted.resultId) return { changeRequestId, approvalId: submitted.resultId };
  return { changeRequestId, approvalId: await findApprovalId() };
}
