FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
RUN microdnf install -y python3 tar && microdnf clean all
WORKDIR /app
COPY app/ /app/
CMD ["python3", "-m", "http.server", "8080", "--bind", "0.0.0.0"]
