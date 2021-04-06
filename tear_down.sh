#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo 'Please enter your bucket name as ./setup_infra.sh your-bucket'
    exit 0
fi

AWS_ID=$(aws sts get-caller-identity --query Account --output text | cat)
AWS_REGION=$(aws configure get region)

echo "Deleting bucket "$1"-script and its contents"
aws s3 rm s3://$1-script --recursive --output text >> tear_down.log
aws s3api delete-bucket --bucket $1-script --output text >> tear_down.log

echo "Deleting bucket "$1"-landing-zone and its contents"
aws s3 rm s3://$1-landing-zone --recursive --output text >> tear_down.log
aws s3api delete-bucket --bucket $1-landing-zone --output text >> tear_down.log

echo "Deleting bucket "$1"-clean-data and its contents"
aws s3 rm s3://$1-clean-data --recursive --output text >> tear_down.log
aws s3api delete-bucket --bucket $1-clean-data --output text >> tear_down.log

echo "Tearing down EMR cluster"
EMR_CLUSTER_ID=$(aws emr list-clusters --active --query 'Clusters[?Name==`sde-lambda-etl-cluster`].Id' --output text)
aws emr terminate-clusters --cluster-ids $EMR_CLUSTER_ID >> tear_down.log

echo "deleting lambda function"
aws lambda remove-permission --function-name emrTrigger --statement-id s3invoke --output text >> tear_down.log
aws lambda delete-function --function-name emrTrigger --output text >> tear_down.log

echo "delete lambda role"
aws iam detach-role-policy --role-name lambda-s3-role --policy-arn arn:aws:iam::$AWS_ID:policy/AWSLambdaS3Policy --output text >> tear_down.log
aws iam detach-role-policy --role-name lambda-s3-role --policy-arn arn:aws:iam::aws:policy/AmazonEMRFullAccessPolicy_v2 --output text >> tear_down.log
aws iam delete-role --role-name lambda-s3-role --output text >> tear_down.log

echo "delete lambda policy"
aws iam delete-policy --policy-arn arn:aws:iam::$AWS_ID:policy/AWSLambdaS3Policy --output text >> tear_down.log

rm -f setup.log
rm -f ./*.json
rm -f tear_down.log
rm -f policy
rm -f myDeploymentPackage.zip