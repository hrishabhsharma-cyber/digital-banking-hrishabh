pipeline {
    agent any
    
    environment {
        IMAGE_NAME = "hrishabhambak/digital-banking-hrishabh"
        IMAGE_TAG = "${BUILD_NUMBER}"
        ROLLBACK_DIR = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "${ROLLBACK_DIR}/LAST_SUCCESS"
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials-id')
    }
    
    stages {
        stage('Install Dependencies') {
            steps {
                script {
                    echo "Installing dependencies..."
                    sh 'npm install'
                }
            }
        }
        
        stage('Build NestJS Project') {
            steps {
                script {
                    echo "Building NestJS project..."
                    sh 'npm run build > build.log 2>&1'
                }
            }
            post {
                failure {
                    script {
                        echo "Node build FAILED."
                        sh 'cp build.log error.log'
                        error("Build failed")
                    }
                }
                success {
                    echo "Node build SUCCESS."
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
                }
            }
        }
        
        stage('Docker Login') {
            steps {
                script {
                    echo "Logging into Docker Hub..."
                    sh '''
                        echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin
                    '''
                }
            }
        }
        
        stage('Push Docker Image') {
            steps {
                script {
                    echo "Pushing image to Docker Hub..."
                    sh "docker push ${IMAGE_NAME}:${IMAGE_TAG}"
                    echo "Docker image pushed successfully: ${IMAGE_NAME}:${IMAGE_TAG}"
                }
            }
        }
        
        stage('Cleanup Build Artifacts') {
            steps {
                script {
                    echo "Removing local Docker image..."
                    sh "docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true"
                    
                    echo "Cleaning dist folder..."
                    sh 'rm -rf dist'
                }
            }
        }
        
        stage('Setup Canary Deployment') {
            steps {
                script {
                    echo "🔥 Starting CANARY Deployment for Digital Banking App"
                    echo "New version: ${IMAGE_TAG}"
                    
                    sh "mkdir -p ${ROLLBACK_DIR}"
                }
            }
        }
        
        stage('Detect Current Blue Port') {
            steps {
                script {
                    echo "Detecting current BLUE port..."
                    
                    def bluePort = sh(
                        script: '''
                            if docker ps --format '{{.Ports}}' --filter "name=digital-banking-blue" | grep -q "4001->"; then
                                echo "4001"
                            else
                                echo "4003"
                            fi
                        ''',
                        returnStdout: true
                    ).trim()
                    
                    def canaryPort = (bluePort == "4001") ? "4003" : "4001"
                    
                    env.BLUE_PORT = bluePort
                    env.CANARY_PORT = canaryPort
                    
                    echo "🔵 BLUE is running on port: ${env.BLUE_PORT}"
                    echo "🟡 CANARY will run on port: ${env.CANARY_PORT}"
                }
            }
        }
        
        stage('Start Canary Container') {
            steps {
                script {
                    echo "Cleaning any previous CANARY container..."
                    sh '''
                        docker stop digital-banking-canary 2>/dev/null || true
                        docker rm digital-banking-canary 2>/dev/null || true
                    '''
                    
                    echo "Force cleaning CANARY port: ${env.CANARY_PORT}..."
                    sh '''
                        docker ps -q --filter "publish=${CANARY_PORT}" | xargs -r docker stop || true
                        docker ps -aq --filter "publish=${CANARY_PORT}" | xargs -r docker rm || true
                    '''
                    
                    echo "Starting CANARY container on port ${env.CANARY_PORT}..."
                    sh """
                        docker run -d \
                            --name digital-banking-canary \
                            -p ${env.CANARY_PORT}:5000 \
                            -e PORT=5000 \
                            ${IMAGE_NAME}:${IMAGE_TAG}
                    """
                    
                    sleep 7
                }
            }
        }
        
        stage('Health Check Canary - Initial') {
            steps {
                script {
                    echo "🏥 Running initial health check on CANARY..."
                    
                    def healthStatus = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || echo '000'",
                        returnStdout: true
                    ).trim()
                    
                    echo "CANARY Health Status: ${healthStatus}"
                    
                    if (healthStatus != "200") {
                        error("❌ CANARY FAILED initial health check!")
                    }
                    
                    echo "✅ CANARY is HEALTHY."
                }
            }
            post {
                failure {
                    script {
                        echo "❌ CANARY FAILED! Starting rollback..."
                        sh '''
                            docker stop digital-banking-canary || true
                            docker rm digital-banking-canary || true
                        '''
                    }
                }
            }
        }
        
        stage('Apply 90/10 Traffic Split') {
            steps {
                script {
                    echo "⚡ Applying 90/10 Nginx weight distribution (BLUE/CANARY)..."
                    
                    sh """
                        sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${env.BLUE_PORT} weight=90/" /etc/nginx/sites-available/nest-proxy.conf
                        sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${env.CANARY_PORT} weight=10/" /etc/nginx/sites-available/nest-proxy.conf
                        sudo systemctl reload nginx
                    """
                    
                    echo "🟡 10% traffic → CANARY | 🔵 90% traffic → BLUE"
                    sleep 10
                }
            }
        }
        
        stage('Health Check Canary - Post Traffic') {
            steps {
                script {
                    echo "🏥 Second health check after traffic routing..."
                    
                    def healthStatus = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:${env.CANARY_PORT}/ || echo '000'",
                        returnStdout: true
                    ).trim()
                    
                    echo "CANARY Health Status: ${healthStatus}"
                    
                    if (healthStatus != "200") {
                        error("❌ CANARY degraded during test!")
                    }
                    
                    echo "🚀 CANARY is stable. Promoting to FULL PRODUCTION..."
                }
            }
            post {
                failure {
                    script {
                        echo "❌ CANARY degraded! Rolling back..."
                        sh '''
                            docker stop digital-banking-canary || true
                            docker rm digital-banking-canary || true
                        '''
                        
                        sh """
                            sudo sed -i "s/server 127.0.0.1:${env.BLUE_PORT} weight=[0-9]*/server 127.0.0.1:${env.BLUE_PORT} weight=100/" /etc/nginx/sites-available/nest-proxy.conf
                            sudo sed -i "s/server 127.0.0.1:${env.CANARY_PORT} weight=[0-9]*/server 127.0.0.1:${env.CANARY_PORT} weight=1/" /etc/nginx/sites-available/nest-proxy.conf
                            sudo systemctl reload nginx
                        """
                    }
                }
            }
        }
        
        stage('Promote Canary to Full Production') {
            steps {
                script {
                    echo "➡ Promoting CANARY to full production (100% traffic)..."
                    
                    sh """
                        sudo sed -i 's/server 127\\.0\\.0\\.1:${env.BLUE_PORT} weight=[0-9]\\+;/server 127.0.0.1:${env.BLUE_PORT} weight=1;/' /etc/nginx/sites-available/nest-proxy.conf
                        sudo sed -i 's/server 127\\.0\\.0\\.1:${env.CANARY_PORT} weight=[0-9]\\+;/server 127.0.0.1:${env.CANARY_PORT} weight=100;/' /etc/nginx/sites-available/nest-proxy.conf
                        sudo nginx -t
                        sudo systemctl reload nginx
                    """
                    
                    echo "➡ 100% traffic now routed to CANARY container (port ${env.CANARY_PORT})"
                }
            }
        }
        
        stage('Switch Canary to Blue') {
            steps {
                script {
                    echo "🟦 Removing old BLUE container..."
                    sh '''
                        docker stop digital-banking-blue || true
                        docker rm digital-banking-blue || true
                    '''
                    
                    echo "🟩 Promoting CANARY → BLUE..."
                    sh 'docker rename digital-banking-canary digital-banking-blue'
                }
            }
        }
        
        stage('Save Stable Version') {
            steps {
                script {
                    echo "Saving stable version..."
                    sh "echo '${IMAGE_TAG}' > ${LAST_SUCCESS_FILE}"
                    echo "🎉 Canary Deployment SUCCESS! Version ${IMAGE_TAG} promoted to BLUE on port ${env.CANARY_PORT}."
                }
            }
        }
    }
    
    post {
        success {
            echo "✅ Pipeline completed successfully!"
        }
        failure {
            echo "❌ Pipeline failed. Check logs for details."
        }
        always {
            echo "Pipeline execution finished."
        }
    }
}