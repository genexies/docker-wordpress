FROM wordpress:4.3-apache
MAINTAINER Javier Jerónimo <jcjeronimo@genexies.net>
#
# @param[in] ENVIRONMENT        Configuration environment to use: wp-config.${ENVIRONMENT}.php will be used.
# @param[in] REPOSITORIES       Git repositories to clone (each: https including credentials in URL)
# @param[in] DEBUG              If present, all debug options are enabled in Wordpress
#

RUN apt-get update && apt-get install -y git



COPY gnx-entrypoint.sh /gnx-entrypoint.sh
RUN chmod u+x /gnx-entrypoint.sh



# Our entry-point that fallsback to parent's
ENTRYPOINT ["/gnx-entrypoint.sh"]

# Same default parameter to parent's entry-point
CMD ["apache2-foreground"]
