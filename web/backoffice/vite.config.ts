import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// mode: `mock`(MSW, 기본 개발) / `local`(게이트웨이 프록시, 로컬 백엔드 필요) / `lan`(.env.lan 의 게이트웨이 주소로 직접, CORS).
export default defineConfig(({ mode }) => ({
  plugins: [react(), tailwindcss()],
  define: {
    // mock·test 모드만 MSW. 그 외(local, production 빌드)는 실제 API 경로를 쓴다(배포 환경은 [결정 필요]).
    'import.meta.env.VITE_PMART_ENV': JSON.stringify(mode === 'mock' || mode === 'test' ? 'mock' : 'local'),
    // lan: 게이트웨이가 다른 출처(PC4). 브라우저는 http://D603-16 으로 열어야 CORS 허용 출처와 맞는다(IP 로 열면 막힘).
    // 비밀값이 아니라 주소라 여기 둔다. 바뀌면 백엔드 deploy/lan/cors-origins.conf 와 함께 고친다.
    ...(mode === 'lan' ? { 'import.meta.env.VITE_PMART_API_BASE': JSON.stringify('http://D603-16:8080/api/v1') } : {}),
  },
  server: {
    port: 5173,
    // local 모드에서만 게이트웨이로 넘긴다. 쿠키·CORS 방식은 BR-03·BR-04 결정 대기.
    proxy: mode === 'local' ? { '/api': 'http://localhost:8080' } : undefined,
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
}));
