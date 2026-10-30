// CommandResponse 를 확정 결과(APPLIED/REJECTED)로 만든다. ACCEPTED·UNKNOWN_RESULT·타임아웃은 짝 조회로 해소한다.
// 짝 조회 키는 requestId(= Idempotency-Key, _common.yaml IdempotencyKey 설명).
import { isFinal, type CommandStatus, type IdempotencyKey } from './command';
import { CommandRejectedFailure, UnknownResultFailure } from './failure';
import { pollUntil } from './poll';

interface StatusLike {
  readonly status?: CommandStatus;
  readonly requestId?: string;
  readonly nextAction?: string;
}

export async function settleCommand<S extends StatusLike, Q extends StatusLike>(
  key: IdempotencyKey,
  send: () => Promise<S>,
  pair: (requestId: string) => Promise<Q>,
): Promise<S | Q> {
  let first: S | undefined;
  try {
    first = await send();
  } catch (e) {
    if (!(e instanceof UnknownResultFailure)) throw e;
  }
  if (first?.status === 'APPLIED') return first;
  if (first?.status === 'REJECTED') throw new CommandRejectedFailure(first.nextAction, first.requestId);

  const requestId = first?.requestId || key.value;
  const outcome = await pollUntil(
    () => pair(requestId),
    (r) => r.status !== undefined && isFinal(r.status),
  );
  if (outcome.kind === 'timeout') throw new UnknownResultFailure(outcome.lastFailure, requestId);
  if (outcome.value.status === 'REJECTED') throw new CommandRejectedFailure(outcome.value.nextAction, requestId);
  return outcome.value;
}
