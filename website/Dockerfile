# Static site — no build step, just Nginx serving the files directly.
# Explicit COPYs (rather than `COPY . .`) so Dockerfile/nginx.conf/content/
# never end up served from the html root.
FROM nginx:alpine
WORKDIR /usr/share/nginx/html
COPY *.html robots.txt sitemap.xml ./
COPY css ./css
COPY js ./js
COPY assets ./assets
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
