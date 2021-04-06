This is the repository for blog post at https://www.startdataengineering.com/post/trigger-emr-spark-job-from-lambda/

## Prerequisites

1. [AWS account](https://aws.amazon.com/)
2. [AWS CLI installed](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html) and [configured](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html)
3. [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

## Setup

If this is your first time using AWS, make sure to check for presence of the `EMR_EC2_DefaultRole` and `EMR_DefaultRole` default role as shown below.

```bash
aws iam list-roles | grep 'EMR_DefaultRole\|EMR_EC2_DefaultRole'
# "RoleName": "EMR_DefaultRole",
# "RoleName": "EMR_EC2_DefaultRole",
```

If the roles not present, create them using the following command

```bash
aws emr create-default-roles
```

**Note** In the following sections replace `<you-bucket-prefix>` with a bucket prefix of your choosing. For example if you choose to use a prefix of `sde-sample` then in the following sections use `sde-sample` in the place of `<your-bucket-prefix>`.

The setups script, `s3_lambda_emr_setup.sh` does the following

1. Set up S3 buckets for storing input data, scripts and output data
2. Create lambda function and configure it to be triggered when a file lands in the data input S3 bucket
3. Create an EMR cluster
4. Setup policies and roles granting sufficient access for the services

```bash
chmod 755 s3_lambda_emr_setup.sh
./s3_lambda_emr_setup.sh <your-bucket-prefix> create-spark
```

The EMR cluster can take up to 10 minutes to start. In the mean time we can trigger our lambda function by sending a sample data to our input bucket. This will cause lambda to add the jobs to our EMR cluster.

```bash
aws s3 cp data/review.csv s3://<you-bucket-prefix>-landing-zone/
```

Once the EMR cluster is ready, the steps will be run. You can check the output using the following command

```bash
aws s3 ls s3://<your-bucket-prefix>-clean-data/clean_data/
```

## Deploy

When you make changes to lambda, you can deploy them using the `./deploy_lambda.sh` script.

## Teardown

When you are done don't forget to tear down the buckets, lambda function, EMR cluster, roles and policies. Use the `tear_down.sh` script as shown below.

```bash
chmod 755 ./tear_down.sh
./tear_down.sh <your-bucket-prefix>
```