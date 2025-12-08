# ----------------------------------------------------------
# CANARY DEPLOYMENT FOR DIGITAL BANKING APP
# ----------------------------------------------------------
set -e
IMAGE_NAME="hrishabhambak/digital-banking-hrishabh"
NEW_VERSION="${BUILD_NUMBER}"
ROLLBACK_DIR="/var/lib/jenkins/rollback"
LAST_SUCCESS_FILE="$ROLLBACK_DIR/LAST_SUCCESS"

mkdir -p $ROLLBACK_DIR

echo "🔥 Starting CANARY Deployment for Digital Banking App"
echo "New version: $NEW_VERSION"

# ----------------------------------------------------------
# STEP 0: DETECT CURRENT BLUE PORT (4001 or 4003)
# ----------------------------------------------------------

if docker ps --format '{{.Ports}}' --filter "name=digital-banking-blue" | grep -q "4001->"; then
    BLUE_PORT=4001
    CANARY_PORT=4003
else
    BLUE_PORT=4003
    CANARY_PORT=4001
fi

echo "🔵 BLUE is running on port: $BLUE_PORT"
echo "🟡 CANARY will run on port: $CANARY_PORT"


# ----------------------------------------------------------
# STEP 1: START CANARY CONTAINER ON FREE PORT
# ----------------------------------------------------------

echo "Cleaning any previous CANARY container..."
docker stop digital-banking-canary 2>/dev/null || true
docker rm digital-banking-canary 2>/dev/null || true

echo "Force cleaning CANARY port: ${CANARY_PORT}..."
docker ps -q --filter "publish=${CANARY_PORT}" | xargs -r docker stop || true
docker ps -aq --filter "publish=${CANARY_PORT}" | xargs -r docker rm || true

echo "Starting CANARY container on port ${CANARY_PORT}..."

docker run -d \
    --name digital-banking-canary \
    -p ${CANARY_PORT}:5000 \
    -e PORT=5000 \
    $IMAGE_NAME:$NEW_VERSION

sleep 7


# ----------------------------------------------------------
# STEP 2: HEALTH CHECK CANARY
# ----------------------------------------------------------

echo "🏥 Running health check on CANARY..."
CANARY_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${CANARY_PORT}/ || true)

echo "CANARY Health Status: $CANARY_HEALTH"

if [ "$CANARY_HEALTH" != "200" ]; then
    echo "❌ CANARY FAILED! Starting rollback..."

    # rollback: just delete canary, BLUE keeps running
    docker stop digital-banking-canary || true
    docker rm digital-banking-canary || true

    exit 1
fi

echo "✅ CANARY is HEALTHY."


# ----------------------------------------------------------
# STEP 3: CANARY TEST TRAFFIC (90/10)
# ----------------------------------------------------------

echo "⚡ Applying 90/10 Nginx weight distribution (BLUE/CANARY)..."

# Update Nginx weights
sudo sed -i "s/server 127.0.0.1:${BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${BLUE_PORT} weight=90/" /etc/nginx/sites-available/nest-proxy.conf
sudo sed -i "s/server 127.0.0.1:${CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${CANARY_PORT} weight=10/" /etc/nginx/sites-available/nest-proxy.conf

sudo systemctl reload nginx
echo "🟡 10% traffic → CANARY | 🔵 90% traffic → BLUE"

sleep 10


# ----------------------------------------------------------
# STEP 4: SECOND HEALTH CHECK BEFORE PROMOTION
# ----------------------------------------------------------

echo "🏥 Second health check before canary promotion..."

CANARY_HEALTH2=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${CANARY_PORT}/ || true)

if [ "$CANARY_HEALTH2" != "200" ]; then
    echo "❌ CANARY degraded during test! Rolling back..."

    docker stop digital-banking-canary || true
    docker rm digital-banking-canary || true

    # restore full Blue traffic
    sudo sed -i "s/server 127.0.0.1:${BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${BLUE_PORT} weight=100/" /etc/nginx/sites-available/nest-proxy.conf
    sudo sed -i "s/server 127.0.0.1:${CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${CANARY_PORT} weight=1/" /etc/nginx/sites-available/nest-proxy.conf
    sudo systemctl reload nginx

    exit 1
fi

echo "🚀 CANARY is stable. Promoting to FULL PRODUCTION..."


# ----------------------------------------------------------
# STEP 5: FULL PROMOTION (100% CANARY)
# ----------------------------------------------------------

# Set CANARY to 100%, BLUE to 0%
echo "➡ Promoting CANARY to full production..."

sudo sed -i 's/server 127\.0\.0\.1:'"$BLUE_PORT"' weight=[0-9]\+;/server 127.0.0.1:'"$BLUE_PORT"' weight=1;/' /etc/nginx/sites-available/nest-proxy.conf
sudo sed -i 's/server 127\.0\.0\.1:'"$CANARY_PORT"' weight=[0-9]\+;/server 127.0.0.1:'"$CANARY_PORT"' weight=100;/' /etc/nginx/sites-available/nest-proxy.conf

sudo nginx -t
sudo systemctl reload nginx

echo "➡ 100% traffic now routed to CANARY container (port ${CANARY_PORT})"


# ----------------------------------------------------------
# STEP 6: PROMOTE CANARY → BLUE
# ----------------------------------------------------------

echo "🟦 Removing old BLUE container..."
docker stop digital-banking-blue || true
docker rm digital-banking-blue || true

echo "🟩 Promoting CANARY → BLUE..."
docker rename digital-banking-canary digital-banking-blue


# ----------------------------------------------------------
# STEP 7: SAVE STABLE VERSION
# ----------------------------------------------------------

echo "$NEW_VERSION" > "$LAST_SUCCESS_FILE"
echo "🎉 Canary Deployment SUCCESS! Version $NEW_VERSION promoted to BLUE on port ${CANARY_PORT}."
