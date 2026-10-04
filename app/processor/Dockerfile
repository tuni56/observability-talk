FROM python:3.12-slim

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.12.7 /uv /usr/local/bin/uv

WORKDIR /app

# Install dependencies from lockfile (deterministic, fast)
COPY processor/requirements.lock .
RUN uv pip install --system --no-cache -r requirements.lock

# Copy shared logger
COPY shared/ ./shared/

# Copy processor code
COPY processor/ .

# Non-root user — security best practice
RUN useradd -m -u 1001 processor
USER processor

CMD ["python", "main.py"]
