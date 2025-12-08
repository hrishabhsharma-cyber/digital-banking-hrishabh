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

echo "Building Docker image..."
docker build -t nestjs-ci-demo:${BUILD_NUMBER} .

if [ $? -eq 0 ]; then
    echo "Docker build SUCCESS."
else
    echo "Docker build FAILED."
    exit 1
fi

echo "Cleaning workspace..."
rm -rf dist
