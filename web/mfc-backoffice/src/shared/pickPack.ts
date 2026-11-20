// 피패킹 — 피킹과 포장은 한 업무 흐름(MFC 업무 원문 §0 "피킹과 패킹은 같은 작업자", capacity WorkArea PICK_PACK = PICK·PACK,
// 0.19.0 다음 작업 받기는 피킹한 사람에게 그 출고 PACK 을 준다 — fulfillment TaskSummary.pickedBy).
// 계약의 작업(PICK 작업·PACK 작업)은 따로 있으므로 서버에는 그대로 보내고, 화면에서만 "피패킹"의 단계로 보인다.
import { messages } from './messages';

export const PICK_PACK = ['PICK', 'PACK'] as const;
export const isPickPack = (t: string | null | undefined): t is (typeof PICK_PACK)[number] => t === 'PICK' || t === 'PACK';

/** 배정 화면의 작업 유형 글 — PICK·PACK 은 "피패킹 · 피킹"/"피패킹 · 포장", 나머지는 작업자 작업 유형 이름 */
export function assignTaskName(t: string | null | undefined): string {
  if (!t) return messages.none;
  return messages.assignments.pickPackStage[t] ?? messages.workers.task[t] ?? t;
}
