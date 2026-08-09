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
    args:
    - --insecure-registry=192.168.142.101:30500
'''
    }
  }

  options {
    disableConcurrentBuilds()
  }

  environment {
    REGISTRY = '192.168.142.101:30500'
    FRONTEND_IMAGE = 'jenkins-argo-demo'
    BACKEND_IMAGE = 'jenkins-argo-backend'
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

    stage('Test Source') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        sh '''
          test -f app/Dockerfile
          test -f app/index.html
          test -f app/frontend.html
          test -f app/nginx.conf
          test -f backend/Dockerfile
          test -f backend/pom.xml
          test -f backend/src/main/java/com/example/demo/CustomerController.java
          grep -q "Jenkins + Argo CD" app/index.html
          grep -q "/api/customers" app/frontend.html
          echo "Frontend + Backend source test passed"
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
            echo "Waiting for Docker daemon"
            COUNT=0
            until docker info >/dev/null 2>&1
            do
              COUNT=$((COUNT+1))
              if [ "$COUNT" -ge 30 ]; then
                echo "ERROR: Docker daemon startup timeout"
                exit 1
              fi
              echo "Waiting Docker daemon... ${COUNT}/30"
              sleep 2
            done
            docker version
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
            echo "Build Frontend: ${REGISTRY}/${FRONTEND_IMAGE}:${IMAGE_TAG}"
            docker build \
              -t ${REGISTRY}/${FRONTEND_IMAGE}:${IMAGE_TAG} \
              ./app

            echo "Build Backend: ${REGISTRY}/${BACKEND_IMAGE}:${IMAGE_TAG}"
            docker build \
              -t ${REGISTRY}/${BACKEND_IMAGE}:${IMAGE_TAG} \
              ./backend
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
            docker push ${REGISTRY}/${FRONTEND_IMAGE}:${IMAGE_TAG}
            docker push ${REGISTRY}/${BACKEND_IMAGE}:${IMAGE_TAG}

            echo "Frontend tags:"
            curl -fsS http://${REGISTRY}/v2/${FRONTEND_IMAGE}/tags/list || true
            echo ""
            echo "Backend tags:"
            curl -fsS http://${REGISTRY}/v2/${BACKEND_IMAGE}/tags/list || true
          '''
        }
      }
    }

    stage('Update GitOps Image Tags') {
      when {
        expression { env.SKIP_PIPELINE != 'true' }
      }
      steps {
        sh '''
          sed -i "/- name: jenkins-argo-demo/{n;s#newName: .*#newName: ${REGISTRY}/${FRONTEND_IMAGE}#;n;s#newTag: .*#newTag: ${IMAGE_TAG}#}" gitops/kustomization.yaml
          sed -i "/- name: jenkins-argo-backend/{n;s#newName: .*#newName: ${REGISTRY}/${BACKEND_IMAGE}#;n;s#newTag: .*#newTag: ${IMAGE_TAG}#}" gitops/kustomization.yaml
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
            git commit -m "[gitops] deploy frontend/backend ${IMAGE_TAG}" || true
            git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git
            git push origin HEAD:main
          '''
        }
      }
    }
  }

  post {
    success {
      echo "CI completed. Argo CD should deploy frontend/backend ${IMAGE_TAG} and MySQL demo resources."
    }
    failure {
      echo 'Pipeline failed. Check Docker, Maven dependency download, Registry connectivity, and github-pat credential.'
    }
  }
}
