// 배치 제출 뒤 승인 요청 본문·승인 ID 를 이 탭의 sessionStorage 에 둔다.
// 제출 응답(approvalRequest)은 서버가 다시 주지 않으므로(배치는 이미 SUBMITTED), 승인 상세에 다녀오거나 새로고침해도
// "승인 요청" 버튼·"승인 상세 보기" 링크가 남아 있게 한다. 비밀값이 아니고 탭을 닫으면 사라진다. localStorage 는 쓰지 않는다.
import type { ApprovalRequestBody } from '../../api/models';

export interface BatchApprovalMemo {
  /** 제출 응답의 승인 요청 본문. 승인 요청을 올리면 지운다. */
  readonly approvalRequest?: ApprovalRequestBody;
  /** 올린 승인 ID. 승인 목록 조회가 늦거나 실패해도 링크를 보일 수 있게 둔다. */
  readonly approvalId?: string;
}

const key = (batchId: string) => `pmart.backoffice.product-import-batch.${batchId}.approval`;

function storage(): Storage | null {
  try {
    return typeof sessionStorage === 'undefined' ? null : sessionStorage;
  } catch {
    return null;
  }
}

export function loadBatchApproval(batchId: string): BatchApprovalMemo | null {
  const raw = storage()?.getItem(key(batchId));
  if (!raw) return null;
  try {
    const v = JSON.parse(raw) as BatchApprovalMemo;
    return typeof v === 'object' && v !== null ? v : null;
  } catch {
    return null;
  }
}

export function saveBatchApproval(batchId: string, memo: BatchApprovalMemo): void {
  try {
    storage()?.setItem(key(batchId), JSON.stringify(memo));
  } catch {
    // 저장 실패는 화면 동작을 막지 않는다(이 탭에서만 못 남길 뿐).
  }
}
