pipeline {
    agent any

    environment {
        IMAGE_NAME        = "hrishabhambak/digital-banking-hrishabh"
        ROLLBACK_DIR      = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "/var/lib/jenkins/rollback/LAST_SUCCESS"
        // initialize as empty; will be set in Detect Active Ports
        BLUE_PORT  = ""
        CANARY_PORT = ""
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Install Dependencies') {
            steps { sh 'npm install' }
        }

        stage('Build App') {
            steps {
                sh '''
                    npm run build > build.log 2>&1 || {
                      echo "Build failed"
                      cp build.log error.log
                      exit 1
                    }
                '''
            }
        }

        stage('Docker Build') {
            steps { sh "docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} ." }
        }

        stage('Docker Push') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-credentials',
                    usernameVariable: 'DOCKER_USER',
                    passwordVariable: 'DOCKER_PASS'
                )]) {
                    // Use Groovy interpolation for credentials/IMAGE_NAME/BUILD_NUMBER
                    sh '''
                        echo "${DOCKER_PASS}" | docker login -u "${DOCKER_USER}" --password-stdin
                        docker push ${IMAGE_NAME}:${BUILD_NUMBER}
                    '''.replace('${DOCKER_PASS}', env.DOCKER_PASS)
                      .replace('${DOCKER_USER}', env.DOCKER_USER)
                      .replace('${IMAGE_NAME}', env.IMAGE_NAME)
                      .replace('${BUILD_NUMBER}', env.BUILD_NUMBER)
                }
            }
        }

        stage('Detect Active Ports') {
            steps {
                script {
                    echo "▶ Checking running BLUE container..."

                    def portInfo = sh(
                        script: "docker ps --filter 'name=digital-banking-blue' --format '{{.Ports}}'",
                        returnStdout: true
                    ).trim()

                    echo "DEBUG: docker ps Ports Output: ${portInfo}"

                    if (!portInfo) {
                        error "❌ No port info — digital-banking-blue is not running."
                    }

                    // SPLIT-based extraction (no matcher/regex objects)
                    def firstSegment = portInfo.split(',')[0].trim()                 // "0.0.0.0:4003->5000/tcp"
                    def afterColon = firstSegment.substring(firstSegment.lastIndexOf(':') + 1) // "4003->5000/tcp"
                    def blue = afterColon.split('->')[0]                             // "4003"

                    if (!blue?.isNumber()) {
                        error "❌ Could not parse BLUE_PORT from: ${portInfo}"
                    }

                    // Persist into env so later stages can use ${env.BLUE_PORT} or $BLUE_PORT in the shell
                    env.BLUE_PORT = blue
                    env.CANARY_PORT = (blue == "4001") ? "4003" : "4001"

                    echo "✔ BLUE_PORT  = ${env.BLUE_PORT}"
                    echo "✔ CANARY_PORT = ${env.CANARY_PORT}"

                    sh "mkdir -p ${ROLLBACK_DIR}"
                }
            }
        }

        stage('Cleanup Previous Canary') {
            steps {
                // Use single-quoted shell block so Groovy doesn't attempt interpolation of $CANARY_PORT.
                // We reference it as ${env.CANARY_PORT} in Groovy only where we need to build the command string.
                script {
                    def cmd = "docker stop digital-banking-canary 2>/dev/null || true\n" +
                              "docker rm digital-banking-canary 2>/dev/null || true\n" +
                              "docker ps -q --filter \"publish=${env.CANARY_PORT}\" | xargs -r docker stop || true\n" +
                              "docker ps -aq --filter \"publish=${env.CANARY_PORT}\" | xargs -r docker rm || true\n"
                    sh cmd
                }
            }
        }

        stage('Start Canary') {
            steps {
                // Build command string in Groovy using ${env.CANARY_PORT} then run as sh
                script {
                    def cmd = """docker run -d --name digital-banking-canary -p ${env.CANARY_PORT}:5000 -e PORT=5000 ${env.IMAGE_NAME}:${env.BUILD_NUMBER}
sleep 7"""
                    sh cmd
                }
            }
        }

        stage('Health Check #1') {
            steps {
                script {
                    def code = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || true", returnStdout: true).trim()
                    if (code != "200") { error "❌ Canary failed initial health check" }
                }
            }
        }

        stage('Traffic Split 90/10') {
            steps {
                // Use Groovy to compose the commands that include env vars, then pass to sh
                script {
                    def cmd = """
sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${env.BLUE_PORT} weight=90/" /etc/nginx/sites-available/nest-proxy.conf
sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${env.CANARY_PORT} weight=10/" /etc/nginx/sites-available/nest-proxy.conf
sudo systemctl reload nginx
sleep 10
"""
                    sh cmd
                }
            }
        }

        stage('Health Check #2') {
            steps {
                script {
                    def code = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || true", returnStdout: true).trim()
                    if (code != "200") { error "❌ Canary degraded during 90/10 phase" }
                }
            }
        }

        stage('Promote 100% Canary') {
            steps {
                script {
                    def cmd = """
sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${env.BLUE_PORT} weight=1/" /etc/nginx/sites-available/nest-proxy.conf
sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${env.CANARY_PORT} weight=100/" /etc/nginx/sites-available/nest-proxy.conf
sudo systemctl reload nginx
"""
                    sh cmd
                }
            }
        }

        stage('Promote Canary to Blue (Zero Downtime)') {
            steps {
                script {
                    // Compose the promote commands using env vars (Groovy interpolation happens here)
                    def cmd = """
echo "Promoting Canary -> Blue"
docker stop digital-banking-blue 2>/dev/null || true
docker rm digital-banking-blue 2>/dev/null || true
docker rename digital-banking-canary digital-banking-blue
# remove duplicate older blues if any (keep newest)
docker ps -aq --filter "name=digital-banking-blue" | tail -n +2 | xargs -r docker rm -f || true
echo "Promotion complete"
"""
                    sh cmd
                }
            }
        }

        stage('Save LAST_SUCCESS Version') {
            steps {
                sh "echo \"${BUILD_NUMBER}\" > ${LAST_SUCCESS_FILE}"
                sh "echo \"Saved stable version: ${BUILD_NUMBER}\""
            }
        }
    }

    post {
        failure {
            sh '''
                echo "❌ Pipeline failed — ensuring rollback safety."
                docker stop digital-banking-canary || true
                docker rm digital-banking-canary || true
            '''
        }
        success {
            echo "🎉 CI/CD Canary Deployment SUCCESS — Version ${BUILD_NUMBER} is LIVE."
        }
    }
}
