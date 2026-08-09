FROM nginx:1.29-alpine

COPY index.html /usr/share/nginx/html/index.html
COPY frontend.html /usr/share/nginx/html/frontend.html
COPY backend.html /usr/share/nginx/html/backend.html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O - http://127.0.0.1/ || exit 1
