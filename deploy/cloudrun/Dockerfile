# Runtime wrapper around the upstream `api-build` image.
#
# Build the base image first:
#   docker build -f Dockerfile.multi --target api-build -t librechat-api-base:cloudrun .
# Then build this wrapper:
#   docker build -f deploy/cloudrun/Dockerfile \
#     --build-arg BASE_IMAGE=librechat-api-base:cloudrun \
#     -t <artifact-registry>/librechat/api:latest .
ARG BASE_IMAGE=librechat-api-base:cloudrun
FROM ${BASE_IMAGE}

COPY deploy/cloudrun/entrypoint.sh /usr/local/bin/librechat-cloudrun-entrypoint
COPY deploy/cloudrun/reset-meili.js /app/reset-meili.js
RUN chmod 755 /usr/local/bin/librechat-cloudrun-entrypoint \
    && mkdir -p /app/logs /app/uploads /app/client/public/images

ENV NODE_ENV=production
EXPOSE 8080

CMD ["/usr/local/bin/librechat-cloudrun-entrypoint"]
