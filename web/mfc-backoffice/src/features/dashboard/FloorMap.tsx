// 센터 도면(위에서 본) + 작업자 점 — 대시보드 B안 가운데(2026-11-21 사용자 "mfc 시뮬레이션 참고해서 위에서 본 도면에 작업자 이동이 점으로").
// - 도면: 가상 현장(pmart-mfc-simulation) 평면 배치(floorLayout.ts — "가정 배치", 실측 아님).
// - 칸 상태: mfc-location `GET /locations` — 실사 잠김·닫힘 수(배지), 서버 position 이 있는 칸은 도면에 점.
// - 작업자 점: 작업자 위치를 주는 API 가 계약에 없다(요청 handoff mfc-backoffice/2026-11-21-backend-worker-floor-positions).
//   목 모드(env.isMock)에서만 시뮬레이션으로 그린다 — 작업자(재직)·휴게·맡은 작업 종류(서버 값)로 역할을 정하고 통로를 따라 걷게 한다.
//   실서버에서는 점을 그리지 않고 "위치 API 없음"을 보인다(추측한 위치를 실제처럼 보이지 않게).
import { useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useState, type KeyboardEvent, type ReactNode } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import type { components as Cap } from '../../api/generated/mfc-capacity';
import type { components as Loc } from '../../api/generated/mfc-location';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { env } from '../../env';
import { messages } from '../../shared/messages';
import { OPS_REFRESH_MS, useOpenTasks } from '../ops/opsQueries';
import { buildFloor, type FloorZoneKind } from './floorLayout';
import { fetchAllLocations } from './floorQueries';
import { NavGrid, type P } from './navGrid';

const m = messages.dashboard.floor;
type Worker = Cap['schemas']['Worker'];
type Location = Loc['schemas']['Location'];
type Role = 'pick' | 'pack' | 'inbound' | 'idle' | 'break';
const ROLES: readonly Role[] = ['pick', 'pack', 'inbound', 'idle', 'break'];
const TICK_MS = 800;

const FLOOR = buildFloor();

/** 구역 바탕(테마 변수 — index.css --pm-zone-*) */
const ZONE_FILL: Readonly<Record<FloorZoneKind, string>> = {
  FROZEN: 'var(--pm-zone-frozen)',
  CHILLED: 'var(--pm-zone-chilled)',
  AMBIENT: 'var(--pm-zone-ambient)',
  INBOUND_STORE: 'var(--pm-zone-neutral)',
  RECEIVING: 'var(--pm-zone-neutral)',
  OFFICE: 'var(--pm-zone-neutral)',
  PACKING: 'var(--pm-zone-packing)',
  QUARANTINE: 'var(--pm-zone-quarantine)',
  SHIPPING: 'var(--pm-zone-neutral)',
  PARKING: 'transparent',
};
/** 작업자 역할 색(범주 — console.css --pm-cat-*, 검사 통과 색) */
const ROLE_COLOR: Readonly<Record<Role, string>> = {
  pick: 'var(--pm-cat-1)',
  pack: 'var(--pm-cat-2)',
  inbound: 'var(--pm-cat-3)',
  idle: 'color-mix(in oklab, var(--color-base-content) 55%, transparent)',
  break: 'var(--pm-cat-4)',
};

interface Dot {
  readonly id: string;
  readonly name: string;
  readonly role: Role;
  readonly x: number;
  readonly z: number;
  /** 남은 길(꺾이는 점들) — 한 번에 다음 꺾이는 점까지만 가므로 모서리를 가로지르지 않는다 */
  readonly path: readonly P[];
  /** 도착 뒤 머무는 횟수 */
  readonly dwell: number;
  /** 피커가 일하는 온도대 */
  readonly temp: 'FROZEN' | 'CHILLED' | 'AMBIENT';
  readonly seed: number;
}

/** 한 번(TICK)에 걷는 거리(m) */
const STRIDE = 1.5;
const hash = (s: string) => [...s].reduce((a, c) => (a * 31 + c.charCodeAt(0)) >>> 0, 7);
const pick = <T,>(list: readonly T[], n: number) => list[n % list.length]!;
const nextSeed = (n: number) => (Math.imul(n, 1103515245) + 12345) >>> 0;
let navCache: NavGrid | null = null;
const nav = () => (navCache ??= new NavGrid(FLOOR));
const TEMPS = ['FROZEN', 'CHILLED', 'AMBIENT'] as const;

/** 역할 — 서버 값(휴게·맡은 작업 종류·업무)으로만. 맡은 작업이 없으면 업무로 시뮬레이션 역할을 정한다 */
function roleOf(w: Worker, taskTypes: ReadonlySet<string>): Role {
  if (w.onBreak) return 'break';
  if (taskTypes.has('PACK') && !taskTypes.has('PICK')) return 'pack';
  if (taskTypes.has('PICK')) return 'pick';
  const types = new Set(w.effectiveTaskTypes ?? []);
  if (types.has('PICK')) return 'pick';
  if (types.has('PACK')) return 'pack';
  if (types.has('PUTAWAY') || types.has('INSPECT')) return 'inbound';
  return 'idle';
}

/** 다음 갈 곳 — 피커: 같은 온도대 통로의 선반 앞(가끔 포장 대기), 포장: 내 포장대(가끔 포장 대기), 입고: 하차 칸·보충 팔레트, 대기·휴게: 제자리 근처 */
function goalOf(d: Dot, index: number): P {
  const r = d.seed % 1000;
  switch (d.role) {
    case 'pick': {
      if (r < 120) return FLOOR.points.packQueue;
      const aisles = FLOOR.aisles.filter((a) => a.zone === d.temp);
      const a = pick(aisles, r);
      const along = a.from + 0.6 + ((d.seed >>> 10) % 1000) / 1000 * (a.to - a.from - 1.2);
      return a.along === 'z' ? { x: a.cross, z: along } : { x: along, z: a.cross };
    }
    case 'pack':
      return r < 150 ? FLOOR.points.packQueue : pick(FLOOR.stations, index);
    case 'inbound':
      return r < 500 ? pick(FLOOR.points.dock, r) : pick(FLOOR.reserves, r);
    case 'break':
      return pick(FLOOR.points.lounge, index + (r < 200 ? 1 : 0));
    default:
      return pick(FLOOR.points.idle, index + (r < 300 ? 1 : 0));
  }
}

function place(id: string, name: string, role: Role, i: number): Dot {
  const h = hash(id);
  const base: Dot = { id, name, role, x: 0, z: 0, path: [], dwell: 0, temp: TEMPS[(i + (h % 3)) % 3]!, seed: h };
  const at = nav().snapPoint(goalOf(base, i));
  return { ...base, ...at, dwell: 1 + (h % 3) };
}

/** 한 걸음 — 머무는 중이면 기다리고, 길이 없으면 다음 갈 곳까지 길을 찾고, 있으면 다음 꺾이는 점 쪽으로 STRIDE 만큼 */
function step(d: Dot, index: number): Dot {
  if (d.dwell > 0) return { ...d, dwell: d.dwell - 1 };
  if (d.path.length === 0) {
    const seed = nextSeed(d.seed);
    const goal = goalOf({ ...d, seed }, index);
    const path = nav().findPath(d, goal) ?? [];
    return { ...d, seed, path, dwell: path.length === 0 ? 2 : 0 };
  }
  const [next, ...rest] = d.path as [P, ...P[]];
  const dx = next.x - d.x;
  const dz = next.z - d.z;
  const dist = Math.hypot(dx, dz);
  if (dist <= STRIDE) {
    // 도착 — 일하는 자리면 잠깐 머문다(피킹 2~3번, 포장 4~6번)
    const done = rest.length === 0;
    const stay = !done ? 0 : d.role === 'pick' ? 2 + (d.seed % 2) : d.role === 'pack' ? 4 + (d.seed % 3) : 3;
    return { ...d, x: next.x, z: next.z, path: rest, dwell: stay };
  }
  return { ...d, x: d.x + (dx / dist) * STRIDE, z: d.z + (dz / dist) * STRIDE };
}

function useWorkerDots(mfcId: string, enabled: boolean) {
  const api = useApi();
  const workers = useQuery({
    queryKey: ['dashboard', mfcId, 'workers'],
    refetchInterval: OPS_REFRESH_MS,
    queryFn: async () => (await request('GET', api.capacity.GET('/mfcs/{mfcId}/workers', { params: { path: { mfcId }, query: { state: 'ACTIVE' } } }))).items ?? [],
  });
  const tasks = useOpenTasks(mfcId);
  const seed = useMemo(() => {
    const byWorker = new Map<string, Set<string>>();
    for (const t of tasks.data?.items ?? []) {
      const w = t.assignment?.workerId;
      if (w && t.taskType) byWorker.set(w, new Set([...(byWorker.get(w) ?? []), t.taskType]));
    }
    return (workers.data ?? []).map((w, i) => place(w.workerId ?? `w${i}`, w.name ?? w.displayName ?? m.noName, roleOf(w, byWorker.get(w.workerId ?? '') ?? new Set()), i));
  }, [workers.data, tasks.data]);
  const [dots, setDots] = useState<{ readonly seed: readonly Dot[]; readonly list: readonly Dot[] }>({ seed, list: seed });
  // 작업자·작업이 바뀌면 처음 자리부터(렌더 중 비교 — 효과 안에서 상태를 맞추지 않는다)
  if (dots.seed !== seed) setDots({ seed, list: seed });
  useEffect(() => {
    if (!enabled) return;
    const t = setInterval(() => {
      setDots((cur) => ({ ...cur, list: cur.list.map((d, i) => step(d, i)) }));
    }, TICK_MS);
    return () => clearInterval(t);
  }, [enabled]);
  return { workers, dots: enabled ? dots.list : [] };
}

/** 도면에서 고른 것 — 랙(칸 코드 앞부분) 또는 작업자 */
export type FloorPick = { readonly kind: 'rack'; readonly code: string; readonly temp: string } | { readonly kind: 'worker'; readonly id: string; readonly name: string; readonly role: Role };

/**
 * preview(대시보드) = 도면 전체가 센터 도면 화면으로 가는 링크, 칸·점은 누를 수 없다.
 * full(센터 도면 화면) = 랙·작업자 점을 눌러 고른다(onPick), 고른 것은 밝게.
 */
export function FloorMap({
  mfcId,
  mode = 'preview',
  picked = null,
  onPick,
}: {
  readonly mfcId: string;
  readonly mode?: 'preview' | 'full';
  readonly picked?: FloorPick | null;
  readonly onPick?: (p: FloorPick) => void;
}) {
  const full = mode === 'full';
  const api = useApi();
  const simulate = env.isMock;
  const { workers, dots } = useWorkerDots(mfcId, simulate);
  const locations = useQuery({
    queryKey: ['dashboard', mfcId, 'locations'],
    refetchInterval: OPS_REFRESH_MS,
    queryFn: async () => (await request('GET', api.location.GET('/locations', { params: { query: { mfcId, size: 200 } } }))).items ?? [],
  });
  // 실사 잠김·닫힘 칸 수 — 상태로 걸러 끝까지(칸이 수천 개라 첫 쪽만 세면 모자란다)
  const lockedQ = useQuery({ queryKey: ['dashboard', mfcId, 'locations', 'COUNT_LOCKED'], refetchInterval: OPS_REFRESH_MS, queryFn: () => fetchAllLocations(api, mfcId, { state: 'COUNT_LOCKED' }) });
  const closedQ = useQuery({ queryKey: ['dashboard', mfcId, 'locations', 'CLOSED'], refetchInterval: OPS_REFRESH_MS, queryFn: () => fetchAllLocations(api, mfcId, { state: 'CLOSED' }) });
  const [hover, setHover] = useState<string | null>(null);
  const items: readonly Location[] = locations.data ?? [];
  const placed = items.filter((l) => l.position);
  const counting = lockedQ.data?.length ?? 0;
  const closed = closedQ.data?.length ?? 0;
  const count = (r: Role) => dots.filter((d) => d.role === r).length;
  const hovered = dots.find((d) => d.id === hover);

  return (
    <div data-testid="floor-map" className={full ? 'relative h-full' : ''}>
      <div className={full ? 'pointer-events-none absolute top-3 left-4 z-[1] flex flex-wrap items-center gap-2 text-xs [&>*]:pointer-events-auto' : 'mb-2 flex flex-wrap items-center gap-2 text-xs'}>
        {simulate ? <span className="badge badge-primary badge-sm">{m.simBadge}</span> : <span className="badge badge-ghost badge-sm">{m.noPositionApi}</span>}
        {locations.isError ? (
          <span className="badge badge-ghost badge-sm">{m.locFailed}</span>
        ) : (
          <>
            {counting > 0 && <span className="badge badge-info badge-sm">{m.counting(counting)}</span>}
            {closed > 0 && <span className="badge badge-warning badge-sm">{m.closed(closed)}</span>}
          </>
        )}
        <span className={`min-h-4 truncate text-base-content/70 ${full ? 'rounded-full bg-base-100/80 px-2.5 py-0.5 backdrop-blur' : 'ml-auto'}`} aria-live="polite" data-testid="floor-tip">
          {hovered ? m.tip(hovered.name, m.role[hovered.role]) : full ? m.hintFull : m.hint}
        </span>
      </div>
      <Frame mfcId={mfcId} full={full}>
        <svg
          viewBox={`-0.6 -0.6 ${FLOOR.width + 1.2} ${FLOOR.buildingDepth + 3.8}`}
          className={`block w-full ${full ? 'h-full' : 'h-[min(46vh,420px)]'}`}
          preserveAspectRatio="xMidYMid meet"
          role={full ? 'group' : 'img'}
          aria-label={m.aria}
        >
          <defs>
            <pattern id="pm-floor-grid" width="1" height="1" patternUnits="userSpaceOnUse">
              <path d="M1 0H0V1" fill="none" className="stroke-base-content/6" strokeWidth="0.03" />
            </pattern>
          </defs>
          <rect x="0" y="0" width={FLOOR.width} height={FLOOR.buildingDepth} fill="url(#pm-floor-grid)" />
          {FLOOR.zones
            .filter((z) => z.kind !== 'PARKING')
            .map((z) => (
              <rect key={z.id} x={z.rect.x0} y={z.rect.z0} width={z.rect.x1 - z.rect.x0} height={z.rect.z1 - z.rect.z0} rx="0.3" style={{ fill: ZONE_FILL[z.kind] }} />
            ))}
          {FLOOR.racks.map((r, i) => {
            const on = picked?.kind === 'rack' && picked.code === r.code;
            return (
              <rect
                key={i}
                x={r.cx - (r.along === 'x' ? 0.6 : 0.22)}
                y={r.cz - (r.along === 'z' ? 0.6 : 0.22)}
                width={r.along === 'x' ? 1.2 : 0.44}
                height={r.along === 'z' ? 1.2 : 0.44}
                rx="0.05"
                className={full ? 'pm-floor-rack' : ''}
                style={full ? undefined : { fill: 'var(--pm-floor-rack)' }}
                {...(full ? { 'aria-pressed': on } : {})}
                {...(full
                  ? {
                      role: 'button',
                      tabIndex: 0,
                      'aria-label': m.rackAria(r.code),
                      'data-testid': 'floor-rack',
                      'data-code': r.code,
                      onClick: () => onPick?.({ kind: 'rack', code: r.code, temp: r.temp }),
                      onKeyDown: (e: KeyboardEvent) => {
                        if (e.key === 'Enter' || e.key === ' ') {
                          e.preventDefault();
                          onPick?.({ kind: 'rack', code: r.code, temp: r.temp });
                        }
                      },
                    }
                  : {})}
              >
                {full && <title>{m.rackAria(r.code)}</title>}
              </rect>
            );
          })}
          {FLOOR.stations.map((s, i) => (
            <rect key={i} x={s.x - 0.8} y={s.z + (s.z < 24 ? -1.6 : 0.8)} width="1.6" height="0.8" rx="0.1" style={{ fill: 'var(--pm-floor-table)' }} />
          ))}
          {FLOOR.walls.map((w, i) => (
            <rect key={i} x={w.x0} y={w.z0} width={w.x1 - w.x0} height={w.z1 - w.z0} style={{ fill: 'var(--pm-floor-wall)' }} />
          ))}
          {/* 구역 이름 — 랙·벽이 없는 자리에, 불투명 바탕(벽·랙 위에 그려도 겹쳐 보이지 않게) */}
          {FLOOR.zones
            .filter((z) => z.kind !== 'PARKING')
            .map((z) => {
              const fs = z.kind === 'QUARANTINE' ? 0.62 : 0.78;
              const w = [...z.label].length * fs * 0.98 + 0.8;
              return (
                <g key={`l-${z.id}`} className="pointer-events-none">
                  <rect x={z.at.x - w / 2} y={z.at.z - fs * 0.85} width={w} height={fs * 1.7} rx={fs * 0.5} style={{ fill: 'var(--pm-floor-label-bg)' }} />
                  <text x={z.at.x} y={z.at.z + fs * 0.33} textAnchor="middle" className="fill-base-content/80" style={{ fontSize: fs, fontWeight: 700 }}>
                    {z.label}
                  </text>
                </g>
              );
            })}
          {/* 서버 position 이 있는 칸 — 상태색 */}
          {placed.map((l) => (
            <g key={l.locationId ?? l.locationCode}>
              <rect
                x={l.position!.xM - 0.35}
                y={l.position!.zM - 0.35}
                width="0.7"
                height="0.7"
                rx="0.12"
                className={l.state === 'CLOSED' ? 'fill-warning' : l.state === 'COUNT_LOCKED' ? 'fill-info pm-pulse' : 'fill-primary/70'}
              >
                <title>{`${l.locationCode} · ${m.state[l.state ?? ''] ?? l.state ?? ''}`}</title>
              </rect>
            </g>
          ))}
          {/* 작업자 점 */}
          {dots.map((d) => {
            const on = picked?.kind === 'worker' && picked.id === d.id;
            const choose = () => onPick?.({ kind: 'worker', id: d.id, name: d.name, role: d.role });
            return (
            <g
              key={d.id}
              className="pm-floor-dot"
              style={{ transform: `translate(${d.x}px, ${d.z}px)` }}
              onMouseEnter={() => setHover(d.id)}
              onMouseLeave={() => setHover(null)}
              data-testid="floor-worker"
              data-role={d.role}
              {...(full
                ? {
                    role: 'button',
                    tabIndex: 0,
                    'aria-label': m.tip(d.name, m.role[d.role]),
                    onClick: choose,
                    onKeyDown: (e: KeyboardEvent) => {
                      if (e.key === 'Enter' || e.key === ' ') {
                        e.preventDefault();
                        choose();
                      }
                    },
                  }
                : {})}
            >
              {/* 고른 작업자는 점에서 조금 떨어진 얇은 흰 고리 */}
              {on ? <circle r="0.62" className="pm-floor-ring fill-none stroke-white" strokeWidth="0.06" /> : <circle r="0.6" style={{ fill: ROLE_COLOR[d.role] }} opacity="0.22" />}
              <circle r="0.3" style={{ fill: ROLE_COLOR[d.role] }} className="pm-floor-core stroke-base-100" strokeWidth="0.09" />
              <title>{m.tip(d.name, m.role[d.role])}</title>
            </g>
            );
          })}
        </svg>
        <span className="pm-mono pointer-events-none absolute right-2 bottom-1.5 text-[10px] text-base-content/40">{m.scale}</span>
        {!full && <span className="pointer-events-none absolute top-2 right-2 badge badge-sm badge-primary opacity-0 transition-opacity group-hover:opacity-100">{m.openFull}</span>}
      </Frame>
      <p className={full ? 'absolute bottom-3 left-4 z-[1] flex flex-wrap items-center gap-x-4 gap-y-1 rounded-field bg-base-100/80 px-3 py-1.5 text-xs text-base-content/70 backdrop-blur' : 'mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content/65'}>
        {simulate &&
          ROLES.map((r) => (
            <span key={r} className="inline-flex items-center gap-1.5">
              <i className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: ROLE_COLOR[r] }} aria-hidden="true" />
              {m.role[r]} <b className="tabular-nums">{count(r)}</b>
            </span>
          ))}
        {simulate && workers.isError && <span className="text-error">{m.workersFailed}</span>}
        <span className={full ? 'text-base-content/45' : 'ml-auto text-base-content/45'}>{m.layoutNote}</span>
      </p>
    </div>
  );
}

/** 도면 틀 — preview 면 센터 도면 화면으로 가는 링크 */
function Frame({ mfcId, full, children }: { readonly mfcId: string; readonly full: boolean; readonly children: ReactNode }) {
  const cls = 'relative overflow-hidden rounded-field border border-base-300 bg-base-200/80';
  // full: 위(배지)·아래(범례)·오른쪽(떠 있는 패널 300px) 자리를 비우고 나머지를 도면으로
  return full ? (
    <div className="absolute inset-0 pt-11 pr-3 pb-12 pl-3 @3xl:pr-[318px]">{children}</div>
  ) : (
    <Link to={centerPath(mfcId, 'floor')} className={`group block transition-colors hover:border-primary/60 ${cls}`} aria-label={m.openFull} data-testid="floor-open">
      {children}
    </Link>
  );
}
