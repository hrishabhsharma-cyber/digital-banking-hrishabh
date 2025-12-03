pipeline {
    agent any

    environment {
        IMAGE_NAME    = "hrishabhambak/digital-banking-hrishabh"
        ROLLBACK_DIR  = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "/var/lib/jenkins/rollback/LAST_SUCCESS"
        BLUE_PORT     = ""        // MUST USE = and MUST be valid syntax
        CANARY_PORT   = ""
    }

    stages {

        stage('Initial Env Check') {
            steps {
                echo "INIT: BLUE_PORT=$BLUE_PORT, CANARY_PORT=$CANARY_PORT"
            }
        }

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

        stage('Detect + Deploy Canary (atomic)') {
          steps {
            script {
              echo "▶ Detecting active BLUE port (atomic deploy)"
        
              // Extract blue port using bash (safe)
              def blue = sh(script: '''
                CID=$(docker ps --filter "name=digital-banking-blue" --format "{{.ID}}" | head -n 1)
                if [ -z "$CID" ]; then
                  echo "NO_CONTAINER"
                  exit 0
                fi
        
                docker inspect "$CID" --format '{{json .NetworkSettings.Ports}}' \
                  | grep -o '"HostPort":"[0-9]*"' \
                  | head -n 1 \
                  | sed 's/"HostPort":"//; s/"//'
              ''', returnStdout: true).trim()
        
              echo "BLUE extracted raw: '${blue}'"
        
              if (blue == "" || blue == "NO_CONTAINER" || !blue.isInteger()) {
                error "❌ Failed to detect BLUE_PORT. Extracted: '${blue}'"
              }
        
              def canary = (blue == "4001") ? "4003" : "4001"
              echo "Deploy plan: BLUE=${blue}, CANARY=${canary}"
        
              // Build deployment script with escaped $ for shell
              def deployCmd = """
                set -euo pipefail
        
                echo "1) Cleaning previous canary on port ${canary}..."
                docker stop digital-banking-canary 2>/dev/null || true
                docker rm  digital-banking-canary 2>/dev/null || true
                docker ps -q --filter "publish=${canary}" | xargs -r docker stop || true
                docker ps -aq --filter "publish=${canary}" | xargs -r docker rm || true
        
                echo "2) Starting canary (image: ${IMAGE_NAME}:${BUILD_NUMBER}) on ${canary}..."
                docker run -d --name digital-banking-canary -p ${canary}:5000 -e PORT=5000 ${IMAGE_NAME}:${BUILD_NUMBER}
                sleep 7
        
                echo "3) Health check (canary) at http://localhost:${canary}/"
                code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${canary}/ || true)
                if [ "\$code" != "200" ]; then
                  echo "Canary initial health check failed with HTTP \$code"
                  exit 2
                fi
        
                echo "4) Traffic split 90/10..."
                sudo sed -i "s/server 127.0.0.1:${blue} weight=[0-9]*/server 127.0.0.1:${blue} weight=90/" /etc/nginx/sites-available/nest-proxy.conf
                sudo sed -i "s/server 127.0.0.1:${canary} weight=[0-9]*/server 127.0.0.1:${canary} weight=10/" /etc/nginx/sites-available/nest-proxy.conf
                sudo systemctl reload nginx
                sleep 10
        
                echo "5) Health check during 90/10 split..."
                code=\$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${canary}/ || true)
                if [ "\$code" != "200" ]; then
                  echo "Canary degraded with HTTP \$code"
                  # Rollback traffic
                  sudo sed -i "s/server 127.0.0.1:${blue} weight=[0-9]*/server 127.0.0.1:${blue} weight=100/" /etc/nginx/sites-available/nest-proxy.conf
                  sudo sed -i "s/server 127.0.0.1:${canary} weight=[0-9]*/server 127.0.0.1:${canary} weight=0/" /etc/nginx/sites-available/nest-proxy.conf
                  sudo systemctl reload nginx || true
                  docker stop digital-banking-canary || true
                  docker rm  digital-banking-canary || true
                  exit 3
                fi
        
                echo "6) Promote canary to 100%..."
                sudo sed -i "s/server 127.0.0.1:${blue} weight=[0-9]*/server 127.0.0.1:${blue} weight=1/" /etc/nginx/sites-available/nest-proxy.conf
                sudo sed -i "s/server 127.0.0.1:${canary} weight=[0-9]*/server 127.0.0.1:${canary} weight=100/" /etc/nginx/sites-available/nest-proxy.conf
                sudo systemctl reload nginx
        
                echo "7) Rename canary to blue (zero downtime)..."
                docker stop digital-banking-blue 2>/dev/null || true
                docker rm   digital-banking-blue 2>/dev/null || true
        
                docker rename digital-banking-canary digital-banking-blue
        
                docker ps -aq --filter "name=digital-banking-blue" | tail -n +2 | xargs -r docker rm -f || true
        
                echo "8) Saving LAST_SUCCESS=${BUILD_NUMBER}"
                mkdir -p ${ROLLBACK_DIR}
                echo "${BUILD_NUMBER}" > ${LAST_SUCCESS_FILE}
              """
        
              sh deployCmd
        
              echo "Atomic deploy complete."
            }
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
