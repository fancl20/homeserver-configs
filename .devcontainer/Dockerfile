FROM debian:testing-slim

RUN groupadd --gid 1000 coder && \
    useradd --uid 1000 --gid 1000 -m coder \

RUN apt-get update && apt-get install -y \
    curl wget git vim jq fish \
    python3 golang \
    && rm -rf /var/lib/apt/lists/*

COPY install_terraform.py /tmp/install_terraform.py
RUN python3 /tmp/install_terraform.py

# Clean up
RUN rm -rf /tmp/* /var/tmp/*

SHELL ["/usr/bin/fish"]
USER coder