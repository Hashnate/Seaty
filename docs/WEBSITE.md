# Marketing website

`website/` is the public marketing site at `seaty.hashnate.com` — plain HTML/CSS/JS, no build
step, no framework. It's separate from `admin/` (the auth-gated operator dashboard) and carries
no dependency on the backend or database; it never calls the API.

## Structure

```
website/
├── index.html               # Home
├── features.html            # Feature deep-dive
├── for-operators.html       # B2B pitch for bus operators
├── download.html            # App Store / Play Store links
├── support.html             # FAQ + contact
├── privacy-policy.html      # Legal
├── terms-and-conditions.html
├── 404.html
├── robots.txt / sitemap.xml
├── css/                     # variables.css (design tokens), base.css, components.css, animations.css
├── js/                      # main.js (nav/accordion/scroll-reveal), animations.js (stagger setup)
├── assets/images/           # logo + illustrations, reused from mobile/assets/images
├── content/                 # *.md authoring sources for the copy — hand-transcribed into the
│                             # .html pages above; edit both when copy changes, since there's no
│                             # templating engine rendering these at build or runtime
├── Dockerfile                # nginx:alpine, single stage — just copies static files in
└── nginx.conf                 # in-container Nginx config (clean URLs, gzip, cache headers)
```

## Editing content

There's no templating engine — `website/content/*.md` are the reviewable copy sources, and the
`.html` files contain the final markup by hand. When you change site copy, legal text, or contact
details, update both the relevant `content/*.md` file and the corresponding `.html` page(s).

Design tokens (colors, fonts, spacing, gradients) live in `css/variables.css` — change a color or
gradient there rather than hard-coding hex values in a page. The brand anchors (navy, blue, ice
blue, coral) match `mobile/lib/theme/app_colors.dart`; everything else (the indigo/cyan depth
ramp, the amber accent, the full slate scale) is specific to this site — the app's own palette is
intentionally flatter and doesn't need to match 1:1.

**Known placeholders to replace before/at launch** (all marked `<!-- TODO -->` in the HTML):
- App Store / Play Store links on `download.html` and the download bands on `index.html`.
- Social links in the footer (Facebook/Instagram/LinkedIn/X) on every page.
- The "Effective date" badge on `privacy-policy.html` and `terms-and-conditions.html`.
- Business registration number — omitted from the legal pages entirely until one exists; add it
  to `website/content/privacy-policy.md`, `terms-and-conditions.md`, and the matching `.html`
  pages once issued.

## Container

Unlike `admin/`, there's no Node build stage — `website/Dockerfile` is a single-stage
`nginx:alpine` image that copies the static files straight in.

**It follows the same "single ingress" rule as the rest of the stack**: per
[ARCHITECTURE.md](ARCHITECTURE.md), only the `admin` container publishes a host port
(`8025:80`) — `backend` and `db` are reachable only on the Compose network, and `admin`'s Nginx
is the one thing a client ever talks to directly. `website` follows `backend`'s lead: it
publishes **no host port**, and `admin/nginx.conf` gets a third `server_name` block
(`seaty.hashnate.com www.seaty.hashnate.com`) that reverse-proxies to `http://website:80` on the
Compose network — the same way its `api.seaty.hashnate.com` block proxies to `backend:8000`.
So the site is served on the same published port as everything else, differentiated purely by
the `Host` header, exactly like `admin.seaty.hashnate.com` vs `api.seaty.hashnate.com` today.

```bash
docker compose build website admin
docker compose up -d website admin
```

`website/nginx.conf` (inside the `website` container itself) serves clean URLs
(`/privacy-policy` resolves the same as `/privacy-policy.html`), gzips text assets, and routes
unknown paths to `404.html`.

## Pointing `seaty.hashnate.com` at it

Because routing happens inside the `admin` container by `Host` header, the host-level Nginx +
certbot vhost for `seaty.hashnate.com` points at the **same port** (`127.0.0.1:8025`) as the
existing `admin.seaty.hashnate.com` / `api.seaty.hashnate.com` vhosts already documented in
[DEPLOYMENT.md](DEPLOYMENT.md) — it's a third vhost forwarding to a port that's already open, not
a new port to expose.

```nginx
# /etc/nginx/sites-available/seaty.hashnate.com
server {
    listen 80;
    server_name seaty.hashnate.com www.seaty.hashnate.com;

    location / {
        proxy_pass http://127.0.0.1:8025;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/seaty.hashnate.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d seaty.hashnate.com -d www.seaty.hashnate.com
```

This is a host-level change outside this repo (and outside what an in-container agent can run) —
apply it on the actual server, the same way the existing two subdomains were set up.

## Verification

No test suite (per [CLAUDE.md](../CLAUDE.md)). `website` has no host-published port by design, so
verify through the `admin` container's port exactly as a real request would arrive — by `Host`
header:

```bash
docker compose up -d --build website admin
curl -I -H "Host: seaty.hashnate.com" http://localhost:8025/            # 200
curl -I -H "Host: seaty.hashnate.com" http://localhost:8025/privacy-policy   # 200, clean URL
curl -I -H "Host: seaty.hashnate.com" http://localhost:8025/does-not-exist  # 404, serves 404.html
```

Then, once the host-level vhost above is live, open `https://seaty.hashnate.com` in a browser at
both desktop and mobile widths and click through every nav link, footer link, and CTA.
