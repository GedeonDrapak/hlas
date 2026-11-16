// hlas.dev: static site from the web/ folder. Besides serving files it
// sends www.hlas.dev to the canonical apex and serves the installers in
// /download/ as attachments. The installers are copied into web/download/ at
// deploy time and are not in git.
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.hostname.startsWith('www.')) {
      url.hostname = url.hostname.slice(4);
      return Response.redirect(url.toString(), 301);
    }
    const res = await env.ASSETS.fetch(request);
    if (url.pathname.startsWith('/download/') && res.ok) {
      const name = url.pathname.split('/').pop();
      const headers = new Headers(res.headers);
      headers.set('Content-Disposition', `attachment; filename="${name}"`);
      headers.set('Cache-Control', 'public, max-age=300');
      if (name.endsWith('.dmg')) headers.set('Content-Type', 'application/x-apple-diskimage');
      if (name.endsWith('.exe')) headers.set('Content-Type', 'application/vnd.microsoft.portable-executable');
      return new Response(res.body, { status: res.status, headers });
    }
    return res;
  },
};
