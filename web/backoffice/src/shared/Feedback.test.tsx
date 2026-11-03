import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';

import { UnknownResultFailure } from '../api/failure';
import { CommandFeedback } from './Feedback';
import type { Command } from './useCommand';

const unknown: Command<null, unknown> = {
  phase: { kind: 'unknown', failure: new UnknownResultFailure(undefined, '16ab6434-a250-46cb-9eb5-6e17bb47f909') },
  run: () => Promise.reject(new Error('unused')),
  resend: () => Promise.reject(new Error('unused')),
  reset: () => {},
  busy: false,
};

describe('명령 결과 불명 표시', () => {
  it('기본은 안내·문의 번호·"같은 요청으로 결과 확인"을 한 상자에 작게 보인다', () => {
    render(<CommandFeedback command={unknown} />);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveAttribute('data-state', 'unknown');
    expect(alert).toHaveTextContent('처리 결과를 확인하고 있어요');
    expect(alert).toHaveTextContent('같은 요청을 다시 하지 마세요');
    expect(alert).toHaveTextContent('문의 번호 16ab6434-a250-46cb-9eb5-6e17bb47f909');
    expect(screen.getByRole('button', { name: '같은 요청으로 결과 확인' })).toBeInTheDocument();
  });

  it('상태를 남기지 않는 명령(로그인)은 본문을 바꾸고 결과 확인 버튼을 뺀다', () => {
    render(<CommandFeedback command={unknown} unknown={{ body: '로그인 결과를 받지 못했어요. 잠시 뒤 다시 로그인해 주세요.', resend: false }} />);
    const alert = screen.getByRole('alert');
    expect(alert).toHaveTextContent('다시 로그인해 주세요');
    expect(alert).not.toHaveTextContent('같은 요청을 다시 하지 마세요');
    expect(screen.queryByRole('button', { name: '같은 요청으로 결과 확인' })).not.toBeInTheDocument();
  });
});
