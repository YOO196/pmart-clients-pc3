// 고객센터·라이더 운영 메뉴(백엔드 요청 2026-11-15 cs-rider-menus) — 목(MSW) 기준. 실서버 확인은 아니다.
import { cleanup, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { http, HttpResponse } from 'msw';
import { describe, expect, it } from 'vitest';

import { API_BASE } from '../api/client';
import { env } from '../env';
import { as, renderAt } from '../test/render';
import { server } from '../test/server';

const groupLabels = () => [...document.querySelectorAll('[data-testid^="nav-group-"] > summary')].map((s) => s.textContent);

describe('메뉴 묶음 — 역할로 보이고(합집합) 접고 편다', () => {
  it('역할마다 보이는 묶음', async () => {
    const cases: Array<[string, string[]]> = [
      [as.md, ['상품 관리', '업무 도우미']],
      [as.approver, ['승인', '업무 도우미']],
      [as.cs, ['고객센터', '업무 도우미']],
      [as.riderOps, ['라이더 운영', '업무 도우미']],
      [as.csRider, ['고객센터', '라이더 운영', '업무 도우미']],
      [as.admin, ['승인', '고객센터', '라이더 운영', '업무 도우미']],
      [as.center, ['업무 도우미']],
    ];
    for (const [token, expected] of cases) {
      renderAt('/session', token);
      await screen.findByRole('link', { name: /내 세션/ });
      expect(groupLabels()).toEqual(expected);
      cleanup();
    }
  });

  it('지금 화면의 묶음만 펼친 채로 시작하고, 묶음 이름을 누르면 접고 편다', async () => {
    const user = userEvent.setup();
    renderAt('/inquiries', as.csRider);
    const cs = await screen.findByTestId('nav-group-cs');
    const riderOps = screen.getByTestId('nav-group-riderOps');
    expect(cs).toHaveAttribute('open');
    expect(riderOps).not.toHaveAttribute('open');
    await user.click(within(riderOps).getByText('라이더 운영'));
    expect(riderOps).toHaveAttribute('open');
    await user.click(within(cs).getByText('고객센터'));
    expect(cs).not.toHaveAttribute('open');
  });

  it('첫 화면은 역할로 보이는 첫 메뉴 — 상담원은 주문 조회, 라이더 운영은 라이더 찾기', async () => {
    renderAt('/', as.cs);
    expect(await screen.findByRole('heading', { name: '주문 조회' })).toBeInTheDocument();
    cleanup();
    renderAt('/', as.riderOps);
    expect(await screen.findByRole('heading', { name: '라이더 찾기·계정 제한' })).toBeInTheDocument();
  });
});

describe('주문 조회', () => {
  it('기본 기간(7일)으로 찾고, 목록 연락처는 서버가 가린 값만 보인다', async () => {
    const view = renderAt('/orders', as.cs);
    expect(await screen.findAllByTestId('order-row')).toHaveLength(3);
    expect(screen.getAllByText('010-****-5678')).toHaveLength(2);
    expect(document.body.textContent).not.toContain('01012345678');
    const sent = view.sent.find((r) => r.url.includes('/orders/lookups'));
    const q = new URL(sent?.url ?? '').searchParams;
    expect(q.get('createdFrom')).toBeTruthy();
    expect(q.get('createdTo')).toBeTruthy();
    view.stop();
  });

  it('주문 ID·고객 ID 없이 기간도 없으면 보내지 않고 안내한다 / 연락처는 숫자 9~11자리', async () => {
    const user = userEvent.setup();
    const view = renderAt('/orders?from=&to=', as.cs);
    expect(await screen.findByTestId('order-search-blocked')).toHaveTextContent('기간을 31일 안으로');
    expect(view.sent.filter((r) => r.url.includes('/orders/lookups'))).toHaveLength(0);

    await user.type(screen.getByLabelText('주문 ID'), 'ORD-MOCK-1002');
    await user.click(screen.getByRole('button', { name: '찾기' }));
    expect(await screen.findAllByTestId('order-row')).toHaveLength(1);

    await user.type(screen.getByLabelText('수령인 연락처'), '1234');
    await user.click(screen.getByRole('button', { name: '찾기' }));
    expect(await screen.findByTestId('order-search-blocked')).toHaveTextContent('숫자 9~11자리');
    view.stop();
  });

  it('연락처는 하이픈을 빼고 숫자만 완전 일치로 보낸다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/orders', as.cs);
    await screen.findAllByTestId('order-row');
    await user.type(screen.getByLabelText('수령인 연락처'), '010-5555-6666');
    await user.click(screen.getByRole('button', { name: '찾기' }));
    await waitFor(() => expect(screen.getAllByTestId('order-row')).toHaveLength(1));
    const last = view.sent.filter((r) => r.url.includes('/orders/lookups')).at(-1);
    expect(new URL(last?.url ?? '').searchParams.get('receiverPhone')).toBe('01055556666');
    view.stop();
  });

  it('상세: 배송지·연락처·출입 메모는 기본으로 가리고 "보기"로 연다. 이 주문의 클레임이 보인다. 취소 버튼 없음', async () => {
    const user = userEvent.setup();
    renderAt('/orders/ORD-MOCK-1002', as.cs);
    const phone = await screen.findByTestId('order-receiver-phone');
    expect(phone).not.toHaveTextContent('01055556666');
    await user.click(within(phone).getByRole('button', { name: '보기' }));
    expect(phone).toHaveTextContent('01055556666');
    expect(await screen.findByRole('link', { name: 'CLM-MOCK-1' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /취소/ })).not.toBeInTheDocument();
  });

  it('권한 밖(MD)은 403 — 빈 목록이 아니라 오류로 보인다', async () => {
    renderAt('/orders', as.md);
    expect(await screen.findByRole('heading', { name: '이용할 수 없는 화면이에요' })).toBeInTheDocument();
    expect(screen.queryByText('조건에 맞는 주문이 없어요.')).not.toBeInTheDocument();
  });
});

describe('라이더 컴플레인', () => {
  it('기록: Idempotency-Key·X-Source-System, 라이더는 서버가 채운다 → 목록에 보인다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/rider-complaints/new?deliveryId=DLV-MOCK-1&orderId=ORD-MOCK-1001', as.cs);
    expect(screen.getByLabelText('배송 번호')).toHaveValue('DLV-MOCK-1');
    await user.click(screen.getByLabelText('파손'));
    await user.type(screen.getByLabelText('내부 메모'), '상자가 찌그러짐');
    await user.click(screen.getByRole('button', { name: '기록하기' }));
    await user.click(await screen.findByRole('link', { name: '기록한 컴플레인 보기' }));
    expect(await screen.findByTestId('complaint-detail')).toHaveTextContent('RID-MOCK-1');
    expect(screen.getByTestId('complaint-note')).toHaveTextContent('상자가 찌그러짐');

    const [post] = view.mutations('/rider-complaints');
    expect(post?.headers.get('Idempotency-Key')).toBeTruthy();
    expect(post?.headers.get('X-Source-System')).toBe('backoffice-web');
    expect(await post?.json()).toEqual({ deliveryId: 'DLV-MOCK-1', complaintType: 'DAMAGE', orderId: 'ORD-MOCK-1001', note: '상자가 찌그러짐' });
    view.stop();
  });

  it('배정 라이더가 없으면 422 RIDER_NOT_ASSIGNED 를 그대로 안내한다', async () => {
    const user = userEvent.setup();
    renderAt('/rider-complaints/new?deliveryId=DLV-MOCK-4', as.cs);
    await user.click(screen.getByLabelText('신고'));
    await user.click(screen.getByRole('button', { name: '기록하기' }));
    expect(await screen.findByText('그 배송에 배정된 라이더가 없어요.')).toBeInTheDocument();
  });

  it('응답을 잃으면 결과 불명 — 같은 키로 확인해 한 건만 기록된다', async () => {
    const user = userEvent.setup();
    let calls = 0;
    server.use(
      http.post(`${API_BASE}/rider-complaints`, () => {
        calls++;
        return calls === 1 ? new HttpResponse('<html>', { status: 502, headers: { 'content-type': 'text/html' } }) : undefined;
      }),
    );
    const view = renderAt('/rider-complaints/new?deliveryId=DLV-MOCK-1', as.cs);
    await user.click(screen.getByLabelText('오배송'));
    await user.click(screen.getByRole('button', { name: '기록하기' }));
    expect(await screen.findByText('처리 결과를 확인하고 있어요')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '같은 요청으로 결과 확인' }));
    expect(await screen.findByRole('link', { name: '기록한 컴플레인 보기' })).toBeInTheDocument();
    const posts = view.mutations('/rider-complaints');
    expect(posts).toHaveLength(2);
    expect(posts[0]?.headers.get('Idempotency-Key')).toBe(posts[1]?.headers.get('Idempotency-Key'));
    view.stop();
  });

  it('라이더 운영은 목록을 보고, 기록은 서버가 403', async () => {
    const user = userEvent.setup();
    renderAt('/rider-complaints', as.riderOps);
    expect(await screen.findAllByTestId('complaint-row')).toHaveLength(2);
    await user.click(screen.getByRole('link', { name: '컴플레인 기록' }));
    await user.type(screen.getByLabelText('배송 번호'), 'DLV-MOCK-1');
    await user.click(screen.getByLabelText('신고'));
    await user.click(screen.getByRole('button', { name: '기록하기' }));
    expect(await screen.findByRole('alert')).toHaveAttribute('data-code', 'FORBIDDEN');
  });

  it('문의 상세에서 컴플레인 기록으로 가면 문의 ID·주문 ID 가 채워진다', async () => {
    const user = userEvent.setup();
    renderAt('/inquiries/INQ-MOCK-3', as.cs);
    await user.click(await screen.findByRole('link', { name: '이 문의로 라이더 컴플레인 기록' }));
    expect(await screen.findByLabelText('문의 ID')).toHaveValue('INQ-MOCK-3');
    expect(screen.getByLabelText('주문 ID')).toHaveValue('ORD-MOCK-1001');
  });
});

describe('클레임 조회', () => {
  it('목록 → 상세·환불. 결정 버튼 없음, PG 성공 전 환불은 완료로 보이지 않는다', async () => {
    const user = userEvent.setup();
    renderAt('/claims', as.cs);
    expect(await screen.findAllByTestId('claim-row')).toHaveLength(2);
    await user.click(screen.getByRole('link', { name: 'CLM-MOCK-2' }));
    expect(await screen.findByTestId('claim-state')).toHaveTextContent('출고 중지 대기');
    expect(await screen.findByTestId('refund-row')).toHaveTextContent('실행 대기');
    expect(screen.queryByText('환불 완료')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /승인|거절|결정/ })).not.toBeInTheDocument();
  });
});

describe('배송 확인', () => {
  it('전달 실패 확정: X-Expected-Version = 수행 version, 반영되면 상태가 바뀐다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/deliveries/DLV-MOCK-2', as.cs);
    expect(await screen.findByTestId('execution-state')).toHaveTextContent('전달 실패 등록');
    expect(screen.getByTestId('delivery-failure')).toHaveTextContent('세 번 전화했지만');
    await user.click(screen.getByLabelText('실패 확정'));
    await user.click(screen.getByRole('button', { name: '결정 보내기' }));
    expect(await screen.findByTestId('decision-result')).toHaveTextContent('반영됐어요.');
    await waitFor(() => expect(screen.getByTestId('execution-state')).toHaveTextContent('전달 실패 확정'));
    const [post] = view.mutations('/failure-decisions');
    expect(post?.headers.get('X-Expected-Version')).toBe('4');
    expect(await post?.json()).toEqual({ decision: 'CONFIRM' });
    view.stop();
  });

  it('상담원은 배차 조회가 아직 403(PC 5 반영 전) — 수행 상태는 보이고 배차는 오류로 따로 보인다', async () => {
    renderAt('/deliveries/DLV-MOCK-1', as.cs);
    expect(await screen.findByTestId('execution-state')).toHaveTextContent('픽업');
    expect(await within(screen.getByTestId('dispatch-panel')).findByRole('heading', { name: '이용할 수 없는 화면이에요' })).toBeInTheDocument();
  });

  it('픽업 전 배차 취소: 202 접수 → 짝 조회로 결과 확인, 같은 키. 운영자 판단 사유는 승인 번호가 필요', async () => {
    const user = userEvent.setup();
    const view = renderAt('/deliveries/DLV-MOCK-3', as.admin);
    expect(await screen.findByTestId('dispatch-state')).toHaveTextContent('배정');
    await user.selectOptions(screen.getByLabelText('사유', { selector: 'select' }), 'OPERATOR');
    expect(screen.getByRole('button', { name: '배차 취소 보내기' })).toBeDisabled();
    await user.selectOptions(screen.getByLabelText('사유', { selector: 'select' }), 'RIDER_UNABLE');
    await user.click(screen.getByRole('button', { name: '배차 취소 보내기' }));
    expect(await screen.findByTestId('cancel-result')).toHaveTextContent('배차를 취소했어요.');
    await waitFor(() => expect(screen.getByTestId('dispatch-state')).toHaveTextContent('배차 중'));

    const [post] = view.mutations('/assignment-cancellations');
    const key = post?.headers.get('Idempotency-Key');
    expect(post?.headers.get('X-Expected-Version')).toBe('2');
    expect(await post?.json()).toEqual({ requestedBy: 'OPERATOR', reason: 'RIDER_UNABLE', reassign: true });
    const pairs = view.sent.filter((r) => r.method === 'GET' && r.url.includes(`/assignment-cancellations/${key ?? ''}`));
    expect(pairs.length).toBeGreaterThanOrEqual(2);
    view.stop();
  });

  it('픽업 뒤면 422 PICKED_UP_CASE_REQUIRED — 지원센터 안내', async () => {
    const user = userEvent.setup();
    server.use(http.post(`${API_BASE}/deliveries/:id/assignment-cancellations`, () => HttpResponse.json({ code: 'PICKED_UP_CASE_REQUIRED', status: 422, title: 'x' }, { status: 422, headers: { 'content-type': 'application/problem+json' } })));
    renderAt('/deliveries/DLV-MOCK-3', as.admin);
    await screen.findByTestId('dispatch-state');
    await user.selectOptions(screen.getByLabelText('사유', { selector: 'select' }), 'NO_SHOW');
    await user.click(screen.getByRole('button', { name: '배차 취소 보내기' }));
    expect(await screen.findByText(/지원센터로 처리해 주세요/)).toBeInTheDocument();
  });
});

describe('라이더 운영', () => {
  it('계정 제한 걸기: X-Expected-Version = 라이더 version, 이력과 현재 제한이 바뀐다', async () => {
    const user = userEvent.setup();
    const view = renderAt('/riders/RID-MOCK-2', as.admin);
    expect(await screen.findByTestId('rider-current-restriction')).toHaveTextContent('정상');
    expect(screen.getAllByTestId('restriction-row')).toHaveLength(2);
    await user.selectOptions(screen.getByLabelText('바꿀 제한'), 'DISPATCH_RESTRICTED');
    await user.type(screen.getByLabelText('사유', { selector: 'textarea' }), '오배송 3건 확인');
    await user.type(screen.getByLabelText('증빙'), 'RCP-MOCK-1, RCP-MOCK-2');
    await user.click(screen.getByRole('button', { name: '제한 보내기' }));
    expect(await screen.findByTestId('restriction-result')).toHaveTextContent('배차 제한');
    await waitFor(() => expect(screen.getByTestId('rider-current-restriction')).toHaveTextContent('배차 제한'));
    expect(screen.getAllByTestId('restriction-row')).toHaveLength(3);
    const [post] = view.mutations('/restrictions');
    expect(post?.headers.get('X-Expected-Version')).toBe('3');
    expect(await post?.json()).toEqual({ restriction: 'DISPATCH_RESTRICTED', reason: '오배송 3건 확인', evidenceRefs: ['RCP-MOCK-1', 'RCP-MOCK-2'] });
    view.stop();
  });

  it('라이더 운영 역할은 계정 제한이 아직 403(PC 5 반영 전) — 오류로 보인다', async () => {
    renderAt('/riders/RID-MOCK-2', as.riderOps);
    expect((await screen.findAllByRole('heading', { name: '이용할 수 없는 화면이에요' })).length).toBeGreaterThanOrEqual(1);
  });

  it('제한 검토: 제한 없이 "제한함"은 거절, 기각은 그 자리에서 닫힌다', async () => {
    const user = userEvent.setup();
    renderAt('/riders/restriction-reviews', as.admin);
    const row = await screen.findByTestId('review-row');
    await user.click(within(row).getByRole('button', { name: '제한함으로 닫기' }));
    expect(await within(row).findByRole('alert')).toHaveAttribute('data-code', 'INVALID_STATE');
    cleanup();

    renderAt('/riders/restriction-reviews', as.admin);
    const again = await screen.findByTestId('review-row');
    await user.type(within(again).getByLabelText('메모'), '같은 주소 착오');
    await user.click(within(again).getByRole('button', { name: '기각' }));
    await waitFor(() => expect(screen.getByTestId('review-row')).toHaveTextContent('기각'));
  });

  it('라이더 찾기(BR-54)·대기 목록(BR-55)은 계약 전 — 목 모드는 목 데이터 표시', async () => {
    const user = userEvent.setup();
    renderAt('/riders', as.riderOps);
    expect(screen.getByTestId('not-in-contract-mock')).toHaveTextContent('BR-54');
    await user.type(screen.getByLabelText('전화번호(완전 일치)'), '010-1111-2222');
    await user.click(screen.getByRole('button', { name: '찾기' }));
    const rows = await screen.findAllByTestId('rider-row');
    expect(rows).toHaveLength(1);
    expect(rows[0]).toHaveTextContent('010-****-2222');
    cleanup();

    renderAt('/delivery-help-requests', as.riderOps);
    const help = await screen.findAllByTestId('help-row');
    expect(help.map((r) => r.textContent)).toEqual([expect.stringContaining('DLV-MOCK-2'), expect.stringContaining('DLV-MOCK-1')]);
  });

  it('실서버 모드에서는 계약 전 화면이 서버를 부르지 않고 안내만 보인다', async () => {
    env.isMock = false;
    try {
      renderAt('/delivery-help-requests', as.riderOps);
      expect(await screen.findByText('서버 API 준비 전이에요')).toBeInTheDocument();
      expect(screen.queryByTestId('help-row')).not.toBeInTheDocument();
      cleanup();
      renderAt('/riders', as.riderOps);
      expect(screen.getByText(/BR-54/)).toBeInTheDocument();
      expect(screen.queryByLabelText('전화번호(완전 일치)')).not.toBeInTheDocument();
    } finally {
      env.isMock = true;
    }
  });
});
