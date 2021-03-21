#!/bin/bash -eu

if [ "${BASH_SOURCE[0]}" != "$0" ]
then
  echo "${BASH_SOURCE[0]} must be executed, not sourced"
  return 1 # shouldn't use exit when sourced
fi

function log_progress () {
  if declare -F setup_progress > /dev/null
  then
    setup_progress "configure: $1"
  fi
  echo "configure: $1"
}

if [ "${FLOCKED:-}" != "$0" ]
then
  PARENT="$(ps -o comm= $PPID)"
  if [ "$PARENT" != "setup-teslausb" ]
  then
    log_progress "STOP: $0 must be called from setup-teslausb: $PARENT"
    exit 1
  fi

  if FLOCKED="$0" flock -en -E 99 "$0" "$0" "$@" || case "$?" in
  99) echo already running
      exit 99
      ;;
  *)  exit $?
      ;;
  esac
  then
    # success
    exit 0
  fi
fi

ARCHIVE_SYSTEM=${ARCHIVE_SYSTEM:-none}

function check_variable () {
    local var_name="$1"
    if [ -z "${!var_name+x}" ]
    then
        log_progress "STOP: Define the variable $var_name like this: export $var_name=value"
        exit 1
    fi
}

function check_archive_configs () {
    log_progress "Checking archive configs: "

    case "$ARCHIVE_SYSTEM" in
        rsync)
            check_variable "RSYNC_USER"
            check_variable "RSYNC_SERVER"
            check_variable "RSYNC_PATH"
            export ARCHIVE_SERVER="$RSYNC_SERVER"
            ;;
        rclone)
            check_variable "RCLONE_DRIVE"
            check_variable "RCLONE_PATH"
            export ARCHIVE_SERVER="8.8.8.8" # since it's a cloud hosted drive we'll just set this to google dns
            ;;
        cifs)
            check_variable "SHARE_NAME"
            check_variable "SHARE_USER"
            check_variable "SHARE_PASSWORD"
            check_variable "ARCHIVE_SERVER"
            ;;
        none)
            export ARCHIVE_SERVER=localhost
            ;;
        *)
            log_progress "STOP: Unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac

    log_progress "done"
}

function get_archive_module () {

    case "$ARCHIVE_SYSTEM" in
        rsync)
            echo "run/rsync_archive"
            ;;
        rclone)
            echo "run/rclone_archive"
            ;;
        cifs)
            echo "run/cifs_archive"
            ;;
        none)
            echo "run/none_archive"
            ;;
        *)
            log_progress "Internal error: Attempting to configure unrecognized archive system: $ARCHIVE_SYSTEM"
            exit 1
            ;;
    esac
}

function install_and_configure_tesla_api () {
  # Install the tesla_api.py script only if the user provided credentials for its use.

  if [ -e /root/bin/tesla_api.py ]
  then
    # if tesla_api.py already exists, update it
    log_progress "Updating tesla_api.py"
    get_script /root/bin tesla_api.py run
    # check if the json file needs to be updated
    readonly json=/mutable/tesla_api.json
    if [ -e $json ] && ! grep -q '"id"' $json
    then
      log_progress "Updating tesla_api.py config file"
      sed -i 's/"vehicle_id"/"id"/' $json
      sed -i 's/"$/",\n  "vehicle_id": 0/' $json
      # Call script to fill in the empty vehicle_id field
      if ! /root/bin/tesla_api.py list_vehicles
      then
        log_progress "tesla_api.py config update failed"
      fi
    fi
  elif [[ ( -n "${TESLA_EMAIL:+x}" && -n "${TESLA_PASSWORD:+x}" ) || ( -n "${TESLA_ACCESS_TOKEN:+x}" && -n "${TESLA_REFRESH_TOKEN:+x}" ) ]]
  then
    log_progress "Installing tesla_api.py"
    get_script /root/bin tesla_api.py run
    # Perform the initial authentication
    mount /mutable || log_progress "Failed to mount /mutable"
    if ! /root/bin/tesla_api.py list_vehicles
    then
      log_progress "tesla_api.py setup failed"
    fi
  else
    log_progress "Skipping tesla_api.py install because no credentials were provided"
  fi
}

function install_archive_scripts () {
  local install_path="$1"
  local archive_module="$2"

  log_progress "Installing base archive scripts into $install_path"
  get_script "$install_path" archiveloop run
  get_script "$install_path" waitforidle run
  get_script "$install_path" remountfs_rw run
  install_and_configure_tesla_api
  log_progress "Installing archive module scripts"
  get_script /tmp verify-and-configure-archive.sh "$archive_module"
  get_script /tmp write-archive-configs-to.sh "$archive_module"
  get_script "$install_path" archive-clips.sh "$archive_module"
  get_script "$install_path" connect-archive.sh "$archive_module"
  get_script "$install_path" disconnect-archive.sh "$archive_module"
  get_script "$install_path" archive-is-reachable.sh "$archive_module"
  # shellcheck disable=SC2154
  if [ -n "${musicsharename:+x}" ] && grep cifs <<< "$archive_module"
  then
    get_script "$install_path" copy-music.sh "$archive_module"
  fi
}

function install_python3_pip () {
  if ! command -v pip3 &> /dev/null
  then
    setup_progress "Installing support for python packages..."
    apt-get --assume-yes install python3-pip
  fi
}

function install_sns_packages () {
  install_python3_pip
  setup_progress "Installing sns python packages..."
  pip3 install boto3
}

function install_matrix_packages () {
  install_python3_pip
  setup_progress "Installing matrix python packages..."
  apt-get --assume-yes install python3-gi
  pip3 install matrix_client
  # matrixcli is currently not available via pip
  curlwrapper -o /root/bin/matrixcli https://raw.githubusercontent.com/saadrushd/matrixcli/23f29933746c38442a5b0f0d94520b5f544a90a4/matrixcli
}

function check_pushover_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${pushover_enabled+x}" ]
    then
        if [ -z "${pushover_user_key+x}" ] || [ -z "${pushover_app_key+x}"  ]
        then
            log_progress "STOP: You're trying to setup Pushover but didn't provide your User and/or App key."
            log_progress "Define the variables like this:"
            log_progress "export pushover_user_key=put_your_userkey_here"
            log_progress "export pushover_app_key=put_your_appkey_here"
            exit 1
        elif [ "${pushover_user_key}" = "put_your_userkey_here" ] || [  "${pushover_app_key}" = "put_your_appkey_here" ]
        then
            log_progress "STOP: You're trying to setup Pushover, but didn't replace the default User and App key values."
            exit 1
        fi
    fi
}

function check_gotify_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${gotify_enabled+x}" ]
    then
        if [ -z "${gotify_domain+x}" ] || [ -z "${gotify_app_token+x}"  ]
        then
            log_progress "STOP: You're trying to setup Gotify but didn't provide your Domain and/or App token."
            log_progress "Define the variables like this:"
            log_progress "export gotify_domain=https://gotify.domain.com"
            log_progress "export gotify_app_token=put_your_token_here"
            exit 1
        elif [ "${gotify_domain}" = "https://gotify.domain.com" ] || [  "${gotify_app_token}" = "put_your_token_here" ]
        then
            log_progress "STOP: You're trying to setup Gotify, but didn't replace the default Domain and/or App token values."
            exit 1
        fi
    fi
}

function check_ifttt_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${ifttt_enabled+x}" ]
    then
        if [ -z "${ifttt_event_name+x}" ] || [ -z "${ifttt_key+x}"  ]
        then
            log_progress "STOP: You're trying to setup IFTTT but didn't provide your Event Name and/or key."
            log_progress "Define the variables like this:"
            log_progress "export ifttt_event_name=put_your_event_name_here"
            log_progress "export ifttt_key=put_your_key_here"
            exit 1
        elif [ "${ifttt_event_name}" = "put_your_event_name_here" ] || [  "${ifttt_key}" = "put_your_key_here" ]
        then
            log_progress "STOP: You're trying to setup IFTTT, but didn't replace the default Event Name and/or key values."
            exit 1
        fi
    fi
}

function check_webhook_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${WEBHOOK_ENABLED+x}" ]
    then
        if [ -z "${WEBHOOK_URL+x}"  ]
        then
            log_progress "STOP: You're trying to setup a Webhook but didn't provide your webhook url."
            log_progress "Define the variable like this:"
            log_progress "export WEBHOOK_URL=http://domain/path/"
            exit 1
        elif [ "${WEBHOOK_URL}" = "http://domain/path/" ]
        then
            log_progress "STOP: You're trying to setup a Webhook, but didn't replace the default url."
            exit 1
        fi
    fi
}

function check_matrix_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${MATRIX_ENABLED+x}" ]
    then
        if [ -z "${MATRIX_SERVER_URL+x}"  ] || [ -z "${MATRIX_USERNAME+x}"  ] || [ -z "${MATRIX_PASSWORD+x}"  ] || [ -z "${MATRIX_ROOM+x}"  ]
        then
            log_progress "STOP: You're trying to setup Matrix but didn't provide your server URL, username, password or room."
            log_progress "Define the variable like this:"
            log_progress "export MATRIX_SERVER_URL=https://matrix.org/"
            log_progress "export MATRIX_USERNAME=put_your_matrix_username_here"
            log_progress "export MATRIX_PASSWORD='put_your_matrix_password_here'"
            log_progress "export MATRIX_ROOM='put_the_matrix_target_room_id_here'"
            exit 1
        elif [ "${MATRIX_USERNAME}" = "put_your_matrix_username_here" ] || [ "${MATRIX_PASSWORD}" = "put_your_matrix_password_here" ] ||[ "${MATRIX_ROOM}" = "put_the_matrix_target_room_id_here" ]
        then
            log_progress "STOP: You're trying to setup Matrix, but didn't replace the default username, password or target room."
            exit 1
        fi
    fi
}

function check_sns_configuration () {
    # shellcheck disable=SC2154
    if [ -n "${sns_enabled+x}" ]
    then
        if [ -z "${aws_access_key_id:+x}" ] || [ -z "${aws_secret_key:+x}" ] || [ -z "${aws_sns_topic_arn:+x}" ]
        then
            echo "STOP: You're trying to setup AWS SNS but didn't provide your User and/or App key and/or topic ARN."
            echo "Define the variables like this:"
            echo "export aws_access_key_id=put_your_accesskeyid_here"
            echo "export aws_secret_key=put_your_secretkey_here"
            echo "export aws_sns_topic_arn=put_your_sns_topicarn_here"
            exit 1
        elif [ "${aws_access_key_id}" = "put_your_accesskeyid_here" ] || [ "${aws_secret_key}" = "put_your_secretkey_here" ] || [ "${aws_sns_topic_arn}" = "put_your_sns_topicarn_here" ]
        then
            echo "STOP: You're trying to setup SNS, but didn't replace the default values."
            exit 1
        fi
    fi
}

function check_telegram_configuration () {
    if [ -n "${TELEGRAM_ENABLED+x}" ]
    then
        if [ -z "${TELEGRAM_BOT_TOKEN+x}"  ] || [ -z "${TELEGRAM_CHAT_ID:+x}" ]
        then
            log_progress "STOP: You're trying to setup Telegram but didn't provide your Bot Token or Chat id."
            echo "Define the variables in config file like this:"
            echo "export TELEGRAM_CHAT_ID=123456789"
            echo "export TELEGRAM_BOT_TOKEN=bot123456789:abcdefghijklmnopqrstuvqxyz987654321"
            exit 1
        elif [ "${TELEGRAM_BOT_TOKEN}" = "bot123456789:abcdefghijklmnopqrstuvqxyz987654321" ] || [ "${TELEGRAM_CHAT_ID}" = "123456789" ]
        then
            log_progress "STOP: You're trying to setup Telegram, but didn't replace the default values."
            exit 1
        fi
    fi
}

function configure_pushover () {
    if [ -n "${pushover_enabled+x}" ]
    then
        log_progress "Enabling pushover"
        {
            echo "export pushover_enabled=true"
            echo "export pushover_user_key=$pushover_user_key"
            echo "export pushover_app_key=$pushover_app_key"
        } > /root/.teslaCamPushoverCredentials
    else
        log_progress "Pushover not configured."
    fi
}

function configure_gotify () {
    # shellcheck disable=SC2154
    if [ -n "${gotify_enabled+x}" ]
    then
        log_progress "Enabling Gotify"
        {
            echo "export gotify_enabled=true"
            echo "export gotify_domain=$gotify_domain"
            echo "export gotify_app_token=$gotify_app_token"
            echo "export gotify_priority=$gotify_priority"
        } > /root/.teslaCamGotifySettings
    else
        log_progress "Gotify not configured."
    fi
}

function configure_ifttt () {
    if [ -n "${ifttt_enabled+x}" ]
    then
        log_progress "Enabling IFTTT"
        {
            echo "export ifttt_enabled=true"
            echo "export ifttt_event_name=$ifttt_event_name"
            echo "export ifttt_key=$ifttt_key"
        } > /root/.teslaCamIftttSettings
    else
        log_progress "IFTTT not configured."
    fi
}

function configure_telegram () {
    if [ -n "${TELEGRAM_ENABLED+x}" ]
    then
        log_progress "Enabling Telegram"
    else
        log_progress "Telegram not configured."
    fi
}

function configure_webhook () {
    if [ -n "${WEBHOOK_ENABLED+x}" ]
    then
        log_progress "Enabling Webhook"
        {
            echo "export WEBHOOK_ENABLED=true"
            echo "export WEBHOOK_URL=$WEBHOOK_URL"
        } > /root/.teslaCamWebhookSettings
    else
        log_progress "Webhook not configured."
    fi
}

function configure_matrix () {
    if [ -n "${MATRIX_ENABLED+x}" ]
    then
        log_progress "Enabling Matrix"
        {
            echo "export MATRIX_ENABLED=true"
            echo "export MATRIX_SERVER_URL=$MATRIX_SERVER_URL"
            echo "export MATRIX_ROOM='$MATRIX_ROOM'"
        } > /root/.teslaCamMatrixSettings
        mkdir -p /root/.config/matrixcli/
        {
	    echo "def password_eval():"
	    echo "    return '$MATRIX_PASSWORD'"
	    echo ""
	    echo "accounts=[{'server': '$MATRIX_SERVER_URL', 'username': '$MATRIX_USERNAME', 'passeval': password_eval}]"
        } > /root/.config/matrixcli/config.py

        install_matrix_packages
    else
        log_progress "Matrix not configured."
    fi
}


function configure_sns () {
    # shellcheck disable=SC2154
    if [ -n "${sns_enabled+x}" ]
    then
        log_progress "Enabling SNS"
        mkdir -p /root/.aws

        echo "[default]" > /root/.aws/credentials
        echo "aws_access_key_id = $aws_access_key_id" >> /root/.aws/credentials
        echo "aws_secret_access_key = $aws_secret_key" >> /root/.aws/credentials

        echo "[default]" > /root/.aws/config
        echo "region = $aws_region" >> /root/.aws/config

        echo "export sns_enabled=true" > /root/.teslaCamSNSTopicARN
        echo "export sns_topic_arn=$aws_sns_topic_arn" >> /root/.teslaCamSNSTopicARN

        install_sns_packages
    else
        log_progress "SNS not configured."
    fi
}

function check_and_configure_pushover () {
    check_pushover_configuration

    configure_pushover
}

function check_and_configure_gotify () {
    check_gotify_configuration

    configure_gotify
}

function check_and_configure_ifttt () {
    check_ifttt_configuration

    configure_ifttt
}

function check_and_configure_webhook () {
    check_webhook_configuration

    configure_webhook
}

function check_and_configure_matrix () {
    check_matrix_configuration

    configure_matrix
}

function check_and_configure_telegram () {
    check_telegram_configuration

    configure_telegram
}

function check_and_configure_sns () {
    check_sns_configuration

    configure_sns
}

function install_push_message_scripts() {
    local install_path="$1"
    get_script "$install_path" send-push-message run
    get_script "$install_path" send_sns.py run
}

if [[ $EUID -ne 0 ]]
then
    log_progress "STOP: Run sudo -i."
    exit 1
fi

mkdir -p /root/bin

check_and_configure_pushover
check_and_configure_gotify
check_and_configure_ifttt
check_and_configure_webhook
check_and_configure_matrix
check_and_configure_telegram
check_and_configure_sns
install_push_message_scripts /root/bin

check_archive_configs

rm -f /root/teslausb.conf
rm -f /root/bin/write-archive-configs-to.sh

archive_module="$( get_archive_module )"
log_progress "Using archive module: $archive_module"

install_archive_scripts /root/bin "$archive_module"
/tmp/verify-and-configure-archive.sh

systemctl disable teslausb.service || true

cat << EOF > /lib/systemd/system/teslausb.service
[Unit]
Description=TeslaUSB archiveloop service
DefaultDependencies=no
After=mutable.mount backingfiles.mount

[Service]
Type=simple
ExecStart=/bin/bash /root/bin/archiveloop
Restart=always

[Install]
WantedBy=backingfiles.mount
EOF

systemctl enable teslausb.service
