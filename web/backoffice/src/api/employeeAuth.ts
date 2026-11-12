// 직원 로그인 employee-auth-service(공통: @pmart/web-core employeeAuth) — 백오피스의 앱 이름·보관 키·로그인 방식.
// ADR-0056, 백엔드 handoff 2026-11-12 clients-request-backoffice-employee-auth-login.
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

export type LoginMode = 'auth-service' | 'employee-auth';

/** 빌드 때 고른 로그인 방식(vite.config.ts). lan = employee-auth, mock·local = auth-service(아이디·비밀번호). */
export const LOGIN_MODE: LoginMode = import.meta.env.VITE_PMART_LOGIN === 'employee-auth' ? 'employee-auth' : 'auth-service';

/** employee-auth 설정의 앱 이름(pmart.employee-auth.apps.backoffice) */
export const EMPLOYEE_APP = 'backoffice';
export const LOGIN_PENDING_KEY = 'pmart.backoffice.login.pending';

export const { beginEmployeeLogin, completeEmployeeLogin, refreshEmployeeTokens, logoutEmployee } = createEmployeeAuth({
  app: EMPLOYEE_APP,
  sourceSystem: SOURCE_SYSTEM,
  pendingKey: LOGIN_PENDING_KEY,
});
