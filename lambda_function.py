import json
import os
from typing import Dict, Any, List
import urllib.parse
import boto3


def _get_spark_steps(ip_data_bkt: str, ip_data_key: str) -> List[Dict[str, Any]]:
    output_bkt = os.environ.get("OUTPUT_LOC")
    script_bkt = os.environ.get("SCRIPT_BUCKET")
    SPARK_STEPS = [
        {
            "Name": "Move raw data from S3 to HDFS",
            "ActionOnFailure": "CANCEL_AND_WAIT",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "s3-dist-cp",
                    f"--src=s3://{ip_data_bkt}/{ip_data_key}",
                    "--dest=/movie",
                ],
            },
        },
        {
            "Name": "Classify movie reviews",
            "ActionOnFailure": "CANCEL_AND_WAIT",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "spark-submit",
                    "--deploy-mode",
                    "client",
                    f"s3://{script_bkt}/random_text_classifier.py",
                ],
            },
        },
        {
            "Name": "Move clean data from HDFS to S3",
            "ActionOnFailure": "CANCEL_AND_WAIT",
            "HadoopJarStep": {
                "Jar": "command-runner.jar",
                "Args": [
                    "s3-dist-cp",
                    "--src=/output",
                    f"--dest=s3://{output_bkt}/clean_data/",
                ],
            },
        },
    ]
    return SPARK_STEPS


def _get_cluster_id(cluster_name: str = "sde-lambda-etl-cluster") -> str:
    """
    Given a cluster name, return the first cluster id
    of all the clusters which have that cluster name
    """
    client = boto3.client("emr")
    clusters = client.list_clusters()
    return [c["Id"] for c in clusters["Clusters"] if c["Name"] == cluster_name][0]


def _add_step_to_cluster(cluster_id: str, spark_steps: List[Dict[str, Any]]) -> None:
    """
    Add the given steps to the cluster_id
    """
    client = boto3.client("emr")
    client.add_job_flow_steps(JobFlowId=cluster_id, Steps=spark_steps)


def lambda_handler(event, context):
    """
    1. get the steps to be added to a EMR cluster.
    2. Add the steps to the EMR cluster.
    """
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(
        event["Records"][0]["s3"]["object"]["key"], encoding="utf-8"
    )
    spark_steps = _get_spark_steps(ip_data_bkt=bucket, ip_data_key=os.path.dirname(key))
    _add_step_to_cluster(cluster_id=_get_cluster_id(), spark_steps=spark_steps)
    return
