// 목 모드 운영자 계정. 역할 이름은 백엔드 handoff 2026-10-30 §2(설정값이라 바뀔 수 있음).
// 비밀번호는 목 전용 값이다(실서버 비밀번호가 아님). 로컬 백엔드 첫 관리자도 admin / pmart-local (ADR-0018 §5).
import { mockOperatorToken } from '@pmart/web-core';

export const MOCK_PASSWORD = 'pmart-local';

export const mockAccounts = [
  { operatorId: 'op-admin-1', loginId: 'admin', displayName: '관리자', password: MOCK_PASSWORD, roles: ['OPERATOR_ADMIN'], centers: [] },
  { operatorId: 'op-md-1', loginId: 'md', displayName: 'MD 김', password: MOCK_PASSWORD, roles: ['MD'], centers: [] },
  {
    operatorId: 'op-approver-1',
    loginId: 'approver',
    displayName: '승인자 이',
    password: MOCK_PASSWORD,
    roles: ['PRODUCT_APPROVER', 'DISPLAY_APPROVER', 'PRICE_APPROVER'],
    centers: [],
  },
  { operatorId: 'op-center-1', loginId: 'center', displayName: '센터 박', password: MOCK_PASSWORD, roles: [], centers: ['MFC-BSN-01', 'CDC01'] },
] as const;

/** 테스트용: 로그인 없이 바로 세션을 여는 목 access token */
export const mockOperators = mockAccounts;

export const mockTokenFor = (o: (typeof mockAccounts)[number], sid = `sess-${o.operatorId}`) =>
  mockOperatorToken({ sub: o.operatorId, roles: o.roles, centers: o.centers, sid });
