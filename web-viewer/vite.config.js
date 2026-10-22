import { defineConfig } from 'vite';
import { cpSync, existsSync, readFileSync, statSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('.', import.meta.url));
const types = { '.js': 'text/javascript', '.css': 'text/css', '.html': 'text/html', '.json': 'application/json', '.riv': 'application/octet-stream', '.gz': 'application/octet-stream' };
function serve(directory, req, res, next) {
  let pathname;
  try { pathname = decodeURIComponent((req.url || '/').split('?')[0]); } catch { res.statusCode = 400; return res.end(); }
  const file = path.resolve(directory, `.${pathname}`);
  if (!file.startsWith(`${directory}${path.sep}`)) return next();
  if (!existsSync(file) || !statSync(file).isFile()) return next();
  res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream');
  res.setHeader('Content-Length', statSync(file).size);
  res.end(readFileSync(file));
}
export default defineConfig({
  base: './', publicDir: false,
  // Keep an active 3D session intact while source files change.
  server: { hmr: false, watch: null },
  optimizeDeps: { entries: ['index.html'] },
  plugins: [{
    name: 'static-viewer-assets',
    configureServer(server) {
      server.middlewares.use('/data', (req, res, next) => serve(path.join(root, 'site-assets'), req, res, next));
      server.middlewares.use((req, res, next) => {
        if (req.url === '/legacy' || req.url === '/legacy/') { res.writeHead(302, { Location: '/legacy/index.html' }); return res.end(); }
        serve(path.join(root, 'public'), req, res, next);
      });
    },
    closeBundle() {
      const dist = path.join(root, 'dist');
      mkdirSync(path.join(dist, 'reference'), { recursive: true });
      for (const name of ['hosted.js', 'hosted.css', 'drawer.riv']) cpSync(path.join(root, 'public/reference', name), path.join(dist, 'reference', name));
      cpSync(path.join(root, 'public/asset-loader.js'), path.join(dist, 'asset-loader.js'));
      if (existsSync(path.join(root, 'public/CNAME'))) cpSync(path.join(root, 'public/CNAME'), path.join(dist, 'CNAME'));
      const manifest = JSON.parse(readFileSync(path.join(root, 'site-assets/manifest.json')));
      const entries = [manifest.scene, manifest.bmw, ...manifest.vehicles.flatMap(v => [v.packed, v.rig].filter(Boolean)), ...Object.values(manifest.files)];
      mkdirSync(path.join(dist, 'data'), { recursive: true });
      for (const name of new Set(['manifest.json', 'animations/catalog.json', ...entries.map(e => e.file)])) {
        mkdirSync(path.dirname(path.join(dist, 'data', name)), { recursive: true });
        cpSync(path.join(root, 'site-assets', name), path.join(dist, 'data', name));
      }
    },
  }],
});
