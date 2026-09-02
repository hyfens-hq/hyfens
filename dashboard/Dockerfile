FROM nginx:1.27-alpine@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10

WORKDIR /opt/hyfens/dashboard

COPY dashboard/index.html .
COPY dashboard/app.js .
COPY dashboard/auth-flow.css .
COPY dashboard/auth-flow.js .
COPY dashboard/brand-mark.svg .
COPY dashboard/styles.css .
COPY dashboard/tokens.css .
COPY dashboard/icons ./icons
COPY dashboard/cli ./cli
COPY dashboard/device ./device
COPY dashboard/runtime-config.js .

COPY LICENSE /opt/hyfens/LICENSE
COPY THIRD_PARTY_NOTICES.md /opt/hyfens/THIRD_PARTY_NOTICES.md

COPY dashboard/docker-entrypoint.sh /usr/local/bin/hyfens-dashboard-entrypoint
RUN chmod 755 /usr/local/bin/hyfens-dashboard-entrypoint

COPY dashboard/nginx.conf /etc/nginx/conf.d/default.conf

ENTRYPOINT ["/usr/local/bin/hyfens-dashboard-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
