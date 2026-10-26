FROM ollama/ollama:0.40.11@sha256:dea72d1e22270fe095b68fdf756d2b489d615643c5a2eaebbc5f569181e322d8
# Build prepara o ponto de montagem; runtime nao precisa de root/chown/capabilities.
RUN mkdir -p /home/ollama/.ollama && chown -R 1000:1000 /home/ollama
ENV HOME=/home/ollama
USER 1000:1000
WORKDIR /home/ollama
