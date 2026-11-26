// 센터 운영판·예외 처리함 — 목(MSW). 출하 약속은 서버 asOf 기준으로 판정해 시계와 무관하게 시험한다.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { delay, http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { as, renderAt } from '../../test/render';
import { server } from '../../test/server';
import { minutesText, promiseRows } from './opsRules';

const NOW = '2026-11-19T03:00:00.000Z';
const at = (min: number) => new Date(Date.parse(NOW) + min * 60_000).toISOString();

interface T {
  readonly taskId: string;
  readonly taskType?: string;
  readonly state?: string;
  readonly shipmentId?: string | null;
  readonly promisedReadyAt?: string | null;
  readonly orderNumber?: string | null;
  readonly workerId?: string | null;
}
const task = (t: T) => ({
  taskId: t.taskId,
  taskType: t.taskType ?? 'PICK',
  state: t.state ?? 'IN_PROGRESS',
  version: 1,
  mfcId: 'MFC-BJG-01',
  fulfillmentId: `FUL-${t.taskId}`,
  shipmentId: t.shipmentId === undefined ? `SHP-${t.taskId}` : t.shipmentId,
  orderNumber: t.orderNumber ?? null,
  assignment: { workerId: t.workerId ?? null, assignmentVersion: 1 },
  lineCount: 1,
  plannedQty: 1,
  completedQty: 0,
  remainingQty: 1,
  promisedReadyAt: t.promisedReadyAt === undefined ? null : t.promisedReadyAt,
  createdAt: '2026-11-19T02:00:00.000Z',
  late: false,
  idle: false,
  lastActivityAt: null,
  headline: { productName: '서울우유 1L', otherLineCount: 0 },
});

/** 작업 목록을 바꾼다(쪽마다 nextCursor) */
function withTasks(pages: ReadonlyArray<ReadonlyArray<ReturnType<typeof task>>>) {
  server.use(
    http.get(`${API_BASE}/tasks`, ({ request }) => {
      const cursor = Number(new URL(request.url).searchParams.get('cursor') ?? 0);
      const next = cursor + 1 < pages.length ? String(cursor + 1) : null;
      return HttpResponse.json({ items: pages[cursor] ?? [], page: { nextCursor: next, size: 200 }, asOf: { asOf: NOW, freshness: 'CURRENT' } });
    }),
  );
}

/**
 * 출하 약속(fulfillment 0.35.0 — 배차 요청 예상 준비 시각): 출고별 약속(shipmentId → 시각, 없으면 배차 요청 전)과 서버 요약.
 * 요약은 부산진구만 이 값, 다른 센터는 0(목포는 늦게 온다).
 */
function withPromises(promises: Readonly<Record<string, string | null>>, summary = { overdue: 0, dueSoon: 0, onTime: 0, noPromise: 0 }) {
  server.use(
    http.get(`${API_BASE}/shipments/promise-summary`, async ({ request }) => {
      const mfcId = new URL(request.url).searchParams.get('mfcId');
      if (mfcId === 'MFC-MOKPO-01') await delay(200);
      const n = mfcId === 'MFC-BJG-01' ? summary : { overdue: 0, dueSoon: 0, onTime: 0, noPromise: 0 };
      return HttpResponse.json({ ...n, dueWithinMinutes: 15, asOf: NOW });
    }),
    http.get(`${API_BASE}/shipments`, ({ request }) => {
      const mfcId = new URL(request.url).searchParams.get('mfcId');
      const items =
        mfcId === 'MFC-BJG-01'
          ? Object.entries(promises).map(([shipmentId, p]) => ({ shipmentId, orderId: `ORD-${shipmentId}`, fulfillmentId: 'F', mfcId, workOrderKind: 'ORIGINAL', state: 'PREPARING', createdAt: NOW, dispatchRequestedAt: p ? NOW : null, packageCounts: { total: 0, sealed: 0, handedOver: 0 }, packages: [] }))
          : [];
      return HttpResponse.json({ items, nextCursor: null, asOf: NOW });
    }),
    http.get(`${API_BASE}/shipments/:shipmentId`, ({ params }) => {
      const id = String(params.shipmentId);
      const p = promises[id] ?? null;
      return HttpResponse.json({ shipmentId: id, orderId: `ORD-${id}`, state: 'PREPARING', packages: [], dispatchRequest: p ? { shipmentId: id, trigger: 'MANUAL', estimatedReadyAt: p, requestedAt: NOW } : null });
    }),
  );
}

const standard = () => {
  // 작업 promisedReadyAt(피킹 시작 가능 시각)은 판정에 쓰지 않는다 — 모두 지난 값이어도 출하 약속은 출고 쪽
  withPromises({ 'SHP-1': at(-30), 'SHP-2': at(10), 'SHP-5': at(90), 'SHP-6': null }, { overdue: 1, dueSoon: 1, onTime: 1, noPromise: 1 });
  return withTasks([
    [
      // 초과 30분 — 피킹·포장이 같은 출고(한 건으로)
      task({ taskId: 'TASK-PICK-1', shipmentId: 'SHP-1', promisedReadyAt: at(-30), orderNumber: '20000001', workerId: 'OP-wkr-1' }),
      task({ taskId: 'TASK-PACK-1', taskType: 'PACK', state: 'WAITING', shipmentId: 'SHP-1', promisedReadyAt: at(-30) }),
      // 임박 10분
      task({ taskId: 'TASK-PICK-2', state: 'READY', shipmentId: 'SHP-2', promisedReadyAt: at(-60) }),
      // 여유(임박 아님)
      task({ taskId: 'TASK-PICK-5', shipmentId: 'SHP-5', promisedReadyAt: at(-60) }),
      // 배차 요청 전(출하 약속 없음) — 세지 않는다
      task({ taskId: 'TASK-PICK-6', shipmentId: 'SHP-6', promisedReadyAt: at(-60) }),
      // 복귀 작업은 출하 약속과 무관
      task({ taskId: 'TASK-RET-1', taskType: 'RETURN', shipmentId: null, promisedReadyAt: at(-100) }),
    ],
  ]);
};

const value = (id: string) => screen.findByTestId(`${id}-value`);
const rows = () => screen.queryAllByTestId('exception-row');

describe('출하 약속 규칙(opsRules)', () => {
  it('출고별로 묶고, 약속 = 출고 배차 요청 예상 준비 시각(작업 promisedReadyAt 은 안 씀), 요청 전 출고는 빼고, 임박은 기준 분 안', () => {
    const now = Date.parse(NOW);
    const r = promiseRows(
      [
        // 작업 promisedReadyAt(피킹 시작 가능 시각)은 지났어도 출하 약속이 아니다
        task({ taskId: 'A', shipmentId: 'S1', promisedReadyAt: at(-90) }),
        task({ taskId: 'B', taskType: 'PACK', state: 'WAITING', shipmentId: 'S1', promisedReadyAt: at(-90) }),
        task({ taskId: 'C', shipmentId: 'S2', promisedReadyAt: at(-90) }),
        task({ taskId: 'D', shipmentId: 'S3', promisedReadyAt: at(-90) }),
        task({ taskId: 'E', shipmentId: 'S4', promisedReadyAt: at(-90) }),
        task({ taskId: 'F', state: 'COMPLETED', shipmentId: 'S5', promisedReadyAt: at(-90) }),
      ] as never,
      new Map([
        ['S1', at(-5)],
        ['S2', at(14)],
        ['S3', at(15)],
        ['S5', at(-50)],
      ]),
      now,
    );
    expect([r.overdue, r.dueSoon, r.noPromise]).toEqual([1, 1, 1]);
    expect(r.rows[0]!.task.taskId).toBe('A'); // 지금 단계 = 피킹
    expect(minutesText(75)).toBe('1시간 15분');
  });
});

describe('센터 운영판', () => {
  it('센터 첫 화면이 홈(오늘 센터 현황)이고 왼쪽 메뉴 맨 위 "홈"으로 돌아온다', async () => {
    standard();
    renderAt('/');
    expect(await screen.findByRole('heading', { name: '오늘 센터 현황' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: '홈' })).toHaveAttribute('href', '/c/MFC-BJG-01/ops');
  });

  it('내 할 일 숫자 칸: 출하 약속(서버 요약 — 배차 요청 예상 준비 시각) · 결품·파손(서버 지표) · 인계 확인 필요 — 작업 목록은 끝나지 않은 상태를 모두, 큰 쪽으로', async () => {
    standard();
    const view = renderAt('/c/MFC-BJG-01/ops');
    expect(await value('tile-overdue')).toHaveTextContent('1건');
    expect(await value('tile-due')).toHaveTextContent('1건');
    expect(screen.getByTestId('ops-rules')).toHaveTextContent('출하 약속 = 배차 요청 때 정한 예상 준비 시각 · 임박 = 15분 안');
    expect(screen.getByTestId('ops-rules')).toHaveTextContent('배차 요청 전이라 약속이 없는 출고 1건은 세지 않아요');
    expect(await value('tile-short')).toHaveTextContent('2줄');
    expect(await value('tile-damaged')).toHaveTextContent('1줄');
    // 변질(SPOILED — fulfillment 0.22.0) 줄도 따로
    expect(await value('tile-spoiled')).toHaveTextContent('1줄');
    expect(await value('tile-handover')).toHaveTextContent('1건');
    // 확인할 일 N가지 한 줄(서버 숫자) — 약속 초과·인계 확인·파손 사고 세 종류(건수가 아니다)
    expect(await screen.findByTestId('ops-status')).toHaveTextContent('확인할 일 3가지');
    expect(new URL(view.gets('/shipments/promise-summary')[0]!.url).searchParams.get('dueWithinMinutes')).toBe('15');
    const q = new URL(view.gets('/tasks')[0]!.url).searchParams;
    expect([q.get('mfcId'), q.getAll('state'), q.get('size')]).toEqual(['MFC-BJG-01', ['WAITING', 'READY', 'ASSIGNED', 'IN_PROGRESS', 'BLOCKED'], '200']);
    const m = new URL(view.gets('/metrics/picking-lines')[0]!.url).searchParams;
    expect(m.get('from')).toBe(m.get('to'));
  });

  it('숫자 칸을 누르면 같은 화면 예외 목록이 그 유형만 — 행은 상세 화면으로 이어진다', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops');
    await waitFor(() => expect(rows().length).toBeGreaterThanOrEqual(4));

    // 출하 약속: 초과(30분 지남) → 임박(10분 남음), 작업 상세로
    await userEvent.click(screen.getByTestId('tile-overdue'));
    await waitFor(() => expect(rows().every((r) => r.dataset.group === 'promise')).toBe(true));
    expect(rows()).toHaveLength(2);
    expect(rows()[0]).toHaveTextContent('출하 약속 초과');
    expect(rows()[0]).toHaveTextContent('20000001');
    expect(rows()[0]).toHaveTextContent('30분 지남');
    expect(rows()[0]).toHaveTextContent('피킹 진행 중');
    expect(rows()[1]).toHaveTextContent('출하 약속 임박');
    expect(rows()[1]).toHaveTextContent('10분 남음');
    expect(rows()[1]).toHaveTextContent('정보 없음'); // 주문번호 없음
    expect(within(rows()[0]!).getByRole('link', { name: '작업 상세 — 재배정·작업 풀기' })).toHaveAttribute('href', '/c/MFC-BJG-01/tasks/TASK-PICK-1#task-actions');
    expect(rows()[0]).toHaveTextContent(/출하 약속 \S/);

    // 결품·파손: 피킹 결품 보고로 열린 파손 사고만(직접 등록 사고 제외), 결품 건별 목록은 계약 없음 안내
    await userEvent.click(screen.getByTestId('tile-damaged'));
    await waitFor(() => expect(rows().every((r) => r.dataset.group === 'picking')).toBe(true));
    expect(rows()).toHaveLength(1);
    expect(rows()[0]).toHaveTextContent('피킹 파손');
    // LOT 은 화면 번호(inventory lot-numbers) — 시스템 LOT ID 는 내지 않는다
    await waitFor(() => expect(rows()[0]).toHaveTextContent('L261107000497'));
    expect(rows()[0]).not.toHaveTextContent('LOT-MILK-A');
    expect(within(rows()[0]!).getByRole('link', { name: '품질 사고 — 격리·폐기' })).toHaveAttribute('href', '/c/MFC-BJG-01/quality?tab=incidents&incidentId=QI-1');
    expect(screen.getByText('결품 건별 목록은 아직 없어요.')).toBeInTheDocument();

    // 인계 확인: 확인 필요 포장 화면으로(확인 버튼은 그 화면)
    await userEvent.click(screen.getByTestId('tile-handover'));
    await waitFor(() => expect(rows().every((r) => r.dataset.group === 'handover')).toBe(true));
    expect(rows()).toHaveLength(1);
    // 목록에는 화면 표기만(포장대 위치) — 포장 시스템 ID 는 내지 않는다(ADR-0070 덧붙임)
    expect(rows()[0]).not.toHaveTextContent('PKG-1');
    expect(within(rows()[0]!).getByRole('link', { name: '확인 필요 포장 — 실물 확인' })).toHaveAttribute('href', '/c/MFC-BJG-01/tasks#handover-checks');
    expect(screen.queryByRole('button', { name: '포장대에 있음' })).not.toBeInTheDocument();

    // 상세로 이동 — 작업 상세(작업 풀기는 그 화면)
    await userEvent.click(screen.getByRole('button', { name: '출하 약속' }));
    await waitFor(() => expect(rows()[0]!.dataset.group).toBe('promise'));
    await userEvent.click(within(rows()[0]!).getByRole('link'));
    expect(await screen.findByRole('heading', { level: 1, name: /^20000001 피킹/ })).toBeInTheDocument();
  });

  it('필터는 URL 에 — 주소로 바로 열어도 그 유형', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops?type=handover');
    await waitFor(() => expect(rows()).toHaveLength(1));
    expect(rows()[0]!.dataset.group).toBe('handover');
    expect(screen.getByRole('button', { name: '인계 확인' })).toHaveAttribute('aria-pressed', 'true');
  });

  it('숫자 칸은 서버 요약(전체) — 작업이 상한을 넘어 줄을 다 못 읽으면 그렇다고 알린다', async () => {
    const page = (n: number) => Array.from({ length: 3 }, (_, i) => task({ taskId: `T-${n}-${i}`, shipmentId: `S-${n}-${i}` }));
    withTasks([page(0), page(1), page(2), page(3), page(4), page(5)]);
    withPromises(Object.fromEntries(Array.from({ length: 18 }, (_, k) => [`S-${Math.floor(k / 3)}-${k % 3}`, at(-5)])), { overdue: 18, dueSoon: 0, onTime: 0, noPromise: 0 });
    const view = renderAt('/c/MFC-BJG-01/ops');
    expect(await value('tile-overdue')).toHaveTextContent('18건');
    await waitFor(() => expect(view.gets('/tasks')).toHaveLength(5));
    expect(await screen.findByText(/일부만 읽었어요/)).toBeInTheDocument();
  });

  it('작업 promisedReadyAt 이 지났어도 배차 요청 전 출고는 "출하 약속 초과"가 아니다(즉시 주문 피킹 중)', async () => {
    withTasks([[task({ taskId: 'TASK-NOW-1', shipmentId: 'SHP-NOW', promisedReadyAt: at(-40), orderNumber: '20009999' })]]);
    withPromises({ 'SHP-NOW': null }, { overdue: 0, dueSoon: 0, onTime: 0, noPromise: 1 });
    renderAt('/c/MFC-BJG-01/ops?type=promise');
    expect(await value('tile-overdue')).toHaveTextContent('0건');
    expect(await screen.findByText('처리할 예외가 없어요')).toBeInTheDocument();
  });

  it('조회 실패는 0건이 아니다 — 실패한 원천만 "조회 실패", 나머지는 보인다', async () => {
    standard();
    server.use(http.get(`${API_BASE}/packages`, () => new HttpResponse(null, { status: 500 })));
    renderAt('/c/MFC-BJG-01/ops');
    const tile = screen.getByTestId('tile-handover');
    expect(await within(tile).findByText('조회 실패')).toBeInTheDocument();
    expect(within(tile).queryByText('0건')).not.toBeInTheDocument();
    expect(await screen.findByTestId('source-failed-handover')).toHaveTextContent('인계 확인 필요 조회에 실패해');
    expect(await value('tile-overdue')).toHaveTextContent('1건');
    expect(screen.queryByText('처리할 예외가 없어요')).not.toBeInTheDocument();
  });

  it('실제 0건은 0건 — 예외가 없으면 빈 목록 안내', async () => {
    withTasks([[]]);
    withPromises({});
    server.use(
      http.get(`${API_BASE}/packages`, () => HttpResponse.json({ items: [], asOf: { asOf: NOW, freshness: 'CURRENT' } })),
      http.get(`${API_BASE}/quality-incidents`, () => HttpResponse.json({ items: [], nextCursor: null })),
      http.get(`${API_BASE}/metrics/picking-lines`, () => HttpResponse.json({ items: [], asOf: NOW })),
    );
    renderAt('/c/MFC-BJG-01/ops');
    expect(await value('tile-overdue')).toHaveTextContent('0건');
    expect(await value('tile-due')).toHaveTextContent('0건');
    expect(await value('tile-short')).toHaveTextContent('0줄');
    expect(await value('tile-damaged')).toHaveTextContent('0줄');
    expect(await value('tile-handover')).toHaveTextContent('0건');
    expect(await screen.findByText('처리할 예외가 없어요')).toBeInTheDocument();
    await waitFor(() => expect(screen.getByTestId('ops-status')).toHaveTextContent('이상 없음'));
  });

  it('센터를 바꾸면 이전 센터 예외가 잠깐도 남지 않는다', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops', as.sup2);
    await waitFor(() => expect(rows().length).toBeGreaterThan(0));
    // 목포는 늦게 온다 — 오는 동안 부산진 값이 보이면 안 된다.
    server.use(
      http.get(`${API_BASE}/tasks`, async ({ request }) => {
        if (new URL(request.url).searchParams.get('mfcId') === 'MFC-MOKPO-01') await delay(200);
        return HttpResponse.json({ items: [], page: { nextCursor: null, size: 200 }, asOf: { asOf: NOW, freshness: 'CURRENT' } });
      }),
    );
    await userEvent.selectOptions(screen.getByRole('combobox', { name: '센터 고르기' }), 'MFC-MOKPO-01');
    expect(screen.queryByText('20000001')).not.toBeInTheDocument();
    expect(screen.queryByTestId('tile-overdue-value')).not.toBeInTheDocument();
    expect(screen.queryByText('PKG-1')).not.toBeInTheDocument();
    expect(await value('tile-overdue')).toHaveTextContent('0건');
  });

  it('권한: 작업자 전용 계정은 막고, 맡지 않은 센터는 운영판을 부르지 않는다', async () => {
    renderAt('/c/MFC-BJG-01/ops', as.worker);
    expect(await screen.findByRole('alert')).toHaveTextContent(/PDA/);
    const view = renderAt('/c/MFC-SEJ-01/ops');
    expect(await screen.findAllByText(/이 센터 권한이 없습니다/)).not.toHaveLength(0);
    expect(view.gets('/tasks')).toHaveLength(0);
  });
});

describe('홈 보탬 — 작업 흐름·작업자 지금·최근 본 것, 메뉴 배지, 단축키 안내', () => {
  it('작업 흐름: 유형별 단계 수(서버 목록), 먼저 확인, 누르면 작업 현황이 그 조건으로', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops');
    const board = await screen.findByTestId('flow-board');
    await waitFor(() => expect(within(board).getByTestId('flow-PICK-doing')).toHaveTextContent(/^3$/));
    expect(within(board).getByTestId('flow-PICK-wait')).toHaveTextContent(/^1$/);
    expect(within(board).getByTestId('flow-PACK-before')).toHaveTextContent(/^1$/);
    expect(within(board).getByTestId('flow-RETURN-doing')).toHaveTextContent(/^1$/);
    expect(within(board).getByTestId('flow-first-unassigned')).toHaveTextContent(/1$/);
    expect(within(board).getByTestId('flow-first-blocked')).toHaveTextContent(/0$/);
    expect(within(board).getByTestId('flow-PICK-wait')).toHaveAttribute('href', '/c/MFC-BJG-01/tasks?type=PICK&state=READY');
  });

  it('쪽 상한에 걸려 다 못 읽었으면 단계 수는 "N+"', async () => {
    withTasks(Array.from({ length: 6 }, (_, p) => [task({ taskId: `T-${p}`, shipmentId: null })]));
    renderAt('/c/MFC-BJG-01/ops');
    const board = await screen.findByTestId('flow-board');
    await waitFor(() => expect(within(board).getByTestId('flow-PICK-doing')).toHaveTextContent(/^5\+$/));
  });

  it('작업자 지금: 재직 작업자마다 맡은 작업 수, 쉬지 않는데 맡은 일 없으면 표시', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops');
    const box = await screen.findByTestId('worker-load');
    await waitFor(() => expect(within(box).getAllByTestId('worker-load-row')).toHaveLength(3));
    const row = (name: string) => within(box).getAllByTestId('worker-load-row').find((r) => r.textContent?.includes(name))!;
    await waitFor(() => expect(row('김현장')).toHaveTextContent('맡은 작업 1(진행 1)'));
    expect(row('이알바')).toHaveTextContent('휴게 중');
    expect(within(row('이알바')).queryByTestId('worker-free')).not.toBeInTheDocument();
    expect(within(row('박일일')).getByTestId('worker-free')).toHaveTextContent('맡은 일 없음');
  });

  it('작업 목록을 못 읽으면 "맡은 일 없음"이라 하지 않는다', async () => {
    server.use(http.get(`${API_BASE}/tasks`, () => HttpResponse.json({ status: 503, code: 'DEPENDENCY_UNAVAILABLE', type: 'about:blank' }, { status: 503, headers: { 'content-type': 'application/problem+json' } })));
    renderAt('/c/MFC-BJG-01/ops');
    const box = await screen.findByTestId('worker-load');
    await waitFor(() => expect(within(box).getAllByTestId('worker-load-row')[0]).toHaveTextContent('맡은 작업 모름'));
    expect(within(box).queryByTestId('worker-free')).not.toBeInTheDocument();
  });

  it('최근 본 것: 상세를 열면 이 센터 홈에 화면 표기로 남는다(시스템 ID 없이)', async () => {
    standard();
    renderAt('/c/MFC-BJG-01/ops');
    expect(await screen.findByTestId('recent-panel')).toHaveTextContent('최근 연 상세가 없어요');
    // 출하 약속 줄(맨 위)은 작업·출고별 약속을 다 읽은 뒤에 나온다
    await waitFor(() => expect(rows()[0]?.dataset.group).toBe('promise'));
    await userEvent.click(within(rows()[0]!).getByRole('link'));
    await screen.findByRole('heading', { level: 1, name: /^20000001 피킹/ });
    await userEvent.click(screen.getByRole('link', { name: '홈' }));
    const item = await screen.findByTestId('recent-item');
    expect(item).toHaveTextContent(/^20000001 피킹$/);
    expect(item).not.toHaveTextContent('TASK-');
  });

  it('메뉴 "작업 현황" 옆 늦음·막힘 수, "?" 로 단축키 안내', async () => {
    withTasks([[{ ...task({ taskId: 'L-1' }), late: true }, task({ taskId: 'B-1', state: 'BLOCKED' }), task({ taskId: 'N-1' })]]);
    renderAt('/c/MFC-BJG-01/ops');
    expect(await screen.findByTestId('menu-alert-tasks')).toHaveTextContent(/^2$/);
    await userEvent.keyboard('?');
    expect(await screen.findByTestId('shortcut-help')).toHaveTextContent('이전 건·다음 건');
    await userEvent.keyboard('{Escape}');
    await waitFor(() => expect(screen.queryByTestId('shortcut-help')).not.toBeInTheDocument());
  });
});
