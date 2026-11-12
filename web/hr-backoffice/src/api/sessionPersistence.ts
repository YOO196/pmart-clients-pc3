// 새로고침 뒤 세션 복원용 보관(공통: @pmart/web-core sessionPersistence) — 인사팀 백오피스의 sessionStorage 키.
import { createSessionPersistence } from '@pmart/web-core';

export const SESSION_STORAGE_KEY = 'pmart.hr-backoffice.session';

export const { loadSavedSession, syncSavedSession, clearSavedSession } = createSessionPersistence(SESSION_STORAGE_KEY);
