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
    FOLDERS=""
    ADDONS=""
    BASE_FOLDERS="addons/local homeassistant media share ssl"
    INSTALLED_ADDONS=$(bashio::supervisor.addons)
    name="${BACKUP_CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"
    bashio::log.info "Creating local backup: \"${name}\""
    if [ -n "${BACKUP_EXCLUDE_ADDONS}" ] || [ -n "${BACKUP_EXCLUDE_FOLDERS}" ] ; then
        EXCLUDED_FOLDERS=$(echo "${BACKUP_EXCLUDE_FOLDERS}")
        EXCLUDED_ADDONS=$(echo "${BACKUP_EXCLUDE_ADDONS}")
        UNFORMATTED_FOLDERS="${BASE_FOLDERS}"
        UNFORMATTED_ADDONS="${INSTALLED_ADDONS}"
    if [ -n "${EXCLUDED_FOLDERS}" ] ; then
        bashio::log.warning "Excluded folders:\n ${EXCLUDED_FOLDERS}"
        for folder in ${EXCLUDED_FOLDERS} ; do
            UNFORMATTED_FOLDERS=$(echo "${UNFORMATTED_FOLDERS}" | sed -e "s/${folder}//g")
        done
    fi
    if [ -n "${EXCLUDED_ADDONS}" ] ; then
        bashio::log.warning "Excluded addons:\n${EXCLUDED_ADDONS}"
        for addon in ${EXCLUDED_ADDONS} ; do
            UNFORMATTED_ADDONS="$(echo "${UNFORMATTED_ADDONS}" | sed -e "s/${addon}//g")"
        done
    fi
    if [ -n "${UNFORMATTED_ADDONS}" ] && [ -n "${UNFORMATTED_FOLDERS}" ] ; then
        for addon in ${UNFORMATTED_ADDONS} ; do
            ADDONS="${ADDONS}--addons ${addon} "
        done
        for folder in ${UNFORMATTED_FOLDERS} ; do
            FOLDERS="${FOLDERS}--folders ${folder} "
        done
        fi
        bashio::log.info "Creating partial backup"
        bashio::log.debug "Including ${FOLDERS} and ${ADDONS}"
        slug=$(ha backups new --raw-json --name="${name}" ${ADDONS} ${FOLDERS} --password="${BACKUP_PASSWORD}" | jq --raw-output '.data.slug')
    else
        bashio::log.info "Creating full backup"
        slug=$(ha backups new --raw-json --name="${name}" --password="${BACKUP_PASSWORD}" | jq --raw-output '.data.slug')
    fi
    bashio::log.info "Backup created: ${slug}"
}

function copy-backup-to-remote {

    if [ "${SSH_ENABLED}" = true ] ; then
        cd /backup/ || exit
            bashio::log.info "Copying ${slug}.tar to ${SSH_REMOTE_DIRECTORY} on ${REMOTE_HOST} using SCP"
            scp -F "${HOME}/.ssh/config" "${slug}.tar" remote:"${SSH_REMOTE_DIRECTORY}/"
            bashio::log.info "Backup copied to ${SSH_REMOTE_DIRECTORY}/${slug}.tar on ${REMOTE_HOST}"

        if [ "${BACKUP_FRIENDLY_NAME}" = true ] ; then
            bashio::log.notice "Renaming ${slug}.tar to ${name}.tar"
            ssh remote "mv \"${SSH_REMOTE_DIRECTORY}/${slug}.tar\" \"${SSH_REMOTE_DIRECTORY}/${name}.tar\""
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
                bashio::log.debug "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${name}.tar"
                rclone copyto "${slug}.tar" "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}/${name}".tar
                bashio::log.debug "Finished rclone copy"
            else
                bashio::log.debug "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${slug}.tar"
                rclone copy "${slug}.tar" "${REMOTE_HOST}:${RCLONE_REMOTE_DIRECTORY}"
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
        bashio::log.warning "Deleting local backup: ${slug}"
        ha backups remove "${slug}"
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
