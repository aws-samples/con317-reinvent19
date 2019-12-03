To set up the environment(s):

With the Console:
1. Create a temporary GitHub OAUTH token (we'll revoke it after setup)
1. Log in as each team using their hash
1. Set up a Secret in Secrets Manager:
    1. Click the `Store a new secret` button
    1. Pick `Other types of secrets`
    1. Click the `Plaintext` Tab and clear the contents so it is empty
    1. Paste the OAUTH token into the now empty box then click the `Next` button
    1. Name the secret `github-token` and click `Next`
    1. Click `Next` and then `Store`
1. Deploy the `EnvironmentStack.template.json` template in Oregon (us-west-2). This will:
    1. Deploy a VPC
    1. Deploy a Cloud9 that will automatically download our repo on first start
    1. Deploy an EKS into that VPC using eksctl via CodePipeline/CodeBuild using an IAM role that is accessible both by CodeBuild and EC2
    1. Assign that same IAM Role to the Cloud9 instance
1. Open the Cloud9 IDE, click the gear in the upper right, and flip off `AWS Managed Temporary Credentials` under `AWS Settings`
1. Run `cd con317-reinvent19/`
1. Run `./setup_cloud9.sh` This will:
    1. Install all the required tools
    1. Do an `aws eks update-kubeconfig`
1. Close all the window and open one big empty Terminal window so it is ready for the Attendee to connect
1. Once you have finished all the setups for the day delete the OAUTH token from GitHub

On the commandline:
1. aws secretsmanager create-secret --name github-token --secret-string <your token>
1. aws cloudformation create-stack --stack-name Environment --template-body file://EnvironmentStack.template.json --capabilities CAPABILITY_IAM

TODO: Put this all in a public S3 bucket an reconfigure CodePipeline to use that instead so we don't need the OAUTH token

TODO: Work out how to get this to work across three AZs - I couldn't get CDK to let me do more than two without having to specify heaps of VPC parameters.