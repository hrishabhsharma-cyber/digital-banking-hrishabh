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
    }
}
