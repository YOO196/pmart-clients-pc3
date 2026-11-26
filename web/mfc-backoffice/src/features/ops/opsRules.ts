// 센터 운영판 규칙 — 한곳에 둔다(화면에도 기준을 보인다).
// - 출하 약속 = 출고의 배차 요청 예상 준비 시각 `dispatchRequest.estimatedReadyAt`(mfc-fulfillment 0.35.0, 사용자 결정 2026-11-24 —
//   `GET /shipments/promise-summary`·`/metrics/ship-promises` 와 같은 값). 배차 요청 전 출고는 약속이 없다(임박·초과에서 빼고 수를 보인다).
//   예전(0.34.0 까지)처럼 작업 promisedReadyAt 을 쓰면 안 된다 — 실제로는 PICK 시작 가능 시각(즉시 주문은 접수 시각)이라 즉시 주문이 피킹 내내 "초과"로 나온다
//   (2026-11-26 홈 평가로 찾음). 숫자 칸은 서버 요약, 예외 줄은 출고마다 같은 규칙으로 판정해 지금 단계 작업과 잇는다.
//   출고 하나에 PICK·PACK 작업이 따로 있어 출고(shipmentId) 단위로 묶는다. 끝나지 않은 PICK·PACK 이 있으면 아직 출하 준비가 안 된 출고다
//   (출고가 READY 가 되면 PICK·PACK 은 COMPLETED — mfc-fulfillment 상태표).
// - 임박 기준: 업무 원문(MFC-business-logic)에 출하 임박 기준이 없다 → 화면 기준 DUE_SOON_MINUTES(백엔드 규칙이 생기면 바꾼다).
// - "지금"은 서버 응답 기준시각(asOf)을 쓴다(단말 시계가 틀려도 같은 판정).
import type { components } from '../../api/generated/mfc-fulfillment';

type Ful = components['schemas'];
export type TaskSummary = Ful['TaskSummary'];
export type TaskState = Ful['TaskState'];

/** 약속 시각까지 이만큼(분) 남았으면 "임박" */
export const DUE_SOON_MINUTES = 15;

/** 끝나지 않은 작업 상태(목록에 명시해서 보낸다 — 서버 기본은 ASSIGNED·IN_PROGRESS 뿐) */
export const OPEN_TASK_STATES: readonly TaskState[] = ['WAITING', 'READY', 'ASSIGNED', 'IN_PROGRESS', 'BLOCKED'];

/** 작업 목록 쪽 크기·최대 쪽 수 — 넘으면 "N건 이상"(첫 쪽만 세지 않는다) */
export const TASK_PAGE_SIZE = 200;
export const TASK_MAX_PAGES = 5;

export interface PromiseRow {
  readonly kind: 'overdue' | 'dueSoon';
  readonly shipmentId: string | null;
  readonly orderNumber: string | null;
  /** 지금 단계 작업(피킹이 남았으면 피킹, 아니면 포장) */
  readonly task: TaskSummary;
  readonly promisedAt: string;
  /** 초과면 지난 분, 임박이면 남은 분 */
  readonly minutes: number;
}

export interface PromiseResult {
  readonly rows: readonly PromiseRow[];
  readonly overdue: number;
  readonly dueSoon: number;
  /** 약속 시각이 없어 뺀 출고 수 */
  readonly noPromise: number;
}

const STAGE_ORDER: Readonly<Record<string, number>> = { PICK: 0, PACK: 1 };

/** 끝나지 않은 작업 + 출고별 출하 약속(shipmentId → estimatedReadyAt) → 출고별 약속 초과·임박 */
export function promiseRows(tasks: readonly TaskSummary[], promises: ReadonlyMap<string, string>, nowMs: number, dueSoonMinutes = DUE_SOON_MINUTES): PromiseResult {
  const groups = new Map<string, TaskSummary[]>();
  for (const t of tasks) {
    if (t.taskType !== 'PICK' && t.taskType !== 'PACK') continue;
    if (!t.state || !OPEN_TASK_STATES.includes(t.state)) continue;
    const key = t.shipmentId ?? `task:${t.taskId ?? ''}`;
    groups.set(key, [...(groups.get(key) ?? []), t]);
  }
  const rows: PromiseRow[] = [];
  let noPromise = 0;
  for (const list of groups.values()) {
    const shipmentId = list[0]!.shipmentId;
    const promisedAt = shipmentId ? promises.get(shipmentId) : undefined;
    if (!promisedAt) {
      noPromise += 1;
      continue;
    }
    const diff = Math.floor((Date.parse(promisedAt) - nowMs) / 60_000);
    const task = [...list].sort((a, b) => (STAGE_ORDER[a.taskType ?? ''] ?? 9) - (STAGE_ORDER[b.taskType ?? ''] ?? 9))[0]!;
    const base = { shipmentId: task.shipmentId ?? null, orderNumber: list.find((t) => t.orderNumber)?.orderNumber ?? null, task, promisedAt };
    if (Date.parse(promisedAt) <= nowMs) rows.push({ ...base, kind: 'overdue', minutes: Math.max(0, -diff) });
    else if (diff < dueSoonMinutes) rows.push({ ...base, kind: 'dueSoon', minutes: diff });
  }
  rows.sort((a, b) => (a.kind === b.kind ? (a.kind === 'overdue' ? b.minutes - a.minutes : a.minutes - b.minutes) : a.kind === 'overdue' ? -1 : 1));
  return { rows, overdue: rows.filter((r) => r.kind === 'overdue').length, dueSoon: rows.filter((r) => r.kind === 'dueSoon').length, noPromise };
}

/** 분 → "1시간 5분"·"12분" */
export function minutesText(min: number): string {
  if (min < 60) return `${min}분`;
  const h = Math.floor(min / 60);
  const rest = min % 60;
  return rest ? `${h}시간 ${rest}분` : `${h}시간`;
}

/** 두 시각 사이 분(음수면 0) */
export const minutesSince = (fromIso: string, nowMs: number) => Math.max(0, Math.floor((nowMs - Date.parse(fromIso)) / 60_000));

/** 오늘 날짜(Asia/Seoul, yyyy-MM-dd) — 결품 지표의 날짜 기준 */
export const seoulToday = (nowMs: number) => new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul' }).format(new Date(nowMs));
