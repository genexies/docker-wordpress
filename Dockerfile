FROM wordpress:4.7.2-fpm
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
# Required to install libapache2-mod-fastcgi
RUN echo "deb http://http.us.debian.org/debian jessie main non-free" >> /etc/apt/sources.list

RUN apt-get update

# Install Supervisor
RUN apt-get install -y supervisor
COPY etc/supervisor/conf.d/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Install Git
RUN apt-get install -y git

# Install wget
RUN apt-get install -y wget

# Install php-pear
RUN apt-get install -y php-pear

# Install sudo
RUN apt-get install -y sudo

# Install OPcache
RUN docker-php-ext-install opcache
COPY opcache.ini /opcache.ini
RUN cat /opcache.ini >> /usr/local/etc/php/conf.d/docker-php-ext-opcache.ini

# Download manually, and install using PHP docker scripts...
RUN cd /usr/src/php/ext && \
    wget https://pecl.php.net/get/memcache-2.2.7.tgz && \
    tar xvzf memcache-2.2.7.tgz && \
    mv memcache-2.2.7 memcache

RUN docker-php-ext-configure memcache && docker-php-ext-install memcache

# Install Apache
RUN apt-get install -y apache2
COPY etc/apache2/apache2.conf /etc/apache2/apache2.conf

# Install FastCGI process
RUN apt-get install -y php5-fpm
COPY usr/local/etc/php-fpm.conf /usr/local/etc/php-fpm.conf

# Apache's MPM module: Event
RUN apt-get -y install apache2-mpm-event
RUN a2enmod mpm_event

# Apache's module to communicate with FastCGI process: fastcgi
RUN apt-get install -y libapache2-mod-fastcgi
COPY etc/apache2/conf-available/fastcgi.conf /etc/apache2/conf-available/fastcgi.conf
RUN a2enconf fastcgi

# Enable Apache modules
RUN a2enmod rewrite actions

# Our entry-point that fallback to parent's
COPY gnx-entrypoint.sh /gnx-entrypoint.sh
RUN chmod u+x /gnx-entrypoint.sh
ENTRYPOINT ["/gnx-entrypoint.sh"]

# Same default parameter to parent's entry-point
CMD ["/usr/bin/supervisord"]
