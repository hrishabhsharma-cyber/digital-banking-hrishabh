pipeline {
    agent any

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Dependencies') {
            steps {
                sh 'npm install'
            }
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
            steps {
                sh "docker build -t hrishabhambak/digital-banking-hrishabh:${env.BUILD_NUMBER} ."
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
                        docker push hrishabhambak/digital-banking-hrishabh:${env.BUILD_NUMBER}
                    """
                }
            }
        }
    }
}
