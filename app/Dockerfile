# Unprivileged nginx: runs as a non-root user on port 8080
FROM nginxinc/nginx-unprivileged:stable-alpine

# Patch all OS packages to their latest fixed versions (needs root),
# and remove curl: the app doesn't use it, so it's just extra attack surface
USER root
RUN apk upgrade --no-cache && apk del --no-cache curl

COPY index.html /usr/share/nginx/html/index.html

# Drop back to the non-root user before the container runs
USER 101
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O /dev/null http://localhost:8080/ || exit 1