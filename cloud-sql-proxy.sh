#!/bin/bash
# Copyright 2019 Google, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This init script installs a cloud-sql-proxy on a GCE node.
# Looks at two local metadata flags
#   cloud_sql_instance_name: CloudSQL instnace name in format "myproject:region:myinstance" (required)
#   cloud_sql_proxy_port: port of the Cloud SQL instance (default = 3306)
#   cloud_sql_proxy_private: flag specifying whether cloud sql instance is using private IP

# Do not use "set -x" to avoid printing passwords in clear in the logs
set -euo pipefail

readonly cloud_sql_instance_name="$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloud-sql-instance-name" -H "Metadata-Flavor: Google")"

# default to MySQL default
readonly cloud_sql_proxy_port="$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloud-sql-proxy-port" -H "Metadata-Flavor: Google" || echo '3306')"

readonly cloud_sql_proxy_private="$(curl "http://metadata.google.internal/computeMetadata/v1/instance/attributes/cloud-sql-proxy-private" -H "Metadata-Flavor: Google" || echo 'false')"

readonly PROXY_DIR='/var/run/cloud_sql_proxy'
readonly PROXY_BIN='/usr/local/bin/cloud_sql_proxy'
readonly SERVICE_DIR='/usr/lib/systemd/system'
readonly INIT_SCRIPT='/usr/lib/systemd/system/cloud-sql-proxy.service'

# Helper to run any command with Fibonacci backoff.
# If all retries fail, returns last attempt's exit code.
# Args: "$@" is the command to run.
function run_with_retries() {
  local retry_backoff=(1 1 2 3 5 8 13 21 34 55 89 144)
  local -a cmd=("$@")
  echo "About to run '${cmd[*]}' with retries..."

  local update_succeeded=0
  for ((i = 0; i < ${#retry_backoff[@]}; i++)); do
    if "${cmd[@]}"; then
      update_succeeded=1
      break
    else
      local sleep_time=${retry_backoff[$i]}
      echo "'${cmd[*]}' attempt $(( $i + 1 )) failed! Sleeping ${sleep_time}." >&2
      sleep ${sleep_time}
    fi
  done

  if ! (( ${update_succeeded} )); then
    echo "Final attempt of '${cmd[*]}'..."
    # Let any final error propagate all the way out to any error traps.
    "${cmd[@]}"
  fi
}

function install_cloud_sql_proxy() {

  proxy_instances_flags=''
  proxy_instances_flags+=" -instances=${cloud_sql_instance_name}=tcp:${cloud_sql_proxy_port}"

  if [[ $cloud_sql_proxy_private = "true" ]]; then
    proxy_instances_flags+=" --ip_address_types=PRIVATE"
  fi

  # Install proxy.
  wget -q https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 \
    || err 'Unable to download cloud-sql-proxy binary'
  mv cloud_sql_proxy.linux.amd64 ${PROXY_BIN}
  chmod +x ${PROXY_BIN}

  mkdir -p ${PROXY_DIR}
  mkdir -p ${SERVICE_DIR}

  # Install proxy as systemd service for reboot tolerance.
  cat << EOF > ${INIT_SCRIPT}
[Unit]
Description=Google Cloud SQL Proxy
After=local-fs.target network-online.target
After=google.service
Before=shutdown.target

[Service]
Type=simple
ExecStart=${PROXY_BIN} \
  -dir=${PROXY_DIR} \
  ${proxy_instances_flags}

[Install]
WantedBy=multi-user.target
EOF
  chmod a+rw ${INIT_SCRIPT}
  systemctl enable cloud-sql-proxy
  systemctl start cloud-sql-proxy \
    || err 'Unable to start cloud-sql-proxy service'
    
  run_with_retries nc -zv localhost ${cloud_sql_proxy_port}

  echo 'Cloud SQL Proxy installation succeeded' >&2
}

function install_dependencies() {
  # install get attributes script
  # install netcat
  # install mysql client
  apt-get -y install mysql-client netcat

}

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
  return 1
}

function main() {

  install_dependencies
  install_cloud_sql_proxy

}

main