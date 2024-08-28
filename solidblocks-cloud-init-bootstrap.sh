
################################################################################
# included 'solidblocks-shell/lib/text-include.sh'
################################################################################
function tput_wrapper() {
  if [[ -t 0 ]]; then
    tput $@
  fi
}

COLOR_RED=$(tput_wrapper -Txterm-256color setaf 1)
COLOR_GREEN=$(tput_wrapper -Txterm-256color setaf 2)
COLOR_YELLOW=$(tput_wrapper -Txterm-256color setaf 3)
COLOR_BLACK=$(tput_wrapper -Txterm-256color setaf 0)
COLOR_BLUE=$(tput_wrapper -Txterm-256color setaf 4)
COLOR_MAGENTA=$(tput_wrapper -Txterm-256color setaf 5)
COLOR_CYAN=$(tput_wrapper -Txterm-256color setaf 6)
COLOR_WHITE=$(tput_wrapper -Txterm-256color setaf 15)

COLOR_RESET=$(tput_wrapper -Txterm-256color sgr0)

FORMAT_BOLD=$(tput_wrapper bold)
FORMAT_DIM=$(tput_wrapper dim)
FORMAT_UNDERLINE=$(tput_wrapper smul)

FORMAT_RESET=${COLOR_RESET}


################################################################################


################################################################################
# included 'solidblocks-shell/lib/utils-include.sh'
################################################################################
function ensure_command() {
    local command=${1:-}

    if ! type "${command}" &>/dev/null; then
      log_echo_die "command '${command}' not installed"
    fi
}

################################################################################


################################################################################
# included 'solidblocks-shell/lib/log-include.sh'
################################################################################
function log_echo_info() {
  echo "${*}"
}

# see https://pellepelster.github.io/solidblocks/shell/log/#log_echo_error
function log_echo_error() {
  echo -e "${COLOR_RED}${*}${COLOR_RESET}" 1>&2;
}

function log_echo_warning() {
  echo -e "${COLOR_YELLOW}${*}${COLOR_RESET}" 1>&2;
}

# see https://pellepelster.github.io/solidblocks/shell/log/#log_echo_die
function log_echo_die() { log_echo_error "${*}"; exit 4;}

# see https://pellepelster.github.io/solidblocks/shell/log/#log_divider_header
function log_divider_header() {
    echo ""
    echo "================================================================================"
    log_info "$@"
    echo "--------------------------------------------------------------------------------"
}

# see https://pellepelster.github.io/solidblocks/shell/log/#log_divider_header
function log_divider_footer() {
    echo "================================================================================"
    echo
}

function log() {
  local log_level=${1}
  shift || true

  local _message="${*}"

  local color="${COLOR_WHITE}"

  case "${log_level}" in
    info)       color="${COLOR_BLACK}" ;;
    debug)      color="${COLOR_CYAN}" ;;
    warning)    color="${COLOR_YELLOW}" ;;
    success)    color="${COLOR_GREEN}" ;;
    error)      color="${COLOR_RED}" ;;
    emergency)  color="${COLOR_RED}" ;;
  esac

  echo -e "$(date -u +"%Y-%m-%d %H:%M:%S UTC") ${color}$(printf "[%9s]" "${log_level}")${COLOR_RESET} ${_message}" 1>&2
}

# see https://pellepelster.github.io/solidblocks/shell/log/#log
function log_info () { log info "${*}"; }
function log_success() { log success "${*}"; }
function log_warning() { log warning "${*}"; }
function log_debug() { log debug "${*}"; }
function log_error() { log error "${*}"; }

# see https://pellepelster.github.io/solidblocks/shell/log/#log_die
function log_die() { log emergency "${*}"; exit 4;}

################################################################################


################################################################################
# included 'solidblocks-shell/lib/curl-include.sh'
################################################################################
CURL_WRAPPER_RETRY_DELAY=${CURL_WRAPPER_RETRY_DELAY:-5}
CURL_WRAPPER_RETRIES=${CURL_WRAPPER_RETRIES:-10}

function curl_wrapper() {
    ensure_command "curl"

    local try=0
    while [ $try -lt ${CURL_WRAPPER_RETRIES} ] && ! curl --retry-connrefused --fail --silent --location --show-error "$@"; do
        try=$((try+1))
        log_echo_error "curl call '$@' (${try}/${CURL_WRAPPER_RETRIES}) failed, retrying in ${CURL_WRAPPER_RETRY_DELAY} seconds"
        sleep "${CURL_WRAPPER_RETRY_DELAY}"
    done
}

################################################################################


################################################################################
# included 'solidblocks-shell/lib/apt.sh'
################################################################################
#!/usr/bin/env bash

function apt_update_repositories {
  apt-get update
}

function apt_update_system() {
    apt-get \
        -o Dpkg::Options::="--force-confnew" \
        --force-yes \
        -fuy \
        dist-upgrade
}

function apt_ensure_package {
	local package=${1}
	echo -n "checking if package '${package}' is installed..."
	if [[ $(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -c "ok installed") -eq 0 ]];
	then
		echo "not found, installing now"
		while ! DEBIAN_FRONTEND="noninteractive" apt-get install --no-install-recommends -qq -y "${package}"; do
    		echo "installing failed retrying in 30 seconds"
    		sleep 30
    		apt_update_repositories
		done
	else
		echo "ok"
	fi
}

################################################################################


################################################################################
# included 'solidblocks-shell/lib/package-include.sh'
################################################################################
function package_update_system() {
  if which apt >/dev/null 2>&1; then
    apt_update_system
  fi
}

function package_update_repositories() {
  if which apt >/dev/null 2>&1; then
    apt_update_repositories
  fi
}

function package_ensure_package() {
  if which apt >/dev/null 2>&1; then
    apt_ensure_package $@
  fi
}


################################################################################

export SOLIDBLOCKS_DIR="${SOLIDBLOCKS_DIR:-/solidblocks}"
export SOLIDBLOCKS_VERSION="v0.2.7-pre1"
export SOLIDBLOCKS_CLOUD_INIT_CHECKSUM="5a0f06d6d3815bca6634bcb21f945f6bff67b6fe8a4d927233f39b596f08cff8"
export SOLIDBLOCKS_BASE_URL="${SOLIDBLOCKS_BASE_URL:-https://github.com}"

function solidblocks_bootstrap_cloud_init() {
  package_update_repositories
  package_ensure_package "unzip"

  groupadd solidblocks
  useradd solidblocks -g solidblocks

  # shellcheck disable=SC2086
  mkdir -p ${SOLIDBLOCKS_DIR}/{templates,lib,secrets}

  chmod 770 ${SOLIDBLOCKS_DIR}
  chown solidblocks:solidblocks ${SOLIDBLOCKS_DIR}

  chmod -R 770 ${SOLIDBLOCKS_DIR}
  chown -R solidblocks:solidblocks ${SOLIDBLOCKS_DIR}

  chmod -R 700 ${SOLIDBLOCKS_DIR}/secrets

  local temp_file="$(mktemp)"
  curl_wrapper "${SOLIDBLOCKS_BASE_URL}/pellepelster/solidblocks/releases/download/${SOLIDBLOCKS_VERSION}/solidblocks-cloud-init-${SOLIDBLOCKS_VERSION}.zip" > "${temp_file}"
  echo "${SOLIDBLOCKS_CLOUD_INIT_CHECKSUM}  ${temp_file}" | sha256sum -c

  (
    cd "${SOLIDBLOCKS_DIR}" || exit 1
    unzip "${temp_file}"
    rm -rf "${temp_file}"
  )

  source "${SOLIDBLOCKS_DIR}/lib/storage.sh"
  source "${SOLIDBLOCKS_DIR}/lib/lego.sh"
}

solidblocks_bootstrap_cloud_init