import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

// mode: `mock`(MSW, 기본 개발) / `local`(게이트웨이 프록시, 로컬 백엔드 필요).
export default defineConfig(({ mode }) => ({
  plugins: [react(), tailwindcss()],
  define: {
    // mock·test 모드만 MSW. 그 외(local, production 빌드)는 실제 API 경로를 쓴다(배포 환경은 [결정 필요]).
    'import.meta.env.VITE_PMART_ENV': JSON.stringify(mode === 'mock' || mode === 'test' ? 'mock' : 'local'),
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
