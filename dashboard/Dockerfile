FROM python:3.11-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements (not code)
COPY ./backend/requirements.txt /app/backend-requirements.txt
COPY ./dashboard/requirements.txt /app/dashboard-requirements.txt

# Install Python dependencies
RUN pip install --no-cache-dir -r /app/backend-requirements.txt && \
    pip install --no-cache-dir -r /app/dashboard-requirements.txt

# Code will be mounted via volumes in docker-compose
# COPY is not needed - volumes override

EXPOSE 8501

# Health check
HEALTHCHECK CMD curl --fail http://localhost:8501/_stcore/health || exit 1

# Run Streamlit
CMD ["streamlit", "run", "/app/dashboard/app.py", "--server.port=8501", "--server.address=0.0.0.0"]
