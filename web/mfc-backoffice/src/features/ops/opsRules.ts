// 센터 운영판 규칙 — 한곳에 둔다(화면에도 기준을 보인다).
// - 출하 약속: 서버 작업의 promisedReadyAt(출하 준비 약속 시각)과 작업 상태만 쓴다. 약속 시각이 없는 출고는 임박·초과에서 뺀다(빼낸 수를 보인다).
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

/** 끝나지 않은 작업 → 출고별 약속 초과·임박 */
export function promiseRows(tasks: readonly TaskSummary[], nowMs: number, dueSoonMinutes = DUE_SOON_MINUTES): PromiseResult {
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
    const promised = list.map((t) => t.promisedReadyAt).filter((v): v is string => !!v);
    if (promised.length === 0) {
      noPromise += 1;
      continue;
    }
    const promisedAt = promised.reduce((a, b) => (Date.parse(a) <= Date.parse(b) ? a : b));
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
