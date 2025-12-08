echo "Installing dependencies..."
npm install

echo "Building NestJS project..."
npm run build > build.log 2>&1

if [ $? -eq 0 ]; then
    echo "Node build SUCCESS."
else
    echo "Node build FAILED."
    cp build.log error.log
    exit 1
fi

# --- Docker Build ---
IMAGE_NAME="hrishabhambak/digital-banking-hrishabh"
IMAGE_TAG="${BUILD_NUMBER}"

echo "Building Docker image: $IMAGE_NAME:$IMAGE_TAG"
docker build -t $IMAGE_NAME:$IMAGE_TAG .

if [ $? -ne 0 ]; then
    echo "Docker build FAILED."
    exit 1
fi

# --- Docker Login ---
echo "Logging into Docker Hub..."
echo $DOCKERHUB_PASSWORD | docker login -u $DOCKERHUB_USERNAME --password-stdin

if [ $? -ne 0 ]; then
    echo "Docker login FAILED."
    exit 1
fi

# --- Docker Push ---
echo "Pushing image to Docker Hub..."
docker push $IMAGE_NAME:$IMAGE_TAG

if [ $? -ne 0 ]; then
    echo "Docker push FAILED."
    exit 1
fi

echo "Docker image pushed successfully: $IMAGE_NAME:$IMAGE_TAG"

# --- Cleanup ---
echo "Removing local Docker image..."
docker rmi $IMAGE_NAME:$IMAGE_TAG || true

echo "Cleaning dist folder..."
rm -rf dist
