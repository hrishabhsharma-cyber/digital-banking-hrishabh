pipeline {
    agent any

    environment {
        IMAGE_NAME       = "hrishabhambak/digital-banking-hrishabh"
        ROLLBACK_DIR     = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "/var/lib/jenkins/rollback/LAST_SUCCESS"
        BLUE_PORT  = ""
        CANARY_PORT = ""
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh "npm install"
            }
        }

        stage('Build App') {
            steps {
                sh """
                npm run build > build.log 2>&1 || {
                    echo "Build failed"
                    cp build.log error.log
                    exit 1
                }
                """
            }
        }

        stage('Docker Build') {
            steps {
                sh "docker build -t $IMAGE_NAME:${BUILD_NUMBER} ."
            }
        }

        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    sh """
                    echo "$DOCKER_PASS" | docker login -u "$DOCKER_USER" --password-stdin
                    docker push $IMAGE_NAME:${BUILD_NUMBER}
                    """
                }
            }
        }

        stage('Detect Active Ports') {
            steps {
                script {
                
                    echo "▶ Detecting active BLUE port..."

                    def blue = sh(
                        script: """
                            docker ps --filter 'name=^digital-banking-blue\$' --format '{{.Ports}}' |
                            awk -F':' '{print \$2}' | awk -F'->' '{print \$1}'
                        """,
                        returnStdout: true
                    ).trim()

                    if (!blue.isInteger()) {
                        error "❌ Port extraction failed. Extracted: '${blue}'"
                    }

                    env.BLUE_PORT   = blue
                    env.CANARY_PORT = (blue == "4001") ? "4003" : "4001"

                    echo "✔ BLUE_PORT  = ${env.BLUE_PORT}"
                    echo "✔ CANARY_PORT = ${env.CANARY_PORT}"

                    sh "mkdir -p $ROLLBACK_DIR"
                }
            }
        }

        stage('Cleanup Previous Canary') {
            steps {
                sh """
                docker stop digital-banking-canary 2>/dev/null || true
                docker rm digital-banking-canary 2>/dev/null || true

                # Cleanup any old container on canary port
                docker ps -q --filter "publish=${env.CANARY_PORT}" | xargs -r docker stop || true
                docker ps -aq --filter "publish=${env.CANARY_PORT}" | xargs -r docker rm || true
                """
            }
        }

        stage('Start Canary') {
            steps {
                sh """
                docker run -d \
                  --name digital-banking-canary \
                  -p ${env.CANARY_PORT}:5000 \
                  -e PORT=5000 \
                  $IMAGE_NAME:${BUILD_NUMBER}

                sleep 7
                """
            }
        }

        stage('Health Check #1') {
            steps {
                script {
                    def code = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || true",
                        returnStdout: true
                    ).trim()

                    if (code != "200") {
                        error "❌ Canary failed health check #1"
                    }
                }
            }
        }

        stage('Traffic Split 90/10') {
            steps {
                sh """
                sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:$BLUE_PORT weight=90/" /etc/nginx/sites-available/nest-proxy.conf
                sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:$CANARY_PORT weight=10/" /etc/nginx/sites-available/nest-proxy.conf

                sudo systemctl reload nginx
                sleep 10
                """
            }
        }

        stage('Health Check #2') {
            steps {
                script {
                    def code = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || true",
                        returnStdout: true
                    ).trim()

                    if (code != "200") {
                        error "❌ Canary failed during 90/10 stage"
                    }
                }
            }
        }

        stage('Promote 100% Canary') {
            steps {
                sh """
                sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${env.BLUE_PORT} weight=1/" /etc/nginx/sites-available/nest-proxy.conf
                sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${env.CANARY_PORT} weight=100/" /etc/nginx/sites-available/nest-proxy.conf

                sudo systemctl reload nginx
                """
            }
        }

        stage('Promote Canary to Blue (Zero Downtime)') {
            steps {
                sh """
                echo "Promoting Canary → Blue..."

                # Remove old blue
                docker stop digital-banking-blue 2>/dev/null || true
                docker rm digital-banking-blue 2>/dev/null || true

                # Rename canary to blue (container keeps running — ZERO downtime)
                docker rename digital-banking-canary digital-banking-blue

                # Clean any leftover duplicates (keeps only newest)
                docker ps -aq --filter "name=digital-banking-blue" | tail -n +2 | xargs -r docker rm -f || true

                echo "Promotion complete."
                """
            }
        }

        stage('Save LAST_SUCCESS Version') {
            steps {
                sh """
                echo "${BUILD_NUMBER}" > $LAST_SUCCESS_FILE
                echo "Saved stable version: ${BUILD_NUMBER}"
                """
            }
        }
    }

    post {
        failure {
            sh """
            echo "❌ Pipeline failed — rolling back canary."
            docker stop digital-banking-canary || true
            docker rm digital-banking-canary || true
            """
        }
        success {
            echo "🎉 CI/CD Canary Deployment SUCCESS — Version ${BUILD_NUMBER} is LIVE."
        }
    }
}
