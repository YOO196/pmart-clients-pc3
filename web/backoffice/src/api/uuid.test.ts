import { randomUuid } from './uuid';

describe('randomUuid', () => {
  const v4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

  it('보안 컨텍스트가 아니라 crypto.randomUUID 가 없어도 v4 UUID 를 만든다(LAN http)', () => {
    const original = Object.getOwnPropertyDescriptor(crypto, 'randomUUID');
    Object.defineProperty(crypto, 'randomUUID', { value: undefined, configurable: true });
    try {
      const a = randomUuid();
      expect(a).toMatch(v4);
      expect(randomUuid()).not.toBe(a);
    } finally {
      if (original) Object.defineProperty(crypto, 'randomUUID', original);
      else delete (crypto as { randomUUID?: unknown }).randomUUID;
    }
  });

  it('randomUUID 가 있으면 그것을 쓴다', () => {
    expect(randomUuid()).toMatch(v4);
  });
});
