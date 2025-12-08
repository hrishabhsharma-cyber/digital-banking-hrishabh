# GREEN BLUE deployment
IMAGE_NAME="hrishabhambak/digital-banking-hrishabh"
NEW_VERSION="${BUILD_NUMBER}"
ROLLBACK_DIR="/var/lib/jenkins/rollback"
LAST_SUCCESS_FILE="$ROLLBACK_DIR/LAST_SUCCESS"

mkdir -p $ROLLBACK_DIR

echo "Starting BLUE-GREEN deployment for Digital Banking App"
echo "New version: $NEW_VERSION"

# ----------------------------------------------------------
# STEP 1: START GREEN CONTAINER
# ----------------------------------------------------------

echo "Cleaning any previous GREEN container..."
docker stop digital-banking-green 2>/dev/null || true
docker rm digital-banking-green 2>/dev/null || true

echo "Force cleaning port 4002 bindings..."
docker ps -q --filter "publish=4002" | xargs -r docker stop || true
docker ps -aq --filter "publish=4002" | xargs -r docker rm || true

echo "Starting GREEN environment..."
docker run -d \
    --name digital-banking-green \
    -p 4002:5000 \
    -e PORT=5000 \
    $IMAGE_NAME:$NEW_VERSION

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start GREEN container."
    exit 1
fi

sleep 6

# ----------------------------------------------------------
# STEP 2: HEALTH CHECK GREEN
# ----------------------------------------------------------

echo "Running health check on GREEN..."
GREEN_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:4002/ || true)

echo "Health status on GREEN: $GREEN_HEALTH"

if [ "$GREEN_HEALTH" != "200" ]; then
    echo "GREEN deployment FAILED. Status code: $GREEN_HEALTH"
    ROLLBACK=true
else
    echo "GREEN is HEALTHY."
    ROLLBACK=false
fi

# ----------------------------------------------------------
# STEP 3: ROLLBACK IF GREEN FAILED
# ----------------------------------------------------------

if [ "$ROLLBACK" = true ]; then
    echo "🚨 Starting rollback..."

    if [ ! -r "$LAST_SUCCESS_FILE" ]; then
        echo "No LAST_SUCCESS file found. Cannot rollback!"
        exit 1
    fi

    PREV_VERSION=$(cat "$LAST_SUCCESS_FILE")

    if [ -z "$PREV_VERSION" ] || [ "$PREV_VERSION" = "0" ]; then
        echo "Invalid previous stable version. Cannot rollback!"
        exit 1
    fi

    echo "Pulling previous stable image: $PREV_VERSION"
    docker pull $IMAGE_NAME:$PREV_VERSION

    echo "Stopping faulty GREEN container..."
    docker stop digital-banking-green || true
    docker rm digital-banking-green || true

    echo "Stopping existing BLUE container..."
    docker stop digital-banking-blue || true
    docker rm digital-banking-blue || true

    echo "Starting BLUE container with stable version: $PREV_VERSION"
    docker run -d \
      --name digital-banking-blue \
      	-p 4001:5000 \
  		-e PORT=5000 \
      $IMAGE_NAME:$PREV_VERSION

    echo "Rollback complete. BLUE environment restored."
    exit 1
fi

# ----------------------------------------------------------
# STEP 4: SWITCH TRAFFIC TO GREEN USING NGINX
# ----------------------------------------------------------

echo "⬆ Switching Nginx traffic from BLUE → GREEN..."

sudo sed -i 's/4001/4002/g' /etc/nginx/sites-available/nest-proxy.conf
sudo systemctl reload nginx

echo "Traffic now routed to GREEN environment."

# ----------------------------------------------------------
# STEP 5: PROMOTE GREEN → BLUE
# ----------------------------------------------------------

echo "Stopping old BLUE container..."
docker stop digital-banking-blue || true
docker rm digital-banking-blue || true

echo "Promoting GREEN as new BLUE..."
docker rename digital-banking-green digital-banking-blue

# ----------------------------------------------------------
# STEP 6: SAVE THIS VERSION AS LAST SUCCESS
# ----------------------------------------------------------

echo "$NEW_VERSION" > "$LAST_SUCCESS_FILE"
echo "✔ Deployment SUCCESS: Version $NEW_VERSION marked as stable."
