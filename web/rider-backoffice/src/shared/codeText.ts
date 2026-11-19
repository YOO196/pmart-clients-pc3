import { messages } from './messages';

const n = messages.names;
/** 서버 글(메모·조치 결과)에 섞인 상태 코드를 화면 말로. 앞의 표가 먼저(겹치는 코드는 제한 단계 → 배차 → 수행 순). */
const tables: readonly Readonly<Record<string, string>>[] = [
  n.restriction,
  n.dispatchState,
  n.executionState,
  n.failureReason,
  n.settlementState,
  n.signupStatus,
  n.helpState,
  n.caseState,
  n.decision,
];

const lookup = (code: string): string | undefined => {
  for (const t of tables) if (Object.hasOwn(t, code)) return t[code];
  return undefined;
};

/**
 * "DISPATCH_RESTRICTED→NORMAL" → "신규배차 제한 → 정상", "CANCELLED_BEFORE_PICKUP — 실패·취소 …" → "픽업 전 취소 — 실패·취소 …".
 * 모르는 코드는 그대로 둔다(서버가 새 값을 보내도 글이 사라지지 않게). 글 자체는 서버 값 그대로 — 뜻을 바꾸지 않는다.
 */
export function humanizeCodes(text: string): string {
  return text.replace(/\b[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*\b/g, (code) => lookup(code) ?? code).replace(/\s*→\s*/g, ' → ');
}
