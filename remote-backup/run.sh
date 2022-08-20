#!/command/with-contenv bashio
# shellcheck shell=bash
# parse inputs from options
DEBUG=$(bashio::config "debug")
REMOTE_HOST=$(bashio::config "remote_host")
REMOTE_PORT=$(bashio::config "remote_port")
REMOTE_USER=$(bashio::config "remote_user")
REMOTE_PASSWORD=$(bashio::config "remote_password")
REMOTE_KEY=$(bashio::config "remote_key")
REMOTE_HOST_KEY_ALGORITHMS=$(bashio::config "remote_host_key_algorithms")

BACKUP_FRIENDLY_NAME=$(bashio::config "backup_friendly_name")
BACKUP_CUSTOM_PREFIX=$(bashio::config "backup_custom_prefix")
BACKUP_EXCLUDE_FOLDERS=$(bashio::config "backup_exclude_folders")
BACKUP_EXCLUDE_ADDONS=$(bashio::config "backup_exclude_addons")
BACKUP_KEEP_LOCAL=$(bashio::config 'backup_keep_local')
BACKUP_PASSWORD=$(bashio::config 'backup_password')

SSH_ENABLED=$(bashio::config "ssh_enabled")
SSH_REMOTE_DIRECTORY=$(bashio::config "ssh_remote_directory")

RSYNC_ENABLED=$(bashio::config "rsync_enabled")
RSYNC_ROOTFOLDER=$(bashio::config "rsync_rootfolder")
RSYNC_EXCLUDE=$(bashio::config "rsync_exclude")

RCLONE_ENABLED=$(bashio::config "rclone_enabled")
RCLONE_REMOTE_DIRECTORY=$(bashio::config "rclone_remote_directory")
RCLONE_COPY=$(bashio::config "rclone_copy")
RCLONE_SYNC=$(bashio::config "rclone_sync")
RCLONE_RESTORE=$(bashio::config "rclone_restore")

BACKUP_NAME="${BACKUP_CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"

function set-debug-level {
  # default log level according to bashio const.sh is INFO
  if bashio::var.true "${DEBUG}"; then    
    bashio::log.level "debug"
  fi
}

function die {
  local message=${1:-'no message'}
  local title=${2:-'Addon: Remote Backup Failed!'}

  # catch return code which is always false, see https://github.com/hassio-addons/bashio/issues/31
  local ret=$(bashio::api.supervisor POST /core/api/services/persistent_notification/create "{\"message\":\"${message}\", \"title\":\"${title}\"}")
  bashio::exit.nok "${message}"
}

# prepare SSH environment/configuration
# function does never fail to continue with further commands
function add-ssh-key {
    if bashio::var.true "${SSH_ENABLED}" || bashio::var.true "${RSYNC_ENABLED}"; then
        bashio::log.info "Adding SSH key."
        (
            mkdir -p ${HOME}/.ssh
            cp "/ssl/${REMOTE_KEY}" "${HOME}/.ssh/id_rsa"
            ssh-keygen -y -f ${HOME}/.ssh/id_rsa > ${HOME}/.ssh/id_rsa.pub
        ) || bashio::log.error "Failed to create SSH key pair!"

        bashio::log.debug "Adding public key of remote host ${REMOTE_HOST} to known hosts."
        ssh-keyscan -t rsa ${REMOTE_HOST} >> ${HOME}/.ssh/known_hosts \
            || bashio::log.error "Failed to add public key for remote host ${REMOTE_HOST}!"
        (
            echo "Host remote"
            echo "    IdentityFile ${HOME}/.ssh/id_rsa"
            echo "    HostName ${REMOTE_HOST}"
            echo "    User ${REMOTE_USER}"
            echo "    Port ${REMOTE_PORT}"
            echo "    StrictHostKeyChecking no"
        if bashio::var.has_value "${REMOTE_HOST_KEY_ALGORITHMS}"; then
            echo "    HostKeyAlgorithms ${REMOTE_HOST_KEY_ALGORITHMS}"
        fi
        ) > "${HOME}/.ssh/config"

        (
            chmod 600 "${HOME}/.ssh/id_rsa"
            chmod 600 "${HOME}/.ssh/config"
            chmod 644 "${HOME}/.ssh/id_rsa.pub"
        ) || bashio::log.error "Failed to set SSH file permissions!"
    fi
}

# call Home Assistant to create a local backup
# function fails in case local backup is not created
function create-local-backup {
    # Bind local variables
    local base_folders="addons/local homeassistant media share ssl"
    local installed_addons=$(bashio::supervisor.addons)
    local data="{\"name\":\"${BACKUP_NAME}\", \"password\": \"${BACKUP_PASSWORD}\"}"

    if bashio::var.has_value "${BACKUP_EXCLUDE_ADDONS}" || bashio::var.has_value "${BACKUP_EXCLUDE_FOLDERS}"; then
        bashio::log.info "Creating partial backup: \"${BACKUP_NAME}\""

        local unformatted_folders="${base_folders}"
        local unformatted_addons="${installed_addons}"
        
        if bashio::var.has_value "${BACKUP_EXCLUDE_FOLDERS}"; then
            bashio::log.notice "Excluded folder(s):\n${BACKUP_EXCLUDE_FOLDERS}"
            for folder in ${BACKUP_EXCLUDE_FOLDERS} ; do
                unformatted_folders=$(echo "${unformatted_folders}" | sed -e "s/${folder}//g")
            done
        fi
        if bashio::var.has_value "${BACKUP_EXCLUDE_ADDONS}"; then
            bashio::log.notice "Excluded addon(s):\n${BACKUP_EXCLUDE_ADDONS}"
            for addon in ${BACKUP_EXCLUDE_ADDONS} ; do
                unformatted_addons="$(echo "${unformatted_addons}" | sed -e "s/${addon}//g")"
            done
        fi

        local addons=$(echo ${unformatted_addons} | sed "s/ /\", \"/g")
        local folders=$(echo "${unformatted_folders}" | sed "s/ /\", \"/g" | sed "s/, \"\"//g")
        bashio::log.debug "Including folder(s) \"${folders}\""
        bashio::log.debug "Including addon(s) \"${addons}\""

        local data="$(echo $data | tr -d '}'), \"addons\": [\"${addons}\"], \"folders\": [\"${folders}\"]}" # append addon and folder set
        if ! SLUG=$(bashio::api.supervisor POST /backups/new/partial "${data}" .slug); then
            bashio::log.fatal "Error creating partial backup!"
            return "${__BASHIO_EXIT_NOK}"
        fi
    else
        bashio::log.info "Creating full backup: \"${BACKUP_NAME}\""

        if ! SLUG=$(bashio::api.supervisor POST /backups/new/full "${data}" .slug); then
            bashio::log.fatal "Error creating full backup!"
            return "${__BASHIO_EXIT_NOK}"
        fi

    fi

    bashio::log.info "Backup created: ${SLUG}"
    return "${__BASHIO_EXIT_OK}"
}

function copy-backup-to-remote {
    if bashio::var.false "${SSH_ENABLED}"; then
        bashio::log.debug "SCP disabled."
        return "${__BASHIO_EXIT_OK}"
    fi

    bashio::log.info "Copying backup using SCP."
    if ! scp -F "${HOME}/.ssh/config" "/backup/${SLUG}.tar" remote:"${SSH_REMOTE_DIRECTORY}/"; then
        bashio::log.error "Error copying backup ${SLUG}.tar to ${SSH_REMOTE_DIRECTORY} on ${REMOTE_HOST}."
        return "${__BASHIO_EXIT_NOK}"
    fi

    if bashio::var.true "${BACKUP_FRIENDLY_NAME}"; then
        bashio::log.info "Renaming ${SLUG}.tar to ${BACKUP_NAME}.tar"
        if ! ssh remote "mv \"${SSH_REMOTE_DIRECTORY}/${SLUG}.tar\" \"${SSH_REMOTE_DIRECTORY}/${BACKUP_NAME}.tar\""; then
            bashio::log.error "Error renaming backup to ${SSH_REMOTE_DIRECTORY}/${BACKUP_NAME}.tar on ${REMOTE_HOST}"
            return "${__BASHIO_EXIT_NOK}"
        fi
    fi
    return "${__BASHIO_EXIT_OK}"
}

function rsync-folders {
    if bashio::var.false "${RSYNC_ENABLED}"; then
        bashio::log.debug "Rsync disabled."
        return "${__BASHIO_EXIT_OK}"
    fi

    local folders="/config /addons /backup /share /ssl" # put directories without trailing slash
    local rsync_url="${REMOTE_USER}@${REMOTE_HOST}:${RSYNC_ROOTFOLDER}"
    local flags='-a -r'

    bashio::log.info "Copying backup using rsync."
    if bashio::var.true "${DEBUG}"; then    
        local flags="${flags} -v"
    fi

    echo "${RSYNC_EXCLUDE}" > /tmp/rsync_exclude.txt
    if bashio::var.has_value "${RSYNC_EXCLUDE}"; then   
        bashio::log.notice "Excluded rsync file patterns:\n${RSYNC_EXCLUDE}"
    fi

    bashio::log.debug "Syncing ${folders}"
    if ! sshpass -p "${REMOTE_PASSWORD}" rsync ${flags} --port ${REMOTE_PORT} --exclude-from='/tmp/rsync_exclude.txt' ${folders} "${rsync_url}/" --delete; then
        bashio::log.error "Error rsyncing folder(s) ${folders} to ${rsync_url}!"
        return "${__BASHIO_EXIT_NOK}"
    fi

    return "${__BASHIO_EXIT_OK}"
}

function rclone-backups {
    if [ "${RCLONE_ENABLED}" = true ] ; then
        cd /backup/ || exit
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
        bashio::log.info "Copying backup using rclone."
        if [ "$RCLONE_COPY" = true ] ; then
            if [ "$BACKUP_FRIENDLY_NAME" = true ] ; then
                bashio::log.debug "Copying ${SLUG}.tar to ${RCLONE_REMOTE_DIRECTORY}/${BACKUP_NAME}.tar"
                rclone copyto "${SLUG}.tar" "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}/${BACKUP_NAME}.tar"
                bashio::log.debug "Finished rclone copy"
            else
                bashio::log.debug "Copying ${SLUG}.tar to ${RCLONE_REMOTE_DIRECTORY}/${SLUG}.tar"
                rclone copy "${SLUG}.tar" "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}"
                bashio::log.debug "Finished rclone copy"
            fi
        fi
        if [ "${RCLONE_SYNC}" = true ] ; then
            bashio::log.info "Syncing Backups"
            rclone sync . "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}"
            bashio::log.info "Finished rclone sync"
        fi
        if [ "${RCLONE_RESTORE}" = true ] ; then
            DATEFORMAT=$(date +%F)
            RESTORENAME="restore-${DATEFORMAT}"
            mkdir -p "${RESTORENAME}"
            bashio::log.info "Restoring Backups to ${RESTORENAME}"
            rclone copyto "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY} ${RESTORENAME}/"
            bashio::log.info "Finished rclone restore"
        fi
    fi
}

function clone-to-remote {
    local ret="${__BASHIO_EXIT_OK}"

    copy-backup-to-remote || ret="${__BASHIO_EXIT_NOK}"
    rsync-folders || ret="${__BASHIO_EXIT_NOK}"
    rclone-backups || ret="${__BASHIO_EXIT_NOK}"

    return "${ret}"
}

function delete-local-backup {
    if bashio::var.equals "${BACKUP_KEEP_LOCAL}" "all"; then
        bashio::log.debug "Keep all backups."
        return "${__BASHIO_EXIT_OK}"
    fi

    if ! bashio::api.supervisor POST /backups/reload; then
        bashio::log.warning "Failed to reload backups!"
    fi

    if bashio::var.is_empty "${BACKUP_KEEP_LOCAL}"; then
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
        local backup_list=$(bashio::api.supervisor GET /backups)
        local last_date_to_keep=$(echo "${backup_list}" | jq ".backups[].date" | sort -r | \
            head -n "${BACKUP_KEEP_LOCAL}" | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

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
bashio::exit.ok
