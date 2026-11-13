// 직원 로그인 employee-auth-service(공통: @pmart/web-core employeeAuth) — 백오피스의 앱 이름·보관 키.
// ADR-0056, 백엔드 handoff 2026-11-12 clients-request-backoffice-employee-auth-login.
// 로그인은 모든 모드에서 이것 하나다(auth-service 운영자 로그인은 2026-11-13 백엔드에서 없어졌다 — clients-notice-auth-operator-login-removed).
import { createEmployeeAuth } from '@pmart/web-core';

import { SOURCE_SYSTEM } from './command';

export {
  base64Url,
  browser,
  CALLBACK_PATH,
  codeChallenge,
  EmployeeLoginError,
  type EmployeeLoginDeps,
  type EmployeeLoginErrorCode,
  type EmployeeLogoutOutcome,
  type EmployeeSession,
} from '@pmart/web-core';

/** employee-auth 설정의 앱 이름(pmart.employee-auth.apps.backoffice) */
export const EMPLOYEE_APP = 'backoffice';
export const LOGIN_PENDING_KEY = 'pmart.backoffice.login.pending';

export const { beginEmployeeLogin, completeEmployeeLogin, refreshEmployeeTokens, logoutEmployee } = createEmployeeAuth({
  app: EMPLOYEE_APP,
  sourceSystem: SOURCE_SYSTEM,
  pendingKey: LOGIN_PENDING_KEY,
});
