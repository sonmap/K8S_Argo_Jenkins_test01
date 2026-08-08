# K8S Argo CD + Jenkins Test Lab

VMware Workstation 기반 Kubernetes 실습 환경에서 **Jenkins CI + Local Registry + GitHub GitOps + Argo CD CD** 흐름을 검증하기 위한 테스트 저장소입니다.

## 목표 아키텍처

```text
GitHub APP/GitOps Repo
        |
        | git push / poll
        v
     Jenkins (CI)
        |
        | build / test / image push
        v
Local Registry 192.168.142.1:5000
        |
        | manifest image tag update
        v
      GitHub
        |
        v
     Argo CD (CD)
        |
        v
 Kubernetes Rolling Update
```

## 기본 가정

- Kubernetes Control Plane: `son01` (`192.168.142.101`)
- Worker: `son02` (메모리가 허용되면 `son03` 추가)
- Local Registry: `192.168.142.1:5000`
- Argo CD namespace: `argocd`
- Demo namespace: `cicd-demo`
- 기본 replica: `1` (저메모리 실습용)
- HA 테스트 시 replica를 `2`로 변경

> `192.168.142.1:5000`은 현재 VMware VMnet8 예시입니다. 실제 Registry IP가 다르면 `Jenkinsfile`과 `gitops/kustomization.yaml`을 수정하세요.

## 저장소 구조

```text
.
├── app/
│   ├── Dockerfile
│   └── index.html
├── argocd/
│   └── application.yaml
├── gitops/
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   └── service.yaml
├── scripts/
│   └── verify.sh
├── Jenkinsfile
├── Jenkinsfile.smoke
└── TEST_CASES.md
```

## 1. Argo CD Application 등록

```bash
kubectl apply -f argocd/application.yaml
kubectl get application -n argocd
```

Argo CD UI에서 `k8s-argo-jenkins-test01` Application이 `Synced / Healthy`가 되는지 확인합니다.

CLI 확인:

```bash
kubectl get pods -n cicd-demo -o wide
kubectl get svc -n cicd-demo
```

## 2. Jenkins Smoke Pipeline

Docker 빌드 없이 Jenkins → GitHub → Argo CD 동기화만 먼저 검증하려면 `Jenkinsfile.smoke`를 사용합니다.

Jenkins Pipeline 설정:

- Repository: `https://github.com/sonmap/K8S_Argo_Jenkins_test01.git`
- Script Path: `Jenkinsfile.smoke`
- GitHub push용 Jenkins Credential ID: `github-pat`

Pipeline은 `gitops/configmap.yaml`의 화면 메시지를 Build 번호로 바꾸고 GitHub에 커밋합니다. Argo CD가 변경을 감지하여 클러스터에 적용하는지 확인합니다.

## 3. Full CI/CD Pipeline

`Jenkinsfile`은 다음을 수행합니다.

1. Checkout
2. HTML 기본 검증
3. Docker image build
4. Local Registry push
5. `gitops/kustomization.yaml`의 image tag 수정
6. GitHub commit/push
7. Argo CD가 자동 Sync
8. Kubernetes Rolling Update

Jenkins 실행 노드에는 `docker` CLI/daemon이 사용 가능해야 합니다.

예상 이미지:

```text
192.168.142.1:5000/jenkins-argo-demo:b100
```

## 4. 배포 확인

```bash
bash scripts/verify.sh
```

또는:

```bash
kubectl get all -n cicd-demo
kubectl rollout status deployment/demo-web -n cicd-demo
kubectl get pods -n cicd-demo -o wide
```

## 5. HA 테스트

Worker가 2대 켜져 있을 때:

```bash
kubectl scale deployment demo-web -n cicd-demo --replicas=2
kubectl get pods -n cicd-demo -o wide
```

`son02`, `son03`에 분산되는지 확인한 후 Pod 하나를 삭제합니다.

```bash
kubectl delete pod -n cicd-demo <POD_NAME>
kubectl get pods -n cicd-demo -w
```

Deployment가 새 Pod를 자동 생성하는지 확인합니다.

자세한 테스트 항목은 [`TEST_CASES.md`](TEST_CASES.md)를 참고하세요.
