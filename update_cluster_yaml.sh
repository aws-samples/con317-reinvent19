#!/bin/bash
cp cluster.yaml.orig cluster.yaml
aws cloudformation list-exports --region us-west-2 > exports.json
PrivateSubnet1AID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PrivateSubnet1AID")) | .Value')
PrivateSubnet2AID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PrivateSubnet2AID")) | .Value')
PrivateSubnet3AID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PrivateSubnet3AID")) | .Value')
PublicSubnet1ID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PublicSubnet1ID")) | .Value')
PublicSubnet2ID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PublicSubnet2ID")) | .Value')
PublicSubnet3ID=$(cat exports.json | jq -r '.Exports[] | select(.Name | contains ("PublicSubnet3ID")) | .Value')
sed -i "s/Quick-Start-VPC-PrivateSubnet1AID/$PrivateSubnet1AID/g" cluster.yaml
sed -i "s/Quick-Start-VPC-PrivateSubnet2AID/$PrivateSubnet2AID/g" cluster.yaml
sed -i "s/Quick-Start-VPC-PrivateSubnet3AID/$PrivateSubnet3AID/g" cluster.yaml
sed -i "s/Quick-Start-VPC-PublicSubnet1ID/$PublicSubnet1ID/g" cluster.yaml
sed -i "s/Quick-Start-VPC-PublicSubnet2ID/$PublicSubnet2ID/g" cluster.yaml
sed -i "s/Quick-Start-VPC-PublicSubnet3ID/$PublicSubnet3ID/g" cluster.yaml
rm exports.json