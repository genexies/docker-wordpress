FROM wordpress:4.3-apache
MAINTAINER Javier Jerónimo <jcjeronimo@genexies.net>
#
# @param[in] ENVIRONMENT        Configuration environment to use:
#                               wp-config.${ENVIRONMENT}.php will be used.
#
# @param[in] REPOSITORIES       Git repositories to clone (each: https including
#                               credentials in URL)
#
# @param[in] DEBUG              If present, all debug options are enabled in
#                               Wordpress
#

RUN apt-get update && apt-get install -y \
        git \
        wget \
        php-pear \
        sudo
RUN docker-php-ext-install opcache


COPY opcache.ini /opcache.ini
RUN cat /opcache.ini >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini


# Download manually, and install using PHP docker scripts...
RUN cd /usr/src/php/ext && \
    wget https://pecl.php.net/get/memcache-2.2.7.tgz && \
    tar xvzf memcache-2.2.7.tgz && \
    mv memcache-2.2.7 memcache

RUN docker-php-ext-configure memcache && docker-php-ext-install memcache
RUN cat /opcache.ini >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini



COPY gnx-entrypoint.sh /gnx-entrypoint.sh
RUN chmod u+x /gnx-entrypoint.sh



# Our entry-point that fallsback to parent's
ENTRYPOINT ["/gnx-entrypoint.sh"]

# Same default parameter to parent's entry-point
CMD ["apache2-foreground"]
