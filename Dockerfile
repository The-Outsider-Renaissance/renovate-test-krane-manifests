# syntax = docker/dockerfile:1.6.0

FROM ruby:3.3.0-slim-bullseye AS base

ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

ARG PACKAGES=" \
  build-essential=12.9 \
  curl=7.74.0-1.3+deb11u11 \
  default-libmysqlclient-dev=1.0.7 \
  default-mysql-client=1.0.7 \
  firefox-esr=102.15.0esr-1~deb11u1 \
  gnupg2=2.2.27-2+deb11u2 \
  ldapscripts=2.0.8-2 \
  libldap2-dev=2.4.57+dfsg-3+deb11u1 \
  libsasl2-dev=2.1.27+dfsg-2.1+deb11u1 \
  lsb-release=11.1.0 \
  openssl=1.1.1w-0+deb11u1 \
  percona-toolkit=3.2.1-1 \
  tzdata=2021a-1+deb11u11 \
  xvfb=2:1.20.11-1+deb11u6 \
  zlib1g=1:1.2.11.dfsg-2+deb11u2 \
  awscli=1.19.1-1 \
"

RUN apt-get update -y \
    && apt-get install -y -o Dpkg::Options::="--force-confold" $PACKAGES \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG PERCONA_VERSION=1.0-27
RUN apt-get update -y \
    && curl -O https://repo.percona.com/apt/percona-release_$PERCONA_VERSION.generic_all.deb \
    && apt-get install -y ./percona-release_$PERCONA_VERSION.generic_all.deb \
    && dpkg -i percona-release_$PERCONA_VERSION.generic_all.deb \
    && rm -rf ./percona-release_$PERCONA_VERSION.generic_all.deb \
    && percona-release setup pt

# renovate: datasource=rubygems depName=bundler
ARG BUNDLER_VERSION=2.5.4
# renovate: datasource=github-releases depName=rubygems/rubygems
ARG RUBYGEMS_VERSION=3.5.4
RUN gem install bundler -v $BUNDLER_VERSION && \
    gem update --system $RUBYGEMS_VERSION

ARG APP_PATH=/opt/app
ARG APP_USER=app
ARG APP_GROUP=app
ARG APP_USER_UID=9999
ARG APP_GROUP_GID=9999

RUN addgroup --gid $APP_GROUP_GID $APP_GROUP && \
    adduser --uid $APP_USER_UID --ingroup $APP_GROUP --disabled-password $APP_USER && \
    mkdir $APP_PATH && \
    chown $APP_USER:$APP_GROUP $APP_PATH

# renovate: datasource=github-releases depName=nvm-sh/nvm
ENV NVM_VERSION 0.39.1
# renovate: datasource=node-version depName=node versioning=node
ENV NODE_VERSION 20.9.0
# renovate: datasource=npm depName=npm
ENV NPM_VERSION 7.24.2
# renovate: datasource=npm depName=yarn
ENV YARN_VERSION 1.22.17
ENV NVM_DIR /home/app/.nvm
ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH
RUN mkdir $NVM_DIR \
    && curl -o- https://raw.githubusercontent.com/creationix/nvm/v${NVM_VERSION}/install.sh | bash \
    && . $NVM_DIR/nvm.sh \
    && nvm install v${NODE_VERSION} \
    && nvm alias default v${NODE_VERSION} \
    && nvm use default \
    && npm install -g npm@${NPM_VERSION} \
    && npm install -g yarn@${YARN_VERSION} \
    && curl -sSL https://nodejs.org/download/release/v${NODE_VERSION}/node-v${NODE_VERSION}-headers.tar.gz -o /tmp/node-headers.tgz \
    && npm config set tarball /tmp/node-headers.tgz

WORKDIR $APP_PATH

FROM base AS prod

RUN bundle config --global frozen true

COPY --chown=$APP_USER:$APP_GROUP Gemfile* $APP_PATH/
RUN bundle install

COPY --chown=$APP_USER:$APP_GROUP package* yarn.lock $APP_PATH/
RUN yarn install

USER $APP_USER

ADD --chown=$APP_USER:$APP_GROUP . $APP_PATH/

RUN RAILS_ENV=production SECRET_KEY_BASE=does_not_matter_here bin/rails assets:precompile

ARG APP_REVISION
RUN echo $APP_REVISION > $APP_PATH/REVISION

CMD [ "bin/rails", "about" ]
