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

        stage('CI Checks') {
            parallel {
                stage('Lint') {
                    steps {
                        cache(maxCacheSize: 1, caches: [
                            arbitraryFileCache(path: 'node_modules', cacheValidityDecidingFile: 'package-lock.json')
                        ]) {
                            sh "npm ci && npm run lint"
                        }
                    }
                }
                stage('Unit Tests') {
                    steps {
                        cache(maxCacheSize: 1, caches: [
                            arbitraryFileCache(path: 'node_modules', cacheValidityDecidingFile: 'package-lock.json')
                        ]) {
                            sh "npm ci && npm run test -- --coverage"
                        }
                    }
                }
                stage('Security Scan') {
                    steps {
                        cache(maxCacheSize: 1, caches: [
                            arbitraryFileCache(path: 'node_modules', cacheValidityDecidingFile: 'package-lock.json')
                        ]) {
                           sh "npm audit --audit-level=high"
                        }
                    }
                }
            }
        }

        stage('Build App') {
            steps {
                echo "Installing deps & building NestJS..."
                sh """
                    npm ci
                    npm run build > build.log 2>&1 || {
                        cp build.log error.log
                        exit 1
                    }
                """
                archiveArtifacts artifacts: 'dist/**', fingerprint: true
            }
        }


        stage('Docker Build & Push') {
            steps {
                echo "Building & pushing image ${IMAGE_NAME}:${IMAGE_TAG}"
                sh """
                    # Pull latest for caching
                    docker pull ${IMAGE_NAME}:latest || true

                    docker build \
                        --cache-from=${IMAGE_NAME}:latest \
                        -t ${IMAGE_NAME}:${IMAGE_TAG} .

                    echo ${DOCKERHUB_PSW} | docker login -u ${DOCKERHUB_USR} --password-stdin
                    docker push ${IMAGE_NAME}:${IMAGE_TAG}

                    # Update latest tag for future cache builds
                    docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                    docker push ${IMAGE_NAME}:latest

                    docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                    docker rmi ${IMAGE_NAME}:latest || true

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
        failure {
            script {
                echo "❌ FAILURE DETECTED — Initiating rollback..."
        
                def lastTag = sh(script: "cat ${LAST_SUCCESS_FILE} || echo 'none'", returnStdout: true).trim()
                if (lastTag == "none" || lastTag == "") {
                    echo "⚠️ No LAST_SUCCESS version found. Cannot rollback."
                    return
                }
        
                echo "🔄 Rolling back to version: ${lastTag}"
        
                sh """
                    echo "📥 Pulling stable image..."
                    docker pull ${IMAGE_NAME}:${lastTag}
                """
        
                sh """
                    echo "🛑 Stopping failed containers..."
                    docker stop digital-banking-blue || true
                    docker rm digital-banking-blue || true
        
                    docker stop digital-banking-canary || true
                    docker rm digital-banking-canary || true
                """
        
                sh """
                    echo "🚀 Starting rollback BLUE container..."
                    docker run -d --name digital-banking-blue \\
                        -p 4001:5000 -e PORT=5000 \\
                        ${IMAGE_NAME}:${lastTag}
                """
        
                sh """
                    echo "🔧 Resetting Nginx to 100% BLUE..."
                    sudo sed -i "s/server 127.0.0.1:4001.*/server 127.0.0.1:4001 weight=100;/" /etc/nginx/sites-available/nest-proxy.conf
                    sudo sed -i "s/server 127.0.0.1:4003.*/server 127.0.0.1:4003 weight=1;/" /etc/nginx/sites-available/nest-proxy.conf
                    sudo nginx -t
                    sudo systemctl reload nginx
                """
        
                def health = sh(script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:4001/ || echo 000", returnStdout: true).trim()
        
                if (health != "200") {
                    echo "🔥 ROLLBACK FAILED! BLUE is unhealthy even after rollback. Manual intervention required!"
                } else {
                    echo "✅ ROLLBACK SUCCESS — system restored to stable version ${lastTag}"
                }
            }
        }

        always  { echo "Pipeline finished." }
    }
}
