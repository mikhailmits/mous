FROM python:3.12-slim-trixie AS builder

COPY --from=ghcr.io/astral-sh/uv:0.12.3 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never

WORKDIR /app

COPY pyproject.toml uv.lock ./
RUN printf 'Personal spending API.\n' > README.md
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-install-project --no-dev

COPY src ./src
COPY oxyde_config.py ./
COPY migrations ./migrations
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM python:3.12-slim-trixie

RUN useradd --uid 1000 --home /app --shell /usr/sbin/nologin mous \
    && mkdir -p /data \
    && chown mous:mous /data

WORKDIR /app
COPY --from=builder --chown=mous:mous /app /app

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    MOUS_DATABASE_URL=sqlite:////data/data.db

USER mous
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=8s --retries=5 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/openapi.json')"
CMD ["mous", "serve", "--host", "0.0.0.0", "--port", "8000"]
