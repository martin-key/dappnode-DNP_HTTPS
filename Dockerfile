FROM ruby:2.7.2-alpine AS ruby-builder

RUN apk add --update build-base 

COPY ./Gemfile .
RUN bundle install



FROM node:12-alpine AS node-builder

WORKDIR /src/api/

# Install all deps to build
COPY api/package.json api/yarn.lock ./
RUN yarn install

COPY ./api ./
RUN yarn run build

# Re-install only production for final layer
RUN rm -rf node_modules && yarn install --production



FROM nginx:1.19.6-alpine
ARG  ARCH=amd64

# Delete sym links from nginx image, install logrotate
RUN rm /var/log/nginx/access.log && \
    rm /var/log/nginx/error.log

WORKDIR /root

ENV S6_OVERLAY_VERSION=v2.2.0.1  \
    ACME_TINY_VERSION=4.1.0  \
# API volume to store domain .txt and .json files
    DOMAINS_DIR=/var/run/domains.d/  \
#
    DAPPMANAGER_SIGN=http://172.33.1.7/sign  \
    DAPPMANAGER_DOMAIN=http://172.33.1.7/global-envs/DOMAIN


ADD https://github.com/just-containers/s6-overlay/releases/download/$S6_OVERLAY_VERSION/s6-overlay-$ARCH.tar.gz /tmp/
ADD https://raw.githubusercontent.com/diafygi/acme-tiny/$ACME_TINY_VERSION/acme_tiny.py /bin/acme_tiny

RUN tar xzf /tmp/s6-overlay-$ARCH.tar.gz -C / && \
    rm /tmp/s6-overlay-$ARCH.tar.gz && \
    rm /etc/nginx/conf.d/default.conf && \
    apk add --update \
    # From original image
    python2 ruby=2.7.2-r0 iproute2 apache2-utils logrotate openssl \
    # For Typescript app
    nodejs \
    && \
    mkdir -p /src/api

ENV GEM_PATH="${GEM_PATH}${GEM_PATH:+:}/usr/local/bundle/"

COPY --from=ruby-builder /usr/local/bundle/ /usr/local/bundle/
COPY ./fs_overlay /
COPY --from=node-builder /src/api/node_modules /src/api/node_modules
COPY --from=node-builder /src/api/dist /src/api/
RUN chmod a+x /bin/*

VOLUME /var/lib/https-portal
VOLUME /var/log/nginx

ENTRYPOINT ["/init"]
