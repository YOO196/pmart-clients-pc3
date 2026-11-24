// 센터 도면(위에서 본) + 작업자 점 — 대시보드 가운데·센터 도면 화면(2026-11-21 사용자 "mfc 시뮬레이션 참고해서 위에서 본 도면에 작업자 이동이 점으로").
// - 도면: 센터마다(features/floor/floorPlan — 시뮬레이터 평면, 서버 칸 좌표와 같은 배치). 도면이 없는 센터는 "도면 없음".
// - 칸 상태: 실사 잠김 수만 배지(mfc-location `GET /locations?state=COUNT_LOCKED`). 닫힘 수·칸 점은 보이지 않는다(2026-11-24 사용자 — 실서버 닫힘은 도면 변경으로 닫힌 칸).
// - 작업자 점: mfc-capacity 0.34.0 `GET /mfcs/{mfcId}/worker-positions`(2026-11-24, 회신 mfc-backoffice/2026-11-21-reply-worker-floor-positions) —
//   작업자마다 "마지막으로 스캔한 칸"(실내 측위가 아님). 새 스캔이 오면 앞 자리에서 통로를 따라 걸어가게 그린다(걷는 길은 화면의 그림, 서버 값이 아니다).
//   피킹·포장·재고 이동·입고가 칸을 스캔할 때마다 움직이므로 시뮬레이터 가상 작업자·실제 PDA 작업과 같이 움직인다.
//   조회 실패는 0명으로 바꾸지 않고 "조회 실패", 좌표 없는 칸의 작업자는 "자리 모름 n명"(unplaced), 원천 일부 실패는 따로 알린다.
import { useQuery } from '@tanstack/react-query';
import { useEffect, useMemo, useState, type KeyboardEvent, type ReactNode } from 'react';
import { Link } from 'react-router';

import { request } from '@pmart/web-core';
import { formatSeoul } from '@pmart/web-ui';
import type { components as Cap } from '../../api/generated/mfc-capacity';
import { useApi } from '../../app/ApiContext';
import { centerPath } from '../../app/nav';
import { messages } from '../../shared/messages';
import { useNow } from '../../shared/motion';
import { OPS_REFRESH_MS } from '../ops/opsQueries';
import { useFloorPlan, type FloorPlan, type FloorZoneKind, type Rect } from '../floor/floorPlan';
import { fetchAllLocations } from './floorQueries';
import { NavGrid, type P } from './navGrid';

const m = messages.dashboard.floor;
type Worker = Cap['schemas']['Worker'];
type Positions = Cap['schemas']['WorkerPositions'];
export type Role = 'pick' | 'pack' | 'move' | 'inbound' | 'break' | 'idle';
const ROLES: readonly Role[] = ['pick', 'pack', 'move', 'inbound', 'break'];
/** 위치 다시 읽기(ms) — 스캔이 몇 초마다 생긴다 */
export const POSITIONS_REFRESH_MS = 5000;
/** 한 번(TICK)에 걷는 거리(m) — 0.5초에 1m(빠른 걸음) */
const TICK_MS = 500;
const STRIDE = 1;
/** 이보다 오래된 마지막 기록은 흐리게(지금 거기 있다고 단정하지 않는다) */
const STALE_MS = 15 * 60_000;
const RACK_LEN = 1.25;
const RACK_DEPTH = 0.45;

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
/** 작업자 역할 색(범주 — index.css --pm-cat-*, dataviz 팔레트 1~5) */
const ROLE_COLOR: Readonly<Record<Role, string>> = {
  pick: 'var(--pm-cat-1)',
  pack: 'var(--pm-cat-2)',
  inbound: 'var(--pm-cat-3)',
  break: 'var(--pm-cat-4)',
  move: 'var(--pm-cat-5)',
  idle: 'color-mix(in oklab, var(--color-base-content) 55%, transparent)',
};

/** 역할 — 휴게(서버 작업자 값)가 먼저, 그다음 마지막 기록의 처리 종류 */
export function roleOf(activityType: string, onBreak: boolean): Role {
  if (onBreak) return 'break';
  switch (activityType) {
    case 'PICK':
    case 'RETURN':
      return 'pick';
    case 'PACK':
      return 'pack';
    case 'MOVE':
    case 'REPLENISH':
    case 'QUARANTINE_MOVE':
      return 'move';
    default:
      return 'inbound';
  }
}

interface Dot {
  readonly id: string;
  readonly x: number;
  readonly z: number;
  /** 남은 길(꺾이는 점들) — 한 번에 다음 꺾이는 점까지만 가므로 모서리를 가로지르지 않는다 */
  readonly path: readonly P[];
  /** 지금 향하는 기록(칸·시각) — 바뀌면 새로 걷는다 */
  readonly key: string;
  readonly code: string;
  readonly activity: string;
  readonly at: string;
}

const reduceMotion = () => typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/** 새 위치 목록을 점에 맞춘다 — 같은 사람이 새 칸을 스캔했으면 지금 자리에서 그 칸까지 길을 찾는다 */
function sync(prev: ReadonlyMap<string, Dot>, items: Positions['items'], nav: NavGrid): Map<string, Dot> {
  const jump = reduceMotion();
  const next = new Map<string, Dot>();
  for (const it of items) {
    const key = `${it.locationCode}@${it.at}`;
    const target = nav.snapPoint({ x: it.xM, z: it.zM });
    const old = prev.get(it.workerId);
    const base = { id: it.workerId, key, code: it.locationCode, activity: it.activityType, at: it.at };
    if (!old) next.set(it.workerId, { ...base, ...target, path: [] });
    else if (old.key === key) next.set(it.workerId, old);
    else next.set(it.workerId, jump ? { ...base, ...target, path: [] } : { ...base, x: old.x, z: old.z, path: nav.findPath(old, target) ?? [target] });
  }
  return next;
}

/** 한 걸음 — 다음 꺾이는 점 쪽으로 STRIDE 만큼 */
function step(d: Dot): Dot {
  if (d.path.length === 0) return d;
  const [next, ...rest] = d.path as [P, ...P[]];
  const dx = next.x - d.x;
  const dz = next.z - d.z;
  const dist = Math.hypot(dx, dz);
  if (dist <= STRIDE) return { ...d, x: next.x, z: next.z, path: rest };
  return { ...d, x: d.x + (dx / dist) * STRIDE, z: d.z + (dz / dist) * STRIDE };
}

function useWorkerDots(mfcId: string, plan: FloorPlan | null | undefined) {
  const api = useApi();
  const workers = useQuery({
    queryKey: ['dashboard', mfcId, 'workers'],
    refetchInterval: OPS_REFRESH_MS,
    queryFn: async () => (await request('GET', api.capacity.GET('/mfcs/{mfcId}/workers', { params: { path: { mfcId }, query: { state: 'ACTIVE' } } }))).items ?? [],
  });
  const positions = useQuery({
    queryKey: ['dashboard', mfcId, 'worker-positions'],
    refetchInterval: POSITIONS_REFRESH_MS,
    queryFn: () => request('GET', api.capacity.GET('/mfcs/{mfcId}/worker-positions', { params: { path: { mfcId }, query: { sinceMinutes: 480 } } })),
  });
  const nav = useMemo(() => (plan ? new NavGrid(plan) : null), [plan]);
  const [dots, setDots] = useState<{ readonly from: Positions | undefined; readonly nav: NavGrid | null; readonly map: ReadonlyMap<string, Dot> }>({ from: undefined, nav: null, map: new Map() });
  // 새 위치가 오면 점을 맞춘다(렌더 중 비교 — 효과 안에서 상태를 맞추지 않는다)
  if (nav && (dots.from !== positions.data || dots.nav !== nav)) setDots({ from: positions.data, nav, map: sync(dots.nav === nav ? dots.map : new Map(), positions.data?.items ?? [], nav) });
  const moving = [...dots.map.values()].some((d) => d.path.length > 0);
  useEffect(() => {
    if (!moving) return;
    const t = setInterval(() => setDots((cur) => ({ ...cur, map: new Map([...cur.map].map(([k, d]) => [k, step(d)])) })), TICK_MS);
    return () => clearInterval(t);
  }, [moving]);
  const byId = useMemo(() => new Map((workers.data ?? []).map((w) => [w.workerId ?? '', w] as const)), [workers.data]);
  return { workers, positions, dots: [...dots.map.values()], byId };
}

/** 도면에서 고른 것 — 랙(칸 코드 앞부분) 또는 작업자 */
export type FloorPick = { readonly kind: 'rack'; readonly code: string; readonly temp: string } | { readonly kind: 'worker'; readonly id: string; readonly name: string; readonly role: Role };

const nameOf = (w: Worker | undefined, id: string) => w?.name ?? w?.displayName ?? id;
const ago = (now: number, at: string) => Math.max(0, Math.round((now - Date.parse(at)) / 60_000));

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
  const planQ = useFloorPlan(mfcId);
  const plan = planQ.data;
  if (planQ.isPending) return <p className="h-[min(46vh,420px)] text-sm text-base-content/40">…</p>;
  if (planQ.isError || !plan)
    return (
      <div data-testid="floor-map" className={full ? 'grid h-full place-items-center' : ''}>
        <p className="rounded-field border border-dashed border-base-300 px-4 py-10 text-center text-sm text-base-content/60" data-testid="floor-none">
          {planQ.isError ? m.planFailed : m.noPlan(mfcId)}
        </p>
      </div>
    );
  return <FloorView mfcId={mfcId} plan={plan} full={full} picked={picked} {...(onPick ? { onPick } : {})} />;
}

function FloorView({ mfcId, plan, full, picked, onPick }: { readonly mfcId: string; readonly plan: FloorPlan; readonly full: boolean; readonly picked: FloorPick | null; readonly onPick?: (p: FloorPick) => void }) {
  const api = useApi();
  const now = useNow(30_000);
  const { workers, positions, dots, byId } = useWorkerDots(mfcId, plan);
  // 실사 잠김·닫힘 칸 — 상태로 걸러 끝까지(칸이 수천 개라 첫 쪽만 세면 모자란다)
  const lockedQ = useQuery({ queryKey: ['dashboard', mfcId, 'locations', 'COUNT_LOCKED'], refetchInterval: OPS_REFRESH_MS, queryFn: () => fetchAllLocations(api, mfcId, { state: 'COUNT_LOCKED' }) });
  const [hover, setHover] = useState<string | null>(null);
  const roleOfDot = (d: Dot) => roleOf(d.activity, byId.get(d.id)?.onBreak === true);
  const count = (r: Role) => dots.filter((d) => roleOfDot(d) === r).length;
  const hovered = dots.find((d) => d.id === hover);
  const unplaced = positions.data?.unplaced ?? [];
  const missing = positions.data?.unavailableSources ?? [];
  const b = plan.bounds;
  const pad = 0.8;
  const tipOf = (d: Dot) => m.tip(nameOf(byId.get(d.id), d.id), m.role[roleOfDot(d)], d.code, ago(now, d.at));

  return (
    <div data-testid="floor-map" data-center={plan.centerId} className={full ? 'relative h-full' : ''}>
      <div className={full ? 'pointer-events-none absolute top-3 left-4 z-[1] flex flex-wrap items-center gap-2 text-xs [&>*]:pointer-events-auto' : 'mb-2 flex flex-wrap items-center gap-2 text-xs'}>
        <span className="badge badge-ghost badge-sm" title={m.scanNote}>
          {m.scanBadge}
        </span>
        {positions.isError && <span className="badge badge-error badge-sm" data-testid="floor-positions-failed">{m.positionsFailed}</span>}
        {missing.length > 0 && (
          <span className="badge badge-warning badge-sm" title={missing.join(', ')}>
            {m.partial}
          </span>
        )}
        {unplaced.length > 0 && (
          <span className="badge badge-ghost badge-sm" title={unplaced.map((u) => `${nameOf(byId.get(u.workerId), u.workerId)} · ${u.locationCode}`).join('\n')} data-testid="floor-unplaced">
            {m.unplaced(unplaced.length)}
          </span>
        )}
        {lockedQ.isError ? (
          <span className="badge badge-ghost badge-sm">{m.locFailed}</span>
        ) : (
          <>
            {(lockedQ.data?.length ?? 0) > 0 && <span className="badge badge-info badge-sm">{m.counting(lockedQ.data!.length)}</span>}
          </>
        )}
        <span className={`min-h-4 truncate text-base-content/70 ${full ? 'rounded-full bg-base-100/80 px-2.5 py-0.5 backdrop-blur' : 'ml-auto'}`} aria-live="polite" data-testid="floor-tip">
          {hovered ? tipOf(hovered) : full ? m.hintFull : m.hint}
        </span>
      </div>
      <Frame mfcId={mfcId} full={full}>
        <svg
          viewBox={`${b.x0 - pad} ${b.z0 - pad} ${b.x1 - b.x0 + pad * 2} ${b.z1 - b.z0 + pad * 2}`}
          className={`block w-full ${full ? 'h-full' : 'h-[min(46vh,420px)]'}`}
          preserveAspectRatio="xMidYMid meet"
          role={full ? 'group' : 'img'}
          aria-label={m.aria(plan.name)}
        >
          <defs>
            <pattern id="pm-floor-grid" width="1" height="1" patternUnits="userSpaceOnUse">
              <path d="M1 0H0V1" fill="none" className="stroke-base-content/6" strokeWidth="0.03" />
            </pattern>
          </defs>
          <rect x={b.x0} y={b.z0} width={b.x1 - b.x0} height={b.z1 - b.z0} fill="url(#pm-floor-grid)" />
          {plan.zones
            .filter((z) => z.kind !== 'PARKING')
            .map((z) =>
              z.outline ? (
                <polygon key={z.id} points={z.outline.map((p) => `${p.x},${p.z}`).join(' ')} style={{ fill: ZONE_FILL[z.kind] }} />
              ) : (
                <rect key={z.id} {...box(z.rect)} rx="0.3" style={{ fill: ZONE_FILL[z.kind] }} />
              ),
            )}
          {plan.obstacles.map((o, i) => (
            <rect key={`o${i}`} {...box(o)} rx="0.06" style={{ fill: o.kind === 'RESERVE' ? 'var(--pm-floor-reserve)' : 'var(--pm-floor-table)' }} />
          ))}
          {plan.racks.map((r) => {
            const on = picked?.kind === 'rack' && picked.code === r.code;
            const w = r.along === 'x' ? RACK_LEN : RACK_DEPTH;
            const h = r.along === 'z' ? RACK_LEN : RACK_DEPTH;
            const choose = () => onPick?.({ kind: 'rack', code: r.code, temp: r.temp });
            return (
              <rect
                key={r.code}
                x={r.cx - w / 2 + 0.03}
                y={r.cz - h / 2 + 0.03}
                width={w - 0.06}
                height={h - 0.06}
                rx="0.05"
                className={full ? 'pm-floor-rack' : ''}
                style={full ? (r.reserve ? { opacity: 0.7 } : undefined) : { fill: r.reserve ? 'var(--pm-floor-reserve)' : 'var(--pm-floor-rack)' }}
                {...(full
                  ? {
                      'aria-pressed': on,
                      role: 'button',
                      tabIndex: 0,
                      'aria-label': m.rackAria(r.code),
                      'data-testid': 'floor-rack',
                      'data-code': r.code,
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
                {full && <title>{m.rackAria(r.code)}</title>}
              </rect>
            );
          })}
          {plan.walls.map((w, i) => (
            <rect key={`w${i}`} {...box(w)} style={{ fill: 'var(--pm-floor-wall)', opacity: w.glass ? 0.45 : 1 }} />
          ))}
          {/* 구역 이름 — 구역 가운데, 불투명 바탕(벽·랙 위에 그려도 겹쳐 보이지 않게) */}
          {plan.zones
            .filter((z) => z.kind !== 'PARKING' && z.tag)
            .map((z) => {
              const fs = Math.min(z.kind === 'QUARANTINE' ? 0.6 : 0.8, (z.rect.x1 - z.rect.x0) / ([...z.label].length + 1.2));
              const w = [...z.label].length * fs * 0.98 + 0.8;
              const cx = (z.rect.x0 + z.rect.x1) / 2;
              const cz = (z.rect.z0 + z.rect.z1) / 2;
              return (
                <g key={`l-${z.id}`} className="pointer-events-none">
                  <rect x={cx - w / 2} y={cz - fs * 0.85} width={w} height={fs * 1.7} rx={fs * 0.5} style={{ fill: 'var(--pm-floor-label-bg)' }} opacity="0.92" />
                  <text x={cx} y={cz + fs * 0.33} textAnchor="middle" className="fill-base-content/80" style={{ fontSize: fs, fontWeight: 700 }}>
                    {z.label}
                  </text>
                </g>
              );
            })}
          {/* 칸 상태(닫힘·실사 잠김) 점은 그리지 않는다(2026-11-24 사용자 — 실서버 닫힘 7천여 칸은 도면 다시 설계·넓은 칸 합침으로 닫힌 칸이라 운영 정보가 아니고 화면만 어지럽힘). 칸 상태는 랙 패널·위치(칸) 메뉴에서 */}
          {/* 작업자 점 — 마지막 스캔 칸(서버) 쪽으로 걷는다 */}
          {dots.map((d) => {
            const role = roleOfDot(d);
            const on = picked?.kind === 'worker' && picked.id === d.id;
            const stale = now - Date.parse(d.at) > STALE_MS;
            const name = nameOf(byId.get(d.id), d.id);
            const choose = () => onPick?.({ kind: 'worker', id: d.id, name, role });
            return (
              <g
                key={d.id}
                className="pm-floor-dot"
                style={{ transform: `translate(${d.x}px, ${d.z}px)` }}
                opacity={stale ? 0.45 : 1}
                onMouseEnter={() => setHover(d.id)}
                onMouseLeave={() => setHover(null)}
                data-testid="floor-worker"
                data-role={role}
                data-worker={d.id}
                {...(full
                  ? {
                      role: 'button',
                      tabIndex: 0,
                      'aria-label': tipOf(d),
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
                {on ? <circle r="0.62" className="pm-floor-ring fill-none stroke-white" strokeWidth="0.06" /> : <circle r="0.6" style={{ fill: ROLE_COLOR[role] }} opacity="0.22" />}
                <circle r="0.3" style={{ fill: ROLE_COLOR[role] }} className="pm-floor-core stroke-base-100" strokeWidth="0.09" />
                <title>{`${tipOf(d)} · ${formatSeoul(d.at)}`}</title>
              </g>
            );
          })}
        </svg>
        <span className="pm-mono pointer-events-none absolute right-2 bottom-1.5 text-[10px] text-base-content/40">{m.scale(plan.size.w, plan.size.d)}</span>
        {!full && <span className="pointer-events-none absolute top-2 right-2 badge badge-sm badge-primary opacity-0 transition-opacity group-hover:opacity-100">{m.openFull}</span>}
      </Frame>
      <p className={full ? 'absolute bottom-3 left-4 z-[1] flex flex-wrap items-center gap-x-4 gap-y-1 rounded-field bg-base-100/80 px-3 py-1.5 text-xs text-base-content/70 backdrop-blur' : 'mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-base-content/65'}>
        {ROLES.map((r) => (
          <span key={r} className="inline-flex items-center gap-1.5" data-testid={`floor-legend-${r}`}>
            <i className="inline-block h-2.5 w-2.5 rounded-full" style={{ background: ROLE_COLOR[r] }} aria-hidden="true" />
            {m.role[r]} <b className="tabular-nums">{positions.isPending ? '…' : positions.isError ? '–' : count(r)}</b>
          </span>
        ))}
        {workers.isError && <span className="text-error">{m.workersFailed}</span>}
        <span className={full ? 'text-base-content/45' : 'ml-auto text-base-content/45'} title={plan.source}>
          {m.layoutNote}
        </span>
      </p>
    </div>
  );
}

const box = (r: Rect) => ({ x: r.x0, y: r.z0, width: r.x1 - r.x0, height: r.z1 - r.z0 });

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
