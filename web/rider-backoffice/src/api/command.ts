// 변경 명령 헬퍼(공통: @pmart/web-core) + 라이더 백오피스의 X-Source-System.
import { commandParamsFor } from '@pmart/web-core';

export { IdempotencyKey } from '@pmart/web-core';

/** 백엔드 2026-11-17(PC 1 — 라이더 백오피스 뼈대) */
export const SOURCE_SYSTEM = 'rider-backoffice-web';

/** openapi-fetch 호출용: `client.POST(path, { ...commandParams(key, { path: { operatorId }, version }), body })` */
export const commandParams = commandParamsFor(SOURCE_SYSTEM);
