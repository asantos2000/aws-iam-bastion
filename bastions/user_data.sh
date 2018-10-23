##
## Environment file
## Choose a key with just IAMReadOnlyAccess
##
cat <<"__EOF__" > /etc/environment
LC_ALL=en_US.UTF-8
LANG=en_US.UTF-8
AWS_ACCESS_KEY_ID=XXXXXXXXXX
AWS_SECRET_ACCESS_KEY=XXXXXXXXXXX/XXXXXXXXXXX
AWS_DEFAULT_REGION=us-west-2
AWS_DEFAULT_OUTPUT=text

__EOF__
chmod 644 /etc/environment

##
## authorized_keys_command file
##
## IAM users need to belongs to the my-admin group
cat <<"__EOF__" > /opt/sync_iam_local_users.sh
#!/bin/bash

LOCAL_MARKER_GROUP=my-admin
SUDOERS_GROUPS=sudo
IAM_AUTHORIZED_GROUPS=my-admin

function clean_iam_username() {
    local clean_username="${1}"
    clean_username=${clean_username//"+"/".plus."}
    clean_username=${clean_username//"="/".equal."}
    clean_username=${clean_username//","/".comma."}
    clean_username=${clean_username//"@"/".at."}
    echo "${clean_username}"
}

# Get previously synced users
function get_local_users() {
    /usr/bin/getent group ${LOCAL_MARKER_GROUP} \
        | cut -d : -f4- \
        | sed "s/,/ /g"
}

function get_sudoers_users() {
    local group

    [[ -z "${SUDOERS_GROUPS}" ]] || [[ "${SUDOERS_GROUPS}" == "##ALL##" ]] ||
        for group in $(echo "${SUDOERS_GROUPS}" | tr "," " "); do
            aws iam get-group \
                --group-name "${group}" \
                --query "Users[].[UserName]" \
                --output text
        done
}

function delete_local_user() {
    # First, make sure no new sessions can be started
    /usr/sbin/usermod -L -s /sbin/nologin "${1}" || true
    # ask nicely and give them some time to shutdown
    /usr/bin/pkill -15 -u "${1}" || true
    sleep 5
    # Dont want to close nicely? DIE!
    /usr/bin/pkill -9 -u "${1}" || true
    sleep 1
    # Remove account now that all processes for the user are gone
    /usr/sbin/userdel -f -r "${1}"
    log "Deleted user ${1}"
}

# Get all IAM users (optionally limited by IAM groups)
function get_iam_users() {
    local group
    if [ -z "${IAM_AUTHORIZED_GROUPS}" ]
    then
        aws iam list-users \
            --query "Users[].[UserName]" \
            --output text \
        | sed "s/\r//g"
    else
        for group in $(echo ${IAM_AUTHORIZED_GROUPS} | tr "," " "); do
            aws iam get-group \
                --group-name "${group}" \
                --query "Users[].[UserName]" \
                --output text \
            | sed "s/\r//g"
        done
    fi
}

# Run all found iam users through clean_iam_username
function get_clean_iam_users() {
    local raw_username

    for raw_username in $(get_iam_users); do
        clean_iam_username "${raw_username}" | sed "s/\r//g"
    done
}

function create_or_update_local_user() {
    local SaveUserName="${1}"
    local localusergroups="${LOCAL_MARKER_GROUP}"

    if id -u "$SaveUserName" >/dev/null 2>&1; then
        log "$SaveUserName exists"
        log "updating public key for $SaveUserName"
        authorized_keys "$SaveUserName"
        log "public key updated"
    else
        #SaveUserFileName=$(echo "$SaveUserName" | tr "." " ")
        log "adding user $SaveUserName"
        log "creating new user ${SaveUserName}"
        /usr/sbin/useradd --user-group --create-home --shell /bin/bash "$SaveUserName"
        /bin/chown -R "${SaveUserName}:${SaveUserName}" "$(eval echo ~$SaveUserName)"
        log "adding $SaveUserName to $localusergroups"
        /usr/sbin/usermod -aG "${localusergroups}" "${SaveUserName}"
        log "authorizing public key for $SaveUserName"
        authorized_keys "$SaveUserName"
    fi
}

function authorized_keys() {
    local SaveUserName="${1}"

    aws iam list-ssh-public-keys --user-name "$SaveUserName" --query "SSHPublicKeys[?Status == 'Active'].[SSHPublicKeyId]" --output text | while read KeyId; do
        Key=$(aws iam get-ssh-public-key --user-name "$SaveUserName" --ssh-public-key-id "$KeyId" --encoding SSH --query "SSHPublicKey.SSHPublicKeyBody" --output text)
        if [ ! -d "/home/$SaveUserName/.ssh" ]; then
            mkdir "/home/$SaveUserName/.ssh"
            chmod 700 "/home/$SaveUserName/.ssh"
            touch "/home/$SaveUserName/.ssh/authorized_keys"
            chmod 600 "/home/$SaveUserName/.ssh/authorized_keys"
            chown -R "$SaveUserName" "/home/$SaveUserName"
        fi
        #echo "$Key" > "/home/$SaveUserName"/.ssh/authorized_keys
        log "adding public key for user $SaveUserName"
        echo "$Key" > "/home/$SaveUserName/.ssh/authorized_keys"
    done
}

function log() {
    /usr/bin/logger -i -t sync-iam-user "$@"
}

##
## Main
##

log "Starting..."

iam_users=$(get_clean_iam_users | sort | uniq)
local_users=$(get_local_users | sort | uniq)
intersection=$(echo ${local_users} ${iam_users} | tr " " "\n" | sort | uniq -D | uniq)
removed_users=$(echo ${local_users} ${intersection} | tr " " "\n" | sort | uniq -u)

# echo "iam_users: $iam_users"
# echo "local_users: $local_users"
# echo "intersection: $intersection"
# echo "removed_users: $removed_users"

# Remove users
for user in ${removed_users}; do
    delete_local_user "${user}"
done

# Create users or update keys
for user in ${iam_users}; do
    create_or_update_local_user "${user}"
done

log  "Finished..."

__EOF__
chmod 755 /opt/sync_iam_local_users.sh

##
## Configure crontab
##
echo "SHELL=/bin/bash"  >> /tmp/mycron
echo 'PATH=/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin' >> /tmp/mycron
echo '*/30 * * * * /opt/sync_iam_local_users.sh' >> /tmp/mycron
crontab /tmp/mycron
rm /tmp/mycron


##
## Password less
##
echo "ALL ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/100-bastion"

##
## Add group st-admin
##
groupadd st-admin