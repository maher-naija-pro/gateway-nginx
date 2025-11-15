FROM python:3.11-slim

WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the exporter script
COPY user_stats_exporter.py .

# Create directory for log position file
RUN mkdir -p /tmp

# Run the exporter
CMD ["python3", "user_stats_exporter.py"]

