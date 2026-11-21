// 구역 칸 지도(대시보드 B안, 2026-11-21 사용자 — 레퍼런스 "센터 디지털 트윈" 자리를 실제 데이터로).
// 원천: mfc-location `GET /locations?mfcId=`(200칸씩 최대 5쪽 — 넘으면 "N칸 이상"). 로봇 위치·작업 밀도는 계약에 없어 그리지 않는다.
// 구역 묶음 = 선반·피킹은 온도대·구역 코드(areaCode), 그 밖은 구역 종류. 작업 흐름 순(수령 → 보관·피킹 → 포장 → 출고 대기, 그 뒤 회수·격리·폐기).
// 칸 하나 = 작은 네모, 색 = 서버 상태(사용 중·실사 잠김·닫힘·폐지) + 고회전 표시. 누르면 그 칸 상세.
import { useQuery } from '@tanstack/react-query';
import { useState } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import type { components } from '../../api/generated/mfc-location';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { messages } from '../../shared/messages';
import { OPS_REFRESH_MS } from '../ops/opsQueries';

type Location = components['schemas']['Location'];
const m = messages.dashboard.zoneMap;
const PAGE = 200;
const MAX_PAGES = 5;

/** 작업 흐름 순서(구역 종류) */
const FLOW: readonly Location['zone'][] = ['RECEIVING', 'PICKING', 'STORAGE', 'PACKING', 'DISPATCH_STAGING', 'RETURN', 'QUARANTINE', 'DISPOSAL'];
const TEMP_ORDER: Readonly<Record<string, number>> = { AMBIENT: 0, CHILLED: 1, FROZEN: 2 };

async function readLocations(api: ReturnType<typeof useApi>, mfcId: string) {
  const items: Location[] = [];
  let cursor: string | undefined;
  for (let page = 0; page < MAX_PAGES; page += 1) {
    const r = await request('GET', api.location.GET('/locations', { params: { query: { mfcId, size: PAGE, ...(cursor ? { cursor } : {}) } } }));
    items.push(...(r.items ?? []));
    cursor = r.page?.nextCursor ?? undefined;
    if (!cursor) return { items, complete: true };
  }
  return { items, complete: false };
}

interface Block {
  readonly key: string;
  readonly title: string;
  readonly sub: string;
  readonly zone: Location['zone'];
  readonly temp: Location['temperatureZone'];
  readonly cells: readonly Location[];
}

function blocksOf(items: readonly Location[]): Block[] {
  const map = new Map<string, Location[]>();
  for (const l of items) {
    if (l.zone === 'CART') continue; // 이동 카트는 바닥 칸이 아니다
    const shelf = l.zone === 'PICKING' || l.zone === 'STORAGE';
    const key = shelf ? `${l.zone}:${l.temperatureZone}:${l.areaCode ?? '-'}` : `${l.zone}`;
    map.set(key, [...(map.get(key) ?? []), l]);
  }
  return [...map.entries()]
    .map(([key, cells]) => {
      const first = cells[0]!;
      const shelf = first.zone === 'PICKING' || first.zone === 'STORAGE';
      const temps = [...new Set(cells.map((c) => c.temperatureZone))];
      return {
        key,
        zone: first.zone,
        temp: first.temperatureZone,
        title: shelf ? `${first.areaCode ?? m.noArea} · ${m.zone[first.zone] ?? first.zone}` : (m.zone[first.zone] ?? first.zone),
        sub: temps.map((t) => m.temp[t] ?? t).join('·'),
        cells: [...cells].sort((a, b) => a.locationCode.localeCompare(b.locationCode)),
      };
    })
    .sort((a, b) => FLOW.indexOf(a.zone) - FLOW.indexOf(b.zone) || (TEMP_ORDER[a.temp] ?? 9) - (TEMP_ORDER[b.temp] ?? 9) || a.title.localeCompare(b.title));
}

const cellClass = (l: Location) => {
  switch (l.state) {
    case 'COUNT_LOCKED':
      return 'bg-info/70 ring-1 ring-info pm-pulse';
    case 'CLOSED':
      return 'bg-warning/70 ring-1 ring-warning';
    case 'RETIRED':
      return 'bg-transparent ring-1 ring-base-content/20';
    default:
      return l.highTurnover ? 'bg-primary ring-1 ring-primary/70 shadow-[0_0_6px] shadow-primary/50' : 'bg-primary/45';
  }
};

export function ZoneMap({ mfcId }: { readonly mfcId: string }) {
  const api = useApi();
  const q = useQuery({ queryKey: ['dashboard', mfcId, 'locations'], refetchInterval: OPS_REFRESH_MS, queryFn: () => readLocations(api, mfcId) });
  const [hover, setHover] = useState<Location | null>(null);
  if (q.isPending) return <p className="text-sm text-base-content/40">…</p>;
  if (q.isError)
    return (
      <p role="alert" className="text-sm font-semibold text-error" data-state="error">
        {messages.dashboard.failed}
      </p>
    );
  const items = q.data.items;
  const blocks = blocksOf(items);
  const n = (s: Location['state']) => items.filter((l) => l.state === s).length;
  if (blocks.length === 0) return <p className="text-sm text-base-content/55">{m.none}</p>;
  return (
    <div data-testid="zone-map">
      <div className="mb-2 flex flex-wrap items-center gap-2 text-xs">
        <span className="badge badge-ghost badge-sm pm-mono">{q.data.complete ? m.cells(items.length) : m.cellsAtLeast(items.length)}</span>
        {n('COUNT_LOCKED') > 0 && <span className="badge badge-info badge-sm">{m.badge.counting(n('COUNT_LOCKED'))}</span>}
        {n('CLOSED') > 0 && <span className="badge badge-warning badge-sm">{m.badge.closed(n('CLOSED'))}</span>}
        <span className="ml-auto min-h-4 truncate text-base-content/70" aria-live="polite" data-testid="zone-map-tip">
          {hover ? m.tip(hover.locationCode, m.state[hover.state ?? ''] ?? hover.state ?? '', hover.stateReason ?? null, hover.highTurnover) : m.hint}
        </span>
      </div>
      <div className="rounded-field border border-base-300 bg-base-200/70 p-3 [background-image:linear-gradient(color-mix(in_oklab,var(--color-base-content)_6%,transparent)_1px,transparent_1px),linear-gradient(90deg,color-mix(in_oklab,var(--color-base-content)_6%,transparent)_1px,transparent_1px)] [background-size:18px_18px]">
        <p className="pm-mono mb-2 text-[10.5px] tracking-wider text-base-content/45">{m.flow}</p>
        <div className="grid grid-cols-[repeat(auto-fill,minmax(150px,1fr))] gap-2.5">
          {blocks.map((b) => {
            const closed = b.cells.filter((c) => c.state === 'CLOSED').length;
            const counting = b.cells.filter((c) => c.state === 'COUNT_LOCKED').length;
            return (
              <section
                key={b.key}
                className={`rounded-field border px-2.5 py-2 ${closed > 0 ? 'border-warning/50 bg-warning/5' : counting > 0 ? 'border-info/50 bg-info/5' : 'border-primary/30 bg-primary/8'}`}
                aria-label={`${b.title} ${b.sub} ${m.cells(b.cells.length)}`}
                data-testid="zone-block"
              >
                <p className="flex items-baseline justify-between gap-2 text-xs font-bold">
                  <span className="truncate">{b.title}</span>
                  <span className="pm-mono shrink-0 text-[10.5px] font-semibold text-base-content/55">{b.cells.length}</span>
                </p>
                <p className="mb-1.5 text-[10.5px] text-base-content/50">{b.sub}</p>
                <div className="flex flex-wrap gap-1">
                  {b.cells.map((l) => (
                    <Link
                      key={l.locationId ?? l.locationCode}
                      to={centerPath(mfcId, `locations/${encodeURIComponent(l.locationId ?? '')}`)}
                      className={`block h-3 w-3 rounded-[3px] transition-transform hover:scale-150 focus-visible:scale-150 ${cellClass(l)}`}
                      aria-label={m.tip(l.locationCode, m.state[l.state ?? ''] ?? l.state ?? '', l.stateReason ?? null, l.highTurnover)}
                      onMouseEnter={() => setHover(l)}
                      onFocus={() => setHover(l)}
                      onMouseLeave={() => setHover(null)}
                      onBlur={() => setHover(null)}
                      data-state={l.state}
                    />
                  ))}
                </div>
              </section>
            );
          })}
        </div>
      </div>
      <p className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content/60">
        <Legend cls="bg-primary/45" label={m.state.ACTIVE ?? ''} />
        <Legend cls="bg-primary ring-1 ring-primary/70" label={m.highTurnover} />
        <Legend cls="bg-info/70 ring-1 ring-info" label={m.state.COUNT_LOCKED ?? ''} />
        <Legend cls="bg-warning/70 ring-1 ring-warning" label={m.state.CLOSED ?? ''} />
        <Legend cls="ring-1 ring-base-content/20" label={m.state.RETIRED ?? ''} />
      </p>
    </div>
  );
}

function Legend({ cls, label }: { readonly cls: string; readonly label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5">
      <i className={`inline-block h-2.5 w-2.5 rounded-[3px] ${cls}`} aria-hidden="true" />
      {label}
    </span>
  );
}
