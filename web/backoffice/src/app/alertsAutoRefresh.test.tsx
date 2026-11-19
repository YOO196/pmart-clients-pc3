// 처리한 뒤 알림 숫자를 바로 맞추기(2026-11-19 사용자 "알람 수가 바로 안 사라지고 시간이 좀 걸린다")
import { QueryClient, QueryClientProvider, useQuery } from '@tanstack/react-query';
import { act, render, waitFor } from '@testing-library/react';
import { afterEach, describe, expect, it } from 'vitest';

import { ALERT_RECHECK_MS, AlertsAutoRefresh } from './AlertsAutoRefresh';

const calls = { alert: 0, dash: 0, list: 0 };
function Probe() {
  useQuery({ queryKey: ['menu-alert', 'approvals'], queryFn: () => ++calls.alert });
  useQuery({ queryKey: ['dashboard', 'work-counts'], queryFn: () => ++calls.dash });
  useQuery({ queryKey: ['approval', 'list'], queryFn: () => ++calls.list });
  return null;
}

function setup() {
  calls.alert = 0;
  calls.dash = 0;
  calls.list = 0;
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={client}>
      <AlertsAutoRefresh />
      <Probe />
    </QueryClientProvider>,
  );
  return client;
}

afterEach(() => {
  ALERT_RECHECK_MS.value = 3_000;
});

describe('처리 뒤 알림 숫자 바로 맞추기', () => {
  it('업무 목록(승인)이 다시 읽히면 메뉴 알림·대시보드 숫자도 바로, 그리고 잠시 뒤 한 번 더(서버가 뒤에서 반영하는 명령)', async () => {
    ALERT_RECHECK_MS.value = 30;
    const client = setup();
    await waitFor(() => expect(calls.alert).toBe(1));
    await act(() => client.invalidateQueries({ queryKey: ['approval'] }));
    await waitFor(() => expect(calls.alert).toBe(2));
    expect(calls.dash).toBe(2);
    await waitFor(() => expect(calls.alert).toBe(3)); // 다시 확인
  });

  it('알림 키끼리는 서로 부르지 않는다(돌고 도는 다시 읽기 없음)', async () => {
    const client = setup();
    await waitFor(() => expect(calls.alert).toBe(1));
    await act(() => client.invalidateQueries({ queryKey: ['menu-alert'] }));
    await waitFor(() => expect(calls.alert).toBe(2));
    expect(calls.dash).toBe(1);
    expect(calls.list).toBe(1);
  });
});
