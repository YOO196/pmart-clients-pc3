// 명령 결과·거절 사유 표시(공통: @pmart/web-ui) + 백오피스의 사유 code → 문구.
import { messages as m } from './messages';

export { CommandFeedback, FailureAlert, failureCode } from '@pmart/web-ui';

export const reasonText = (code: string | null | undefined) => (code ? (m.reason[code] ?? code) : m.none);
