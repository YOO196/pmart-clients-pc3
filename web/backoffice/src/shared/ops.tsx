// 고객센터·라이더 운영 화면 공통 부품: 값 이름표, 정의 목록, 서울 날짜, 개인정보 가림, 계약 전 화면 안내.
import { useState, type ReactNode } from 'react';

import { formatKrw, formatSeoul } from '@pmart/web-ui';
import { env } from '../env';
import { messages as m } from './messages';

/** 계약 값 → 문구. 모르는 값은 지어내지 않고 원문 그대로. 없으면 "-". */
export const label = (map: Readonly<Record<string, string>>, v: string | null | undefined) => (v ? (map[v] ?? v) : m.none);

export const when = (iso: string | null | undefined) => (iso ? formatSeoul(iso) : m.none);
export const won = (n: number | null | undefined) => (n === null || n === undefined ? m.none : formatKrw(n));
export const text = (v: string | number | null | undefined) => (v === null || v === undefined || v === '' ? m.none : String(v));

const DAY = 86_400_000;
const seoulDate = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Seoul', year: 'numeric', month: '2-digit', day: '2-digit' });

/** 서울 기준 오늘(YYYY-MM-DD). */
export const seoulToday = (now: Date = new Date()) => seoulDate.format(now);
/** 서울 날짜 d 에 n 일 더한 날짜. */
export const addSeoulDays = (d: string, n: number) => seoulDate.format(new Date(Date.parse(`${d}T00:00:00+09:00`) + n * DAY));
/** 서울 날짜 d 의 0시(포함 하한). */
export const seoulDayStart = (d: string) => new Date(`${d}T00:00:00+09:00`).toISOString();
/** 서울 날짜 d 다음 날 0시(끝 날짜를 포함하는 미포함 상한). */
export const seoulDayEnd = (d: string) => new Date(Date.parse(`${d}T00:00:00+09:00`) + DAY).toISOString();
/** 두 서울 날짜 사이 일수(끝 포함). */
export const spanDays = (from: string, to: string) => Math.round((Date.parse(`${to}T00:00:00+09:00`) - Date.parse(`${from}T00:00:00+09:00`)) / DAY) + 1;
export const isSeoulDate = (v: string | null): v is string => v !== null && /^\d{4}-\d{2}-\d{2}$/.test(v) && !Number.isNaN(Date.parse(`${v}T00:00:00+09:00`));

/** 정의 목록(왼쪽 이름표, 오른쪽 값). */
export function Facts({ rows, testId }: { readonly rows: ReadonlyArray<readonly [string, ReactNode]>; readonly testId?: string }) {
  return (
    <dl className="grid grid-cols-[9rem_1fr] gap-x-3 gap-y-1 rounded-box bg-base-100 p-4 text-sm" data-testid={testId}>
      {rows.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="opacity-70">{k}</dt>
          <dd className="min-w-0 break-words">{v}</dd>
        </div>
      ))}
    </dl>
  );
}

/**
 * 개인정보는 기본으로 가린다. "보기"를 눌러야 원문이 보인다(화면 안에서만 — 로그·전송 없음).
 * 원문 열람 사유 입력 흐름은 계약에 없어 두지 않는다(백오피스 규칙 §1 — BR 회신 대상).
 */
export function Masked({ value, testId }: { readonly value: string | null | undefined; readonly testId?: string }) {
  const [shown, setShown] = useState(false);
  if (!value) return <span>{m.none}</span>;
  return (
    <span className="inline-flex items-center gap-2" data-testid={testId}>
      <span data-masked={!shown}>{shown ? value : '••••••'}</span>
      <button type="button" className="btn btn-ghost btn-xs" onClick={() => setShown((s) => !s)}>
        {shown ? m.masked.hide : m.masked.reveal}
      </button>
    </span>
  );
}

/**
 * 서버 API 가 아직 계약에 없는 화면. 실서버 모드에서는 부르지 않고 안내만, 목 모드에서는 목 데이터로 화면을 보인다.
 * `br` = docs/backend-requests.md 항목.
 */
export function NotInContract({ br, children }: { readonly br: string; readonly children: () => ReactNode }) {
  if (!env.isMock) {
    return (
      <div role="alert" data-state="not-in-contract" className="alert alert-warning alert-soft flex-col items-start">
        <span className="font-bold">{m.notInContract.title}</span>
        <span className="text-sm">{m.notInContract.body(br)}</span>
      </div>
    );
  }
  return (
    <>
      <p className="badge badge-warning badge-outline" data-testid="not-in-contract-mock">
        {m.notInContract.mockNote(br)}
      </p>
      {children()}
    </>
  );
}
