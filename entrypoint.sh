#!/bin/bash
# Entrypoint for the contractor image, first argument is the role:
#   contractor     - configure, set up the database on first run, run apache.
#                    With FULL set it is the "contractor host": also runs the
#                    caching proxy, bind (DNS) and tftp
#   subcontractor  - configure and run subcontractor
#   dhcpd          - configure and run the DHCP server
#   anything else  - exec'd as is, ie: bash
#
# Settings (environment), * is only for FULL:
#   DB_HOST DB_PORT DB_NAME DB_USER DB_PASSWORD   postgres, default postgres/5432/contractor/contractor/contractor
#   MONGO_HOST                                    mongo url, default mongodb://mongo:27017/
#   SITE_NAME SITE_DOMAIN                         initial site, default site1/site1.test
#   ROOT_PASSWORD                                 password for the root user, default root
#   PRIMARY_INTERFACE                             interface contractor is on, default eth0
#   CONTRACTOR_RESPKGS                            respkgs to install, in order, default is the demo set
#   CONTRACTOR_PLUGINS                            plugins to add to the respkgs, ie: "virtualbox vcenter"
#   FULL                                          set to run as the contractor host
#   UPSTREAM_PROXY *                              proxy the caching proxy goes through, ie: http://myproxy:3128/
#   NTP_SERVER *                                  ntp server to give the site, default ntp.ubuntu.com
#   IP_RESERVATION *                              set to have setupWizard reserve and pool addresses
#   TFTP_OPTIONS *                                options for tftpd, default "--verbose"
#   CONTRACTOR_URL                                (subcontractor, dhcpd) where contractor is, default http://contractor
#   SUBCONTRACTOR_MODULES                         (subcontractor) modules to enable, "name" or "name:limit", default manual,test,iputils
#   LISTEN_INTERFACE TFTP_SERVER                  (dhcpd) interface to serve on, ip of the tftp server, default is the interface's ip
#
# Files:
#   /respkgs/*.respkg                             installed after the built in ones, ie: the disks packages
#   /config/subcontractor.conf                    if present, used as is for subcontractor and dhcpd
#   ~/.contractorcli.ini                          written for the contractor role, host http://127.0.0.1, user root

set -e

DB_HOST="${DB_HOST:-postgres}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-contractor}"
DB_USER="${DB_USER:-contractor}"
DB_PASSWORD="${DB_PASSWORD:-contractor}"
MONGO_HOST="${MONGO_HOST:-mongodb://mongo:27017/}"
SITE_NAME="${SITE_NAME:-site1}"
SITE_DOMAIN="${SITE_DOMAIN:-site1.test}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
PRIMARY_INTERFACE="${PRIMARY_INTERFACE:-eth0}"
CONTRACTOR_PLUGINS="${CONTRACTOR_PLUGINS:-}"
FULL="${FULL:-}"
UPSTREAM_PROXY="${UPSTREAM_PROXY:-}"
NTP_SERVER="${NTP_SERVER:-ntp.ubuntu.com}"
IP_RESERVATION="${IP_RESERVATION:-}"
TFTP_OPTIONS="${TFTP_OPTIONS:---verbose}"
CONTRACTOR_URL="${CONTRACTOR_URL:-http://contractor}"
SUBCONTRACTOR_MODULES="${SUBCONTRACTOR_MODULES:-manual,test,iputils}"
LISTEN_INTERFACE="${LISTEN_INTERFACE:-eth0}"
TFTP_SERVER="${TFTP_SERVER:-}"

if [ -n "$FULL" ]
then
  CONTRACTOR_RESPKGS="${CONTRACTOR_RESPKGS:-contractor-os-base contractor-ubuntu-base contractor-ipxe contractor-plugins-manual contractor-plugins-iputils}"
else
  CONTRACTOR_RESPKGS="${CONTRACTOR_RESPKGS:-contractor-os-base contractor-plugins-manual contractor-plugins-test}"
fi

wait_for()  # host port what
{
  echo "Waiting for $3 at $1:$2..."
  for i in $( seq 1 60 )
  do
    if ( exec 3<>"/dev/tcp/$1/$2" ) 2> /dev/null
    then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for $3" >&2
  exit 1
}

url_host_port()  # url default_port -> "host port"
{
  local hostport="${1#*://}"
  hostport="${hostport%%/*}"
  if [[ "$hostport" == *:* ]]
  then
    echo "${hostport%%:*} ${hostport##*:}"
  else
    echo "$hostport $2"
  fi
}

interface_ip()  # interface
{
  ip -4 -o address show dev "$1" | awk '{ print $4 }' | cut -d/ -f1 | head -n 1
}

contractor_config()
{
  # the values are written into the file, not read from the environment, so
  # apache, cron and manage.py all see the same thing
  mkdir -p /var/lib/contractor
  if [ ! -f /var/lib/contractor/secret_key ]
  then
    python3 -c "import secrets; print( secrets.token_urlsafe( 50 ) )" > /var/lib/contractor/secret_key
    chmod 600 /var/lib/contractor/secret_key
  fi

  cp /etc/contractor.conf.sample /etc/contractor.conf
  DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" DB_PASSWORD="$DB_PASSWORD" MONGO_HOST="$MONGO_HOST" python3 - >> /etc/contractor.conf << 'PY_EOF'
import os

print()
print( '# written by the container entrypoint' )
print( 'SECRET_KEY = {0!r}'.format( open( '/var/lib/contractor/secret_key' ).read().strip() ) )
print( 'DATABASES[ "default" ].update( {{ "NAME": {0!r}, "USER": {1!r}, "PASSWORD": {2!r}, "HOST": {3!r}, "PORT": {4!r} }} )'.format( os.environ[ 'DB_NAME' ], os.environ[ 'DB_USER' ], os.environ[ 'DB_PASSWORD' ], os.environ[ 'DB_HOST' ], os.environ[ 'DB_PORT' ] ) )
print( 'MONGO_HOST = {0!r}'.format( os.environ[ 'MONGO_HOST' ] ) )
PY_EOF

  ln -sf /etc/contractor.conf /usr/lib/python3/dist-packages/contractor/settings.py
}

install_respkgs()
{
  # the plugin enable is on the filesystem, which is new every time the
  # container is created, the rest of what the respkgs do is safe to repeat
  local names="$CONTRACTOR_RESPKGS"
  for plugin in $CONTRACTOR_PLUGINS
  do
    names="$names contractor-plugins-$plugin"
  done

  for name in $names
  do
    for file in /usr/share/contractor-respkgs/${name}_*.respkg
    do
      echo "Installing $( basename "$file" )..."
      respkg -i "$file"
    done
  done

  for file in /respkgs/*.respkg
  do
    [ -f "$file" ] || continue
    echo "Installing $( basename "$file" )..."
    respkg -i "$file"
  done
}

run_wizard()
{
  local args=( --site-name="$SITE_NAME" --site-domain="$SITE_DOMAIN" --primary-interface="$PRIMARY_INTERFACE" --superuser-password="$ROOT_PASSWORD" )

  if [ -z "$IP_RESERVATION" ]
  then
    args+=( --no-ip-reservation )
  fi

  if [ -n "$FULL" ]
  then
    local ip
    ip="$( interface_ip "$PRIMARY_INTERFACE" )"
    args+=( --proxy-server="http://$ip:3128/" --ntp-server="$NTP_SERVER" )
  fi

  # exit code 2 is "already set up"
  local rc=0
  /usr/lib/contractor/setup/setupWizard "${args[@]}" || rc=$?
  if [ "$rc" != "0" ] && [ "$rc" != "2" ]
  then
    echo "setupWizard failed with $rc" >&2
    exit "$rc"
  fi
}

supervise()  # "name:command"...  runs each in the background, exits when any of them does
{
  local pids=()
  trap 'kill "${pids[@]}" 2> /dev/null; wait; exit 0' TERM INT

  for item in "$@"
  do
    local name="${item%%:*}"
    local command="${item#*:}"
    echo "Starting $name..."
    $command &
    pids+=( $! )
  done

  wait -n || true
  echo "A process exited, stopping..." >&2
  kill "${pids[@]}" 2> /dev/null || true
  wait || true
  exit 1
}

contractorcli_config()
{
  # so "docker-compose exec contractor contractorcli ..." works without any setup
  printf '[contractor]\nhost: http://127.0.0.1\nusername: root\npassword: %s\n' "$ROOT_PASSWORD" > "$HOME/.contractorcli.ini"
  chmod 600 "$HOME/.contractorcli.ini"
}

run_contractor()
{
  contractor_config
  contractorcli_config

  wait_for "$DB_HOST" "$DB_PORT" "postgres"
  wait_for $( url_host_port "$MONGO_HOST" 27017 ) "mongo"

  /usr/lib/contractor/util/manage.py migrate

  install_respkgs
  run_wizard

  if [ -z "$FULL" ]
  then
    cron
    exec apachectl -D FOREGROUND
  fi

  local proxy_args=( --site-domain "$SITE_DOMAIN" )
  if [ -n "$UPSTREAM_PROXY" ]
  then
    proxy_args+=( --upstream-proxy "$UPSTREAM_PROXY" )
  fi
  /usr/lib/contractor/setup/apache_setup "${proxy_args[@]}"

  # /etc/bind is a volume, the key it came with is the same in every container
  # made from the image
  if [ ! -f /etc/bind/.entrypoint_key ]
  then
    rndc-confgen -a -u bind
    touch /etc/bind/.entrypoint_key
  fi

  mkdir -p /var/cache/bind /run/named
  chown bind:bind /var/cache/bind /run/named
  /usr/lib/contractor/cron/genDNS || echo "WARNING: genDNS failed"

  # tftpd, bind and cron are the parts a PXE booting machine needs from the
  # contractor host, apache is already serving static, proxy and the API/UI
  supervise "cron:cron -f" \
            "named:named -f -g -u bind" \
            "tftpd:in.tftpd -L -u tftp --secure $TFTP_OPTIONS /srv/tftp" \
            "apache:apachectl -D FOREGROUND"
}

subcontractor_config()
{
  if [ -f /config/subcontractor.conf ]
  then
    cp /config/subcontractor.conf /etc/subcontractor.conf
    return
  fi

  {
    echo "[contractor]"
    echo "host: $CONTRACTOR_URL"
    echo
    echo "[subcontractor]"
    echo "site: $SITE_NAME"
    echo "poll_interval: 20"
    echo "job_delay: 2"
    echo "max_concurent_jobs: 10"
    echo "max_job_request_size: 5"
    echo
    echo "[modules]"
    for item in ${SUBCONTRACTOR_MODULES//,/ }
    do
      local name="${item%%:*}"
      local limit=5
      if [[ "$item" == *:* ]]
      then
        limit="${item##*:}"
      fi
      echo "subcontractor_plugins.$name: $limit"
    done
    echo
    echo "[credentials]"
    echo
    echo "[dhcpd]"
    echo "cache_file: /var/lib/dhcpd/dhcpd.cache"
    echo "dynamic_pool_mtu:"
    echo "dynamic_pool_vlan:"
    echo "dynamic_pool_console: console"
    echo "poll_interval: 40"
    echo "dynamic_lease_time: 600"
    echo "static_lease_time: 3600"
    echo "listen_interface: $LISTEN_INTERFACE"
    echo "listen_address: 0.0.0.0"
    echo "tftp_server: ${TFTP_SERVER:-$( interface_ip "$LISTEN_INTERFACE" )}"
  } > /etc/subcontractor.conf
}

wait_for_contractor()
{
  wait_for $( url_host_port "$CONTRACTOR_URL" 80 ) "contractor"
}

run_subcontractor()
{
  subcontractor_config
  wait_for_contractor
  exec subcontractor -i foreground
}

run_dhcpd()
{
  mkdir -p /var/lib/dhcpd
  subcontractor_config
  wait_for_contractor
  exec dhcpd -i foreground
}

case "$1" in
  contractor)    run_contractor ;;
  subcontractor) run_subcontractor ;;
  dhcpd)         run_dhcpd ;;
  *)             exec "$@" ;;
esac
