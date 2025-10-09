#!/bin/bash

set -e

# Default values
UPDATE_ALL=false
CONTAINER_NAME=""
DATABASE=""
IMAGE=""

# Function to display usage
usage() {
    echo
    echo "Usage: $0 [-c container] [-d database] [-i image] [-u]"
    echo "  -c container Specify the container name or ID"
    echo "  -d database  Specify the database to use"
    echo "  -i image     Specify the image name to use"
    echo "  -u           Specify if it is an update of all the modules"
    echo
    exit 1
}

# Show usage if no arguments provided
if [ $# -eq 0 ]; then
    usage
fi

# Parse command-line options
# c: - option that requires an argument (the colon means "takes a value")
# d: - option that requires an argument
# i: - option that requires an argument
while getopts "uc:d:i:" opt; do
    case $opt in
        u)
            UPDATE_ALL=true
            ;;
        c)
            CONTAINER_NAME="$OPTARG"
            ;;
        d)
            DATABASE="$OPTARG"
            ;;
        i)
            IMAGE="$OPTARG"
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
if [ -z "$CONTAINER_NAME" ]; then
    echo "Error: -c container is required" >&2
    usage
fi

if [ -z "$DATABASE" ]; then
    echo "Error: -d database is required" >&2
    usage
fi

if [ -z "$IMAGE" ]; then
    echo "Error: -i image is required" >&2
    usage
fi

# Your script logic here
#echo "Container: ${CONTAINER_NAME}"
#echo "Database: ${DATABASE}"
#echo "Image: ${IMAGE}"
#echo "Update: ${UPDATE_ALL}"

CMD_OPTIONS="-d ${DATABASE}"
if [ "$UPDATE_ALL" = true ]; then
    CMD_OPTIONS="-d ${DATABASE} -u all"
fi

if [ "$UPDATE_ALL" = true ]; then
    echo "Stopping container: ${CONTAINER_NAME}"
    systemctl --user stop ${CONTAINER_NAME}
fi

echo "Running update for database: ${DATABASE} with image: ${IMAGE}"
echo
podman run \
--rm \
--name ${CONTAINER_NAME} \
--network=host \
-v ${CONTAINER_NAME}-data:/opt/odoo-data \
-v ${CONTAINER_NAME}-logs:/var/log/odoo \
-v ./${CONTAINER_NAME}/maintenance.conf:/opt/odoo/odoo.conf \
docker.io/hwkcld/${IMAGE} \
${CMD_OPTIONS}

if [ "$UPDATE_ALL" = true ]; then
    echo
    echo "Starting container: ${CONTAINER_NAME}"
    systemctl --user start ${CONTAINER_NAME}
    echo
fi
