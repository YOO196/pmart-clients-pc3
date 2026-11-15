// 변경 명령 헬퍼(공통: @pmart/web-core) + MFC 백오피스의 X-Source-System.
import { commandParamsFor } from '@pmart/web-core';

export { IdempotencyKey } from '@pmart/web-core';

/** 백엔드 handoff 2026-11-13 mfc-backoffice/2026-11-15-request-mfc-backoffice §1 */
export const SOURCE_SYSTEM = 'mfc-backoffice-web';

/** openapi-fetch 호출용: `client.POST(path, { ...commandParams(key, { path: { operatorId }, version }), body })` */
export const commandParams = commandParamsFor(SOURCE_SYSTEM);
