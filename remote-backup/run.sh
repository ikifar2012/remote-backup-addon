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

function set-debug-level {
  # default log level according to bashio const.sh is INFO
  if bashio::var.true "${DEBUG}"; then    
    bashio::log.level "debug"
  fi
}

function add-ssh-key {
    if [ "${SSH_ENABLED}" = true ] || [ "${RSYNC_ENABLED}" = true ] ; then
        bashio::log.info "Adding SSH key"
        mkdir -p ~/.ssh
        cp "/ssl/${REMOTE_KEY}" "${HOME}"/.ssh/id_rsa
        chmod 600 "${HOME}/.ssh/id_rsa"
        bashio::log.debug "Adding key of remote host ${REMOTE_HOST} to known hosts."
        ssh-keyscan -t rsa ${REMOTE_HOST} >> ${HOME}/.ssh/known_hosts \
          || bashio::log.error "Failed to add ${REMOTE_HOST} host key"
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        (
            echo "Host remote"
            echo "    IdentityFile ${HOME}/.ssh/id_rsa"
            echo "    HostName ${REMOTE_HOST}"
            echo "    User ${REMOTE_USER}"
            echo "    Port ${REMOTE_PORT}"
            echo "    StrictHostKeyChecking no"
        if [ -n "${REMOTE_HOST_KEY_ALGORITHMS}" ] ; then
            echo "    HostKeyAlgorithms ${REMOTE_HOST_KEY_ALGORITHMS}"
        fi
        ) > "${HOME}/.ssh/config"

        chmod 600 "${HOME}/.ssh/config"
        chmod 644 "${HOME}/.ssh/id_rsa.pub"
        bashio::log.info "SSH key added"
    fi
}

function create-local-backup {
    # Bind variables
    local base_folders="addons/local homeassistant media share ssl"
    local installed_addons=$(bashio::supervisor.addons)
    local name="${BACKUP_CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"
    local data="{\"name\":\"${name}\" \"password\": \"${BACKUP_PASSWORD}\"}"

    if bashio::var.has_value "${BACKUP_EXCLUDE_ADDONS}" ] || bashio::var.has_value "${BACKUP_EXCLUDE_FOLDERS}"; then
        bashio::log.info "Creating partial backup: \"${name}\""

        local excluded_folders=$(echo "${BACKUP_EXCLUDE_FOLDERS}")
        local excluded_addons=$(echo "${BACKUP_EXCLUDE_ADDONS}")
        local unformatted_folders="${base_folders}"
        local unformatted_addons="${installed_addons}"
        
        if bashio::var.has_value "${excluded_folders}"; then
          bashio::log.warning "Excluded folder(s):\n ${excluded_folders}"
          for folder in ${excluded_folders} ; do
              unformatted_folders=$(echo "${unformatted_folders}" | sed -e "s/${folder}//g")
          done
        fi
        if bashio::var.has_value "${excluded_addons}"; then
          bashio::log.warning "Excluded addon(s):\n${excluded_addons}"
          for addon in ${excluded_addons} ; do
              unformatted_addons="$(echo "${unformatted_addons}" | sed -e "s/${addon}//g")"
          done
        fi

        local addons=$(echo ${unformatted_addons} | sed "s/ /\", \"/g")
        local folders=$(echo "${unformatted_folders}" | sed "s/ /\", \"/g" | sed "s/, \"\"//g")
        bashio::log.debug "Including folder(s) \"${folders}\""
        bashio::log.debug "Including addon(s) \"${addons}\""

        local data="$(echo $data | tr -d '}'), \"addons\": [\"${addons}\"], \"folders\": [\"${folders}\"]}" # append addon and folder set
        if ! SLUG=$(bashio::api.supervisor "POST" "/backups/new/partial" "${data}" ".slug"); then
            bashio::exit.nok "Error creating partial backup!"
        fi
    else
        bashio::log.info "Creating full backup: \"${name}\""

        if ! SLUG=$(bashio::api.supervisor "POST" "/backups/new/full" "${data}" ".slug"); then
            bashio::exit.nok "Error creating full backup!"
        fi

    fi

    bashio::log.info "Backup created: ${SLUG}"
    return "${__BASHIO_EXIT_OK}"
}

function copy-backup-to-remote {

    if [ "${SSH_ENABLED}" = true ] ; then
        cd /backup/ || exit
            bashio::log.info "Copying ${SLUG}.tar to ${SSH_REMOTE_DIRECTORY} on ${REMOTE_HOST} using SCP"
            scp -F "${HOME}/.ssh/config" "${SLUG}.tar" remote:"${SSH_REMOTE_DIRECTORY}/"
            bashio::log.info "Backup copied to ${SSH_REMOTE_DIRECTORY}/${SLUG}.tar on ${REMOTE_HOST}"

        if [ "${BACKUP_FRIENDLY_NAME}" = true ] ; then
            bashio::log.notice "Renaming ${SLUG}.tar to ${name}.tar"
            ssh remote "mv \"${SSH_REMOTE_DIRECTORY}/${SLUG}.tar\" \"${SSH_REMOTE_DIRECTORY}/${name}.tar\""
            bashio::log.info "Backup renamed to ${SSH_REMOTE_DIRECTORY}/${name}.tar on ${REMOTE_HOST}"
        fi
    bashio::log.info "SCP complete"
    fi
}

function rsync_folders {
    if bashio::var.false "${RSYNC_ENABLED}"; then
        bashio::log.debug "rsync disabled."
        return
    fi

    local FOLDERS="/config /addons /backup /share /ssl" # put directories without trailing slash
    local RSYNC_URL="${REMOTE_USER}@${REMOTE_HOST}:${RSYNC_ROOTFOLDER}"

    bashio::log.info "Starting rsync"
    if bashio::var.true "${DEBUG}"; then    
        local FLAGS='-av'
    else
        local FLAGS='-a'
    fi

    echo "${RSYNC_EXCLUDE}" > /tmp/rsync_exclude.txt
    if bashio::var.has_value "${RSYNC_EXCLUDE}"; then   
        bashio::log.warning "File patterns that have been excluded:\n${RSYNC_EXCLUDE}"
    fi

    bashio::log.debug "Syncing ${FOLDERS}"
    sshpass -p "${REMOTE_PASSWORD}" \
      rsync ${FLAGS} --port ${REMOTE_PORT} --exclude-from='/tmp/rsync_exclude.txt' ${FOLDERS} "${RSYNC_URL}/" --delete \
      || bashio::log.fatal "Error syncing folder(s) ${FOLDERS}"

    bashio::log.info "Finished rsync"
}

function rclone_backups {
    if [ "${RCLONE_ENABLED}" = true ] ; then
        cd /backup/ || exit
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
        bashio::log.info "Starting rclone"
        if [ "$RCLONE_COPY" = true ] ; then
            if [ "$BACKUP_FRIENDLY_NAME" = true ] ; then
                bashio::log.debug "Copying ${SLUG}.tar to ${RCLONE_REMOTE_DIRECTORY}/${name}.tar"
                rclone copyto "${SLUG}.tar" "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}/${name}".tar
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


function delete-local-backup {

    ha backups reload

    if [[ "${BACKUP_KEEP_LOCAL}" == "all" ]]; then
        :
    elif [[ -z "${BACKUP_KEEP_LOCAL}" ]]; then
        bashio::log.warning "Deleting local backup: ${SLUG}"
        ha backups remove "${SLUG}"
    else

        last_date_to_keep=$(ha backups list --raw-json | jq .data.backups[].date | sort -r | \
            head -n "${BACKUP_KEEP_LOCAL}" | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

        ha backups list --raw-json | jq -c .data.backups[] | while read -r backup; do
            if [[ $(echo "${backup}" | jq .date | xargs date -D "%Y-%m-%dT%T" +%s --date ) -lt ${last_date_to_keep} ]]; then
                bashio::log.warning "Deleting local backup: $(echo "${backup}" | jq -r .slug)"
                ha backups remove "$(echo "${backup}" | jq -r .slug)"
                bashio::log.info "Finished deleting local backup: $(echo "${backup}" | jq -r .slug)"
            fi
        done

    fi
}

set-debug-level
add-ssh-key
create-local-backup
copy-backup-to-remote
rsync_folders
rclone_backups
delete-local-backup

bashio::log.info "Backup process done!"
bashio::exit.ok
