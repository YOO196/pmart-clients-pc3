// 직원 로그인 employee-auth-service(공통: @pmart/web-core employeeAuth) — MFC 백오피스의 앱 이름·보관 키.
// 백엔드 handoff 2026-11-15 mfc-backoffice/2026-11-15-request-mfc-backoffice §1: app=mfc-backoffice, SSO(두 백오피스와 Keycloak 세션을 같이 쓴다).
import { createEmployeeAuth } from '@pmart/web-core';

import { SOURCE_SYSTEM } from './command';

export { browser, CALLBACK_PATH, EmployeeLoginError, type EmployeeLoginErrorCode, type EmployeeSession } from '@pmart/web-core';

/** employee-auth 설정의 앱 이름(pmart.employee-auth.apps.mfc-backoffice) */
export const EMPLOYEE_APP = 'mfc-backoffice';
export const LOGIN_PENDING_KEY = 'pmart.mfc-backoffice.login.pending';
/** 이 탭에서 조용한 로그인 확인(silent)을 이미 했다는 표시 */
export const LOGIN_SILENT_KEY = 'pmart.mfc-backoffice.login.silent';

export const { beginEmployeeLogin, canTrySilentLogin, beginSilentEmployeeLogin, completeEmployeeLogin, refreshEmployeeTokens, logoutEmployee } = createEmployeeAuth({
  app: EMPLOYEE_APP,
  sourceSystem: SOURCE_SYSTEM,
  pendingKey: LOGIN_PENDING_KEY,
  silentKey: LOGIN_SILENT_KEY,
});
