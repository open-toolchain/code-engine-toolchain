#!/bin/bash
set -e -o pipefail

if [ $(params.pipeline-debug) == 1 ]; then
    env
    pwd
    ls -l
    echo "=== cat /artifacts/_toolchain.json ==="
    cat /artifacts/_toolchain.json
    echo ""
    echo "======================================"
    trap env EXIT
    set -x
fi

# SETUP BEGIN
ibmcloud config --check-version false
if [ "$(params.region)" ]; then
    # if cluster region is in the 'ibm:yp:<region>' just keep the region part
    IBM_CLOUD_REGION=$(echo "$(params.region)" | awk -F ':' '{print $NF;}')
else
    IBM_CLOUD_REGION=$(jq -r '.region_id' /artifacts/_toolchain.json | awk -F: '{print $3}')
fi

ibmcloud login -a $(params.ibmcloud-api) -r $IBM_CLOUD_REGION --apikey $PIPELINE_BLUEMIX_API_KEY

# Kin: Only need to target one resource group
ibmcloud target -g "$(params.resource-group)"

# View shuttle properties
cat $(params.shuttle-properties-file)

source $(params.shuttle-properties-file)
export $(cut -d= -f1 $(params.shuttle-properties-file))

ibmcloud plugin install code-engine

# Kin: See if projects need to be created if missing (This means to)
echo "Check if the Code Engine projects are availability on IBM Cloud"
MYPROJECTS=($(echo "$params.code-engine-projects" | tr ',' '\n'))
MYREGIONS=($(echo "$params.regions" | tr ',' '\n'))
echo -e "Targeting Code Engine projects ${MYPROJECTS[@]} in regions ${MYREGIONS[@]}"

for i in "${MYPROJECTS[@]}"
do
    echo "Target region ${MYREGIONS[i]}"
    ibmcloud target -g "${MYREGIONS[i]}"

    echo "Loading Kube config for project ${MYPROJECTS[i]}"
    ibmcloud ce proj select -n ${MYPROJECTS[i]} -k

    echo -e "Configuring access to private image registry"
    PIPELINE_TOOLCHAIN_ID=$(jq -j '.toolchain_guid' /artifacts/_toolchain.json)
    IMAGE_PULL_SECRET_NAME="ibmcloud-toolchain-${PIPELINE_TOOLCHAIN_ID}-${REGISTRY_URL}"

    if ! kubectl get secret ${IMAGE_PULL_SECRET_NAME}; then
        echo -e "${IMAGE_PULL_SECRET_NAME} not found, creating it"
        # for Container Registry, docker username is 'token' and email does not matter
        kubectl create secret docker-registry ${IMAGE_PULL_SECRET_NAME} --docker-server=${REGISTRY_URL} --docker-password=${PIPELINE_BLUEMIX_API_KEY} --docker-username=iamapikey --docker-email=a@b.com
    fi

    # Check if the application exists in the targeted CE project
    if ibmcloud ce app get -n $(params.app-name) | grep Age; then
        echo "Code Engine app with name $(params.app-name) found, updating it"
        ibmcloud ce app update -n $(params.app-name) \
        -i $(params.image-repository):$(params.image-tags) \
        --rs ${IMAGE_PULL_SECRET_NAME} \
        -w=false \
        --cpu $(params.cpu) \
        --max $(params.max-scale) \
        -m $(params.memory) \
        -p $(params.port)
    else
        echo "Code Engine app with name $(params.app-name) not found, creating it"
        ibmcloud ce app create -n $(params.app-name) \
        -i $(params.image-repository):$(params.image-tags) \
        --rs ${IMAGE_PULL_SECRET_NAME} \
        -w=false \
        --cpu $(params.cpu) \
        --max $(params.max-scale) \
        -m $(params.memory) \
        -p $(params.port)
    fi

    # Bind services, if any
    while read;
    do
        NAME=$(echo "$REPLY" | jq -j '.key')
        PREFIX=$(echo "$REPLY" | jq -j '.value')

        if ! ibmcloud ce app get -n $(params.app-name) | grep "$NAME"; then
        ibmcloud ce app bind -n $(params.app-name) --si "$NAME" -p "$PREFIX" -w=false
        fi
    done < <(jq -c 'to_entries | .[]' <<< $(echo $(params.service-bindings) | base64 -d))

    echo "Checking if application is ready..."
    KUBE_SERVICE_NAME=$(params.app-name)

    for ITERATION in {1..100}
    do
        sleep 3

        kubectl get ksvc/${KUBE_SERVICE_NAME} --output=custom-columns=DOMAIN:.status.conditions[*].status
        SVC_STATUS_READY=$( kubectl get ksvc/${KUBE_SERVICE_NAME} -o json | jq '.status?.conditions[]?.status?|select(. == "True")' )
        echo SVC_STATUS_READY=$SVC_STATUS_READY

        SVC_STATUS_NOT_READY=$( kubectl get ksvc/${KUBE_SERVICE_NAME} -o json | jq '.status?.conditions[]?.status?|select(. == "False")' )
        echo SVC_STATUS_NOT_READY=$SVC_STATUS_NOT_READY

        SVC_STATUS_UNKNOWN=$( kubectl get ksvc/${KUBE_SERVICE_NAME} -o json | jq '.status?.conditions[]?.status?|select(. == "Unknown")' )
        echo SVC_STATUS_UNKNOWN=$SVC_STATUS_UNKNOWN

        if [ \( -n "$SVC_STATUS_NOT_READY" \) -o \( -n "$SVC_STATUS_UNKNOWN" \) ]; then
        echo "Application not ready, retrying"
        elif [ -n "$SVC_STATUS_READY" ]; then
        echo "Application is ready"
        break
        else
        echo "Application status unknown, retrying"
        fi
    done

    echo "Application service details:"
    kubectl describe ksvc/${KUBE_SERVICE_NAME}
    if [ \( -n "$SVC_STATUS_NOT_READY" \) -o \( -n "$SVC_STATUS_UNKNOWN" \) ]; then
        echo "Application is not ready after waiting maximum time"
        exit 1
    fi

    # Determine app url for polling from knative service
    TEMP_URL=$( kubectl get ksvc/${KUBE_SERVICE_NAME} -o json | jq '.status.url' )
    echo "Application status URL: $TEMP_URL"
    TEMP_URL=${TEMP_URL%\"} # remove end quote
    TEMP_URL=${TEMP_URL#\"} # remove beginning quote
    APPLICATION_URL=$TEMP_URL
    if [ -z "$APPLICATION_URL" ]; then
        echo "Deploy failed, no URL found for application"
        exit 1
    fi
    echo "Application is available"
    echo "=========================================================="
    echo -e "View the application at: $APPLICATION_URL"

    # Record task results
    if i == 1
    then
        echo -n "$APPLICATION_URL" > $(results.app-url.paths)
    else
        echo -n "$(results.app-url.paths),$APPLICATION_URL" > $(results.app-url.paths)
    fi
    
done

echo -n "Task result: $(results.app-url.paths)"
