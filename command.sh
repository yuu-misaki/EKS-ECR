CLUSTER_NAME="ecr-app"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

POLICY_NAME="myAWSLoadBalancerControllerIAMPolicy"
SERVICE_ACCOUNT="aws-load-balancer-controller"
ECR_REPO_NAME="fastapi"

SAMPLE_APP_NAMESPACE="fastapi"
SAMPLE_APP_NAME="fastapi-sample"
TAG="latest"

########## EKSリソースの作成 ##########
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

########## aws load balancer controllerの作成 ##########
# IAMロールを使用したサービスアカウントを有効化するための設定
eksctl utils associate-iam-oidc-provider \
    --region ap-northeast-1 \
    --cluster ${CLUSTER_NAME} \
    --approve

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


######### ECRリポジトリの作成 ###########
aws ecr create-repository --repository-name ${ECR_REPO_NAME}


######### サンプルアプリのデプロイ ###########
# ECRリポジトリへのアクセス権限を付与するサービスアカウントの作成
eksctl create iamserviceaccount \
    --name ecr-access \
    --namespace ${SAMPLE_APP_NAMESPACE} \
    --cluster ${CLUSTER_NAME} \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
    --approve \
    --override-existing-serviceaccounts

# sampleイメージをamd64アーキテクチャでビルドして、ECRリポジトリにpush
docker buildx build --platform linux/amd64 -t ${SAMPLE_APP_NAME}:${TAG} --load .
aws ecr get-login-password --region ap-northeast-1 | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com
docker tag ${SAMPLE_APP_NAME}:${TAG} ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.ap-northeast-1.amazonaws.com/${ECR_REPO_NAME}:${TAG}

# sampleアプリのデプロイ
kubectl apply -f manifest/fastapi-sample-deploy.yaml




