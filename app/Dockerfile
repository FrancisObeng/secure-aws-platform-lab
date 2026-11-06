# Unprivileged nginx: runs as a non-root user on port 8080
FROM nginxinc/nginx-unprivileged:stable-alpine

COPY index.html /usr/share/nginx/html/index.html

USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://localhost:8080/ || exit 1