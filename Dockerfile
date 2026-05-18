# =============================================================================
# Session Essence — Docker image
# =============================================================================
# v2.0.1 hardening (see CHANGELOG.md):
# - F-ARCH-002: prompts.js is generated from prompts.template.js at build
#   time so clean clones / CI can build without manual preconditions.
#   Operators who want personalized prompts mount their own prompts.js at
#   /app/prompts.js (read-only) at `docker run` time.
# - F-ARCH-007: removed redundant ENV SYNTHESIS_BACKEND=claude (the index.js
#   default kicks in when unset; the image is now backend-neutral).
# - F-OPUS-003: shell-form CMD with `exec` so ${PORT} is expanded at runtime
#   and overriding `-e PORT=...` actually works.
# - F-SEC-004 partial: dropped `--cors`, restored `--logLevel info`. Bearer-
#   token auth + localhost-default binding are tracked for v2.1 (operator's
#   current deployment is LAN-trusted).
# =============================================================================

FROM node:22-slim

WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --production
COPY index.js prompts.template.js ./

# F-ARCH-002: build-time fallback prompts.js. Operators with personalized
# prompts mount their own prompts.js read-only at runtime to override.
RUN cp prompts.template.js prompts.js

ENV OLLAMA_HOST=http://host.docker.internal:11434
ENV OLLAMA_MODEL=qwq:32b
ENV CLAUDE_MODEL=claude-haiku-4-5-20251001
ENV PORT=3250

EXPOSE ${PORT}

# F-OPUS-003: shell-form CMD so ${PORT} expands at runtime. Prior version
# used JSON-form with hardcoded "3250", which silently ignored -e PORT.
# F-SEC-004: --cors removed (no documented browser caller); --logLevel
# moved to info so invocation source IP + payload size land in container
# logs. --healthEndpoint kept (information disclosure is mitigated by the
# bearer-token auth landing in v2.1).
CMD exec npx supergateway \
     --stdio "node /app/index.js" \
     --outputTransport streamableHttp \
     --port "${PORT}" \
     --logLevel info \
     --healthEndpoint /health
