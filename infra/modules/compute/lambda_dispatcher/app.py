import json
import os
import boto3

ecs = boto3.client("ecs")

CLUSTER_ARN = os.environ["CLUSTER_ARN"]
TASK_DEF_ARN = os.environ["TASK_DEF_ARN"]
SUBNET_ID = os.environ["SUBNET_ID"]
SECURITY_GROUP_ID = os.environ["SECURITY_GROUP_ID"]

def handler(event, context):
    resp = ecs.run_task(
        cluster=CLUSTER_ARN,
        launchType="FARGATE",
        taskDefinition=TASK_DEF_ARN,
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": [SUBNET_ID],
                "securityGroups": [SECURITY_GROUP_ID],
                "assignPublicIp": "ENABLED",
            }
        },
        count=1,
    )

    failures = resp.get("failures", [])
    if failures:
        return {
            "statusCode": 500,
            "headers": {"content-type": "application/json"},
            "body": json.dumps({"failures": failures}),
        }

    task_arns = [t["taskArn"] for t in resp.get("tasks", [])]
    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"started_tasks": task_arns}),
    }