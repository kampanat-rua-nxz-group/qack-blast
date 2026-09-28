FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl unzip libfontconfig1 nginx \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fL "https://downloads.godotengine.org/?version=4.7.2&flavor=stable&platform=linux.64&slug=linux.x86_64.zip" -o /tmp/godot.zip \
    && unzip /tmp/godot.zip -d /tmp \
    && mv /tmp/Godot_v4.7.2-stable_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY project.godot ./
COPY scenes ./scenes
COPY scripts ./scripts
COPY deploy/nginx.conf.template /etc/nginx/conf.d/qack.conf.template
COPY deploy/start-server.sh /usr/local/bin/start-server
RUN chmod +x /usr/local/bin/start-server \
    && rm /etc/nginx/sites-enabled/default

EXPOSE 10000
CMD ["/usr/local/bin/start-server"]
