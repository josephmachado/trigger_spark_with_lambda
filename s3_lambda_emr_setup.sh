#!/bin/bash

if [[ $# -eq 0 ]] ; then
    echo 'Please enter your bucket name as ./setup_infra.sh your-bucket'
    exit 0
fi

ARG2=${2:-foo}
SCRIPTBUCKET=$1-script
LANDINGZONE=$1-landing-zone
CLEANDATABUCKET=$1-clean-data

AWS_ID=$(aws sts get-caller-identity --query Account --output text | cat)
AWS_REGION=$(aws configure get region)

echo "Creating bucket "$1"-script"
aws s3api create-bucket --acl public-read-write --bucket $SCRIPTBUCKET --output text > setup.log
echo "Creating bucket "$1"-landing-zone"
aws s3api create-bucket --acl public-read-write --bucket $LANDINGZONE --output text > setup.log
echo "Creating bucket "$1"-clean-data"
aws s3api create-bucket --acl public-read-write --bucket $CLEANDATABUCKET --output text > setup.log

echo "Copy script to S3 bucket"
aws s3 cp ./scripts/random_text_classifier.py s3://$SCRIPTBUCKET/

echo "Copy sample data to S3 bucket"
aws s3 cp ./data/movie_review.csv s3://$LANDINGZONE/

echo "Creating local config files for lambda setup"

echo '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::'$1'/*"
        }
    ]
}' > ./policy

echo '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' > ./trust-policy.json

echo '[
  {
    "Id": "1",
    "Arn": "arn:aws:lambda:'$AWS_REGION':'$AWS_ID':function:emrTrigger"
  }
]' > ./targets.json

echo "Creating lambda Policy"
aws iam create-policy --policy-name AWSLambdaS3Policy --policy-document file://policy --output text >> setup.log

echo "Creating lambda Role"
aws iam create-role --role-name lambda-s3-role --assume-role-policy-document file://trust-policy.json --output text >> setup.log

echo "Attaching lambda Policy to Role"
aws iam attach-role-policy --role-name lambda-s3-role --policy-arn arn:aws:iam::$AWS_ID:policy/AWSLambdaS3Policy --output text >> setup.log

echo "Attaching emr full access Policy to lambda Role"
aws iam attach-role-policy --role-name lambda-s3-role --policy-arn arn:aws:iam::aws:policy/AmazonEMRFullAccessPolicy_v2 --output text >> setup.log

echo "Sleeping 10 seconds to allow lambda policy to attach to role"
sleep 10s

echo "Packaging local lambda_function.py"

mkdir emrTrigger
cp lambda_function.py emrTrigger
cd emrTrigger
zip -r ../myDeploymentPackage.zip .
cd ..
rm emrTrigger/lambda_function.py
rmdir emrTrigger

echo "Creating Lambda function"
aws lambda create-function --function-name emrTrigger --runtime python3.7 --role  arn:aws:iam::$AWS_ID":"role/lambda-s3-role --handler lambda_function.lambda_handler --zip-file fileb://myDeploymentPackage.zip  --timeout 60 --output text >> setup.log
rm myDeploymentPackage.zip

echo "Creating lambda S3 event trigger"
aws lambda add-permission --function-name emrTrigger --principal s3.amazonaws.com \
--statement-id s3invoke --action "lambda:InvokeFunction" \
--source-arn arn:aws:s3:::$LANDINGZONE \
--source-account $AWS_ID --output text >> setup.log


echo '{
    "LambdaFunctionConfigurations": [
        {
            "Id": "landingZoneFileCreateTrigger",
            "LambdaFunctionArn": "arn:aws:lambda:'$AWS_REGION':'$AWS_ID':function:emrTrigger", 
            "Events": [
                "s3:ObjectCreated:*"
            ]
        }
    ]
}' > ./notification.json

aws s3api put-bucket-notification-configuration --bucket $LANDINGZONE --notification-configuration file://notification.json --output text >> setup.log

echo "creating lambda environment variables"
aws lambda update-function-configuration --function-name emrTrigger --environment "Variables={SCRIPT_BUCKET="$1"-script,OUTPUT_LOC="$1"-clean-data}" --output text >> setup.log

if [ $ARG2 == "create-spark" ]; then
    echo "Creating an AWS EMR Cluster"
    aws emr create-default-roles > setup.log
    aws emr create-cluster --applications Name=Hadoop Name=Spark --release-label emr-6.2.0 --name 'sde-lambda-etl-cluster' --scale-down-behavior TERMINATE_AT_TASK_COMPLETION  --service-role EMR_DefaultRole --instance-groups '[
        {
            "InstanceCount": 1,
            "EbsConfiguration": {
                "EbsBlockDeviceConfigs": [
                    {
                        "VolumeSpecification": {
                            "SizeInGB": 32,
                            "VolumeType": "gp2"
                        },
                        "VolumesPerInstance": 2
                    }
                ]
            },
            "InstanceGroupType": "MASTER",
            "InstanceType": "m4.xlarge",
            "Name": "Master - 1"
        },
        {
            "InstanceCount": 2,
            "BidPrice": "OnDemandPrice",
            "EbsConfiguration": {
                "EbsBlockDeviceConfigs": [
                    {
                        "VolumeSpecification": {
                            "SizeInGB": 32,
                            "VolumeType": "gp2"
                        },
                        "VolumesPerInstance": 2
                    }
                ]
            },
            "InstanceGroupType": "CORE",
            "InstanceType": "m4.xlarge",
            "Name": "Core - 2"
        }
            ]' > setup.log
fi
