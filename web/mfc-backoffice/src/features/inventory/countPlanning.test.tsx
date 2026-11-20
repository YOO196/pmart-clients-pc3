// 재고 실사 시간대(capacity 0.33.0)·순환 실사 시작(inventory 0.42.0) — 백엔드 지침 2026-11-20.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../../api/client';
import { db } from '../../mocks/db';
import { problem } from '../../mocks/support';
import { renderAt } from '../../test/render';
import { server } from '../../test/server';
import { windowProblem } from './CountPlanning';

const sentBody = async (r: Request) => (await r.clone().json()) as Record<string, unknown>;
const sentTo = (sent: Request[], method: string, suffix: string) => sent.filter((r) => r.method === method && new URL(r.url).pathname.endsWith(suffix));

describe('재고 실사 시간대', () => {
  it('바꾼 적 없으면 기본값 07:00–08:00 · 20:00–21:00 과 "기본값" 꼬리표', async () => {
    renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const card = await screen.findByTestId('count-windows');
    expect(await within(card).findByTestId('count-windows-text')).toHaveTextContent('07:00–08:00 · 20:00–21:00');
    expect(within(card).getByText('기본값')).toBeInTheDocument();
  });

  it('바꾸기 → 목록 통째로 X-Expected-Version 0 으로 보내고 응답으로 다시 그린다', async () => {
    const view = renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const card = await screen.findByTestId('count-windows');
    await userEvent.click(await within(card).findByRole('button', { name: '바꾸기' }));
    const start1 = within(card).getByLabelText('1번째 시작');
    await userEvent.clear(start1);
    await userEvent.type(start1, '06:30');
    const end1 = within(card).getByLabelText('1번째 끝');
    await userEvent.clear(end1);
    await userEvent.type(end1, '07:30');
    await userEvent.click(within(card).getByRole('button', { name: '시간대 저장' }));
    expect(await within(card).findByText('실사 시간대를 저장했어요.')).toBeInTheDocument();
    expect(within(card).getByTestId('count-windows-text')).toHaveTextContent('06:30–07:30 · 20:00–21:00');
    expect(within(card).queryByText('기본값')).not.toBeInTheDocument();
    const put = sentTo(view.sent, 'PUT', '/count-windows')[0]!;
    expect(put.headers.get('X-Expected-Version')).toBe('0');
    expect(put.headers.get('Idempotency-Key')).toBeTruthy();
    expect(await sentBody(put)).toEqual({ windows: [{ startTime: '06:30', endTime: '07:30' }, { startTime: '20:00', endTime: '21:00' }] });
    expect(db.countWindows.get('MFC-BSN-01')!.version).toBe(1);
  });

  it('미리 검사: 시작 ≥ 끝, 겹침, 7개 이상', () => {
    expect(windowProblem([{ startTime: '08:00', endTime: '07:00' }])).toContain('시작이 끝보다');
    expect(windowProblem([{ startTime: '07:00', endTime: '08:00' }, { startTime: '07:30', endTime: '09:00' }])).toContain('겹쳐요');
    expect(windowProblem(Array.from({ length: 7 }, (_, i) => ({ startTime: `0${i}:00`, endTime: `0${i}:30` })))).toContain('6개까지');
    expect(windowProblem([])).toBeNull();
  });

  it('그 사이 다른 관리자가 바꿨으면(409) 거절 안내 + 다시 읽기', async () => {
    server.use(http.put(`${API_BASE}/mfcs/:mfcId/count-windows`, () => problem(409, 'VERSION_CONFLICT')));
    const view = renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const card = await screen.findByTestId('count-windows');
    await userEvent.click(await within(card).findByRole('button', { name: '바꾸기' }));
    await userEvent.click(within(card).getByRole('button', { name: '시간대 저장' }));
    await waitFor(() => expect(within(card).getByRole('alert')).toBeInTheDocument());
    await waitFor(() => expect(view.gets('/count-windows').length).toBeGreaterThan(1));
  });
});

describe('순환 실사 시작', () => {
  it('칸 수 → "다음"에서 잠김 확인 → 시작하기: rotationSize 만 보내고 고른 칸을 보인다', async () => {
    const view = renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const box = await screen.findByTestId('rotation-count');
    await userEvent.click(within(box).getByRole('button', { name: '순환 실사 시작' }));
    const size = within(box).getByLabelText('칸 수(1~200)');
    await userEvent.clear(size);
    await userEvent.type(size, '3');
    await userEvent.click(within(box).getByRole('button', { name: '다음' }));
    expect(within(box).getByTestId('rotation-confirm')).toHaveTextContent('칸 최대 3개');
    expect(sentTo(view.sent, 'POST', '/count-plans')).toHaveLength(0);
    await userEvent.click(within(box).getByRole('button', { name: '시작하기' }));
    const result = await within(box).findByTestId('rotation-result');
    expect(result).toHaveTextContent('실사 계획을 열었어요');
    const post = sentTo(view.sent, 'POST', '/count-plans')[0]!;
    expect(await sentBody(post)).toEqual({ rotationSize: 3 });
    expect(post.headers.get('Idempotency-Key')).toBeTruthy();
  });

  it('고를 칸이 없으면(422 NO_COUNT_LOCATIONS) 그 이유', async () => {
    server.use(http.post(`${API_BASE}/mfcs/:mfcId/count-plans`, () => problem(422, 'NO_COUNT_LOCATIONS')));
    renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const box = await screen.findByTestId('rotation-count');
    await userEvent.click(within(box).getByRole('button', { name: '순환 실사 시작' }));
    await userEvent.click(within(box).getByRole('button', { name: '다음' }));
    await userEvent.click(within(box).getByRole('button', { name: '시작하기' }));
    expect(await within(box).findByText(/지금 실사할 칸이 없어요/)).toBeInTheDocument();
  });

  it('칸 수 0·201 은 막는다', async () => {
    renderAt('/c/MFC-BSN-01/inventory?tab=counts');
    const box = await screen.findByTestId('rotation-count');
    await userEvent.click(within(box).getByRole('button', { name: '순환 실사 시작' }));
    const size = within(box).getByLabelText('칸 수(1~200)');
    await userEvent.clear(size);
    await userEvent.type(size, '201');
    expect(within(box).getByText('칸 수는 1~200 이에요.')).toBeInTheDocument();
    expect(within(box).getByRole('button', { name: '다음' })).toBeDisabled();
  });
});
