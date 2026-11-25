// 품질 사고(MB-2 1차, quality 0.6.0)·상품 취급 단종·신상품 배너(inventory 0.27.0) — 목(MSW) 기준. 실서버 확인은 아니다.
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { renderAt } from '../../test/render';

const posts = (sent: readonly Request[], end: string) => sent.filter((r) => r.method === 'POST' && new URL(r.url).pathname.endsWith(end));
const bodyOf = async (r: Request) => (await r.clone().json()) as Record<string, unknown>;

describe('품질 사고', () => {
  it('목록은 이 센터의 끝나지 않은 사고(처리 중·닫기 대기) — 자동/직접·남은 LOT 은 서버 값', async () => {
    const view = renderAt('/c/MFC-BJG-01/quality?tab=incidents');
    const list = await screen.findByTestId('list-incidents');
    const rows = await within(list).findAllByTestId('list-incidents-row');
    expect(rows).toHaveLength(2);
    // 목록에는 사고 번호(시스템 ID)를 내지 않는다(ADR-0070 덧붙임) — 종류·경로·시각으로 알아본다
    expect(list).not.toHaveTextContent('QI-');
    const auto = rows.find((r) => r.textContent?.includes('자동(결품 보고)'))!;
    expect(auto).toHaveTextContent('파손');
    expect(auto).toHaveTextContent('자동(결품 보고)');
    expect(auto).toHaveTextContent('1개');
    const manual = rows.find((r) => r.textContent?.includes('직접 등록'))!;
    expect(manual).toHaveTextContent('처리 끝 — 닫기 대기');
    expect(manual).toHaveTextContent('직접 등록');
    // 목록 요청(숫자 카드는 state 를 보낸다)
    const q = view.gets('/quality-incidents').find((r) => new URL(r.url).searchParams.getAll('state').length === 0)!;
    expect(new URL(q.url).searchParams.get('mfcId')).toBe('MFC-BJG-01');
    expect(new URL(q.url).searchParams.getAll('state')).toEqual([]);
    // 상태 숫자 카드(서버 목록으로 셈)
    expect(await screen.findByTestId('count-OPEN-value')).toHaveTextContent(/1건$/);
    expect(await screen.findByTestId('count-DECIDED-value')).toHaveTextContent(/1건$/);
  });

  it('남은 LOT 이 있으면 닫기 대신 안내, "격리 요청"은 격리·해제 탭에 사고 번호·LOT 을 채워 판정에 잇는다', async () => {
    const view = renderAt('/c/MFC-BJG-01/quality?tab=incidents&incidentId=QI-1');
    const card = await screen.findByTestId('incident');
    expect(card).toHaveTextContent('남은 LOT 1개');
    expect(within(card).queryByRole('button', { name: '사고 닫기' })).not.toBeInTheDocument();
    expect(card).toHaveTextContent('LineShortageReported');
    await userEvent.click(within(card).getByRole('button', { name: '격리 요청' }));

    expect(await screen.findByTestId('decision-incident')).toHaveTextContent('품질 사고 QI-1 의 판정으로 요청해요.');
    const line = screen.getByRole('group', { name: '대상 줄 1' });
    expect(within(line).getByLabelText('LOT')).toHaveValue('LOT-MILK-A');
    expect(within(line).getByLabelText('상품 코드')).toHaveValue('SKU-MILK-1');
    await userEvent.type(within(line).getByLabelText('위치'), 'A-P1-01-1-01');
    await userEvent.click(screen.getByRole('button', { name: '판정 보내기' }));
    await waitFor(() => expect(posts(view.sent, '/quality-decisions')).toHaveLength(1));
    expect(await bodyOf(posts(view.sent, '/quality-decisions')[0]!)).toMatchObject({ incidentId: 'QI-1', decisionType: 'QUARANTINE', lines: [{ lotId: 'LOT-MILK-A', qty: 2 }] });
  });

  it('모두 처리됐으면 사유를 적고 한 번 더 확인한 뒤 닫는다(지금 버전으로)', async () => {
    const view = renderAt('/c/MFC-BJG-01/quality?tab=incidents&incidentId=QI-2');
    const card = await screen.findByTestId('incident');
    expect(within(card).getByTestId('incident-lot')).toHaveTextContent('처리됨');
    const close = within(card).getByRole('button', { name: '사고 닫기' });
    expect(close).toBeDisabled();
    await userEvent.type(within(card).getByLabelText('닫는 사유(300자)'), '오염 LOT 전량 폐기');
    await userEvent.click(close);
    await userEvent.click(within(card).getByRole('button', { name: '닫기' }));
    await waitFor(() => expect(posts(view.sent, '/closures')).toHaveLength(1));
    const req = posts(view.sent, '/closures')[0]!;
    expect(req.headers.get('X-Expected-Version')).toBe('1');
    expect(req.headers.get('Idempotency-Key')).toBeTruthy();
    expect(await bodyOf(req)).toEqual({ reason: '오염 LOT 전량 폐기' });
    expect(await screen.findByText(/오염 LOT 전량 폐기/)).toBeInTheDocument();
    expect(screen.getByTestId('incident')).toHaveTextContent('닫힘');
  });

  it('직접 등록: 이 센터에 없는 LOT 은 422 로 거절, 있는 LOT 이면 등록 뒤 상세를 연다', async () => {
    const view = renderAt('/c/MFC-BJG-01/quality?tab=incidents');
    const form = await screen.findByRole('form', { name: '품질 사고 등록' });
    await userEvent.selectOptions(within(form).getByLabelText('종류'), 'SPOILAGE');
    await userEvent.type(within(form).getByLabelText('설명(300자)'), '냉장 우유 변질 냄새');
    await userEvent.type(within(form).getByLabelText('LOT ID'), 'LOT-NOPE');
    await userEvent.type(within(form).getByLabelText('수량'), '1');
    await userEvent.click(within(form).getByRole('button', { name: '등록' }));
    expect(await within(form).findByText(/이 센터에 재고가 없는 LOT/)).toBeInTheDocument();

    await userEvent.clear(within(form).getByLabelText('LOT ID'));
    await userEvent.type(within(form).getByLabelText('LOT ID'), 'LOT-MILK-B');
    await userEvent.click(within(form).getByRole('button', { name: '등록' }));
    const card = await screen.findByTestId('incident');
    expect(card).toHaveTextContent('변질');
    expect(card).toHaveTextContent('냉장 우유 변질 냄새');
    expect(card).toHaveTextContent('직접 등록');
    const sent = posts(view.sent, '/quality-incidents').at(-1)!;
    expect(await bodyOf(sent)).toEqual({ mfcId: 'MFC-BJG-01', kind: 'SPOILAGE', description: '냉장 우유 변질 냄새', affectedLots: [{ lotId: 'LOT-MILK-B', qty: 1 }] });
  });
});

describe('상품 취급 — 단종·신상품(inventory 0.27.0)', () => {
  it('맨 위 배너에 정하지 않은 새 상품 수(서버 totalCount), 누르면 그 상품만', async () => {
    const view = renderAt('/c/MFC-BJG-01/inventory?tab=handlings');
    const banner = await screen.findByTestId('new-products-banner');
    expect(banner).toHaveTextContent('새 상품 2개가 들어왔어요');
    const count = view.gets('/sku-handlings').map((r) => new URL(r.url).searchParams).find((p) => p.get('undecided') === 'true')!;
    expect(count.get('introducedSince')).toBeTruthy();
    await userEvent.click(within(banner).getByRole('button', { name: '새 상품 보기' }));
    await waitFor(() => expect(screen.getAllByTestId('handling-row')).toHaveLength(2));
    expect(screen.getAllByTestId('handling-row')[0]).toHaveTextContent(/새 상품 · /);
  });

  it('본사 단종 상품은 "본사 단종"이고 켜기를 막는다, 정하면 배너에서 빠진다', async () => {
    renderAt('/c/MFC-BJG-01/inventory?tab=handlings');
    await waitFor(() => expect(screen.getAllByTestId('handling-row')).toHaveLength(14));
    const disc = screen.getAllByTestId('handling-row').find((r) => r.textContent?.includes('SKU-DISC-3'))!;
    expect(disc).toHaveTextContent('본사 단종');
    expect(within(disc).getByRole('button', { name: '켜기' })).toBeDisabled();

    const fresh = screen.getAllByTestId('handling-row').find((r) => r.textContent?.includes('SKU-NEW-1'))!;
    await userEvent.click(within(fresh).getByRole('button', { name: '켜기' }));
    await waitFor(() => expect(screen.getByTestId('new-products-banner')).toHaveTextContent('새 상품 1개가'));
  });
});
