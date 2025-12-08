!/bin/bash

echo "Installing dependencies..."
npm install

echo "Building NestJS project..."
LOG_FILE="build-$(date +%Y%m%d-%H%M%S).log"
npm run build > $LOG_FILE 2>&1

if [ $? -eq 0 ]; then
    echo "Build SUCCESS."
    BUILD_STATUS="SUCCESS"

    echo "Starting PM2 app..."
    run main.js from dist folder
    pm2 start dist/main.js --name digital-banking-Hrishabh || pm2 restart digital-banking-Hrishabh

else
    echo "Build FAILED. Storing error logs..."
    cp $LOG_FILE error.log
    echo "Error stored in error.log"
    BUILD_STATUS="FAILURE"

    # optional: delete dist folder
    rm -rf dist

    # Fail the Jenkins build
    exit 1
fi
