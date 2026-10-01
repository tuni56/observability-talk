FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy shared logger
COPY ../shared /app/shared

# Copy processor code
COPY . .

# Non-root user — security best practice
RUN useradd -m -u 1001 processor
USER processor

CMD ["python", "main.py"]
