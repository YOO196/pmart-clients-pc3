// 나머지 메뉴도 같은 틀(2026-11-19) — 안내 상자 없음(2026-11-21), 검색 칩 접기·내 보기, 위치 최근 봄·이전/다음, 센터 목록 건수.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { openFilter, renderAt } from '../test/render';

describe('나머지 메뉴도 같은 틀', () => {
  it.each(['assignments', 'deliveries', 'packing-handover', 'return-handovers', 'inbound', 'inventory', 'locations', 'quality', 'restrictions', 'moves', 'tasks', 'dispatch-delays'])(
    '%s: 맨 위 안내 상자는 없다(2026-11-21 사용자 — 실사용에 쓸모없음)',
    async (segment) => {
      renderAt(`/c/MFC-BJG-01/${segment}`);
      await screen.findByRole('heading', { level: 1 });
      expect(screen.queryByTestId('guide-box')).not.toBeInTheDocument();
      // 안내 상자는 "… 안내" 제목 단추로 접고 폈다
      expect(screen.queryByRole('button', { name: /안내/ })).not.toBeInTheDocument();
    },
  );

  it('배송 현황: 상태를 고르면 칩으로 접히고 내 보기로 저장할 수 있다', async () => {
    renderAt('/c/MFC-BJG-01/deliveries?state=ASSIGNED');
    const bar = await screen.findByTestId('search-bar');
    expect(within(bar).getByTestId('search-chip').querySelector('button')?.title).toMatch(/상태/);
    expect(within(bar).getByRole('form', { hidden: true })).not.toBeVisible();
    await userEvent.click(within(screen.getByTestId('saved-views')).getByRole('button', { name: '+ 지금 조건 저장' }));
    await userEvent.type(screen.getByRole('textbox', { name: '보기 이름' }), '배정됨');
    await userEvent.click(screen.getByRole('button', { name: '저장' }));
    expect(within(screen.getByTestId('saved-views')).getByRole('link', { name: '배정됨' })).toHaveAttribute('href', '/c/MFC-BJG-01/deliveries?state=ASSIGNED');
  });

  it('배정: 작업자 거르기는 이름으로 쳐서 찾기(운영자 ID 를 치지 않는다)', async () => {
    const view = renderAt('/c/MFC-BJG-01/assignments');
    await openFilter();
    const box = await screen.findByRole('combobox', { name: '작업자' });
    await userEvent.click(box);
    await userEvent.type(box, 'ㄱㅎㅈ');
    await userEvent.keyboard('{ArrowDown}{Enter}');
    await waitFor(() => expect(view.gets('/assignments').some((r) => new URL(r.url).searchParams.get('workerId') === 'OP-wkr-1')).toBe(true));
  });

  it('위치: 상세를 열면 목록에 "최근 봄", 상세는 목록 순서대로 이전·다음', async () => {
    renderAt('/c/MFC-BJG-01/locations');
    const rows = await screen.findAllByTestId('location-row');
    await userEvent.click(within(rows[0]!).getByRole('link'));
    expect(await screen.findByTestId('queue-pos')).toHaveTextContent(`1 / ${rows.length}`);
    expect(screen.getByTestId('system-numbers')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('link', { name: '‹ 보던 목록으로' }));
    expect(await screen.findByTestId('seen-mark')).toBeInTheDocument();
  });

  it('센터 목록: 불러온 건수를 보인다', async () => {
    renderAt('/c/MFC-BJG-01/quality');
    expect(await screen.findByTestId('list-decisions-count')).toHaveTextContent(/^1건$/);
  });
});
