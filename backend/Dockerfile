FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# Nothing here needs root, and nothing is written to disk: receipt images are
# processed in memory and never stored.
RUN useradd --system --no-create-home app
USER app

EXPOSE 8000
CMD uvicorn app:app --host 0.0.0.0 --port ${PORT:-8000}
