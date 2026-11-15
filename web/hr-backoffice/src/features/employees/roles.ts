// 직원 역할 목록 — `GET /employee-auth/roles`(employee-auth 0.5.0, BR-57). 직원 토큰이면 누구나 부른다. items 는 order 오름차순.
// 화면의 고정 목록(GRANT_ROLES)을 대신한다. 못 불러오면 빈 목록이 아니라 오류로 보인다(요청 권한을 고를 수 없다).
// centerScoped = 권한 센터를 함께 골라야 의미가 있는 역할 — 안내만 한다(판정은 서버).
import { useQuery } from '@tanstack/react-query';

import { request, type EmployeeRole } from '@pmart/web-core';
import { useApi } from '../../app/ApiContext';

export function useEmployeeRoles() {
  const api = useApi();
  return useQuery({
    queryKey: ['employee-auth', 'roles'],
    queryFn: async (): Promise<readonly EmployeeRole[]> => {
      const r = await request('GET', api.employeeAuth.GET('/employee-auth/roles', {}));
      return [...r.items].sort((a, b) => a.order - b.order);
    },
    staleTime: 10 * 60_000,
  });
}

/** 화면 표시: "이름 (코드)". 이름이 코드와 같으면(설정에 이름 없음) 코드만 */
export const roleLabel = (r: EmployeeRole) => (r.name && r.name !== r.code ? `${r.name} (${r.code})` : r.code);
