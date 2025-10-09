#!/bin/bash

# Default values
ADMIN_MODE=false
IMAGE=""
MACHINE=""
CONTAINER_NAME=""
HTTP_PORT=8069
LONGPOLLING_PORT=8072

# Function to display usage
usage() {
    echo
    echo "Usage: $0 [-a] [-i image] [-m machine] [-c container] [-h http_port] [-l longpolling_port]"
    echo "  -a           Specify script is run from admin"
    echo "  -i image     Specify the image name"
    echo "  -m machine   Specify the machine name e.g. cpu1-2gb"
    echo "  -c container Specify the container name to use. If not specified, a random name will be used."
    echo "  -h http_port     Specify the http port. Default is ${HTTP_PORT}"
    echo "  -l polling_port  Specify the long polling port. Default is ${LONGPOLLING_PORT}"
    echo
    exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse command-line options
# a - flag with no argument
# i: - option that requires an argument (the colon means "takes a value")
# m: - option that requires an argument
# c: - option that requires an argument (optional)
while getopts "ai:m:c:h:l:" opt; do
    case $opt in
        a)
            ADMIN_MODE=true
            ;;
        i)
            IMAGE="$OPTARG"
            ;;
        m)
            MACHINE="$OPTARG"
            ;;
        c)
            CONTAINER_NAME="$OPTARG"
            ;;
        h)
            HTTP_PORT="$OPTARG"
            ;;
        l)
            LONGPOLLING_PORT="$OPTARG"
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            ;;
    esac
done

# Shift past the parsed options
shift $((OPTIND-1))

# Validate required parameters
if [ -z "$IMAGE" ]; then
    echo "Error: -i image is required" >&2
    usage
fi

if [ -z "$MACHINE" ]; then
    echo "Error: -m machine is required" >&2
    usage
fi

# Your script logic here
#echo "Host: ${ADMIN_MODE}"
#echo "Image: ${IMAGE}"
#echo "Machine: ${MACHINE}"
#echo "Machine: ${CONTAINER_NAME}"

OS_USER=appuser
REPO_SOURCE=https://raw.githubusercontent.com/hwkcld/hwkapp/main
SETUP_SCR=setup-app.sh
CTN_CONFIG=odoo.conf

set -o pipefail

if [ "$ADMIN_MODE" = true ]; then

    echo "Adding user: ${OS_USER} ..."
    sudo useradd -ms /bin/bash ${OS_USER}
    if [ $? -eq 0 ]; then
      echo "Please enter password for new user: ${OS_USER}"
      sudo passwd ${OS_USER}
    fi

    echo "enable linger for ${OS_USER}"
    sudo loginctl enable-linger ${OS_USER}

    CONTAINER_ARG=""
    if [[ -n "$CONTAINER_NAME" ]]; then
        CONTAINER_ARG="-c ${CONTAINER_NAME}"
    fi
    
    sudo runuser -l ${OS_USER} -c "wget -O ~/${SETUP_SCR} ${REPO_SOURCE}/${SETUP_SCR} && chmod 700 ~/${SETUP_SCR} && ~/${SETUP_SCR} -i ${IMAGE} -m ${MACHINE} ${CONTAINER_ARG}"

    echo "Status: $?"

else

    OCI_IMAGE="docker.io/hwkcld/${IMAGE}"

    podman pull docker.io/library/busybox:latest
    if [[ $? -ne 0 ]]; then
        echo "Failed downloading busybox."
        exit 1
    fi

    podman pull ${OCI_IMAGE}
    if [[ $? -ne 0 ]]; then
        echo "Failed downloading ${OCI_IMAGE}."
        exit 1
    fi

    if [ -z "$CONTAINER_NAME" ]; then
        # Get unique name for new container from podman
        podman run -d busybox \
            && CONTAINER_NAME=$(podman ps -a --filter "ancestor=busybox:latest" --sort created --format "{{.Names}}" | tail -1) \
            && podman rm ${CONTAINER_NAME}
    fi

    MOUNT_DATA=${CONTAINER_NAME}-data
    MOUNT_LOGS=${CONTAINER_NAME}-logs
    CONFIG_PATH=${HOME}/${CONTAINER_NAME}
    QUADLET_PATH=${HOME}/.config/containers/systemd

    export XDG_RUNTIME_DIR=/run/user/${UID}
    echo "XDG_RUNTIME_DIR = ${XDG_RUNTIME_DIR}"

    echo "create named volume for ${OS_USER}: ${MOUNT_DATA}"
    podman volume create ${MOUNT_DATA}

    echo "create named volume for ${OS_USER}: ${MOUNT_LOGS}"
    podman volume create ${MOUNT_LOGS}

    echo "Create directory for config files"
    mkdir -p ${CONFIG_PATH}

    srcfile="${REPO_SOURCE}/${MACHINE}/${CTN_CONFIG}"
    echo "Downloading ${srcfile}"

    wget -O ${CONFIG_PATH}/${CTN_CONFIG} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi

    sed -i -e "s|%HTTP_PORT%|${HTTP_PORT}|g" \
    -e "s|%LONGPOLLING_PORT%|${LONGPOLLING_PORT}|g" \
    ${CONFIG_PATH}/${CTN_CONFIG}

    filename=maint.conf
    srcfile="${REPO_SOURCE}/${MACHINE}/${filename}"
    echo "Downloading ${srcfile}"

    wget -O ${HOME}/${filename} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi

    filename=maint.sh
    srcfile="${REPO_SOURCE}/${filename}"
    echo "Downloading ${srcfile}"

    wget -O ${HOME}/${filename} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi
    chmod 700 ${HOME}/${filename}

    echo "Create directory for quadlet"
    mkdir -p ${QUADLET_PATH}

    quadlet_template=quadlet.template
    echo "Download the default ${quadlet_template}"
    srcfile="${REPO_SOURCE}/${MACHINE}/${quadlet_template}"

    quadlet_file=${QUADLET_PATH}/${CONTAINER_NAME}.container
    
    wget -O ${quadlet_file} ${srcfile}
    if [[ $? -ne 0 ]]; then
        echo "Error downloading ${srcfile}."
        exit 1
    fi

    sed -i -e "s|%OCI_IMAGE%|${OCI_IMAGE}|g" \
    -e "s|%CONTAINER_NAME%|${CONTAINER_NAME}|g" \
    -e "s|%MOUNT_DATA%|${MOUNT_DATA}|g" \
    -e "s|%MOUNT_LOGS%|${MOUNT_LOGS}|g" \
    -e "s|%CONFIG_PATH%|${CONFIG_PATH}|g" \
    -e "s|%HTTP_PORT%|${HTTP_PORT}|g" \
    -e "s|%LONGPOLLING_PORT%|${LONGPOLLING_PORT}|g" \
    ${quadlet_file}

    echo "Record image used by container"
    echo $(date +"%Y-%m-%d %H:%M:%S") ${OCI_IMAGE} >> ${CONFIG_PATH}/reference.txt

    echo "Create the ${CONTAINER_NAME} service"
    systemctl --user daemon-reload

    echo "Start the service using systemd i.e. auto reload even after system restart"
    echo -e "\n" | systemctl --user start ${CONTAINER_NAME}.service
    if [[ $? -ne 0 ]]; then
        echo "Failed starting server"
        exit 1
    fi

fi
