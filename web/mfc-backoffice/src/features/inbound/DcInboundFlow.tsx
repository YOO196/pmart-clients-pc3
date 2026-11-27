// DC 이관 입고 탭 맨 위 흐름 한 줄 — DC 에서 이 센터까지 TRF 가 지금 어디 있는지 단계별 건수(사용자 2026-11-26 "입고 예정 trf 실시간 흐름",
// PR #607 의 흐름 그림만 #604 DcInboundTab 위로 옮김 — 2026-11-27, 같은 탭을 두 화면이 맡던 것을 하나로).
// 서버: mfc-inbound `GET /inbound-promises?mfcId=`(끝나지 않은 EXPECTED·RECEIVING) + `?state=TIN_POSTED&date=오늘`(오늘 받은 것), 15초마다.
// 단계는 서버 상태 그대로 — 출발(departureId) 전 EXPECTED = DC 에서 준비 중, 출발 뒤 EXPECTED = 오는 중, RECEIVING = 도착·수령 중, TIN_POSTED = 받음.
// 못 읽으면 그 칸은 "조회 실패"(0 으로 꾸미지 않는다). 칸을 누르면 아래 목록을 그 상태로 거른다.
import { useQuery } from '@tanstack/react-query';
import { Fragment } from 'react';

import { request } from '@pmart/web-core';
import type { components } from '../../api/generated/mfc-inbound';
import { useApi } from '../../app/ApiContext';
import { messages } from '../../shared/messages';

const t = messages.inbound.dc.flow;
type InboundPromise = components['schemas']['InboundPromise'];

export const FLOW_REFRESH = 15_000;
const STEPS = ['PREP', 'GOING', 'RECEIVING', 'DONE'] as const;
export type FlowStep = (typeof STEPS)[number];
const STEP_COLOR: Record<FlowStep, string> = { PREP: 'bg-base-content/30', GOING: 'bg-info', RECEIVING: 'bg-warning', DONE: 'bg-success' };
/** 칸을 누르면 목록 거르기 — 준비·오는 중은 같은 서버 상태(EXPECTED) */
const FILTER: Record<FlowStep, string> = { PREP: 'EXPECTED', GOING: 'EXPECTED', RECEIVING: 'RECEIVING', DONE: 'TIN_POSTED' };

/** 서버 상태 → 흐름 단계(취소·종결은 빼고) */
export function flowStepOf(x: Pick<InboundPromise, 'state' | 'departureId'>): FlowStep | null {
  if (x.state === 'RECEIVING') return 'RECEIVING';
  if (x.state === 'TIN_POSTED') return 'DONE';
  if (x.state === 'EXPECTED') return x.departureId ? 'GOING' : 'PREP';
  return null;
}

const qtyOf = (x: InboundPromise, k: 'expectedQty' | 'receivedQty') => (x.lines ?? []).reduce((a, l) => a + (l[k] ?? 0), 0);
const todaySeoul = () => new Date(Date.now() + 9 * 3_600_000).toISOString().slice(0, 10);

export function DcInboundFlow({ mfcId, onPick }: { readonly mfcId: string; readonly onPick: (state: string) => void }) {
  const api = useApi();
  const open = useQuery({
    queryKey: ['inbound-promises-flow', mfcId, 'open'],
    refetchInterval: FLOW_REFRESH,
    queryFn: async () => (await request('GET', api.inbound.GET('/inbound-promises', { params: { query: { mfcId, size: 200 } } }))).items ?? [],
  });
  const day = todaySeoul();
  const done = useQuery({
    queryKey: ['inbound-promises-flow', mfcId, 'TIN_POSTED', day],
    refetchInterval: FLOW_REFRESH,
    queryFn: async () =>
      (await request('GET', api.inbound.GET('/inbound-promises', { params: { query: { mfcId, state: 'TIN_POSTED', date: day, size: 200 } } }))).items ?? [],
  });
  const count = (s: FlowStep) => {
    const src = s === 'DONE' ? done.data : open.data;
    if (!src) return null;
    const xs = src.filter((x) => flowStepOf(x) === s);
    return { n: xs.length, qty: xs.reduce((a, x) => a + qtyOf(x, s === 'DONE' ? 'receivedQty' : 'expectedQty'), 0) };
  };
  return (
    <ol className="flex flex-col items-stretch gap-2 md:flex-row md:items-center" data-testid="dc-inbound-flow">
      {STEPS.map((s, i) => {
        const failed = s === 'DONE' ? done.isError : open.isError;
        const c = count(s);
        return (
          <Fragment key={s}>
            {i > 0 && (
              <li aria-hidden className="hidden text-xl text-base-content/30 md:block">
                →
              </li>
            )}
            <li className="flex-1">
              <button
                type="button"
                className={`w-full rounded-box border p-3 text-left transition hover:border-primary/40 hover:bg-base-200/40 ${c && c.n > 0 ? 'border-base-300 bg-base-100' : 'border-dashed border-base-300'}`}
                data-testid={`dc-flow-${s}`}
                onClick={() => onPick(FILTER[s])}
              >
                <span className="flex items-center gap-2 text-sm font-semibold">
                  <span aria-hidden className={`inline-block size-2.5 rounded-full ${STEP_COLOR[s]}`} />
                  {t.steps[s]}
                </span>
                <span className="mt-1 block text-2xl font-semibold tabular-nums">{failed ? t.failed : c ? t.trfs(c.n) : '…'}</span>
                <span className="block text-xs text-base-content/60">{failed ? t.failedSub : !c ? ' ' : s === 'PREP' && c.n === 0 ? t.prepHint : t.stepSub[s](c.qty)}</span>
              </button>
            </li>
          </Fragment>
        );
      })}
    </ol>
  );
}
