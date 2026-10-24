import { http, HttpResponse } from 'msw';

import { API_BASE } from '../api/client';
import { approvalInbox } from './fixtures';

export const handlers = [
  http.get(`${API_BASE}/views/approval-inbox`, () => HttpResponse.json(approvalInbox)),
];
