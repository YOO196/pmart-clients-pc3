import { act, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';

import { tokens } from '../../api/client';
import { App } from '../../app/App';
import { as } from '../../test/render';
import { createDraftAssistantMock, type DraftMockOptions, type DraftScenario } from './draftMock';
import { isDisplayableDocRef } from './model';
import { notConnectedAssistant, type AssistantPort } from './port';
import { answerFromWire } from './wire';

/** 목 + 보낸 키 기록 */
function setup(opts: DraftMockOptions & { scenario?: DraftScenario } = {}) {
  const mock = createDraftAssistantMock({ ...opts, ...(opts.scenario ? { script: () => opts.scenario as DraftScenario } : {}) });
  const keys: string[] = [];
  const port: AssistantPort = {
    ...mock,
    ask: (q, k) => {
      keys.push(k.value);
      return mock.ask(q, k);
    },
  };
  return { mock, port, keys };
}

async function ask(question: string) {
  const user = userEvent.setup();
  await user.type(await screen.findByRole('textbox', { name: '질문' }), question);
  await user.click(screen.getByRole('button', { name: '질문 보내기' }));
  return user;
}

describe('업무 도우미 (계약 확정 전 목, BR-46)', () => {
  it('정상 답변: 답변·근거 문서·절·버전·기준 시점·확정/제안/미결정을 보이고, 목 표시를 붙인다', async () => {
    const { port } = setup();
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    await ask('반품 기한은?');

    expect(await screen.findByTestId('answer-text')).toHaveTextContent('[목 답변]');
    expect(screen.getByText('목 데이터 · 계약 확정 전 화면(BR-46)')).toBeInTheDocument();
    const cites = screen.getAllByTestId('citation');
    expect(cites).toHaveLength(3);
    expect(within(cites[0]!).getByText('확정 정책')).toBeInTheDocument();
    expect(within(cites[0]!).getByText('MOCK-POLICY-COMMERCE')).toBeInTheDocument();
    expect(within(cites[0]!).getByText('§4.9')).toBeInTheDocument();
    expect(within(cites[0]!).getAllByText('v3')).toHaveLength(2); // 문서 버전 v3 · 정책 버전 v3
    expect(within(cites[1]!).getByText('설계 제안')).toBeInTheDocument();
    expect(within(cites[2]!).getByText('미결정')).toBeInTheDocument();
    // 출처는 링크가 아니다(문서 여는 방법은 계약 미정)
    expect(within(cites[0]!).queryByRole('link')).not.toBeInTheDocument();
    // 답변 기록에 남고, 답변 번호로 다시 연다
    expect(screen.getByRole('link', { name: 'ans-mock-1' })).toHaveAttribute('href', '/assistant/answers/ans-mock-1');
  });

  it('모델 응답의 HTML 은 실행·해석하지 않고 글자로 보인다', async () => {
    const { port } = setup();
    const { container } = render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    await ask('표시 확인');
    const text = await screen.findByTestId('answer-text');
    expect(text.textContent).toContain('<b>강조</b>');
    expect(container.querySelector('[data-testid="answer-text"] b')).toBeNull();
  });

  it('근거 부족(NO_GROUNDING)은 오류가 아니라 "근거 문서를 찾지 못했어요"', async () => {
    const { port } = setup({ scenario: 'noGrounding' });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    await ask('없는 정책');
    expect(await screen.findByText('근거 문서를 찾지 못했어요')).toBeInTheDocument();
    expect(screen.queryByTestId('answer-text')).not.toBeInTheDocument();
  });

  it('권한 범위 밖(200 FORBIDDEN_SCOPE)과 권한 거절(403 Problem)을 구분해 보인다', async () => {
    const scope = setup({ scenario: 'forbiddenScope' });
    const first = render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={scope.port} />);
    await ask('남의 센터 정책');
    expect(await screen.findByText('내 권한 범위 밖의 질문이에요')).toBeInTheDocument();
    first.unmount();

    const denied = setup({ scenario: 'forbidden' });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={denied.port} />);
    await ask('질문');
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveAttribute('data-state', 'rejected');
    expect(alert).toHaveAttribute('data-code', 'FORBIDDEN');
    expect(screen.queryByText('근거 문서를 찾지 못했어요')).not.toBeInTheDocument();
  });

  it('서비스 장애: health DOWN 이면 장애 안내 + 새 질문을 막고, "관련 문서 없음"으로 보이지 않는다', async () => {
    const { port } = setup({ health: () => 'DOWN' });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    expect(await screen.findByText('업무 도우미 서비스에 장애가 있어요')).toBeInTheDocument();
    await userEvent.setup().type(screen.getByRole('textbox', { name: '질문' }), '질문');
    expect(screen.getByRole('button', { name: '질문 보내기' })).toBeDisabled();
    expect(screen.queryByText('근거 문서를 찾지 못했어요')).not.toBeInTheDocument();
  });

  it('질의 중 503(결과 불명): 실패·완료로 단정하지 않고 "결과 확인" — 같은 키로만 다시 보낸다', async () => {
    const { port, keys } = setup({ scenario: 'unavailable' });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    const user = await ask('질문');
    expect(await screen.findByText('처리 결과를 확인하고 있어요')).toBeInTheDocument();
    expect(screen.queryByText('근거 문서를 찾지 못했어요')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '질문 보내기' })).toBeDisabled(); // 새 키로 보내지 않는다
    await user.click(screen.getByRole('button', { name: '같은 요청으로 결과 확인' }));
    expect(keys).toHaveLength(2);
    expect(keys[1]).toBe(keys[0]);
  });

  it('응답 유실 뒤 복구: 같은 Idempotency-Key 재전송으로 서버가 이미 만든 답변을 받는다(새로 만들지 않음)', async () => {
    const { port, keys, mock } = setup({ scenario: 'lostOnce' });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    const user = await ask('유실 시험');
    expect(await screen.findByText('처리 결과를 확인하고 있어요')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '같은 요청으로 결과 확인' }));

    expect(await screen.findByTestId('answer-text')).toBeInTheDocument();
    expect(keys).toEqual([keys[0], keys[0]]);
    expect(mock.received).toHaveLength(1); // 서버 처리는 한 번
    expect(screen.getAllByRole('link', { name: 'ans-mock-1' }).length).toBeGreaterThan(0);
  });

  it('중복 전송: 진행 중 다시 눌러도 한 번만 보낸다', async () => {
    const { port, mock } = setup({ delayMs: 30 });
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    const user = userEvent.setup();
    await user.type(await screen.findByRole('textbox', { name: '질문' }), '한 번만');
    const button = screen.getByRole('button', { name: '질문 보내기' });
    await user.click(button);
    await user.click(button);
    await user.keyboard('{Enter}');
    expect(await screen.findByTestId('answer-text')).toBeInTheDocument();
    expect(mock.received).toHaveLength(1);
  });

  it('계정 전환: 이전 사용자의 질문·답변·답변 기록을 화면에서 지운다', async () => {
    const { port } = setup();
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    const user = await ask('A 의 질문');
    expect(await screen.findByTestId('answer-text')).toBeInTheDocument();
    expect(screen.getAllByText(/A 의 질문/).length).toBeGreaterThan(0);

    act(() => {
      tokens.accessToken = as.approver;
    });
    expect(await screen.findByText('아직 받은 답변이 없어요.')).toBeInTheDocument();
    expect(screen.queryByText(/A 의 질문/)).not.toBeInTheDocument();
    expect(screen.queryByTestId('answer-text')).not.toBeInTheDocument();
    expect(screen.getByRole('textbox', { name: '질문' })).toHaveValue('');
    void user;
  });

  it('기존 답변 조회: 남의 답변·없는 번호는 오류로 보이고 "근거 문서를 찾지 못했어요"로 바꾸지 않는다', async () => {
    const { port } = setup();
    render(<App memory initialPath="/assistant/answers/ans-mock-999" initialToken={as.md} assistantPort={port} />);
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveAttribute('data-state', 'error');
    expect(screen.queryByText('근거 문서를 찾지 못했어요')).not.toBeInTheDocument();
  });

  it('기존 답변 조회: 내 답변은 답변 번호로 다시 연다', async () => {
    const { port } = setup();
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    const user = await ask('다시 볼 질문');
    await screen.findByTestId('answer-text');
    await user.click(screen.getAllByRole('link', { name: 'ans-mock-1' })[0]!);
    expect(await screen.findByRole('heading', { name: '업무 도우미 답변' })).toBeInTheDocument();
    expect(await screen.findByTestId('answer-text')).toHaveTextContent('[목 답변]');
  });

  it('실서버 모드(계약 확정 전): 호출하지 않고 "아직 연결되지 않았어요"만 보인다', async () => {
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={notConnectedAssistant} />);
    expect(await screen.findByText('업무 도우미는 아직 서버에 연결되지 않았어요')).toBeInTheDocument();
    expect(screen.queryByRole('textbox', { name: '질문' })).not.toBeInTheDocument();
  });

  it('메뉴는 권한과 관계없이 보인다(권한은 서버 판정)', async () => {
    const { port } = setup();
    render(<App memory initialPath="/assistant" initialToken={as.center} assistantPort={port} />);
    expect(await screen.findByRole('link', { name: '업무 도우미' })).toBeInTheDocument();
  });
});

describe('업무 도우미 — 출처 식별자·초안 계약 대조', () => {
  it('파일시스템 절대 경로·URL·상위 경로는 표시하지 않는다', () => {
    for (const bad of ['C:\\docs\\a.md', 'C:/docs/a.md', '/srv/rag/a.md', '\\\\host\\a', '~/a.md', 'file:///a', 'https://x', 'a/../b'])
      expect(isDisplayableDocRef(bad)).toBe(false);
    for (const ok of ['MOCK-POLICY-COMMERCE', 'POLICY.COMMERCE.4-9', 'docs:business/overview#4'.replace('docs:', '')])
      expect(isDisplayableDocRef(ok)).toBe(true);
  });

  it('경로 형식 출처는 화면에서 가린다', async () => {
    const port: AssistantPort = {
      ...createDraftAssistantMock(),
      ask: () =>
        Promise.resolve(
          answerFromWire({
            answerId: 'a1',
            state: 'ANSWERED',
            answer: '답',
            citations: [{ docRef: 'C:\\pmart\\secret\\policy.md', policyVersion: 1 }],
          }),
        ),
    };
    render(<App memory initialPath="/assistant" initialToken={as.md} assistantPort={port} />);
    await ask('q');
    expect(await screen.findByText('표시할 수 없는 출처 식별자(경로 형식)')).toBeInTheDocument();
    expect(screen.queryByText(/secret/)).not.toBeInTheDocument();
  });

  it('초안 계약 응답 변환: 필수로 쓰는 answerId·state 가 없으면 빈 값으로 메우지 않고 계약 위반', () => {
    expect(() => answerFromWire({ state: 'ANSWERED', answer: 'x' })).toThrow(/CONTRACT_VIOLATION/);
    expect(() => answerFromWire({ answerId: 'a', answer: 'x' })).toThrow(/CONTRACT_VIOLATION/);
    // 초안 GET 응답(citations 없음) → citations=null(“0건”과 구분)
    expect(answerFromWire({ answerId: 'a', state: 'ANSWERED', answer: 'x' }).citations).toBeNull();
    // 초안 POST 응답(BR-46 확장 없음)도 그대로 읽힌다 — 구분 정보는 없음으로
    const plain = answerFromWire({ answerId: 'a', state: 'ANSWERED', answer: 'x', citations: [{ docRef: 'D1', policyVersion: null }] });
    expect(plain.citations).toEqual([{ docRef: 'D1', policyVersion: null }]);
  });

  it('목의 멱등 규칙(초안 계약 _common IdempotencyKey): 같은 키·다른 질문은 409 IDEMPOTENCY_CONFLICT', async () => {
    const mock = createDraftAssistantMock();
    tokens.accessToken = as.md;
    const { IdempotencyKey } = await import('../../api/command');
    const key = IdempotencyKey.generate();
    const a = await mock.ask('q1', key);
    expect((await mock.ask('q1', key)).answerId).toBe(a.answerId);
    await expect(mock.ask('q2', key)).rejects.toMatchObject({ problem: { code: 'IDEMPOTENCY_CONFLICT', status: 409 } });
    tokens.accessToken = null;
  });
});

describe('업무 도우미 — 계정 전환 뒤 이전 답변', () => {
  it('다른 계정은 이전 사용자의 답변 번호를 조회할 수 없고(NOT_FOUND), 캐시된 답변도 보이지 않는다', async () => {
    const { IdempotencyKey } = await import('../../api/command');
    const mock = createDraftAssistantMock();
    tokens.accessToken = as.md;
    const mine = await mock.ask('A 만의 질문', IdempotencyKey.generate());
    tokens.accessToken = as.approver;
    await expect(mock.get(mine.answerId)).rejects.toMatchObject({ problem: { code: 'NOT_FOUND' } });
    tokens.accessToken = null;

    // 화면: A 로 답변을 연 뒤(캐시) B 로 바뀌면 그 답변 화면은 다시 조회해 오류로 보인다
    tokens.accessToken = as.md;
    render(<App memory initialPath={`/assistant/answers/${mine.answerId}`} initialToken={as.md} assistantPort={mock} />);
    expect(await screen.findByTestId('answer-text')).toBeInTheDocument();
    act(() => {
      tokens.accessToken = as.approver;
    });
    const alert = await screen.findByRole('alert');
    expect(alert).toHaveAttribute('data-state', 'error');
    expect(screen.queryByTestId('answer-text')).not.toBeInTheDocument();
  });
});
