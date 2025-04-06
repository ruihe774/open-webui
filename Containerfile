FROM ghcr.io/astral-sh/uv:bookworm-slim

RUN --mount=type=cache,target=/var/lib/apt --mount=type=cache,target=/var/cache/apt apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates --no-install-recommends

WORKDIR /app
RUN uv venv -p 311
ENV PATH=/app/.venv/bin:/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
RUN --mount=type=bind,source=dist,target=/dist uv pip install /dist/open_webui-0.6.14-py3-none-any.whl --extra-index-url https://download.pytorch.org/whl/cpu --index-strategy unsafe-best-match
RUN ln -s /app/.venv/lib/python3.11/site-packages/open_webui/frontend build
COPY CHANGELOG.md package.json /app
RUN mkdir -p backend/data
WORKDIR /app/backend
RUN ln -s /app/.venv/lib/python3.11/site-packages/open_webui .

ENV DOCKER=true

CMD ["/bin/bash", "-ec", "if [ \"x$LISTEN_PID\" = x$$ -a \"x$LISTEN_FDS\" = x1 ]; then exec uvicorn open_webui.main:app --fd 3 --forwarded-allow-ips '*'; else exec uvicorn open_webui.main:app --host \"${HOST:-0.0.0.0}\" --port \"${PORT:-8080}\" --forwarded-allow-ips '*'; fi"]
