pipeline {
  agent {
    kubernetes {
      yaml '''
apiVersion: v1
kind: Pod
metadata:
  labels:
    app: jenkins-agent-dind
spec:
  containers:
  - name: docker
    image: docker:cli
    command:
    - cat
    tty: true
    env:
    - name: DOCKER_HOST
      value: tcp://localhost:2375
  - name: dind
    image: docker:dind
    securityContext:
      privileged: true
    env:
    - name: DOCKER_TLS_CERTDIR
      value: ""
'''
    }
  }

  options {
    disableConcurrentBuilds()
  }

  environment {
    REGISTRY = '192.168.142.1:5000'
    IMAGE_NAME = 'jenkins-argo-demo'
    REPO = 'sonmap/K8S_Argo_Jenkins_test01'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Skip GitOps Generated Commit') {
      steps {
        script {
          def msg = sh(returnStdout: true, script: 'git log -1 --pretty=%B').trim()
          if (msg.contains('[gitops]')) {
            echo 'GitOps-generated commit detected. Skip CI to prevent a commit loop.'
            env.SKIP_PIPELINE = 'true'
          } else {
            env.SKIP_PIPELINE = 'false'
          }
        }
      }
    }

    stage('Test') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        sh '''
          test -f app/Dockerfile
          test -f app/index.html
          grep -q "Jenkins + Argo CD" app/index.html
          echo "Basic source test passed"
        '''
      }
    }

    stage('Check Docker') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('docker') {
          sh '''
            docker version
            curl -fsS http://${REGISTRY}/v2/ >/dev/null || true
            echo "Docker and Local Registry test completed"
          '''
        }
      }
    }

    stage('Docker Build') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        script {
          env.IMAGE_TAG = "b${BUILD_NUMBER}"
        }
        container('docker') {
          sh '''
            docker build \
              -t ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} \
              ./app
          '''
        }
      }
    }

    stage('Push Local Registry') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        container('docker') {
          sh '''
            docker push ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
            curl -fsS http://${REGISTRY}/v2/${IMAGE_NAME}/tags/list || true
          '''
        }
      }
    }

    stage('Update GitOps Image Tag') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        sh '''
          sed -i "s#newName: .*#newName: ${REGISTRY}/${IMAGE_NAME}#" gitops/kustomization.yaml
          sed -i "s#newTag: .*#newTag: ${IMAGE_TAG}#" gitops/kustomization.yaml
          cat gitops/kustomization.yaml
        '''
      }
    }

    stage('Commit GitOps Change') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
          sh '''
            git config user.name "jenkins-bot"
            git config user.email "jenkins@local.lab"
            git add gitops/kustomization.yaml
            git commit -m "[gitops] deploy ${IMAGE_NAME}:${IMAGE_TAG}" || true
            git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git
            git push origin HEAD:main
          '''
        }
      }
    }
  }

  post {
    success {
      echo "CI completed. Argo CD should deploy ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}."
    }
    failure {
      echo 'Pipeline failed. Check Docker access, Registry connectivity, and github-pat credential.'
    }
  }
}
