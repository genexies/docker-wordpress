#!/bin/bash

set -e

log() {
	echo -e >&2 "[${1}]\t$(date +%Y-%m-%d:%H:%M:%S.%N)\t${2}"
}

sudorun() {
	sudo bash -c "$1"
}

# ################################################################################
# ################################################################################
# ################################################################################
# CUSTOM PRE-entry-point...
# ################################################################################
# ################################################################################
# ################################################################################
while [ "$ADDITIONAL_TARGZ_URLS" ]; do
	i=${ADDITIONAL_TARGZ_URLS%%;*}
	repo_id=$(echo "${i}" | sed -e 's/[^A-Za-z0-9._-]/_/g')
	log DEBUG "Dowloading tar.gz ${i} in /tmp/${repo_id} ..."
	mkdir -p /tmp/${repo_id}
	chown www-data /tmp/${repo_id}
	sudorun "curl -L ${i} -o /tmp/${repo_id}/output.tar.gz"
	log INFO "Done downloading URL ${i}"

	log DEBUG "Uncompressing ${i} in /var/www/html ..."
	sudorun "cd /var/www/html && tar xvzf /tmp/${repo_id}/output.tar.gz"
	log INFO "Done uncompressing ${i}"
	[ "$ADDITIONAL_TARGZ_URLS" = "$i" ] && \
		ADDITIONAL_TARGZ_URLS='' || \
		ADDITIONAL_TARGZ_URLS="${ADDITIONAL_TARGZ_URLS#*;}"
done


# noop

# ################################################################################
# ################################################################################
# ################################################################################
# Original entry-point, but removed .htaccess and wp-config.php stuff...
# ################################################################################
# ################################################################################
# ################################################################################
if [ -n "$MYSQL_PORT_3306_TCP" ]; then
	if [ -z "$WORDPRESS_DB_HOST" ]; then
		WORDPRESS_DB_HOST='mysql'
	else
		log WARN 'both WORDPRESS_DB_HOST and MYSQL_PORT_3306_TCP found'
		log WARN "  Connecting to WORDPRESS_DB_HOST ($WORDPRESS_DB_HOST)"
		log WARN '  instead of the linked mysql container'
	fi
fi

if [ -z "$WORDPRESS_DB_HOST" ]; then
	log ERROR 'missing WORDPRESS_DB_HOST and MYSQL_PORT_3306_TCP environment variables'
	log ERROR '  Did you forget to --link some_mysql_container:mysql or set an external db'
	log ERROR '  with -e WORDPRESS_DB_HOST=hostname:port?'
	exit 1
fi

# if we're linked to MySQL, and we're using the root user, and our linked
# container has a default "root" password set up and passed through... :)
: ${WORDPRESS_DB_USER:=root}
if [ "$WORDPRESS_DB_USER" = 'root' ]; then
	: ${WORDPRESS_DB_PASSWORD:=$MYSQL_ENV_MYSQL_ROOT_PASSWORD}
fi
: ${WORDPRESS_DB_NAME:=wordpress}

if [ -z "$WORDPRESS_DB_PASSWORD" ]; then
	log ERROR 'missing required WORDPRESS_DB_PASSWORD environment variable'
	log ERROR '  Did you forget to -e WORDPRESS_DB_PASSWORD=... ?'
	log ERROR
	log ERROR '  (Also of interest might be WORDPRESS_DB_USER and WORDPRESS_DB_NAME.)'
	exit 1
fi

chown www-data:www-data /usr/src/wordpress

log DEBUG "Copying now Wordpress in $(pwd) ..."
sudorun "tar cf - --one-file-system -C /usr/src/wordpress . | tar xf -"
log INFO "Complete! WordPress has been successfully copied to $(pwd)"

# see http://stackoverflow.com/a/2705678/433558
sed_escape_lhs() {
	echo "$@" | sed 's/[]\/$*.^|[]/\\&/g'
}
sed_escape_rhs() {
	echo "$@" | sed 's/[\/&]/\\&/g'
}
php_escape() {
	php -r 'var_export((string) $argv[1]);' "$1"
}
set_config() {
	key="$1"
	value="$2"
	regex="(['\"])$(sed_escape_lhs "$key")\2\s*,"
	if [ "${key:0:1}" = '$' ]; then
		regex="^(\s*)$(sed_escape_lhs "$key")\s*="
	fi
	sed -ri "s/($regex\s*)(['\"]).*\3/\1$(sed_escape_rhs "$(php_escape "$value")")/" /var/www/html/wp-config.php
}

# ################################################################################
# ################################################################################
# ################################################################################
# Custom POST...
# ################################################################################
# ################################################################################
# ################################################################################

while [ "$REPOSITORIES" ]; do
	i=${REPOSITORIES%%;*}
	repo_id=$(echo "${i}" | sed -e 's/[^A-Za-z0-9._-]/_/g')
	log DEBUG "Cloning repo ${i} in /tmp/${repo_id} ..."
	mkdir -p /tmp/${repo_id}
	chown www-data /tmp/${repo_id}
	sudorun "git clone ${i} /tmp/${repo_id}"
	log INFO "Done cloning repo ${i}"

	log DEBUG "Installing repo ${i} in /var/www/html ..."
	sudorun "cd /tmp/${repo_id} && git --work-tree=/var/www/html checkout -f"
	log INFO "Done installing repo ${i}"
	[ "$REPOSITORIES" = "$i" ] && \
		REPOSITORIES='' || \
		REPOSITORIES="${REPOSITORIES#*;}"
done


if [[ -f /var/www/html/wp-config.${ENVIRONMENT}.php ]]; then
	log INFO "Configuring Wordpress using environment ${ENVIRONMENT} ..."
	sudorun "cp /var/www/html/wp-config.${ENVIRONMENT}.php /var/www/html/wp-config.php"
	chmod 444 wp-config.php
fi
if [[ -f /var/www/html/htaccess.${ENVIRONMENT}.txt ]]; then
	log INFO "Configuring .htaccess using environment ${ENVIRONMENT} ..."
	sudorun "cp /var/www/html/htaccess.${ENVIRONMENT}.txt /var/www/html/.htaccess"
	chmod 444 .htaccess
fi
if [[ -f /var/www/html/robots.${ENVIRONMENT}.txt ]]; then
	log INFO "Configuring SEO - robots.txt using environment ${ENVIRONMENT} ..."
	sudorun "cp /var/www/html/robots.${ENVIRONMENT}.txt /var/www/html/robots.txt"
	chmod 444 robots.txt
fi


# Now, inject DB config from container execution env...
set_config 'DB_HOST' "$WORDPRESS_DB_HOST"
set_config 'DB_USER' "$WORDPRESS_DB_USER"
set_config 'DB_PASSWORD' "$WORDPRESS_DB_PASSWORD"
set_config 'DB_NAME' "$WORDPRESS_DB_NAME"

# Run original parameter (CMD in image / command in container)
cd /var/www/html
exec "$@"
