// 내 인사 정보(GET /hr/employees/me — 모든 직원). 인사 기록이 없는 계정은 404 → 오류가 아니라 "기록 없음"(null).
import { useQuery } from '@tanstack/react-query';

import { ProblemCode, ProblemFailure, request } from '@pmart/web-core';
import { useApi } from '../../app/ApiContext';
import { useSession } from '../../app/SessionContext';

export function useMe() {
  const api = useApi();
  const { session } = useSession();
  return useQuery({
    queryKey: ['hr', 'me', session?.subject],
    enabled: session !== null,
    staleTime: 5 * 60_000,
    queryFn: async () => {
      try {
        return await request('GET', api.hr.GET('/hr/employees/me', {}));
      } catch (e) {
        if (e instanceof ProblemFailure && e.problem.code === ProblemCode.notFound) return null;
        throw e;
      }
    },
  });
}
