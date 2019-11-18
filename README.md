# re:Invent 2019 - CON317 - Securing your EKS Cluster

## Prerequisites
In the interests of time, we have pre-created a few things for each of you:
* An AWS account
* An EKS cluster created by eksctl with the cluster.yaml file we'll look through together
* A Cloud9 instance which, in addition to being a great web-based IDE, has a web-based Terminal to run commands on the dedicated EC2 instance that backs it. This means that you don't need to install anything on your laptop and can do everything today via a web browser.

By pre-provisioning these things it means you don't need to wait the ~15-20 minutes these things take to set up and we can jump right into the session.

The only things you need to do are:
1. Go to the AWS Console in the Oregon or us-west-2 region
1. Go to the Cloud9 service
1. Click on the `Open IDE` button

You'll be presented with a Terminal Window ready to go. Type `kubectl get nodes` to confirm it is all working.

## Walkthrough of securing a new EKS cluster

### AWS IAM mapping to Kubernetes RBAC and least privilege on k8s

There are two types of accounts in Kubernetes - `User Accounts` and `Service Accounts`. With EKS, AWS requires you to map/delegate authentication of User Accounts to an AWS IAM User or Role. You can, however, directly authenticate via Service Accounts with their associated long lived tokens for any situations where this is not suitable.

The way that this works is that there is a `ConfigMap` created in Kubernetes' called `aws-auth`. This YAML document maps the AWS IAM ARNs to Kubernetes `Roles` or `ClusterRoles`.

The worker `Nodes` where your containers run can't even connect to the cluster without adding their roles to this ConfigMap. The `eksctl` tool adds it to this as one of the last steps in its NodeGroup creation.

#### Step 1 - Let's look at the aws-auth that eksctl created
Let's have a look at it by running the following command in the Terminal on our Cloud9:\
`kubectl describe configmap -n kube-system aws-auth`

You'll see something that looks like this:
```
mapRoles:
----
- groups:
  - system:bootstrappers
  - system:nodes
  rolearn: arn:aws:iam::838424723531:role/eksctl-cluster-nodegroup-ng-NodeInstanceRole-1THTCV49YIX7K
  username: system:node:{{EC2PrivateDNSName}}
```

What it is doing is saying that the AWS IAM Role assigned to the EC2 instance we'd like to make a worker node, eksctl-cluster-nodegroup-XXXXX, should be mapped to the username `system:node:{{it's DNS name}}` within Kubernetes and that User should be mapped to the groups `system:bootstrappers` and `system:nodes` within Kubernetes' Role Based Access Control (RBAC).

**NOTE:** That you don't see the IAM User or Role that created the cluster in the ConfigMap even though it is a full `cluster-admin`. It is a hidden full administrator of this cluster forever that you can't see easily outside of the CloudTrail of the EKS create cluster API call. As such, many customers choose to create the cluster from a dedicated user/role named after the cluster. I suggest that you do that and treat it similarly to the way you'd treat the AWS Root Account and limit its use to only recovering the cluster if you lock yourselves out.

#### Step 2 - Create an IAM Role, Map it into Kubernetes and give it access to a Kubernetes Namespace
First we'll create an IAM Role in AWS with the CLI to map to something within Kubernetes. Run these two commands:
* Run `create-trust-document.sh` to create the trust-policy-document.json
* Run `cat trust-policy-document.json` to see what we just made
    * This will limit the ability to assume this new role to your account
* Run `aws iam create-role --role-name eks-user1 --assume-role-policy-document file://trust-policy-document.json`

Next we'll apply the `user1.yaml` file. This will create three Kubernetes objects:
* A `Namespace`, or virtual cluster within the cluster, called `user1`
* A `Role` called `user1:admins` that gives people who have it admin rights within the boundaries of the user1 Namespace
* A `RoleBinding` that says that members of the `Group` `user1:admins` get access to that Role

Finally we'll add a mapping to the aws-auth ConfigMap:
* Run the command `kubectl edit configmap -n kube-system aws-auth` to edit the ConfigMap
    * If you'd prefer to not use the vi editor you can use nano by running this instead `KUBE_EDITOR="nano" kubectl edit configmap -n kube-system aws-auth`
* Then append the following to the bottom of the MapRoles section replacing the 111111111111 with the account number in the Node role ARN above it:
    ````
        - groups:
          - user1:admins
          rolearn: arn:aws:iam::111111111111:role/eks-user1
          username: user1
    ````

So now if I connect to the cluster with the eks-user1 AWS IAM role then it'll map me to the user1-admins `Group` and therefore to the `Role` it is mapped to which makes me an admin of the user1 `Namespace`. Let's try it!

#### Step 3 - Testing it
First we'll generate a new kubeconfig file (~/.kube/config) that will log in as our new role. To do that run the following commands: 
* `mv ~/.kube/config ~/.kube/config-admin`
* Run `aws sts get-caller-identity` to find the account number
* `aws eks update-kubeconfig --name cluster --role-arn arn:aws:iam::111111111111:role/eks-user1 --alias eks-user1 --region us-west-2` where you replace the 111111111111's with the account number from the last step.

If you run `kubectl get all` you'll notice that it'll give you permissions errors about the default namespace. Run `kubectl config set-context --current --namespace=user1` to change our namespace to user1 and then re-run the get all and you'll see it succeeds.

Now let's launch something to see that everything works as user1 in our user1 namespace. Run `kubectl create deployment nginx --image=nginx` to create a single-`Pod` `Deployment` of nginx. 

Then run `kubectl expose deployment nginx --port=80 --target-port=80 --name nginx --type=LoadBalancer` to create a `Service` backed by an AWS Elastic Load Balancer to expose that nginx Deployment to the Internet.

Wait a couple minutes for the ELB to be created then run `kubectl get services` and try going to the `EXTERNAL-IP` in your browser with an http://EXTERNAL-IP.

We'll leave that running to do some things with `NetworkPolicies` later.

Also note that the cluster-admin role can see and change things in all namespaces. Let's see that in action:
* `mv ~/.kube/config ~/.kube/config-user1` to back up our limited eks-user1 config
* `cp ~/.kube/config-admin ~/.kube/config` to restore our full admin config
* `kubectl get all --all-namespaces` - see not only the nginx service we set up in namespace user1 but we can see some of the processes like coredns in kube-system as well.

So, as you can see, `cluster-admins` are very powerful and you should limit how many people have access to those roles.

#### Step 4 - Securely managing Kubernetes Secrets w/RBAC & namespaces
Most apps will require some secrets to work properly - database connection strings/passwords, API keys, etc. Kubernetes has a way to handle this - `Secrets`. These secrets can either be put into our running pods as environment variables or mounted as whole files. And these secrets, like many Kubernetes resources, live within `Namespaces` and can be easily secured by Kubernetes RBAC.

What we're going to do is create a secret in the default namespace as our admin, see how that works and then finally prove that we can't get at it with our eks-user1 role.

Please run the following commands:
* `kubectl create secret generic db-login --from-literal=username=user --from-literal=password=password --from-literal=address=db.example.com` to create our secret
* `kubectl get secret db-login -o yaml` to retrieve our new secret
* Note that everything is base64 encoded run `echo <each encoded block> | base64 --decode` to decode them

Now, based on the way that we had configured RBAC, eks-user1 should not have the rights to get to things outside of its namespace. Let's confirm that's the case with this secret:
* `cp ~/.kube/config-user1 ~/.kube/config`
* `kubectl get secret db-login -o yaml --namespace=default`

And you should see the error `Error from server (Forbidden): secrets "db-login" is forbidden: User "user1" cannot get resource "secrets" in API group "" in the namespace "default"` showing that our RBAC is protecting our secrets from people/roles that do not need access to them.

You can find out more about Secrets and how to use them in the Kubernetes documentation - https://kubernetes.io/docs/concepts/configuration/secret/#using-secrets.

### Assuming IAM roles to use AWS CLI/SDK within pods
Often the containers running on top of EKS will need to call AWS CLI/SDK/APIs for things like S3 or DynamoDB. If this code was running directly on EC2 or within a Lambda function the way that you'd do this would be to assign an IAM role to that instance/function and it would auto-magically get the credentials it needs by checking the associated metadata endpoint (http://169.254.169.254/latest/meta-data/).

With EKS, the solution to this problem instead involves federating AWS IAM with Kubernetes via OpenID Connect (OIDC). This means that the the Kubernetes cluster can generate JWT tokens that AWS IAM will trust and exchange for temporary AWS role credentials.

First, run the following command to create the IAM OIDC provider for the cluster - `eksctl utils associate-iam-oidc-provider --name cluster --approve --region us-west-2`

Then we can use `eksctl` to both create the AWS IAM role as well as the corresponding service account on EKS to map to it. Let's create one that maps to a read-only access to S3 - `eksctl create iamserviceaccount --name aws-s3-read --namespace default --cluster cluster --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess --approve --region us-west-2`

Let's go and have a look at the IAM role and Service account that were created:
* In the AWS Console go to the IAM Service
* Choose Roles on the Left
* The role will start with eksctl-cluster-addon-iamserviceaccount - click on that role to go into its details
* Look at the Trust relationships tab to see that it can only be assumed by the `aws-s3-read` service account in the `default` namespace of our specific EKS cluster
* On the Kubernetes side first ensure that we are going in with admin access by `cp ~/.kube/config-admin ~/.kube/config`
* Then run `kubectl describe serviceaccount aws-s3-read`

To test this role we are going to connect interactively to a container that has the AWS CLI in it and attempt to do an S3 read command:
* Run the following command - `kubectl run my-shell --generator=run-pod/v1 --rm -i --tty --image amazonlinux --serviceaccount aws-s3-read -- bash`
* Run `yum install python3 -y` to install the AWS CLI
* Run `pip3 install awscli`
* Run `aws s3 ls` and see that it doesn't error out
* Run `aws sts get-caller-identity` and see that just by adding the service account all the right things have happened so that the pod is running commands as our IAM role
* Open another terminal, run `kubectl desribe pod my-shell` and note the Environment Variables and Volumes that were mounted in to enable that to work just because we specified our IAM-enabled service account
* Go back to the original Terminal and run `exit` - Kubernetes will automatically clean up the Pod because we specified --rm when we created it.

Since this service account is in the default namespace you'd be unable to use it from our user1 account and namespace (feel free to try it by doing a `cp ~/.kube/config-user1 ~/.kube/config` and repeating the last few steps above). While it may be possible to limit access to use it to certain pods within a namespace, it is generally easier with that to separate things by namespace-level granularity with Kubernetes' RBAC.

**OPTIONAL:** Now that there is a way to assume an IAM role without needing to leverage the roles assigned to an EC2 instance you can reconfigure things like the AWS CNI Plugin to use this method instead and remove those roles from the role assigned to the Instance. We cover how to do that in our documentation - https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts-cni-walkthrough.html.

**OPTIONAL:** You can also introduce an iptables firewall rule on each of your worker nodes blocking Pods from reaching the EC2 metadata endpoint so that you never inadvertently have a Pod get access to aspects of the platform via roles there they shouldn't - https://docs.aws.amazon.com/eks/latest/userguide/restrict-ec2-credential-access.html.

**NOTE:** This ability to connect to pods interactively is something that you need to be mindful of within Kubernetes RBAC - if you can do this you can see all of the secrets that Pod has access to as well as access to anything that it can from a NetworkPolicy perspective via the tools they can run within that Pod's shell.

### Making the control plane endpoints private & DNS repercussions
When EKS launched its API endpoints, which not just kubectl but also the worker nodes use to communicate with the control plane, were public. This wasn't viewed as inherently insecure as any connection to/from the control plane is always encrypted and you always need to authenticate with a Kubernetes User or Service Account. 

Many customers wanted this to be not on the Internet, however, so we then launched a feature allowing you to turn these public endpoints on/off as well as offering new private endpoints which you can turn on/off. This means that you can have both public and private endpoints if you want. And, while this might not seem like something many would want, it means that the worker nodes do not need to have a NAT out to the public Internet to reach the control plane but you can still reach it via things like kubectl from anywhere - which suits some customer network and DNS topologies.

Note that there are a few complications to disabling public endpoints and going private-only:
* eksctl can't launch a cluster with only private endpoints from the start at the moment because it has to connect to the cluster with kubectl to add the worker node policy ARN to the aws-auth configmap - and by default the private endpoints have a SecurityGroup that would block it. https://github.com/weaveworks/eksctl/pull/1434 
* You need to resolve the address of the cluster via DNS resolvers within the VPC that you launch the worker nodes in (due to the use of a private DNS zone). If you need access to this from outside that VPC then you need to forward DNS requests to that zone and ensure they are resolved there using things like Route 53 Resolver. 
    * Note that the underlying IPs can change during things like upgrades so, rather than doing this statically in upstream DNS servers or hosts files, you really do need to ensure that it gets forwarded/resolved every time by the DNS within that VPC.
    * You can work around this by leveraging a bastion/jumpbox where people run kubectl commands and ensuring any pipelines that interact with the cluster run within the VPC where it lives so no resolution outside that VPC is required.

If you want to flip public off and private on you can do it either via the console or via eksctl. We'll use the console in this case:
* Go to the AWS Console ensuring you are the Oregon us-west-2 region
* Go to the EKS Service
* Click on the name of our cluster (which is a link)
* Copy the API server endpoint to your clipboard
* In a terminal do a `nslookup` of that endpoint removing the `https://` e.g. `nslookup 962D4705F9C2FEE51C9372170C96B7F1.yl4.us-west-2.eks.amazonaws.com` and note that you get back two public IPs back. Also, you can do this lookup from either your laptop or the Cloud9 because the DNS zone is public.
* Scroll down to the Networking section and note that Private access is false and Public access is true
* Click the Update button in the upper right of the Networking section
* Flip Private access to Enabled and Public access to disabled and click the Update button
* Once that completes do the nslookup again. Note the private addresses when you look it up from Cloud9 (which is in the same VPC and DNS resolver network as EKS) and that it no longer resolves from your laptop.

### Enabling Network Policies for in-Kubernetes ‘firewall’ rules
In AWS you would usually leverage Security Groups for your firewalling needs. In the other AWS container offering, ECS, each Task (ECS equivalent to a Kubernetes Pod) is given its own ENI and Security Group(s) which will enforce those egress/ingress rules even between Tasks running on the same Node.

Within Kubernetes the equivalent functionality is `NetworkPolicies` and they are enforced by a `Network Policy Provider`. EKS does not come with one by default but we document how to install the one from Calico - https://docs.aws.amazon.com/eks/latest/userguide/calico.html.

To install the Network Policy Provider:
* Ensure that you are under the full admin context with a `cp ~/.kube/config-admin ~/.kube/admin`
* Run the following command `kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.5/config/v1.5/calico.yaml` to deploy the NPP as a DaemonSet (ensures this runs on every Node) in the kube-system namespace.

Now that we have a Network Policy Provider we can set up some `NetworkPolicies`. The  NetworkPolicy in `default-deny.yaml` will put a default deny on everything within a namespace - lets do it to the `user1` namespace:
* Run `cat default-deny.yaml` to have a look at our policy
* Run `kubectl apply -f default-deny.yaml --namespace user1` to apply it
* Earlier we had created a Service in `user1` that we could reach from the Internet - try going to that again and see that it failed.
    * You can find that address again with a `kubectl get services -A`
* Now lets allow that traffic specifically with `kubectl apply -f nginx-allow-external.yaml --namespace user1`
    * Have a look at it with a `cat nginx-allow-external.yaml` - we are allowing anything to talk to pods with the label `nginx` on port 80.
* Verify that worked by refreshing the browser to the load balancer address again

For examples of other policies you can try I have found this GitHub project to be quite a good resource - https://github.com/ahmetb/kubernetes-network-policy-recipes 

#### (Optional - Investigate RBAC implications) 
The eks-user1 role we created, since it is a full admin in the user1 namespace, can delete or change the NetworkPolicies we've created there. Do a `cp ~/.kube/config-user1 ~/.kube/config` and give it a try. If you, for example, want developers to have access to deploy things there but not change NetworkPolicies then you'll need to create another role that has less access and give them that instead.

When I needed to do just that recently I took the built-in `edit` ClusterRole as inspiration and cloned it to a new role that was the same but with the NetworkPolicy bits removed. You can do a `kubectl get clusterrole edit -o yaml > newrole.yaml` to generate a file that contains the edit role. You then would: 
* Open that file and copy the `rules` section across to user1.yaml
* Remove the `NetworkPolicy` bits and save it
* Apply it with `kubectl -f`
* Now our user1 profile can't make any changed to NetworkPolicies any longer

### Enabling and parsing the audit trail for EKS control plane activity
The EKS control plane will send logs about various aspects of its operation to CloudWatch logs. This logging needs to be turned on but if you Next Next through the console's EKS creation or run a minimal eksctl command it may not have been.

In our case we requested that it be in our cluster.yaml file that was used by eksctl to create the cluster. You can verify that by:
* Going to the AWS Console in the Oregon region
* Going to the EKS Service
* Click on the name of our cluster (which is a link)
* Scroll down to the Logging section and see that it is enabled

The most important of these logs from a security perspective is the audit trail of Kubernetes API actions. You can use the CloudWatch Logs Insights feature to query those:
* Go to the AWS Console in the Oregon region
* Go to the CloudWatch Service
* Choose Insights under Logs on the left-hand side
* Pick the EKS loggroup in the dropdown at the top and then search with the following query for the last 1h - `fields @message | filter user.username = "kubernetes-admin"`
    * This will show you all the things you did with kubectl when signed in with the `~/.kube/config-admin` profile that created the cluster
* If you'd instead like to see the things done as the eks-user1 IAM role run this query - `fields @message | filter user.username = "user1"`

In addition to searching these logs in an ad-hoc basis when looking into why something happened you can actually alert in near-realtime on various things that might appear here that are potentially 'bad'. A few examples might include: 
* Alerting when the `kubernetes-admin` user does something instead of a more restricted IAM role you expect to be
* Alerting when the sourceIP for an API action is something other than what you expected
* etc.

Here is a good example of how to set that up - https://theithollow.com/2017/12/11/use-amazon-cloudwatch-logs-metric-filters-send-alerts/.

### Where to from here?
The next more advanced topics that I'd investigate from here would be the use of `AdmissionsControllers` (https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/) and `Pod Security Policies` (https://kubernetes.io/docs/concepts/policy/pod-security-policy/) as these allow for much more granularity on what is allowed within the cluster than RBAC. 

While RBAC gives you rather blunt verbs like `create`, `get`, `update` and `delete`, these controllers let you verify, and even change/mutate, the parameters of the objects with almost total granularity.

A couple of the sorts of things you'd likely want to use them to limit include:
* `--privileged` mode for containers/Pods that let them directly launch other containers on the host's Docker daemon (often called Docker-in-Docker)
    * These additional containers run via `--privileged` would not be scheduled/orchestrated by Kubernetes but instead via a container/Pod controlling its local Docker daemon. So, even beyond the security risks, it is better for a Kubernetes node to be fully managed by Kubernetes and its kubelet.
* The use of `hostPath` which lets you mount arbitrary paths in the host's filesystem into the containers/Pods.

And, of course, planning and practicing how you'll do your EKS control plane and worker node updates so that you can regularly and safely deploy security-related updates as they come up is important too.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.