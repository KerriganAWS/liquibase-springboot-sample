# Core Concepts of AWS Services
1. [AWS CodeBuild](https://aws.amazon.com/codebuild/)
2. [AWS CodePipeline](https://aws.amazon.com/codepipeline/)

# Prerequisite
1. You need to have an Amazon EKS Cluster. See [here](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html) to create an Amazon EKS cluster
2. Creating an STS Assume IAM role for AWS CodeBuild to apply K8s manifests to Amazon EKS. In this step, we are going to create an IAM role and add an inline policy EKS:Describe that we will use in the CodeBuild stage to interact with the EKS cluster via kubectl.
```shell
export ACCOUNT_ID=123456789

TRUST="{ \"Version\": \"2012-10-17\", \"Statement\": [ { \"Effect\": \"Allow\", \"Principal\": { \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\" }, \"Action\": \"sts:AssumeRole\" } ] }"

echo $TRUST

aws iam create-role --role-name EksCodeBuildKubectlRole --assume-role-policy-document "$TRUST" --output text --query 'Role.Arn'

echo '{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": "eks:Describe*", "Resource": "*" } ] }' > /tmp/iam-eks-describe-policy

aws iam put-role-policy --role-name EksCodeBuildKubectlRole --policy-name eks-describe --policy-document file:///tmp/iam-eks-describe-policy

```

3. Update the aws-auth ConfigMap with the IAM Role (EksCodeBuildKubectlRole) in Amazon EKS Cluster.

```shell
kubectl get configmap aws-auth -o yaml -n kube-system

export ACCOUNT_ID=180789647333

ROLE="    - rolearn: arn:aws:iam::$ACCOUNT_ID:role/EksCodeBuildKubectlRole\n      username: build\n      groups:\n        - system:masters"

kubectl get -n kube-system configmap/aws-auth -o yaml | awk "/mapRoles: \|/{print;print \"$ROLE\";next}1" > /tmp/aws-auth-patch.yml

kubectl patch configmap/aws-auth -n kube-system --patch "$(cat /tmp/aws-auth-patch.yml)"

kubectl get configmap aws-auth -o yaml -n kube-system
```

# Create an AWS CodeBuild Project.
1. Create an buildspec.yaml. The sample is below. You can find it in [here](https://github.com/KerriganAWS/liquibase-app-demo/blob/main/buildspec.yml).
```yaml
version: 0.2
env:
  secrets-manager:
    LIQUIBASE_DEV_URL: LIQUIBASE_DEV:host
    LIQUIBASE_DEV_USERNAME: LIQUIBASE_DEV:username
    LIQUIBASE_DEV_PASSWORD: LIQUIBASE_DEV:password
    LIQUIBASE_TESTING_URL: LIQUIBASE_TESTING:host
    LIQUIBASE_TESTING_USERNAME: LIQUIBASE_TESTING:username
    LIQUIBASE_TESTING_PASSWORD: LIQUIBASE_TESTING:password
phases:
  install:
    runtime-versions:
      java: corretto11
    commands: 
        - chmod +x ./liquibase/liquibase
  pre_build:
      commands:
        # Docker Image Tag with Date Time & Code Buiild Resolved Source Version
        - TAG="$(date +%Y-%m-%d.%H.%M.%S).$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | head -c 8)"
        - MANIFEST_FILE_NAME="liquibase-deployment.yml"
        # Update Image tag in our Kubernetes Deployment Manifest        
        - echo "Update Image tag in kube-manifest..."
        - sed -i 's@CONTAINER_IMAGE@'"$REPOSITORY_URI:$TAG"'@' kube-manifests/$MANIFEST_FILE_NAME
        # Verify AWS CLI Version        
        - echo "Verify AWS CLI Version..."
        - aws --version
        # Login to ECR Registry for docker to push the image to ECR Repository
        - echo "Login in to Amazon ECR..."
        - $(aws ecr get-login --no-include-email)
        # Update Kube config Home Directory
        - export KUBECONFIG=$HOME/.kube/config
  build:
    commands:
      # Generate the changelog xml file.
      - echo "Comparing databases DEV to Testing"
      - ./liquibase/liquibase --changelog-file=src/main/resources/db/changelog/changes/codebuild-$CODEBUILD_BUILD_NUMBER.xml
                  --url="jdbc:mysql://$LIQUIBASE_TESTING_URL:3306/demo?autoReconnect=true&useSSL=false"
                  --username=$LIQUIBASE_TESTING_USERNAME
                  --password=$LIQUIBASE_TESTING_PASSWORD
                  --referenceUrl="jdbc:mysql://$LIQUIBASE_DEV_URL:3306/demo?autoReconnect=true&useSSL=false"
                  --referenceUsername=$LIQUIBASE_DEV_USERNAME
                  --referencePassword=$LIQUIBASE_DEV_PASSWORD
                  --classpath=./liquibase/lib/mysql-connector-java-8.0.12.jar
                  diff-changelog
      # Build Docker Image
      - echo "Build started on `date`"
      - echo "Building the Docker image..."
      # Package demo via Maven Wrapper
      - ./mvnw clean package
      - docker build --tag $REPOSITORY_URI:$TAG .
  post_build:
    commands:
      # Push Docker Image to ECR Repository
      - echo "Build completed on `date`"
      - echo "Pushing the Docker image to ECR Repository"
      - docker push $REPOSITORY_URI:$TAG
      - echo "Docker Image Push to ECR Completed -  $REPOSITORY_URI:$TAG"    
      # Extracting AWS Credential Information using STS Assume Role for kubectl
      - echo "Setting Environment Variables related to AWS CLI for Kube Config Setup"          
      - CREDENTIALS=$(aws sts assume-role --role-arn $EKS_KUBECTL_ROLE_ARN --role-session-name codebuild-kubectl --duration-seconds 900)
      - export AWS_ACCESS_KEY_ID="$(echo ${CREDENTIALS} | jq -r '.Credentials.AccessKeyId')"
      - export AWS_SECRET_ACCESS_KEY="$(echo ${CREDENTIALS} | jq -r '.Credentials.SecretAccessKey')"
      - export AWS_SESSION_TOKEN="$(echo ${CREDENTIALS} | jq -r '.Credentials.SessionToken')"
      - export AWS_EXPIRATION=$(echo ${CREDENTIALS} | jq -r '.Credentials.Expiration')
      # Setup kubectl with our EKS Cluster              
      - echo "Update Kube Config"      
      - aws eks update-kubeconfig --name $EKS_CLUSTER_NAME
      # Apply changes to our Application using kubectl
      - echo "Apply changes to kube manifests"            
      - kubectl apply -f kube-manifests/$MANIFEST_FILE_NAME
      - echo "Completed applying changes to Kubernetes Objects"           
      # Create Artifacts which we can use if we want to continue our pipeline for other stages
      - printf '[{"name":"$MANIFEST_FILE_NAME","imageUri":"%s"}]' $REPOSITORY_URI:$TAG > build.json         
artifacts:
  files: 
    - build.json   
    - kube-manifests/*
    - src/main/resources/db/changelog/changes/*
```
2. How to create an AWS CodeBuild Project
      - Project Configuration
      - Project Name: eks-devops-cb-for-pipe
      - Description: CodeBuild Project for EKS DevOps Pipeline
      - Environment
        - Environment Image: Managed Image
        - Operating System: Amazon Linux 2
        - Runtimes: Standard
        - Image: aws/codebuild/amazonlinux2-x86_64-standard:3.0
        - Image Version: Always use the latest version for this runtime
        - Environment Type: Linux
        - Privileged: Enable
        - Role Name: Auto-populated
        - Additional Configurations
        - All leave to defaults except Environment Variables
        - Add Environment Variables
        - REPOSITORY_URI = 180789647333.dkr.ecr.us-east-1.amazonaws.com/eks-devops-nginx
        - EKS_KUBECTL_ROLE_ARN = arn:aws:iam::180789647333:role/EksCodeBuildKubectlRole
        - EKS_CLUSTER_NAME = eksdemo1
      - Buildspec
        - leave to defaults
3. How to create an AWS CodePipeline Project
      - Create CodePipeline
      - Create CodePipeline
      - Go to Services -> CodePipeline -> Create Pipeline
      - Pipeline Settings
        - Pipeline Name: eks-devops-pipe
        - Service Role: New Service Role (leave to defaults)
        - Role Name: Auto-populated
        - Rest all leave to defaults and click Next
      - Source
        - Source Provider: AWS CodeCommit
        - Repository Name: eks-devops-nginx
        - Branch Name: main
        - Change Detection Options: CloudWatch Events (leave to defaults)
      - Build
        - Build Provider: AWS CodeBuild
        - Region: ap-northeast-1 (Tokyo)
        - Project Name: Choose the project (eks-devops-cb-for-pipe) you just created.
# Clean-Up
1. Delete All kubernetes Objects in EKS Cluster
```shell
kubectl delete -f kube-manifests/
```
2. Delete Pipeline
3. Delete CodeBuild Project
4. Delete CodeCommit Repository
5. Delete Roles and Policies created

