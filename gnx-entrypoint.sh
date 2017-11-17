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
APPLICATION_PATH=${APPLICATION_PATH:-/var/www/html}
while [ "$REPOSITORIES" ]; do
	repo_url_and_branch=${REPOSITORIES%% *}
	repo_url=${repo_url_and_branch%%\\*}
	repo_branch=${repo_url_and_branch#*\\}
	clone_dir="/tmp/$(echo ${repo_url_and_branch} | sed -e 's/[^A-Za-z0-9._-]/_/g')"
	if [ ! -d "$clone_dir" ]; then
        log DEBUG "Cloning repo ${repo_url} with branch ${repo_branch} in ${clone_dir} ..."
        mkdir -p ${clone_dir}
        chown www-data ${clone_dir}
        sudorun "git clone -b ${repo_branch} ${repo_url} ${clone_dir}"
        log INFO "Done cloning repo ${repo_url} with branch ${repo_branch} in ${clone_dir}"

        log DEBUG "Installing repo ${repo_url} with branch ${repo_branch} in ${APPLICATION_PATH} ..."
        sudorun "cd ${clone_dir} && git --work-tree=${APPLICATION_PATH} checkout -f"
        log INFO "Done installing repo ${repo_url} with branch ${repo_branch} in ${APPLICATION_PATH}"
    else
        log DEBUG "Repo repo ${repo_url} with branch ${repo_branch} already cloned in ${clone_dir} ..."
    fi
	[ "$REPOSITORIES" = "$repo_url_and_branch" ] && \
		REPOSITORIES='' || \
		REPOSITORIES=${REPOSITORIES#* }
done

# TODO: create a function for doing this:
if [[ -f ${APPLICATION_PATH}/wp-config.${ENVIRONMENT}.php ]]; then
	log INFO "Configuring Wordpress using environment ${ENVIRONMENT} ..."
	sudorun "cp ${APPLICATION_PATH}/wp-config.${ENVIRONMENT}.php ${APPLICATION_PATH}/wp-config.php"
	chmod 444 wp-config.php
fi
if [[ -f ${APPLICATION_PATH}/htaccess.${ENVIRONMENT}.txt ]]; then
	log INFO "Configuring .htaccess using environment ${ENVIRONMENT} ..."
	sudorun "cp ${APPLICATION_PATH}/htaccess.${ENVIRONMENT}.txt ${APPLICATION_PATH}/.htaccess"
	chmod 444 .htaccess
fi
if [[ -f /var/www/html/robots.${ENVIRONMENT}.txt ]]; then
	log INFO "Configuring SEO - robots.txt using environment ${ENVIRONMENT} ..."
	sudorun "cp ${APPLICATION_PATH}/robots.${ENVIRONMENT}.txt ${APPLICATION_PATH}/robots.txt"
	chmod 444 robots.txt
fi


# Now, inject DB config from container execution env...
set_config 'DB_HOST' "$WORDPRESS_DB_HOST"
set_config 'DB_USER' "$WORDPRESS_DB_USER"
set_config 'DB_PASSWORD' "$WORDPRESS_DB_PASSWORD"
set_config 'DB_NAME' "$WORDPRESS_DB_NAME"

#GA 
set_config 'GA_ACCOUNT' "$GOOGLE_ANALYTICS_ACCOUNT"

# Run original parameter (CMD in image / command in container)
cd ${APPLICATION_PATH}
exec "$@"
