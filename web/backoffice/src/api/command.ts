// 변경 명령 헬퍼(공통: @pmart/web-core) + 백오피스의 X-Source-System.
import { commandParamsFor } from '@pmart/web-core';

export { command, IdempotencyKey, isFinal, resolveResult, type CommandResponse, type CommandStatus, type Resolution } from '@pmart/web-core';

/** `_common.yaml` SourceSystem. 값 확정은 BR-08. */
export const SOURCE_SYSTEM = 'backoffice-web';

/** openapi-fetch 호출용: `client.POST(path, { ...commandParams(key, { path: { id }, version }), body })` */
export const commandParams = commandParamsFor(SOURCE_SYSTEM);
