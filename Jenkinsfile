pipeline {
    agent none

    environment {
        IMAGE_TAG = "${BUILD_NUMBER}"
        IMAGE_NAME = "hrishabhambak/digital-banking-hrishabh"
        CONTAINER_NAME = "digital-banking-hrishabh"
        ROLLBACK_FOLDER = "${env.ROLLBACK_DIR}/Digital-Banking"
        LAST_SUCCESS_FILE = "${ROLLBACK_FOLDER}/LAST_SUCCESS"
        APP_PORT = "4001"
    }

    stages {
        stage('Init') {
            agent any
            steps {
                sh 'mkdir -p ${ROLLBACK_FOLDER} && [ -f ${LAST_SUCCESS_FILE} ] || echo "none" > ${LAST_SUCCESS_FILE}'
            }
        }

        // ═══════════════════════════════════════════
        // CI Checks - Runs inside Node container agent
        // ═══════════════════════════════════════════
        stage('CI & Build') {
            agent {
                docker {
                    image 'node:22-alpine'  // Project-specific Node version
                    args '-v $HOME/.npm:/root/.npm'  // Cache npm globally
                }
            }
            stages {
                stage('Install Deps') {
                    steps {
                        sh 'npm ci'
                    }
                }
                stage('CI Checks') {
                    parallel {
                        stage('Lint')     { steps { sh 'npm run lint' } }
                        stage('Test')     { steps { sh 'npm run test -- --coverage' } }
                        stage('Audit')    { steps { sh 'npm audit --audit-level=high || true' } }
                    }
                }
                stage('Build') {
                    steps {
                        sh 'npm run build'
                        stash includes: 'dist/**', name: 'build-artifacts'
                    }
                }
            }
        }

        // ═══════════════════════════════════════════
        // Docker stages - Runs on Jenkins agent
        // ═══════════════════════════════════════════
        stage('Docker') {
            agent any
            stages {
                stage('Login') {
                    steps {
                        withCredentials([usernamePassword(
                            credentialsId: 'registry-docker',
                            usernameVariable: 'REG_USER',
                            passwordVariable: 'REG_PASS'
                        )]) {
                            sh 'echo "$REG_PASS" | docker login ${REGISTRY_HOST} -u "$REG_USER" --password-stdin'
                        }
                    }
                }
                stage('Build & Push') {
                    steps {
                        unstash 'build-artifacts'
                        sh """
                            docker build --load -t ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG} -t ${REGISTRY_HOST}/${IMAGE_NAME}:latest .
                            docker push ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${REGISTRY_HOST}/${IMAGE_NAME}:latest
                            docker rmi ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG} ${REGISTRY_HOST}/${IMAGE_NAME}:latest || true
                        """
                    }
                }
                stage('Deploy') {
                    steps {
                        sh """
                            docker stop ${CONTAINER_NAME} || true
                            docker rm ${CONTAINER_NAME} || true
                            docker run -d --name ${CONTAINER_NAME} \
                                --restart unless-stopped \
                                -p ${APP_PORT}:5000 -e PORT=5000 \
                                ${REGISTRY_HOST}/${IMAGE_NAME}:${IMAGE_TAG}
                            sleep 5
                        """
                    }
                }
                stage('Health Check') {
                    steps {
                        sh "curl -sf --max-time 10 http://localhost:${APP_PORT}/ || exit 1"
                    }
                }
                stage('Save Version') {
                    steps {
                        sh "echo '${IMAGE_TAG}' > ${LAST_SUCCESS_FILE}"
                    }
                }
            }
        }
    }

    post {
        success { echo "🎉 SUCCESS: Released version ${IMAGE_TAG}" }
        failure {
            node('') {
                script {
                    def lastTag = sh(script: "cat ${LAST_SUCCESS_FILE} || echo 'none'", returnStdout: true).trim()
                    if (lastTag != "none" && lastTag != "") {
                        echo "🔄 Rolling back to: ${lastTag}"
                        sh """
                            docker stop ${CONTAINER_NAME} || true
                            docker rm ${CONTAINER_NAME} || true
                            docker run -d --name ${CONTAINER_NAME} --restart unless-stopped \
                                -p ${APP_PORT}:5000 -e PORT=5000 \
                                ${REGISTRY_HOST}/${IMAGE_NAME}:${lastTag}
                        """
                    }
                }
            }
        }
    }
}
