FROM alpine:latest

ADD https://github.com/just-containers/s6-overlay/releases/\
download/v1.21.8.0/s6-overlay-amd64.tar.gz \
/tmp/
RUN tar xzf /tmp/s6-overlay-amd64.tar.gz -C /

ARG VCS_USER=git

ENV SCHEME http
ENV DOMAIN phabricator.localhost
ENV CDN_DOMAIN usercontent.localhost
ENV PORT 80
ENV SSH_PORT 22
ENV LOCK_AUTH 0
ENV TZ Etc/UTC

RUN apk add --no-cache \
    git \
    mariadb \
    mariadb-client \
    mercurial \
    ncurses \
    nginx \
    nodejs \
    npm \
    openssh-server \
    postfix \
    php7 \
    php7-apcu \
    php7-bcmath \
    php7-bz2 \
    php7-ctype \
    php7-curl \
    php7-dom \
    php7-fileinfo \
    php7-fpm \
    php7-gd \
    php7-gettext \
    php7-iconv \
    php7-json \
    php7-ldap \
    php7-mbstring \
    php7-mcrypt \
    php7-memcached \
    php7-mysqli \
    php7-odbc \
    php7-opcache \
    php7-pcntl \
    php7-pdo \
    php7-pdo_mysql \
    php7-posix \
    php7-session \
    php7-zip \
    procps \
    py3-pygments \
    py3-setuptools \
    sudo \
    && rm -f /tmp/s6-overlay-*.tar.gz \
    && for repo in libphutil arcanist phabricator ; \
    do git clone --depth=1 https://github.com/phacility/$repo.git /$repo ; \
    done \
    && ( cd /phabricator/support/aphlict/server && npm install ws )

COPY etc /etc
COPY bin/phabricator-ssh-hook.sh /usr/local/bin/
COPY config.json /phabricator/conf/local/local.json

RUN ln -s /usr/bin/pygmentize-3 /usr/bin/pygmentize \
    && addgroup phd \
    && adduser -G phd -h /var/lib/phabricator -H -D phd \
    && addgroup $VCS_USER \
    && adduser -G $VCS_USER -D $VCS_USER \
    && passwd -u $VCS_USER \
    && sed -i "s/VCS_USER/$VCS_USER/g" /etc/sudoers.d/diffusion \
    && sed -i "s/VCS_USER/$VCS_USER/g" /etc/ssh/sshd_config \
    && sed -i "s/VCS_USER/$VCS_USER/g" /usr/local/bin/phabricator-ssh-hook.sh \
    && sed -i "s/VCS_USER/$VCS_USER/g" /phabricator/conf/local/local.json \
    && sed -i "s/post_max_size =.*/post_max_size = 0/" /etc/php7/php.ini \
    && sed -i \
    "s/;opcache.validate_timestamps=.*/opcache.validate_timestamps=0/" \
    /etc/php7/php.ini \
    && sed -i "s@;error_log =.*@error_log = /run/logpipe@" \
    /etc/php7/php-fpm.conf \
    && sed -i "s@listen =.*@listen = /run/php/php-fpm.sock@" \
    /etc/php7/php-fpm.d/www.conf \
    && sed -i "s/;listen.owner =.*/listen.owner = nginx/" \
    /etc/php7/php-fpm.d/www.conf \
    && sed -i "s/;listen.group =.*/listen.group = nginx/" \
    /etc/php7/php-fpm.d/www.conf \
    && s6-setuidgid phd s6-mkdir -p /var/tmp/phd/log \
    && ln -s /run/logpipe /var/tmp/phd/log/daemons.log

EXPOSE 80
EXPOSE 22

ENTRYPOINT ["/init"]
