// Content-addressed assets stay cached between showroom visits and car changes.
export async function readAsset(url, onProgress = () => {}) {
  let cache;
  try { cache = await caches.open('tesla-assets-v1'); } catch { /* HTTP/disabled storage */ }
  let response = cache && await cache.match(url);
  if (!response) {
    response = await fetch(url);
    if (!response.ok) throw new Error(`Asset request failed (${response.status}). Please retry.`);
    if (cache) cache.put(url, response.clone()).catch(() => {});
  }
  const total = Number(response.headers.get('Content-Length'));
  const reader = response.body.getReader();
  const chunks = [];
  let loaded = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    chunks.push(value); loaded += value.byteLength;
    onProgress(loaded, total);
  }
  const blob = new Blob(chunks);
  // Gzip containers use .bin names so static servers do not auto-decompress them.
  const signature = new Uint8Array(await blob.slice(0, 2).arrayBuffer());
  if (signature[0] === 0x1f && signature[1] === 0x8b) {
    return new Response(blob.stream().pipeThrough(new DecompressionStream('gzip'))).arrayBuffer();
  }
  return blob.arrayBuffer();
}
