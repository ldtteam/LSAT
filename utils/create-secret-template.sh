#!/usr/bin/env bash

# This script takes in the following parameters:
# - Service type. Supported are the values for which a "-charts" directory exists in this repo
# - Service name. Supported are the values for which a "-extras" directory exists within the service type directory
# - Secret name.
# - Secret key.
# Example: ./create-secret-template.sh core prometheus github-client
# The secret value is then read from STDIN and the secret file is output to the target directory for the service.

# Set up variables
SERVICE_TYPE=$1
SERVICE_NAME=$2
SECRET_NAME=$3
SECRET_KEY=$4

# Check if service type and name are provided
if [ -z "${SERVICE_TYPE}" ]; then
    echo "Service type is not provided."
    exit 1
fi

if [ -z "${SERVICE_NAME}" ]; then
    echo "Service name is not provided."
    exit 2
fi

if [ -z "${SECRET_NAME}" ]; then
    echo "Secret name is not provided."
    exit 3
fi

# Initialize FROM_LITERAL variable
FROM_LITERAL=""

# If neither secret name nor key is provided, ask for key-value pairs
# Check for additional parameters beyond the initial four
if [ $# -gt 3 ]; then
    # Ensure an even number of additional parameters for key-value pairs
    if [ $(( ($# - 3) % 2 )) -ne 0 ]; then
        echo "Error: Missing value for the last secret key."
        exit 5
    fi

    # Process additional key-value pairs
    for (( i=4; i<=$#; i+=2 ))
    do
        KEY=${!i}
        let "VAL_INDEX = i + 1"
        VALUE=${!VAL_INDEX}
        FROM_LITERAL="$FROM_LITERAL --from-literal=$KEY=$VALUE"
    done
elif [ -z "${SECRET_KEY}" ]; then
    echo "Enter the number of key-value pairs for the secret:"
    read -r PAIR_COUNT

    if ! [[ "$PAIR_COUNT" =~ ^[0-9]+$ ]]; then
        echo "Please enter a valid number."
        exit 4
    fi

    for (( i=1; i<=PAIR_COUNT; i++ ))
    do
        echo "Enter key #$i:"
        read -r KEY
        echo "Enter value for $KEY:"
        read -r VALUE
        FROM_LITERAL="$FROM_LITERAL --from-literal=$KEY=$VALUE"
    done
else
    # Request secret value from user for the single key-value pair
    echo "Enter secret value for ${SECRET_NAME}.${SECRET_KEY}:"
    read -r -s SECRET_VALUE
    FROM_LITERAL="--from-literal=${SECRET_KEY}=${SECRET_VALUE}"
fi

# Find the parent directory of this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
# Go up to the root project directory
PROJECT_DIR=$(realpath "${SCRIPT_DIR}/../")

# Set up paths
SERVICE_TYPE_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-charts"
APPLICATION_SERVICES_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-services"
# Check if we are a core service type
if [ "${SERVICE_TYPE}" == "core" ]; then
    APPLICATION_SERVICES_DIR="${PROJECT_DIR}/core-service"
fi
SERVICE_NAME_DIR="${SERVICE_TYPE_DIR}/${SERVICE_NAME}-extras"
TEMPLATE_DIR="${SERVICE_NAME_DIR}/templates"
SECRET_FILE="${TEMPLATE_DIR}/${SECRET_NAME}.yaml"

# Check if the application services directory exists
if [ ! -d "${APPLICATION_SERVICES_DIR}" ]; then
    # If it does not exist try the singular form
    APPLICATION_SERVICES_DIR="${PROJECT_DIR}/${SERVICE_TYPE}-service"
    if [ ! -d "${APPLICATION_SERVICES_DIR}" ]; then
        echo "Application services directory ${APPLICATION_SERVICES_DIR} does not exist."
        exit 1
    fi
fi

# We need to extract the used namespace.
# This is done by looking in the "-services" service type directory, for the application template, and looking in the yaml property: spec.destination.namespace
# This is then used to set the namespace in the secret template.
# The namespace is then used to create the secret in the correct namespace.
APPLICATION_FILE="${APPLICATION_SERVICES_DIR}/templates/${SERVICE_NAME}.yaml"

# Check if the application file exists
if [ ! -f "${APPLICATION_FILE}" ]; then
    echo "Application file ${APPLICATION_FILE} does not exist."
    exit 1
fi

SERVICE_NAMESPACE=$(yq eval '.spec.destination.namespace' "${APPLICATION_FILE}")

# Check if the service namespace is set
if [ -z "${SERVICE_NAMESPACE}" ]; then
    echo "Service namespace is not set in ${APPLICATION_FILE}."
    exit 2
fi

# Ensure the template directory exists
mkdir -p "${TEMPLATE_DIR}"

# Create the secret file
echo "Creating secret file ${SECRET_FILE} for ${SERVICE_NAME} in namespace ${SERVICE_NAMESPACE}."
echo "Using the following kubectl command:"
echo "kubectl create secret generic -n ${SERVICE_NAMESPACE} --dry-run=client $FROM_LITERAL -o yaml ${SECRET_NAME} | kubeseal --format yaml > ${SECRET_FILE}"

kubectl create secret generic -n "${SERVICE_NAMESPACE}" "${SECRET_NAME}" --dry-run=client $FROM_LITERAL -o yaml | kubeseal --format yaml > "$SECRET_FILE"

# Append the application marker labels:
echo "      labels:" >> "$SECRET_FILE"
echo "        app.kubernetes.io/part-of: ${SERVICE_NAME}" >> "$SECRET_FILE"

# On the outputted file we need to remove lines containing the following: creationTimestamp, resourceVersion, selfLink, uid
# This is because these values will change on each run, and we want to be able to compare the outputted file with the sealed secret file.
sed -i '/creationTimestamp/d' "$SECRET_FILE"
sed -i '/resourceVersion/d' "$SECRET_FILE"
sed -i '/selfLink/d' "$SECRET_FILE"
sed -i '/uid/d' "$SECRET_FILE"
