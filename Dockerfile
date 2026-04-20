FROM --platform=$BUILDPLATFORM alpine:3.23 AS certs
RUN apk add --no-cache ca-certificates tzdata

FROM alpine:3.23
ARG BINARY_PATH
LABEL org.opencontainers.image.authors="Jeeva Kandasamy"
LABEL org.opencontainers.image.licenses="Apache-2.0"
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=certs /usr/share/zoneinfo /usr/share/zoneinfo
COPY ${BINARY_PATH} /usr/local/bin/promptd
COPY config.sample.yaml /promptd/config.sample.yaml
COPY config.sample.yaml /promptd/config.yaml
RUN mkdir -p /promptd/system-prompts
COPY resources/assistant.txt /promptd/system-prompts/assistant.txt
RUN chmod +x /usr/local/bin/promptd
WORKDIR /promptd
EXPOSE 8090
ENTRYPOINT ["/usr/local/bin/promptd"]
CMD ["serve", "--config", "/promptd/config.yaml"]
