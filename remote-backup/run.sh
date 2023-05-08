#!/command/with-contenv bashio
# shellcheck shell=bash
# parse global options from configuration

bashio::config.require "remote_host" "A target host for copying backups is necessary."
bashio::config.require "remote_port" "A target host port for communication is necessary."
bashio::config.require.username "remote_user"
bashio::config.suggest.password "backup_password"
declare -r REMOTE_HOST=$(bashio::config "remote_host")
declare -r REMOTE_PORT=$(bashio::config "remote_port")
declare -r REMOTE_USER=$(bashio::config "remote_user")
declare -r REMOTE_PASSWORD=$(bashio::config "remote_password" "")

# script global shortcuts
declare -r BACKUP_NAME="$(bashio::config 'backup_custom_prefix' '') $(date +'%Y-%m-%d %H-%M')"
declare -r SSH_HOME="${HOME}/.ssh"

function set-debug-level {
    # default log level according to bashio const.sh is INFO
    if bashio::config.true "debug"; then
        bashio::log.level "debug"
        declare -r -g DEBUG_FLAG="-v"
    fi
}

function sshpass_error {
  local -r -i errno=${1}
  local -r sshpass_err=("OK" "Invalid command line argument" "Conflicting arguments given" "General runtime error" "Unrecognized response from ssh (parse error)" "Invalid/incorrect password" "Host public key is unknown." "IP public key changed.")

  if [[ $errno -ge 0 && $errno -le ${#sshpass_err[@]} ]]; then
    echo ${sshpass_err[$errno]}
  else
    echo "unknown error: $errno"
  fi

  return "${__BASHIO_EXIT_OK}"
}

# Arguments:
#   $1 result should be ok or error
#   $2 message message to send with the event
function fire-event {
    local -r result=${1}
    local message=${2:-}

    if bashio::var.has_value "${message}"; then
        message=",\"message\":\"${message}\""
    fi

    # catch return code which is always false, see https://github.com/hassio-addons/bashio/issues/31
    local ret=$(bashio::api.supervisor POST /core/api/events/remote_backup_status "{\"result\":\"${result}\"${message}}")
}
function die {
    local -r message=${1:-'no message'}
    local -r title=${2:-'Addon: Remote Backup Failed!'}

    # catch return code which is always false, see https://github.com/hassio-addons/bashio/issues/31
    local ret=$(bashio::api.supervisor POST /core/api/services/persistent_notification/create \
        "{\"message\":\"${message}\", \"title\":\"${title}\", \"notification_id\":\"addon-remote-backup\"}")
    fire-event "error" "${message}"
    bashio::exit.nok "${message}"
}

# prepare SSH environment/configuration
# function does never fail to continue with further commands
function add-ssh-key {
    if ! bashio::config.true "ssh_enabled" && ! bashio::config.true "rsync_enabled"; then
        bashio::log.debug "Not creating configuration, SSH/RSYNC disabled."
        return
    fi

    bashio::log.info "Adding SSH configuration."
    # prepare SSH key pair
    mkdir -p ${SSH_HOME} || bashio::log.error "Failed to create .ssh directory!"
    if bashio::config.has_value "remote_key"; then
        (
            cp "/ssl/$(bashio::config 'remote_key')" "${SSH_HOME}/id_rsa"
            ssh-keygen -y -f ${SSH_HOME}/id_rsa > ${SSH_HOME}/id_rsa.pub
            chmod 600 "${SSH_HOME}/id_rsa"
            chmod 644 "${SSH_HOME}/id_rsa.pub"
        ) || bashio::log.error "Failed to create SSH key pair!"
    fi

    # copy known_hosts if available
    if bashio::fs.file_exists "/ssl/known_hosts"; then
      bashio::log.debug "Using existing /ssl/known_hosts file."
      cp "/ssl/known_hosts" "${SSH_HOME}/known_hosts" \
          || bashio::log.error "Failed to copy known_hosts file!"
    else
      bashio::log.warning "Missing known_hosts file! Retrieving public key of remote host ${REMOTE_HOST}."
      ssh-keyscan -t rsa -p ${REMOTE_PORT} ${REMOTE_HOST} >> ${SSH_HOME}/known_hosts \
          || bashio::log.error "Failed to add public key for remote host ${REMOTE_HOST}!"
    fi

    # generate configuration file
    (
        echo "Host remote"
        if bashio::fs.file_exists "${SSH_HOME}/id_rsa"; then
            echo "    IdentityFile ${SSH_HOME}/id_rsa"
        fi
        echo "    HostName ${REMOTE_HOST}"
        echo "    User ${REMOTE_USER}"
        echo "    Port ${REMOTE_PORT}"
        if bashio::config.has_value "remote_host_key_algorithms"; then
            echo "    HostKeyAlgorithms $(bashio::config 'remote_host_key_algorithms')"
        fi
    ) > "${SSH_HOME}/config"
    chmod 600 "${SSH_HOME}/config" || bashio::log.error "Failed to set SSH configuration file permissions!"
}

# call Home Assistant to create a local backup
# function fails in case local backup is not created
function create-local-backup {
    local -r base_folders="addons/local homeassistant media share ssl"
    local data="{\"name\":\"${BACKUP_NAME}\"}"
    local bak_type="non-encrypted"

    if bashio::config.has_value "backup_password"; then
        data="$(echo $data | tr -d '}'), \"password\": \"$(bashio::config 'backup_password')\"}"
        local -r bak_type="password encrypted"
    fi
    if bashio::config.has_value "backup_exclude_addons" || bashio::config.has_value "backup_exclude_folders"; then
        bashio::log.info "Creating ${bak_type} partial backup: \"${BACKUP_NAME}\""

        local unformatted_folders="${base_folders}"
        local unformatted_addons=$(bashio::supervisor.addons)

        if bashio::config.has_value "backup_exclude_folders"; then
            local -r backup_exclude_folders=$(bashio::config "backup_exclude_folders")
            bashio::log.notice "Excluded folder(s):\n${backup_exclude_folders}"
            for folder in ${backup_exclude_folders} ; do
                unformatted_folders="${unformatted_folders[@]/$folder}"
            done
        fi
        if bashio::config.has_value "backup_exclude_addons"; then
            local -r backup_exclude_addons=$(bashio::config "backup_exclude_addons")
            bashio::log.notice "Excluded addon(s):\n${backup_exclude_addons}"
            for addon in ${backup_exclude_addons} ; do
                unformatted_addons="${unformatted_addons[@]/$addon}"
            done
        fi

        local -r addons=$(jq -nc '$ARGS.positional' --args ${unformatted_addons[@]})
        local -r folders=$(jq -nc '$ARGS.positional' --args ${unformatted_folders[@]})
        bashio::log.debug "Including folder(s) ${folders}"
        bashio::log.debug "Including addon(s) ${addons}"

        data="$(echo $data | tr -d '}'), \"addons\": ${addons}, \"folders\": ${folders}}" # append addon and folder set
        if ! SLUG=$(bashio::api.supervisor POST /backups/new/partial "${data}" .slug); then
            bashio::log.fatal "Error creating ${bak_type} partial backup!"
            return "${__BASHIO_EXIT_NOK}"
        fi
    else
        bashio::log.info "Creating ${bak_type} full backup: \"${BACKUP_NAME}\""

        if ! SLUG=$(bashio::api.supervisor POST /backups/new/full "${data}" .slug); then
            bashio::log.fatal "Error creating ${bak_type} full backup!"
            return "${__BASHIO_EXIT_NOK}"
        fi

    fi

    bashio::log.info "Backup created: ${SLUG}"
    return "${__BASHIO_EXIT_OK}"
}

function copy-backup-to-remote {
    if ! bashio::config.true "ssh_enabled"; then
        bashio::log.debug "SFTP/SCP disabled."
        return "${__BASHIO_EXIT_OK}"
    fi

    local -r remote_directory=$(bashio::config "ssh_remote_directory" "")
    local remote_name=$SLUG
    if bashio::config.true "backup_friendly_name"; then
        remote_name=$BACKUP_NAME
    fi

    bashio::log.info "Copying backup using SFTP/SCP."
    (
      sshpass -p "${REMOTE_PASSWORD}" \
        scp ${DEBUG_FLAG:-} -F "${SSH_HOME}/config" "/backup/${SLUG}.tar" remote:"${remote_directory}/${remote_name}.tar" || (
        bashio::log.warning "SFTP transfer failed, falling back to SCP: $(sshpass_error $?)"
        sshpass -p "${REMOTE_PASSWORD}" \
          scp ${DEBUG_FLAG:-} -O -F "${SSH_HOME}/config" "/backup/${SLUG}.tar" remote:"${remote_directory}/${remote_name}.tar" || (
            bashio::log.error "Error copying backup ${SLUG}.tar to ${remote_directory} on ${REMOTE_HOST}:  $(sshpass_error $?)"
            return "${__BASHIO_EXIT_NOK}"
        )
      )
    )

    return "$?"
}

function rsync-folders {
    if ! bashio::config.true "rsync_enabled"; then
        bashio::log.debug "Rsync disabled."
        return "${__BASHIO_EXIT_OK}"
    fi

    local -r folders="/config /addons /backup /share /ssl" # put directories without trailing slash
    local -r rsync_url="${REMOTE_USER}@${REMOTE_HOST}:$(bashio::config 'rsync_rootfolder')"
    local flags="-a -r ${DEBUG_FLAG:-}"

    bashio::log.info "Copying backup using rsync."

    local -r rsync_exclude=$(bashio::config "rsync_exclude" "")
    echo "${rsync_exclude}" > /tmp/rsync_exclude.txt
    if bashio::config.has_value "rsync_exclude"; then
        bashio::log.notice "Excluded rsync file patterns:\n${rsync_exclude}"
    fi

    bashio::log.debug "Syncing ${folders}"
    (
      sshpass -p "${REMOTE_PASSWORD}" rsync ${flags} --port ${REMOTE_PORT} --exclude-from='/tmp/rsync_exclude.txt' ${folders} "${rsync_url}/" --delete || (
        bashio::log.error "Error rsyncing folder(s) ${folders} to ${rsync_url}: $(sshpass_error $?)!"
        return "${__BASHIO_EXIT_NOK}"
      )
    )

    return "${__BASHIO_EXIT_OK}"
}

function rclone-backups {
    if ! bashio::config.true "rclone_enabled"; then
        bashio::log.debug "Rclone disabled."
        return "${__BASHIO_EXIT_OK}"
    fi

    bashio::config.require "rclone_remote_host" " rclone was enabled and a target for copying is necessary."
    local -r rclone_remote_host=$(bashio::config "rclone_remote_host" "")
    local remote_directory=""
    if bashio::config.exists 'rclone_remote_directory'; then
      local -r remote_directory=$(bashio::config "rclone_remote_directory")
    fi
    (
        cd /backup/
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
    ) || bashio::log.error "Failed to prepare rclone configuration!"

    if bashio::config.true "rclone_copy"; then
        local remote_name=$SLUG
        if bashio::config.true "backup_friendly_name"; then
            remote_name=$BACKUP_NAME
        fi
        bashio::log.info "Copying backup using rclone."
        (
            rclone ${DEBUG_FLAG:-} copyto "/backup/${SLUG}.tar" "${rclone_remote_host}:${remote_directory}/${remote_name}.tar" || (
                bashio::log.error "Error rclone ${SLUG}.tar to ${rclone_remote_host}:${remote_directory}/${remote_name}.tar!"
                return "${__BASHIO_EXIT_NOK}"
            )
        )
    fi
    if bashio::config.true "rclone_sync"; then
        bashio::log.info "Syncing backups using rclone"
        (
            rclone ${DEBUG_FLAG:-} sync "/backup" "${rclone_remote_host}:${remote_directory}" || (
                bashio::log.error "Error syncing backups by rclone!"
                return "${__BASHIO_EXIT_NOK}"
            )
        )
    fi
    if bashio::config.true "rclone_restore"; then
        local restore_name="restore-$(date +%F)"
        mkdir -p "${restore_name}"
        bashio::log.info "Restoring backups to ${restore_name} using rclone"
        (
            rclone ${DEBUG_FLAG:-} copyto "${rclone_remote_host}:${remote_directory}" "/backup/${restore_name}/" || (
                bashio::log.error "Error restoring backups from ${rclone_remote_host}:${remote_directory}!"
                return "${__BASHIO_EXIT_NOK}"
            )
        )
    fi
    return "${__BASHIO_EXIT_OK}"
}

function clone-to-remote {
    local ret="${__BASHIO_EXIT_OK}"

    copy-backup-to-remote || ret="${__BASHIO_EXIT_NOK}"
    rsync-folders || ret="${__BASHIO_EXIT_NOK}"
    rclone-backups || ret="${__BASHIO_EXIT_NOK}"

    return "${ret}"
}

function delete-local-backup {
    if bashio::config.equals "backup_keep_local" "all"; then
        bashio::log.debug "Keep all backups."
        return "${__BASHIO_EXIT_OK}"
    fi

    if ! bashio::api.supervisor POST /backups/reload; then
        bashio::log.warning "Failed to reload backups!"
    fi

    if bashio::config.is_empty "backup_keep_local" || bashio::config.equals "backup_keep_local" "null" || bashio::config.equals "keep_backup_local" "0"; then
        if bashio::var.has_value "$SLUG"; then
            bashio::log.notice "Deleting local backup: ${SLUG}"
            if ! bashio::api.supervisor DELETE /backups/${SLUG}; then
                bashio::log.error "Failed to delete backup: ${SLUG}"
                return "${__BASHIO_EXIT_NOK}"
            fi
        else
            bashio::log.debug "No current backup to delete."
        fi
    else
        local ret="${__BASHIO_EXIT_OK}"
        local -r backup_list=$(bashio::api.supervisor GET /backups)
        local -r last_date_to_keep=$(echo "${backup_list}" | jq ".backups[].date" | sort -r | \
            head -n $(bashio::config "backup_keep_local") | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

        echo "${backup_list}" | jq -c ".backups[]" | while read -r backup; do
            if [[ $(echo "${backup}" | jq ".date" | xargs date -D "%Y-%m-%dT%T" +%s --date ) -lt ${last_date_to_keep} ]]; then
                local backup_slug=$(echo "${backup}" | jq -r .slug)
                bashio::log.notice "Deleting local backup: ${backup_slug}"
                if ! bashio::api.supervisor DELETE /backups/${backup_slug}; then
                    bashio::log.error "Failed to delete backup: ${backup_slug}"
                    ret="${__BASHIO_EXIT_NOK}"
                fi
            fi
        done
        return "${ret}"
    fi

    return "${__BASHIO_EXIT_OK}"
}

# general setup and backup
set-debug-level
add-ssh-key

create-local-backup || die "Local backup process failed! See log for details."
clone-to-remote || die "Cloning backup(s) to remote host ${REMOTE_HOST} failed! See log for details."
delete-local-backup || die "Removing local backup(s) failed! See log for details."

bashio::log.info "Backup process done!"
fire-event "ok" "Backup ${BACKUP_NAME} created."
bashio::exit.ok
