// 시뮬레이터 평면(pmart-mfc-simulation buildLayout 계열)을 센터별 도면 JSON 으로 뽑는다 — run.mjs 가 rolldown 으로 묶어 실행한다.
// `sim/…` 은 run.mjs 가 시뮬레이터 src 폴더로 바꾼다(시뮬레이터 저장소는 읽기만).
// 백엔드는 같은 시뮬레이터 평면의 칸 위치 파일(layoutExport)로 센터 칸 좌표를 등록했다 → 이 도면과 서버 칸 position 이 같은 좌표계(x 동쪽·z 남쪽 m).
import { buildLayout, type Layout } from 'sim/domain/layout';
import { buildBusanjinLayout } from 'sim/domain/layoutBusanjin';
import { buildBusanNamguLayout } from 'sim/domain/layoutBusanNamgu';
import { buildChuncheonLayout } from 'sim/domain/layoutChuncheon';
import { applyMokpo } from 'sim/domain/layoutMokpo';
import { buildSejongLayout } from 'sim/domain/layoutSejong';
import { buildLocationCodeMap, shelfBackendCode } from 'sim/domain/locationCodes';
import { applyWideCells } from 'sim/domain/wideCells';

/** 실서버 센터 ID → 시뮬레이터 평면(시뮬레이터 config MFC_SITES 와 같음) */
const SITES: ReadonlyArray<{ id: string; name: string; build: () => Layout }> = [
  { id: 'MFC-SEED-01', name: '부산진구 MFC', build: buildBusanjinLayout },
  { id: 'MFC-MOKPO-01', name: '목포 MFC', build: () => applyMokpo(buildLayout()) },
  { id: 'MFC-SEJ-01', name: '세종 MFC', build: buildSejongLayout },
  { id: 'MFC-CHC-01', name: '춘천 MFC', build: buildChuncheonLayout },
  { id: 'MFC-BNG-01', name: '부산남구 MFC', build: buildBusanNamguLayout },
];

const r2 = (v: number) => Math.round(v * 100) / 100;
const rect = (r: { x0: number; z0: number; x1: number; z1: number }) => [r2(r.x0), r2(r.z0), r2(r.x1), r2(r.z1)];
const pt = (p: { x: number; z: number }) => [r2(p.x), r2(p.z)];

export function exportFloors(source: string): Array<{ id: string; json: unknown; summary: string }> {
  return SITES.map(({ id, name, build }) => {
    const L = build();
    const codes = buildLocationCodeMap(L);
    applyWideCells(L, codes);
    const open = L.locations.filter((l) => !l.closed);
    const byRack = new Map<string, { n: number; x: number; z: number }>();
    for (const l of open) {
      const a = byRack.get(l.rackId) ?? { n: 0, x: 0, z: 0 };
      a.n += 1;
      a.x += l.pick.x;
      a.z += l.pick.z;
      byRack.set(l.rackId, a);
    }
    const racks = L.racks.map((r) => {
      const a = byRack.get(r.id);
      const code = shelfBackendCode(r.temp, r.group, r.rackNo, 1, 1).replace(/-1-01$/, '');
      return {
        code,
        temp: r.temp,
        c: pt({ x: r.cx, z: r.cz }),
        along: r.along,
        face: r.face,
        levels: r.levels,
        slots: r.slotsPerLevel,
        cells: a?.n ?? 0,
        stand: a ? pt({ x: a.x / a.n, z: a.z / a.n }) : null,
        ...(r.reserve ? { reserve: true } : {}),
      };
    });
    const json = {
      centerId: id,
      name,
      variant: L.variant,
      source,
      width: r2(L.width),
      depth: r2(L.depth),
      buildingDepth: r2(L.buildingDepth),
      yardX: [r2(L.geo.yardX[0]), r2(L.geo.yardX[1])],
      floorX0: r2(L.geo.floorX0 ?? 0),
      outsideYards: (L.geo.outsideYards ?? []).map(rect),
      zones: L.zones.map((z) => ({
        id: z.id,
        kind: z.kind,
        label: z.label,
        rect: rect(z.rect),
        ...(z.outline ? { outline: z.outline.map(pt) } : {}),
        ...(z.noTag ? { noTag: true } : {}),
        ...(z.noOutline ? { noOutline: true } : {}),
      })),
      walls: L.walls.map((w) => (w.glass ? { r: rect(w.rect), glass: true } : { r: rect(w.rect) })),
      obstacles: L.obstacles.map((o) => ({ r: rect(o.rect), kind: o.kind })),
      racks,
      stations: L.stations.map((s) => ({ id: s.id, table: pt(s.table), stand: pt(s.stand) })),
      reserves: L.reserves.map((s) => ({ id: s.id, temp: s.temp, role: s.role, r: rect(s.rect), stand: pt(s.stand), code: codes.toBackend(s.id) })),
      dock: L.dockSlots.map((d) => pt(d.pos)),
      ship: L.shippingSlots.map((s) => pt(s.pos)),
      points: {
        truckDoor: pt(L.points.truckDoor),
        inboundIdle: L.points.inboundIdle.map(pt),
        cartDepot: pt(L.points.cartDepot),
        idle: L.points.idle.map(pt),
        packQueue: pt(L.points.packQueue),
        shipDrop: pt(L.points.shipDrop),
        riderPickup: pt(L.points.riderPickup),
      },
    };
    const shelf = open.filter((l) => !l.reserve).length;
    return { id, json, summary: `${id} ${L.variant} ${L.width.toFixed(1)}×${L.buildingDepth.toFixed(1)}m 랙 ${L.racks.filter((r) => !r.reserve).length}(+보충 ${L.racks.filter((r) => r.reserve).length}) 선반 칸 ${shelf}` };
  });
}
