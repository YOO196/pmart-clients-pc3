// 포장 인계 현황(bff 0.11.0 packing-handover, 보기만) — 목(MSW) 기준. 실서버 확인은 아니다.
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';

const calls = (sent: readonly Request[]) =>
  sent.filter((r) => new URL(r.url).pathname.endsWith('/backoffice/views/packing-handover')).map((r) => new URL(r.url).searchParams);

describe('포장 인계 현황(우리 센터)', () => {
  it('주소의 센터로 고정해 끝나지 않은 출고만 — 주문번호·단계·포장별 인계·배송', async () => {
    const view = renderAt('/c/MFC-BSN-01/packing-handover');
    const rows = await screen.findAllByTestId('packing-row');
    expect(rows).toHaveLength(4); // 취소 출고·다른 센터 출고는 없다
    expect(screen.queryByText('10000009')).not.toBeInTheDocument();
    const q = calls(view.sent)[0]!;
    expect([q.get('mfcId'), q.get('size'), q.getAll('state'), q.get('cursor')]).toEqual(['MFC-BSN-01', '50', [], null]);

    const row = (orderNumber: string) => rows.find((r) => r.textContent?.includes(orderNumber))!;
    expect(within(row('10000001')).getByTestId('stage')).toHaveTextContent('출고요청');
    expect(within(row('10000002')).getByTestId('stage')).toHaveTextContent('피킹중');
    expect(within(row('10000002')).getByTestId('delivery')).toHaveTextContent('배정 RD-1');
    // 단계 규칙에 없는 조합은 추정하지 않고 원천 출고 상태
    expect(within(row('10000003')).getByTestId('stage')).toHaveTextContent('단계 없음 — 출고 준비 중');
    expect(within(row('10000003')).getByTestId('delivery')).toHaveTextContent('배송 없음');
    // 일부 인계: 가져간 포장과 남은 포장
    const partial = row('10000004');
    expect(within(partial).getByTestId('stage')).toHaveTextContent('일부 인계');
    expect(within(partial).getByText('재발송')).toBeInTheDocument();
    expect(within(partial).getByTestId('packages')).toHaveTextContent('밀봉 1 / 2 · 인계 1 · 남음 1');
    expect(within(partial).getByTestId('packages')).toHaveTextContent(/PKG-4-1 · 인계됨 · 인계 확정 · .* RD-2 인계/);
    expect(within(partial).getByTestId('packages')).toHaveTextContent('PKG-4-2 · 밀봉');
  });

  it('상태를 고르면 state 로 부르고, 배송 원천을 못 읽으면 "모름(조회 실패)"와 경고(배송 없음과 구분)', async () => {
    const view = renderAt('/c/MFC-BSN-01/packing-handover');
    await screen.findAllByTestId('packing-row');
    await userEvent.selectOptions(screen.getByLabelText('출고 상태'), 'CANCELLED');
    expect(await screen.findByRole('alert')).toHaveTextContent('delivery-execution-service');
    const rows = await screen.findAllByTestId('packing-row');
    expect(rows).toHaveLength(1);
    expect(within(rows[0]!).getByTestId('delivery')).toHaveTextContent('모름(조회 실패)');
    // 주문번호가 없는 옛 주문은 주문 ID
    expect(rows[0]).toHaveTextContent('ORD-P-5');
    expect(calls(view.sent).at(-1)!.getAll('state')).toEqual(['CANCELLED']);
  });
});
