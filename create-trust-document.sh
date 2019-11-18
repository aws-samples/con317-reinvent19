#!/bin/bash
cat > trust-policy-document.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::AWS_ACCOUNT_ID:root"
        },
        "Action": "sts:AssumeRole"
      }
    ]
}
EOF
ACCTNUM=$(aws sts get-caller-identity | jq -r '.Account')
sed -i "s/AWS_ACCOUNT_ID/$ACCTNUM/g" trust-policy-document.json