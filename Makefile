CLUSTER_NAME := test-cluster
AWS_ACCOUNT_ID := $(shell aws sts get-caller-identity --query "Account" --output text)

POLICY_NAME:=myAWSLoadBalancerControllerIAMPolicy
SERVICE_ACCOUNT:=aws-load-balancer-controller
ECR_REPO_NAME:=fastapi

SAMPLE_APP_NAMESPACE:=fastapi
SAMPLE_APP_NAME:=fastapi-sample
TAG:=latest

.PHONY: cluster
cluster:
	# clusterの作成
	eksctl create cluster \
		--name= ${CLUSTER_NAME} \
		--nodes=1 \
		--node-type=t3.small \
		--zones=ap-northeast-1a,ap-northeast-1c --without-nodegroup 

	# nodegroupの作成
	eksctl create nodegroup \
		--cluster ${CLUSTER_NAME} \
		--name=ng-default \
		--node-type=t3.small \
		--nodes=2 \
		--nodes-min=1 \
		--nodes-max=3 \
		--managed

	# IAMロールを使用したサービスアカウントを有効化するための設定
	eksctl utils associate-iam-oidc-provider \
		--region ap-northeast-1 \
		--cluster ${CLUSTER_NAME} \
		--approve

.PHONY: delete-cluster
delete-cluster:
	eksctl delete cluster --name=${CLUSTER_NAME}


.PHONY: aws-load-balancer-controller
aws-load-balancer-controller:
	# IAM ポリシー定義ファイルのダウンロード
	curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json

	# IAM ポリシーの作成
	aws iam create-policy \
		--policy-name ${POLICY_NAME} \
		--policy-document file://iam_policy.json

	# サービスアカウントの作成
	eksctl create iamserviceaccount \
		--name=${SERVICE_ACCOUNT} \
		--cluster=${CLUSTER_NAME} \
		--namespace="kube-system" \
		--attach-policy-arn=arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME} \
		--override-existing-serviceaccounts \
		--approve

	# aws load balancer controllerのインストール
	helm repo add eks https://aws.github.io/eks-charts
	wget https://raw.githubusercontent.com/aws/eks-charts/master/stable/aws-load-balancer-controller/crds/crds.yaml
	kubectl apply -f crds.yaml
	helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
		-n kube-system \
		--set clusterName=${CLUSTER_NAME} \
		--set serviceAccount.create=false \
		--set serviceAccount.name=aws-load-balancer-controller

.PHONY:delete-aws-load-balancer-controller
delete-aws-load-balancer-controller:
	helm uninstall aws-load-balancer-controller -n kube-system
	kubectl delete -f crds.yaml
	eksctl delete iamserviceaccount --cluster=${CLUSTER_NAME} \
	--name=${SERVICE_ACCOUNT} \
	--namespace=kube-system

.PHONY:delete-iam-policy
delete-iam-policy:
	aws iam delete-policy --policy-arn arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}

.PHONY:ecr-repository
ecr-repository:
	aws ecr create-repository --repository-name ${ECR_REPO_NAME}

.PHONY:delete-ecr-repository
delete-ecr-repository:
	aws ecr delete-repository --repository-name ${ECR_REPO_NAME} --force

.PHONY:app
app:
	# sampleイメージをamd64アーキテクチャでビルドして、ECRリポジトリにpush
	docker buildx build --platform linux/amd64 -t ${SAMPLE_APP_NAME}:${TAG} --load .
	aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
	docker tag ${SAMPLE_APP_NAME}:${TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}
	docker push ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}

	# sampleアプリのデプロイ
	kubectl apply -f manifest/fastapi-sample-deploy.yaml

.PHONY: update-app
update-app:
	# sampleイメージをamd64アーキテクチャでビルドして、ECRリポジトリにpush
	docker buildx build --platform linux/amd64 -t ${SAMPLE_APP_NAME}:${TAG} --load .
	aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
	docker tag ${SAMPLE_APP_NAME}:${TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}
	docker push ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}
	
	kubectl delete -f manifest/fastapi-sample-deploy.yaml
	kubectl apply -f manifest/fastapi-sample-deploy.yaml
	

.PHONY: delete-app
delete-app:
	kubectl delete -f manifest/fastapi-sample-deploy.yaml

.PHONY: all
all: cluster aws-load-balancer-controller ecr-repository app

.PHONY: delete-all
delete-all: delete-app delete-ecr-repository delete-aws-load-balancer-controller delete-cluster delete-iam-policy
	rm -f crds.yaml
	rm -f iam_policy.json
