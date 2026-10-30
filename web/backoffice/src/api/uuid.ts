// UUID v4. crypto.randomUUID 는 보안 컨텍스트(HTTPS·localhost)에서만 있어 LAN(http://d603-16)에서는 없다.
// getRandomValues 는 보안 컨텍스트가 아니어도 있으므로 없을 때 그것으로 만든다.
export function randomUuid(): string {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6]! & 0x0f) | 0x40; // 버전 4
  b[8] = (b[8]! & 0x3f) | 0x80; // RFC 4122 변형
  const h = Array.from(b, (x) => x.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
