# Add automatic rollback on failure
echo "Pulling latest Docker image..."
docker pull hrishabhambak/digital-banking-hrishabh:${BUILD_NUMBER}

if [ $? -ne 0 ]; then
    echo "Docker pull FAILED."
    exit 1
fi

# Stop old container if running
echo "Checking for existing container..."
RUNNING_CONTAINER=$(docker ps -aq --filter "name=digital-banking-hrishabh")

if [ ! -z "$RUNNING_CONTAINER" ]; then
    echo "Stopping old container..."
    docker stop digital-banking-hrishabh
    docker rm digital-banking-hrishabh
else
    echo "No running container detected."
fi

# Deploy new container
echo "Starting new container..."
docker run -d \
    --name digital-banking-hrishabh \
    -p 5000:5000 \
    -e PORT=5000 \
    hrishabhambak/digital-banking-hrishabh:${BUILD_NUMBER}

if [ $? -ne 0 ]; then
    echo "Container deployment FAILED."
    exit 1
fi

echo "Deployment SUCCESS. App running at http://localhost:5000"

LAST_SUCCESS_FILE="/var/lib/jenkins/rollback/LAST_SUCCESS"

echo "Checking application health..."
sleep 5

HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000 || true)

if [ "$HEALTH" != "200" ]; then
    echo "Health check FAILED with status: $HEALTH"
    ROLLBACK=true
else
    echo "Health check SUCCESS"
    ROLLBACK=false
fi

if [ "$ROLLBACK" = true ]; then
    echo "Starting rollback..."

    if [ ! -r "$LAST_SUCCESS_FILE" ]; then
        echo "No LAST_SUCCESS file found or not readable. Cannot rollback."
        exit 1
    fi

    PREV_VERSION=$(cat "$LAST_SUCCESS_FILE")

    if [ -z "$PREV_VERSION" ] || [ "$PREV_VERSION" = "0" ]; then
        echo "No previous stable version value. Cannot rollback."
        exit 1
    fi

    echo "Pulling previous stable image: ${PREV_VERSION}"
    docker pull hrishabhambak/digital-banking-hrishabh:${PREV_VERSION}

    echo "Stopping faulty container..."
    docker stop digital-banking-hrishabh || true
    docker rm digital-banking-hrishabh || true

    echo "Starting previous stable version..."
    docker run -d \
        --name digital-banking-hrishabh \
        -p 5000:5000 \
    	-e PORT=5000 \
        hrishabhambak/digital-banking-hrishabh:${PREV_VERSION}

    echo "Rollback complete. Reverted to version ${PREV_VERSION}"
    exit 1
else
    echo "Deployment healthy. Marking this build as last stable version..."
    echo "${BUILD_NUMBER}" > "$LAST_SUCCESS_FILE"
    echo "Deployment SUCCESS: Version ${BUILD_NUMBER} is now the active stable version."
fi
