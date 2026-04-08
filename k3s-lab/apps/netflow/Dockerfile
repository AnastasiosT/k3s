FROM python:3.12-slim

WORKDIR /app

# Copy script
COPY netflow-gen.py .

# Make executable
RUN chmod +x netflow-gen.py

# Run script
CMD ["python3", "netflow-gen.py"]
