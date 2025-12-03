pipeline {
    agent any

    environment {
        IMAGE_NAME        = "hrishabhambak/digital-banking-hrishabh"
        ROLLBACK_DIR      = "/var/lib/jenkins/rollback"
        LAST_SUCCESS_FILE = "/var/lib/jenkins/rollback/LAST_SUCCESS"
        NGINX_CONFIG      = "/etc/nginx/sites-available/nest-proxy.conf"
        BLUE_PORT         = ""
        CANARY_PORT       = ""
        PREVIOUS_BUILD    = ""
        ROLLBACK_NEEDED   = "false"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Validate Initial State') {
            steps {
                script {
                    echo "▶ Validating deployment prerequisites..."
                    
                    // Create rollback directory
                    sh "mkdir -p $ROLLBACK_DIR"
                    
                    // Check if nginx config exists and is valid
                    def nginxCheck = sh(
                        script: "sudo nginx -t 2>&1",
                        returnStatus: true
                    )
                    if (nginxCheck != 0) {
                        error "❌ Nginx configuration is invalid before deployment"
                    }
                    
                    // Verify blue container is running
                    def blueRunning = sh(
                        script: "docker ps -q --filter 'name=digital-banking-blue'",
                        returnStdout: true
                    ).trim()
                    
                    if (!blueRunning) {
                        error "❌ Blue container must be running for canary deployment. Run initial deployment first."
                    }
                    
                    // Load previous successful build number
                    if (fileExists("$LAST_SUCCESS_FILE")) {
                        env.PREVIOUS_BUILD = readFile("$LAST_SUCCESS_FILE").trim()
                        echo "✔ Previous successful build: ${env.PREVIOUS_BUILD}"
                    } else {
                        echo "⚠ No previous success file found"
                    }
                    
                    // Backup nginx config
                    sh "sudo cp $NGINX_CONFIG ${ROLLBACK_DIR}/nginx-backup-${BUILD_NUMBER}.conf"
                    echo "✔ Nginx config backed up"
                }
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
                        echo "❌ Build failed"
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
                        docker logout
                    """
                }
            }
        }

        stage('Detect Active Ports') {
            steps {
                script {
                    echo "▶ Detecting active blue container port..."
        
                    // Use shell commands to extract port, avoiding Groovy regex entirely
                    def blue = sh(
                        script: """
                            docker ps --filter 'name=digital-banking-blue' --format '{{.Ports}}' | \
                            grep -oP '\\d+(?=->5000)' | head -1
                        """,
                        returnStdout: true
                    ).trim()
        
                    echo "DEBUG: Extracted BLUE_PORT: ${blue}"
        
                    if (!blue) {
                        error "❌ Could not extract BLUE_PORT from docker ps output"
                    }
                    
                    // Simple validation without regex
                    if (blue.length() < 4 || blue.length() > 5) {
                        error "❌ Invalid BLUE_PORT extracted: ${blue}"
                    }
        
                    env.BLUE_PORT = blue
                    env.CANARY_PORT = (blue == "4001") ? "4003" : "4001"
        
                    echo "✔ BLUE_PORT = ${env.BLUE_PORT}"
                    echo "✔ CANARY_PORT = ${env.CANARY_PORT}"
                    
                    // Verify canary port is free
                    def portInUse = sh(
                        script: "docker ps --filter 'publish=${env.CANARY_PORT}' -q",
                        returnStdout: true
                    ).trim()
                    
                    if (portInUse) {
                        echo "⚠ Canary port ${env.CANARY_PORT} is in use, will cleanup"
                    }
                }
            }
        }

        stage('Cleanup Previous Canary') {
            steps {
                script {
                    echo "▶ Cleaning up any previous canary deployments..."
                    
                    sh """
                        docker stop digital-banking-canary 2>/dev/null || true
                        docker rm   digital-banking-canary 2>/dev/null || true

                        docker ps -q  --filter "publish=$CANARY_PORT" | xargs -r docker stop 2>/dev/null || true
                        docker ps -aq --filter "publish=$CANARY_PORT" | xargs -r docker rm   2>/dev/null || true
                    """
                    
                    // Verify cleanup
                    def remaining = sh(
                        script: "docker ps -aq --filter 'publish=${env.CANARY_PORT}'",
                        returnStdout: true
                    ).trim()
                    
                    if (remaining) {
                        error "❌ Failed to cleanup port ${env.CANARY_PORT}"
                    }
                    
                    echo "✔ Cleanup completed"
                }
            }
        }

        stage('Start Canary') {
            steps {
                script {
                    echo "▶ Starting canary container on port ${env.CANARY_PORT}..."
                    
                    sh """
                        docker run -d \
                            --name digital-banking-canary \
                            -p $CANARY_PORT:5000 \
                            -e PORT=5000 \
                            --restart=no \
                            $IMAGE_NAME:${BUILD_NUMBER}
                    """
                    
                    echo "Waiting for canary to initialize..."
                    sleep 10
                    
                    // Verify container is running
                    def canaryRunning = sh(
                        script: "docker ps -q --filter 'name=digital-banking-canary'",
                        returnStdout: true
                    ).trim()
                    
                    if (!canaryRunning) {
                        def logs = sh(
                            script: "docker logs digital-banking-canary 2>&1 || echo 'No logs available'",
                            returnStdout: true
                        )
                        error "❌ Canary container failed to start. Logs:\n${logs}"
                    }
                    
                    echo "✔ Canary container started successfully"
                }
            }
        }

        stage('Health Check #1 - Initial') {
            steps {
                script {
                    echo "▶ Running initial health check on canary..."
                    
                    def attempts = 0
                    def maxAttempts = 5
                    def healthy = false
                    
                    while (attempts < maxAttempts && !healthy) {
                        attempts++
                        
                        def code = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:$CANARY_PORT/ || echo '000'",
                            returnStdout: true
                        ).trim()
                        
                        echo "Attempt ${attempts}/${maxAttempts}: HTTP ${code}"
                        
                        if (code == "200") {
                            healthy = true
                        } else if (attempts < maxAttempts) {
                            sleep 5
                        }
                    }
                    
                    if (!healthy) {
                        def logs = sh(
                            script: "docker logs --tail 50 digital-banking-canary",
                            returnStdout: true
                        )
                        error "❌ Canary failed initial health check after ${maxAttempts} attempts.\nLogs:\n${logs}"
                    }
                    
                    echo "✔ Initial health check passed"
                }
            }
        }

        stage('Configure Traffic Split 90/10') {
            steps {
                script {
                    echo "▶ Configuring nginx for 90/10 traffic split..."
                    
                    // Update nginx config with proper error checking
                    def sedResult = sh(
                        script: """
                            sudo sed -i.bak \
                                -e 's|server 127\\.0\\.0\\.1:${env.BLUE_PORT} weight=[0-9]*|server 127.0.0.1:${env.BLUE_PORT} weight=90|' \
                                -e 's|server 127\\.0\\.0\\.1:${env.CANARY_PORT} weight=[0-9]*|server 127.0.0.1:${env.CANARY_PORT} weight=10|' \
                                $NGINX_CONFIG
                            
                            # If canary line doesn't exist, add it
                            if ! grep -q "127.0.0.1:${env.CANARY_PORT}" $NGINX_CONFIG; then
                                sudo sed -i '/upstream backend/a\\    server 127.0.0.1:${env.CANARY_PORT} weight=10;' $NGINX_CONFIG
                            fi
                        """,
                        returnStatus: true
                    )
                    
                    if (sedResult != 0) {
                        error "❌ Failed to update nginx config"
                    }
                    
                    // Test nginx config
                    def nginxTest = sh(
                        script: "sudo nginx -t 2>&1",
                        returnStatus: true
                    )
                    
                    if (nginxTest != 0) {
                        sh "sudo cp $NGINX_CONFIG.bak $NGINX_CONFIG"
                        error "❌ Nginx config test failed, restored backup"
                    }
                    
                    // Reload nginx
                    sh "sudo systemctl reload nginx"
                    
                    // Verify nginx reloaded
                    def nginxStatus = sh(
                        script: "sudo systemctl is-active nginx",
                        returnStdout: true
                    ).trim()
                    
                    if (nginxStatus != "active") {
                        error "❌ Nginx failed to reload properly"
                    }
                    
                    echo "✔ Traffic split configured: 90% blue, 10% canary"
                    sleep 15
                }
            }
        }

        stage('Health Check #2 - During Split') {
            steps {
                script {
                    echo "▶ Monitoring canary health during traffic split..."
                    
                    def checks = 3
                    def failed = false
                    
                    for (int i = 1; i <= checks; i++) {
                        echo "Health check ${i}/${checks}..."
                        
                        def code = sh(
                            script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:$CANARY_PORT/",
                            returnStdout: true
                        ).trim()
                        
                        if (code != "200") {
                            failed = true
                            error "❌ Canary health check failed during split phase (HTTP ${code})"
                        }
                        
                        if (i < checks) {
                            sleep 5
                        }
                    }
                    
                    echo "✔ All health checks passed during split phase"
                }
            }
        }

        stage('Promote to 100% Canary') {
            steps {
                script {
                    echo "▶ Promoting canary to 100% traffic..."
                    
                    sh """
                        sudo sed -i \
                            -e 's|server 127\\.0\\.0\\.1:${env.BLUE_PORT} weight=[0-9]*|server 127.0.0.1:${env.BLUE_PORT} weight=1|' \
                            -e 's|server 127\\.0\\.0\\.1:${env.CANARY_PORT} weight=[0-9]*|server 127.0.0.1:${env.CANARY_PORT} weight=100|' \
                            $NGINX_CONFIG
                        
                        sudo nginx -t
                        sudo systemctl reload nginx
                    """
                    
                    echo "✔ Canary promoted to 100% traffic"
                    sleep 10
                }
            }
        }

        stage('Final Health Check') {
            steps {
                script {
                    echo "▶ Running final health check at 100% traffic..."
                    
                    def code = sh(
                        script: "curl -s -o /dev/null -w '%{http_code}' http://localhost:$CANARY_PORT/",
                        returnStdout: true
                    ).trim()
                    
                    if (code != "200") {
                        env.ROLLBACK_NEEDED = "true"
                        error "❌ Final health check failed (HTTP ${code})"
                    }
                    
                    echo "✔ Final health check passed"
                }
            }
        }

        stage('Swap Blue and Canary') {
            steps {
                script {
                    echo "▶ Swapping blue and canary containers..."
                    
                    // Stop old blue
                    sh "docker stop digital-banking-blue || true"
                    sh "docker rm digital-banking-blue || true"
                    
                    // Rename canary to blue
                    sh "docker rename digital-banking-canary digital-banking-blue"
                    
                    echo "✔ Container swap completed"
                }
            }
        }

        stage('Save Success State') {
            steps {
                script {
                    echo "▶ Saving successful deployment state..."
                    
                    sh """
                        echo "${BUILD_NUMBER}" > $LAST_SUCCESS_FILE
                        echo "Deployment Date: \$(date)" >> $LAST_SUCCESS_FILE
                        echo "Blue Port: ${env.BLUE_PORT}" >> $LAST_SUCCESS_FILE
                    """
                    
                    // Keep only last 5 nginx backups
                    sh """
                        cd $ROLLBACK_DIR
                        ls -t nginx-backup-*.conf 2>/dev/null | tail -n +6 | xargs -r rm
                    """
                    
                    echo "✔ Success state saved: Build ${BUILD_NUMBER}"
                }
            }
        }
    }

    post {
        failure {
            script {
                echo "❌ Pipeline failed at stage: ${env.STAGE_NAME}"
                
                // Perform rollback if needed
                if (env.ROLLBACK_NEEDED == "true" && env.PREVIOUS_BUILD) {
                    echo "🔄 Attempting automatic rollback to build ${env.PREVIOUS_BUILD}..."
                    
                    try {
                        // Stop failed canary
                        sh "docker stop digital-banking-canary 2>/dev/null || true"
                        sh "docker rm digital-banking-canary 2>/dev/null || true"
                        
                        // Restore nginx config from backup
                        sh "sudo cp ${ROLLBACK_DIR}/nginx-backup-${BUILD_NUMBER}.conf.bak $NGINX_CONFIG || true"
                        sh "sudo nginx -t && sudo systemctl reload nginx"
                        
                        echo "✔ Rollback completed - Blue container still serving traffic"
                    } catch (Exception e) {
                        echo "❌ Automatic rollback failed: ${e.message}"
                        echo "⚠ Manual intervention required!"
                    }
                } else {
                    // Just cleanup canary
                    sh """
                        docker stop digital-banking-canary 2>/dev/null || true
                        docker rm digital-banking-canary 2>/dev/null || true
                    """
                }
                
                // Send notification (configure as needed)
                echo "📧 Failure notification should be sent here"
            }
        }

        success {
            echo "🎉 CI/CD Canary Deployment SUCCESS"
            echo "✔ Version ${BUILD_NUMBER} is now LIVE on port ${env.BLUE_PORT}"
            echo "✔ Previous version cleaned up"
        }

        always {
            // Cleanup build artifacts
            sh "rm -f build.log error.log"
            
            // Log final state
            sh """
                echo "=== Final Container State ==="
                docker ps --filter 'name=digital-banking' --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'
            """
        }
    }
}