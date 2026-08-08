# Jenkins + Argo CD 테스트 케이스

## 1. 테스트 목적

다음 CI/CD 및 GitOps 흐름을 단계적으로 검증합니다.

```text
GitHub
  ↓
Jenkins CI
  ├─ Source Test
  ├─ Docker Build
  └─ Local Registry Push
          ↓
GitHub GitOps Manifest 변경
          ↓
Argo CD Auto Sync / Self Heal
          ↓
Kubernetes Rolling Update
```

## 2. 테스트 환경 가정

| 항목 | 값 |
|---|---|
| Kubernetes Control Plane | son01 / 192.168.142.101 |
| Worker | son02, 필요 시 son03 |
| Jenkins | Kubernetes 내부 설치 |
| Argo CD | Kubernetes 내부 설치 |
| Local Registry | 192.168.142.1:5000 |
| GitHub | sonmap/K8S_Argo_Jenkins_test01 |
| Demo Namespace | cicd-demo |
| Argo Application | k8s-argo-jenkins-test01 |

메모리가 부족하면 `son03`을 종료하고 `replicas: 1`로 테스트합니다. HA 테스트 때만 `son03`을 켜고 `replicas: 2`로 변경합니다.

---

# TC-01. Kubernetes / Jenkins / Argo CD 기본 Health Check

**목적**: CI/CD 테스트 전 플랫폼이 정상인지 확인합니다.

**명령**:

```bash
kubectl get nodes -o wide
kubectl get pods -n jenkins -o wide
kubectl get pods -n argocd -o wide
kubectl get svc -n jenkins
kubectl get svc -n argocd
```

**기대 결과**:

- son01 `Ready`
- 사용 중인 Worker `Ready`
- Jenkins Controller `Running`
- Argo CD 주요 Pod `Running`
- Jenkins/Argo CD UI 접속 가능

**실패 시 확인**:

```bash
free -h
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
```

---

# TC-02. Argo CD Application 등록

**목적**: Argo CD가 GitHub의 `gitops/` 디렉터리를 감시하도록 등록합니다.

**실행**:

```bash
kubectl apply -f argocd/application.yaml
kubectl get application -n argocd
```

상세 확인:

```bash
kubectl describe application k8s-argo-jenkins-test01 -n argocd
```

**기대 결과**:

```text
SYNC STATUS   HEALTH STATUS
Synced        Healthy
```

---

# TC-03. 초기 GitOps 배포

**목적**: GitHub에 저장된 Kustomize manifest가 Kubernetes에 자동 배포되는지 확인합니다.

**실행**:

```bash
kubectl get all -n cicd-demo
kubectl get pods -n cicd-demo -o wide
kubectl get svc -n cicd-demo
```

**기대 결과**:

- `demo-web` Deployment 생성
- Pod `1/1 Running`
- Service Type = `LoadBalancer`
- MetalLB `EXTERNAL-IP` 자동 할당

VIP 확인:

```bash
kubectl get svc demo-web -n cicd-demo
```

브라우저:

```text
http://<EXTERNAL-IP>/
http://<EXTERNAL-IP>/status.html
```

---

# TC-04. Jenkins GitHub Checkout

**목적**: Jenkins가 GitHub Repository를 정상적으로 읽는지 확인합니다.

Jenkins Pipeline 생성:

```text
Pipeline definition : Pipeline script from SCM
SCM                 : Git
Repository URL      : https://github.com/sonmap/K8S_Argo_Jenkins_test01.git
Branch              : */main
Script Path         : Jenkinsfile.smoke
```

**기대 결과**:

- Checkout 성공
- Workspace에 `app`, `gitops`, `argocd` 디렉터리가 존재

---

# TC-05. Jenkins → GitHub → Argo CD Smoke Test

**목적**: Docker Build 없이 GitOps 연동만 먼저 검증합니다.

Jenkins Script Path:

```text
Jenkinsfile.smoke
```

사전 조건:

Jenkins Credential에 GitHub PAT를 등록합니다.

```text
Kind          : Secret text
ID            : github-pat
Secret        : GitHub PAT
```

PAT에는 이 Repository의 Contents Read/Write 권한이 필요합니다.

Jenkins에서 `Build Now` 실행.

Pipeline이 다음 파일을 변경합니다.

```text
gitops/configmap.yaml
```

예:

```text
Last Jenkins update: build-10
```

**기대 결과**:

1. Jenkins Build SUCCESS
2. GitHub main에 `[gitops] smoke build ...` commit 생성
3. Argo CD가 OutOfSync를 감지
4. 자동으로 `Synced / Healthy` 복귀
5. `/status.html` 페이지의 build 번호 변경

검증:

```bash
kubectl get configmap demo-status -n cicd-demo -o yaml
```

---

# TC-06. Local Registry 연결 테스트

**목적**: Jenkins 실행 노드에서 Local Registry에 접근할 수 있는지 확인합니다.

Jenkins 실행 노드 또는 Agent에서:

```bash
curl http://192.168.142.1:5000/v2/
docker version
```

**기대 결과**:

```text
{}
```

그리고 Docker Client/Daemon 정상 확인.

Registry catalog:

```bash
curl http://192.168.142.1:5000/v2/_catalog
```

---

# TC-07. Full Jenkins CI - Docker Build / Push

**목적**: Application image를 Build하고 Local Registry에 Push합니다.

Jenkins Script Path:

```text
Jenkinsfile
```

Jenkins `Build Now` 실행.

예상 이미지:

```text
192.168.142.1:5000/jenkins-argo-demo:b10
```

Registry 확인:

```bash
curl http://192.168.142.1:5000/v2/jenkins-argo-demo/tags/list
```

**기대 결과**:

```json
{"name":"jenkins-argo-demo","tags":["b10"]}
```

---

# TC-08. Jenkins Image Tag 변경 → Argo CD Rolling Update

**목적**: Jenkins가 새 image tag를 GitOps manifest에 기록하고 Argo CD가 배포하는지 확인합니다.

변경 대상:

```text
gitops/kustomization.yaml
```

예:

```yaml
images:
  - name: jenkins-argo-demo
    newName: 192.168.142.1:5000/jenkins-argo-demo
    newTag: b10
```

Jenkins 성공 후 확인:

```bash
kubectl get deployment demo-web -n cicd-demo -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

**기대 결과**:

```text
192.168.142.1:5000/jenkins-argo-demo:b10
```

Rolling Update 확인:

```bash
kubectl rollout status deployment/demo-web -n cicd-demo
kubectl get rs -n cicd-demo
kubectl get pods -n cicd-demo -o wide
```

---

# TC-09. Argo CD Self-Heal 테스트

**목적**: 운영자가 Kubernetes를 직접 변경했을 때 Git 상태로 자동 복원되는지 검증합니다.

현재 desired replica는 1입니다.

의도적으로 변경:

```bash
kubectl scale deployment demo-web -n cicd-demo --replicas=2
kubectl get deployment demo-web -n cicd-demo
```

Argo CD `selfHeal: true`이므로 Git의 desired state인 `replicas: 1`로 다시 돌아오는지 확인합니다.

```bash
watch kubectl get deployment demo-web -n cicd-demo
```

**기대 결과**:

```text
replicas 2 → replicas 1
```

이 테스트는 "운영자가 kubectl로 임의 변경해도 Git이 기준"이라는 GitOps 특성을 검증합니다.

---

# TC-10. Pod 장애 자동복구

**목적**: Deployment가 장애 난 Pod를 자동 복구하는지 확인합니다.

```bash
kubectl get pods -n cicd-demo
kubectl delete pod -n cicd-demo <DEMO_WEB_POD>
```

실시간 확인:

```bash
kubectl get pods -n cicd-demo -w
```

**기대 결과**:

- 기존 Pod 삭제
- ReplicaSet이 신규 Pod 자동 생성
- 최종 `1/1 Running`

---

# TC-11. 잘못된 Image Tag 장애 테스트

**목적**: GitOps에 잘못된 image tag가 들어갔을 때 장애 상태와 복구 절차를 확인합니다.

테스트 브랜치 또는 의도적인 Git 변경으로:

```yaml
newTag: does-not-exist
```

Commit 후:

```bash
kubectl get pods -n cicd-demo
```

**예상 장애**:

```text
ImagePullBackOff
```

상세 확인:

```bash
kubectl describe pod -n cicd-demo <POD_NAME>
```

**복구**:

GitHub에서 정상 `newTag`로 되돌리고 commit.

**기대 결과**:

Argo CD가 정상 tag를 다시 적용하고 Pod가 `Running`으로 복구됩니다.

---

# TC-12. Argo CD Drift / 수동 변경 복구

**목적**: Kubernetes object의 Git 외 변경을 Argo CD가 되돌리는지 확인합니다.

의도적으로 image 변경:

```bash
kubectl set image deployment/demo-web \
  demo-web=nginx:1.28-alpine \
  -n cicd-demo
```

확인:

```bash
kubectl get deployment demo-web -n cicd-demo \
  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

Argo CD Self Heal 후 Git의 image로 복귀하는지 확인합니다.

---

# TC-13. Git Rollback 테스트

**목적**: 배포 실패 시 Git revert만으로 이전 버전으로 복구할 수 있는지 확인합니다.

GitHub에서 최신 GitOps image tag commit을 revert 합니다.

Argo CD 확인:

```bash
kubectl get application k8s-argo-jenkins-test01 -n argocd
kubectl rollout status deployment/demo-web -n cicd-demo
```

**기대 결과**:

- Git의 이전 image tag로 자동 복귀
- Deployment Rolling Update 완료

---

# TC-14. Worker 2대 HA / Pod 분산 테스트

**조건**: son02 + son03 모두 `Ready`일 때만 수행합니다.

Git에서 `gitops/deployment.yaml`을 다음과 같이 변경합니다.

```yaml
replicas: 2
```

Commit 후 Argo CD Sync 확인:

```bash
kubectl get pods -n cicd-demo -o wide
```

**기대 결과**:

가능하면 Pod가 서로 다른 노드에 분산됩니다.

```text
demo-web-...   son02
demo-web-...   son03
```

현재 manifest는 `topologySpreadConstraints`를 포함합니다.

---

# TC-15. Worker 장애 테스트

**조건**: Worker 2대 + replicas 2 상태.

son02에서 서비스되는 Pod를 확인한 후 VMware에서 son02를 종료하거나 Kubernetes에서 drain 합니다.

계획 점검 테스트:

```bash
kubectl drain son02 --ignore-daemonsets --delete-emptydir-data
```

상태 확인:

```bash
kubectl get nodes
kubectl get pods -n cicd-demo -o wide
```

**기대 결과**:

- son02 Pod 제거/재배치
- son03에서 서비스 지속 가능

테스트 종료:

```bash
kubectl uncordon son02
```

---

# TC-16. Registry 장애 테스트

**목적**: Registry 장애 시 기존 Pod와 신규 배포의 차이를 확인합니다.

Local Registry를 일시 중단합니다.

기존 실행 중 Pod는 일반적으로 계속 서비스합니다.

새 Pod를 강제로 만들면 image가 Node cache에 없는 경우 Pull 실패가 발생할 수 있습니다.

확인:

```bash
kubectl describe pod -n cicd-demo <POD_NAME>
```

**검증 포인트**:

- 기존 Pod 서비스 지속 여부
- 신규 Pod `ImagePullBackOff` 여부
- Registry 복구 후 Pod 자동 정상화 여부

---

# TC-17. Jenkins 실패 처리 테스트

**목적**: Source Test 실패 시 Image Push/GitOps 변경이 진행되지 않는지 확인합니다.

`app/index.html`에서 다음 문자열을 임시로 제거합니다.

```text
Jenkins + Argo CD
```

`Jenkinsfile` Test stage의 grep이 실패해야 합니다.

**기대 결과**:

- Jenkins Build = FAILURE
- Docker Build 실행 안 됨
- Registry 새 tag 없음
- GitOps manifest 변경 없음
- Argo CD 기존 서비스 영향 없음

---

# TC-18. 저메모리 환경 안정성 테스트

현재 son01이 Control Plane + Jenkins + Argo CD를 같이 운영하는 경우 반드시 확인합니다.

```bash
free -h
kubectl get pods -n jenkins
kubectl get pods -n argocd
kubectl get events -A --sort-by='.lastTimestamp' | tail -50
sudo dmesg -T | grep -i -E 'oom|out of memory|killed process'
```

**실패 기준**:

- `OOMKilled`
- `Evicted`
- `MemoryPressure=True`
- available memory가 지속적으로 매우 낮음

메모리가 부족하면 son03을 종료하여 확보한 메모리를 son01에 할당하고, 기본 `replicas: 1` 테스트만 수행합니다.

---

# 권장 테스트 수행 순서

```text
TC-01  Platform Health
  ↓
TC-02  Argo Application 등록
  ↓
TC-03  초기 GitOps 배포
  ↓
TC-04  Jenkins Git Checkout
  ↓
TC-05  Docker 없는 Smoke GitOps
  ↓
TC-06  Local Registry 통신
  ↓
TC-07  Docker Build / Push
  ↓
TC-08  Full CI/CD Rolling Update
  ↓
TC-09  Argo Self-Heal
  ↓
TC-10  Pod 장애 복구
  ↓
TC-11~13 장애 / Rollback
  ↓
TC-14~15 Worker HA (son03 사용 시)
  ↓
TC-16~18 Registry/Jenkins/Resource 장애 테스트
```

## 테스트 완료 기준

핵심 성공 기준은 다음 6개입니다.

1. Jenkins가 GitHub Source를 Checkout한다.
2. Jenkins가 Local Registry로 Image를 Push한다.
3. Jenkins가 GitOps image tag를 GitHub에 Commit한다.
4. Argo CD가 변경을 자동 감지하고 Sync한다.
5. Kubernetes가 Rolling Update를 완료한다.
6. Git 외 수동 변경을 Argo CD가 Self-Heal한다.
