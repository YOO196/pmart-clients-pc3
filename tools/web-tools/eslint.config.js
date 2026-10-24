// web/backoffice 린트. TS 7 에는 typescript-eslint 가 쓰는 컴파일러 JS API 가 없어서
// 이 패키지(TS 5.9)의 eslint 로 실행한다(web/backoffice 에서 `npm run lint`). typescript-eslint 가 TS 7 을 지원하면 web/backoffice 로 옮긴다.
import js from '@eslint/js';
import reactHooks from 'eslint-plugin-react-hooks';
import globals from 'globals';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import tseslint from 'typescript-eslint';

const backoffice = resolve(dirname(fileURLToPath(import.meta.url)), '../../web/backoffice');

export default tseslint.config(
  { ignores: ['**/generated/**', '**/dist/**', '**/public/**'] },
  {
   
    files: ['**/*.{ts,tsx}'],
    extends: [js.configs.recommended, ...tseslint.configs.recommendedTypeChecked],
    languageOptions: {
      globals: globals.browser,
      parserOptions: {
        project: [resolve(backoffice, 'tsconfig.app.json')],
        tsconfigRootDir: backoffice,
      },
    },
    plugins: { 'react-hooks': reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      // 오류 분기는 Problem code 로만 한다: 문자열 비교 대신 instanceof·code 를 쓰는지 리뷰로 본다.
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
      'no-restricted-globals': ['error', { name: 'localStorage', message: '토큰·개인정보를 localStorage 에 두지 않는다(BR-03).' }],
    },
  },
  {
   
    files: ['**/*.test.{ts,tsx}', '**/test/**'],
    rules: {
      '@typescript-eslint/no-non-null-assertion': 'off',
      '@typescript-eslint/require-await': 'off',
    },
  },
);
