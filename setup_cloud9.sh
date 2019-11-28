#!/bin/bash
# Install kubectl, aws-iam-authenticator and eksctl
sudo curl --silent --location -o /usr/local/bin/kubectl "https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl"
sudo chmod +x /usr/local/bin/kubectl
sudo curl --silent --location -o /usr/local/bin/aws-iam-authenticator "https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/aws-iam-authenticator"
sudo chmod +x /usr/local/bin/aws-iam-authenticator
curl --silent --location "https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_Linux_amd64.tar.gz" | tar xz -C /tmp
sudo mv -v /tmp/eksctl /usr/local/bin
sudo chmod +x /usr/local/bin/eksctl
sudo yum -y install jq
export AWS_DEFAULT_REGION=us-west-2
aws eks update-kubeconfig --name cluster
curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/master/k8s-yaml-templates/quickstart/cwagent-fluentd-quickstart.yaml | sed "s/{{cluster_name}}/cluster/;s/{{region_name}}/$AWS_DEFAULT_REGION/" | kubectl apply -f -
echo export AWS_DEFAULT_REGION=us-west-2 > ~/.bashrc