pipeline {
    agent any

    environment {
        IMAGE_NAME = "hrishabhambak/digital-banking-hrishabh"
        IMAGE_TAG = "${BUILD_NUMBER}"
        ROLLBACK_DIR = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "${ROLLBACK_DIR}/LAST_SUCCESS"
        DOCKERHUB = credentials('dockerhub-credentials')
    }

    stages {

        stage('Build App') {
            steps {
                echo "Installing deps & building NestJS..."
                sh """
                    npm install
                    npm run build > build.log 2>&1 || {
                        cp build.log error.log
                        exit 1
                    }
                """
            }
        }

        stage('Docker Build & Push') {
            steps {
                echo "Building & pushing image ${IMAGE_NAME}:${IMAGE_TAG}"
                sh """
                    docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                    echo ${DOCKERHUB_PSW} | docker login -u ${DOCKERHUB_USR} --password-stdin
                    docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                    rm -rf dist || true
                """
            }
        }

        stage('Detect Ports') {
            steps {
                script {
                    BLUE = sh(
                        script: '''
                            if docker ps --format "{{.Ports}}" --filter "name=digital-banking-blue" | grep -q "4001->";
                                then echo "4001"; else echo "4003";
                            fi
                        ''',
                        returnStdout: true
                    ).trim()

                    CANARY = (BLUE == "4001") ? "4003" : "4001"

                    env.BLUE_PORT = BLUE
                    env.CANARY_PORT = CANARY

                    echo "🔵 BLUE on ${BLUE}"
                    echo "🟡 CANARY on ${CANARY}"
                }
            }
        }

        stage('Start Canary') {
            steps {
                echo "Starting Canary on ${env.CANARY_PORT}"
                sh """
                    docker stop digital-banking-canary || true
                    docker rm digital-banking-canary || true

                    docker run -d \
                        --name digital-banking-canary \
                        -p ${env.CANARY_PORT}:5000 \
                        -e PORT=5000 \
                        ${IMAGE_NAME}:${IMAGE_TAG}

                    sleep 7
                """
            }
        }

        stage('Health Check Canary') {
            steps {
                script {
                    def status = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || echo 000",
                        returnStdout: true
                    ).trim()

                    echo "CANARY Health: ${status}"

                    if (status != "200") {  
                        error("CANARY FAILED health check")
                    }
                }
            }
        }

        stage('Shift Traffic (90/10)') {
            steps {
                echo "Applying 90/10 traffic split..."
                sh """
                    sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT}.*/server 127.0.0.1:${env.BLUE_PORT} weight=90;/" /etc/nginx/sites-available/nest-proxy.conf
                    sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT}.*/server 127.0.0.1:${env.CANARY_PORT} weight=10;/" /etc/nginx/sites-available/nest-proxy.conf
                    sudo systemctl reload nginx
                """
                sleep 10
            }
        }

        stage('Promote Canary → Production') {
            steps {
                script {
                    echo "Checking CANARY after traffic shift..."

                    def status = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || echo 000",
                        returnStdout: true
                    ).trim()

                    if (status != "200") {
                        error("CANARY degraded! Rolling back.")
                    }

                    echo "Promoting CANARY to 100% traffic..."
                    sh """
                        sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT}.*/server 127.0.0.1:${env.BLUE_PORT} weight=1;/" /etc/nginx/sites-available/nest-proxy.conf
                        sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT}.*/server 127.0.0.1:${env.CANARY_PORT} weight=100;/" /etc/nginx/sites-available/nest-proxy.conf
                        sudo nginx -t
                        sudo systemctl reload nginx
                    """
                }
            }
        }

        stage('Finalize Release') {
            steps {
                echo "Switching CANARY → BLUE and saving version"
                sh """
                    docker stop digital-banking-blue || true
                    docker rm digital-banking-blue || true
                    docker rename digital-banking-canary digital-banking-blue

                    mkdir -p ${ROLLBACK_DIR}
                    echo '${IMAGE_TAG}' > ${LAST_SUCCESS_FILE}
                """
            }
        }
    }

    post {
        success { echo "🎉 SUCCESS: Released version ${IMAGE_TAG}" }
        failure { echo "❌ FAILURE: Rolling back to previous version..." }
        always  { echo "Pipeline finished." }
    }
}
