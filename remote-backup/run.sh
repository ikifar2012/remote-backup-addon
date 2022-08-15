#!/command/with-contenv bashio
# shellcheck shell=bash
# parse inputs from options
DEBUG=$(bashio::config 'debug')
SSH_ENABLED=$(bashio::config "ssh_enabled")
FRIENDLY_NAME=$(bashio::config "friendly_name")
CUSTOM_PREFIX=$(bashio::config "custom_prefix")
SSH_HOST=$(bashio::config "ssh_host")
SSH_PORT=$(bashio::config "ssh_port")
SSH_USER=$(bashio::config "ssh_user")
SSH_KEY=$(bashio::config "ssh_key")
SSH_HOST_KEY_ALGORITHMS=$(bashio::config "ssh_host_key_algorithms")
EXCLUDE_FOLDERS=$(bashio::config "exclude_folders")
EXCLUDE_ADDONS=$(bashio::config "exclude_addons")
REMOTE_DIRECTORY=$(bashio::config "remote_directory")
ZIP_PASSWORD=$(bashio::config 'zip_password')
KEEP_LOCAL_BACKUP=$(bashio::config 'keep_local_backup')

RSYNC_ENABLED=$(bashio::config "rsync_enabled")
RSYNC_VERBOSE=$(bashio::config "rsync_verbose")
RSYNC_HOST=$(bashio::config "rsync_host")
RSYNC_ROOTFOLDER=$(bashio::config "rsync_rootfolder")
RSYNC_USER=$(bashio::config "rsync_user")
RSYNC_EXCLUDE=$(bashio::config "rsync_exclude")
RSYNC_PASSWORD=$(bashio::config "rsync_password")
RCLONE_ENABLED=$(bashio::config "rclone_enabled")
RCLONE_COPY=$(bashio::config "rclone_copy")
RCLONE_SYNC=$(bashio::config "rclone_sync")
RCLONE_RESTORE=$(bashio::config "rclone_restore")
RCLONE_REMOTE=$(bashio::config "rclone_remote")
RCLONE_REMOTE_DIRECTORY=$(bashio::config "rclone_remote_directory")

# create variables
SSH_ID="/ssl/${SSH_KEY}"
SSH_ID=$(echo -n "${SSH_ID}")

function set-debug-level {
  # default log level according to bashio const.sh is INFO
  if [ "${DEBUG}" = true ] ; then
    bashio::log.level "debug"
  fi
}

function add-ssh-key {
    if [ "${SSH_ENABLED}" = true ] ; then
        bashio::log.info "Adding SSH key"
        mkdir -p ~/.ssh
        cp "${SSH_ID}" "${HOME}"/.ssh/id_rsa
        chmod 600 "${HOME}/.ssh/id_rsa"
        ssh-keygen -y -f ~/.ssh/id_rsa > ~/.ssh/id_rsa.pub
        (
            echo "Host remote"
            echo "    IdentityFile ${HOME}/.ssh/id_rsa"
            echo "    HostName ${SSH_HOST}"
            echo "    User ${SSH_USER}"
            echo "    Port ${SSH_PORT}"
            echo "    StrictHostKeyChecking no"
        if [ -n "${SSH_HOST_KEY_ALGORITHMS}" ] ; then
            echo "    HostKeyAlgorithms ${SSH_HOST_KEY_ALGORITHMS}"
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
    name="${CUSTOM_PREFIX} $(date +'%Y-%m-%d %H-%M')"
    bashio::log.info "Creating local backup: \"${name}\""
    if [ -n "${EXCLUDE_ADDONS}" ] || [ -n "${EXCLUDE_FOLDERS}" ] ; then
        EXCLUDED_FOLDERS=$(echo "${EXCLUDE_FOLDERS}" | tr ',' '\n')
        EXCLUDED_ADDONS=$(echo "${EXCLUDE_ADDONS}" | tr ',' '\n')
        UNFORMATTED_FOLDERS="${BASE_FOLDERS}"
        UNFORMATTED_ADDONS="${INSTALLED_ADDONS}"
    if [ -n "${EXCLUDED_FOLDERS}" ] ; then
        bashio::log.warning "Excluded folders: \n ${EXCLUDED_FOLDERS}"
        for folder in ${EXCLUDED_FOLDERS} ; do
            UNFORMATTED_FOLDERS=$(echo "${UNFORMATTED_FOLDERS}" | sed -e "s/${folder}//g")
        done
    fi
    if [ -n "${EXCLUDED_ADDONS}" ] ; then
        bashio::log.warning "Excluded addons: \n ${EXCLUDED_ADDONS}"
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
        slug=$(ha backups new --raw-json --name="${name}" ${ADDONS} ${FOLDERS} | jq --raw-output '.data.slug')
    else
        bashio::log.info "Creating full backup"
        slug=$(ha backups new --raw-json --name="${name}" | jq --raw-output '.data.slug')
    fi
    bashio::log.info "Backup created: ${slug}"
}

function copy-backup-to-remote {

    if [ "${SSH_ENABLED}" = true ] ; then
        cd /backup/ || exit
        if [[ -z "${ZIP_PASSWORD}" ]]; then
            bashio::log.info "Copying ${slug}.tar to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            scp -F "${HOME}/.ssh/config" "${slug}.tar" remote:"${REMOTE_DIRECTORY}"
            bashio::log.info "Backup copied to ${REMOTE_DIRECTORY}/${slug}.tar on ${SSH_HOST}"
        else
            bashio::log.info "Copying password-protected ${slug}.zip to ${REMOTE_DIRECTORY} on ${SSH_HOST} using SCP"
            zip -P "$ZIP_PASSWORD" "${slug}.zip" "${slug}".tar
            scp -F "${HOME}/.ssh/config" "${slug}.zip" remote:"${REMOTE_DIRECTORY}" && rm "${slug}.zip"
            bashio::log.info "Backup copied to ${REMOTE_DIRECTORY}/${slug}.zip on ${SSH_HOST}"
        fi
        if [ "${FRIENDLY_NAME}" = true ] ; then
            if [[ -z "${ZIP_PASSWORD}" ]]; then
                bashio::log.notice "Renaming ${slug}.tar to ${name}.tar"
                ssh remote "mv \"${REMOTE_DIRECTORY}/${slug}.tar\" \"${REMOTE_DIRECTORY}/${name}.tar\""
                bashio::log.info "Backup renamed to ${REMOTE_DIRECTORY}/${name}.tar on ${SSH_HOST}"
            else
                bashio::log.info "Renaming ${slug}.zip to ${name}.zip"
                ssh remote "mv \"${REMOTE_DIRECTORY}/${slug}.zip\" \"${REMOTE_DIRECTORY}/${name}.zip\""
                bashio::log.info "Backup renamed to ${REMOTE_DIRECTORY}/${name}.zip on ${SSH_HOST}"
            fi
        fi
    bashio::log.info "SCP complete"
    fi
}

function rsync_folders {

    if [ "${RSYNC_ENABLED}" = true ] ; then
        rsyncurl="${RSYNC_USER}@${RSYNC_HOST}:${RSYNC_ROOTFOLDER}"
        if [ "${RSYNC_VERBOSE}" = true ] ; then
            FLAGS='-av'
        else
            FLAGS='-a'
        fi
        if [ -z "${RSYNC_EXCLUDE}" ]; then
            bashio::log.debug "Syncing /config"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude '*.db-shm' --exclude '*.db-wal' --exclude '*.db' /config/ "${rsyncurl}/config/" --delete
            bashio::log.debug "/config sync complete"

            bashio::log.debug "Syncing /addons"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /addons/ "${rsyncurl}/addons/" --delete
            bashio::log.debug "/addons sync complete"

            bashio::log.debug "Syncing /backup"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /backup/ "${rsyncurl}/backup/" --delete
            bashio::log.debug "/backup sync complete"

            bashio::log.debug "Syncing /share"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /share/ "${rsyncurl}/share/" --delete
            bashio::log.debug "/share sync complete"

            bashio::log.debug "Syncing /ssl"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} /ssl/ "${rsyncurl}/ssl/" --delete
            bashio::log.debug "/ssl sync complete"
        else
            echo "${RSYNC_EXCLUDE}" | tr -s ", " "\n" > /tmp/rsync_exclude.txt
            bashio::log.warning "Files you excluded will be displayed below:"
            cat /tmp/rsync_exclude.txt
            bashio::log.debug "Starting rsync"
            bashio::log.debug "Syncing /config"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' --exclude '*.db-shm' --exclude '*.db-wal' --exclude '*.db' /config/ "${rsyncurl}/config/" --delete
            bashio::log.debug "/config sync complete"

            bashio::log.debug "Syncing /addons"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /addons/ "${rsyncurl}/addons/" --delete
            bashio::log.debug "/addons sync complete"

            bashio::log.debug "Syncing /backup"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /backup/ "${rsyncurl}/backup/" --delete
            bashio::log.debug "/backup sync complete"

            bashio::log.debug "Syncing /share"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /share/ "${rsyncurl}/share/" --delete
            bashio::log.debug "/share sync complete"

            bashio::log.debug "Syncing /ssl"
             sshpass -p "${RSYNC_PASSWORD}" rsync ${FLAGS} --exclude-from='/tmp/rsync_exclude.txt' /ssl/ "${rsyncurl}/ssl/" --delete
            bashio::log.debug "/ssl sync complete"
        fi
        bashio::log.info "Finished rsync"
    fi
}

function rclone_backups {
    if [ "${RCLONE_ENABLED}" = true ] ; then
        cd /backup/ || exit
        mkdir -p ~/.config/rclone/
        cp -a /ssl/rclone.conf ~/.config/rclone/rclone.conf
        bashio::log.info "Starting rclone"
        if [ "$RCLONE_COPY" = true ] ; then
            if [ "$FRIENDLY_NAME" = true ] ; then
                if [[ -z $ZIP_PASSWORD  ]]; then
                    bashio::log.debug "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${name}.tar"
                    rclone copyto "${slug}.tar" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/${name}".tar
                    bashio::log.debug "Finished rclone copy"
                else
                    bashio::log.debug "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${name}.zip"
                    rclone copyto "${slug}.zip" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}/${name}".zip
                    bashio::log.debug "Finished rclone copy"
                fi
            else
                if [[ -z "${ZIP_PASSWORD}"  ]]; then
                    bashio::log.debug "Copying ${slug}.tar to ${RCLONE_REMOTE_DIRECTORY}/${slug}.tar"
                    rclone copy "${slug}.tar" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
                    bashio::log.debug "Finished rclone copy"
                else
                    bashio::log.debug "Copying ${slug}.zip to ${RCLONE_REMOTE_DIRECTORY}/${slug}.zip"
                    rclone copy "${slug}.zip" "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
                    bashio::log.debug "Finished rclone copy"
                fi
            fi
        fi
        if [ "${RCLONE_SYNC}" = true ] ; then
            bashio::log.info "Syncing Backups"
            rclone sync . "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY}"
            bashio::log.info "Finished rclone sync"
        fi
        if [ "${RCLONE_RESTORE}" = true ] ; then
            DATEFORMAT=$(date +%F)
            RESTORENAME="restore-${DATEFORMAT}"
            mkdir -p "${RESTORENAME}"
            bashio::log.info "Restoring Backups to ${RESTORENAME}"
            rclone copyto "${RCLONE_REMOTE}:${RCLONE_REMOTE_DIRECTORY} ${RESTORENAME}/"
            bashio::log.info "Finished rclone restore"
        fi
    fi
}


function delete-local-backup {

    ha backups reload

    if [[ "${KEEP_LOCAL_BACKUP}" == "all" ]]; then
        :
    elif [[ -z "${KEEP_LOCAL_BACKUP}" ]]; then
        bashio::log.warning "Deleting local backup: ${slug}"
        ha backups remove "${slug}"
    else

        last_date_to_keep=$(ha backups list --raw-json | jq .data.backups[].date | sort -r | \
            head -n "${KEEP_LOCAL_BACKUP}" | tail -n 1 | xargs date -D "%Y-%m-%dT%T" +%s --date )

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
exit 0
