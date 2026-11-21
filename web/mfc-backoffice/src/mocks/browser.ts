import { setupWorker } from 'msw/browser';

import { seedDemoFloor } from './db';
import { handlers } from './handlers';

// 브라우저 목에서만 시연용 칸을 더한다(대시보드 구역 칸 지도) — 시험 데이터는 그대로
seedDemoFloor();

export const worker = setupWorker(...handlers);
