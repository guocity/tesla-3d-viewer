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
  const first = await reader.read();
  if (first.done) return new ArrayBuffer(0);
  let loaded = first.value.byteLength;
  onProgress(loaded, total);
  const gzipped = first.value.byteLength >= 2 && first.value[0] === 0x1f && first.value[1] === 0x8b;
  const stream = new ReadableStream({
    start(controller) { controller.enqueue(first.value); },
    async pull(controller) {
      const { done, value } = await reader.read();
      if (done) { controller.close(); return; }
      loaded += value.byteLength;
      onProgress(loaded, total);
      controller.enqueue(value);
    },
    cancel(reason) { return reader.cancel(reason); },
  });
  return new Response(gzipped ? stream.pipeThrough(new DecompressionStream('gzip')) : stream).arrayBuffer();
}
