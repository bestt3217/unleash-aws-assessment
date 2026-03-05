import json
import os
import time
import traceback

import boto3
from botocore.exceptions import ClientError

def jdump(obj):
    return json.dumps(obj, default=str)

dynamodb = boto3.resource("dynamodb")

SNS_REGION = os.environ.get("SNS_REGION", "us-east-1")
TABLE_NAME = os.environ.get("TABLE_NAME")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")
EMAIL = os.environ.get("EMAIL")
REPO_URL = os.environ.get("REPO_URL")
REGION = os.environ.get("AWS_REGION", "unknown")

sns = boto3.client("sns", region_name=SNS_REGION)
table = dynamodb.Table(TABLE_NAME) if TABLE_NAME else None

def handler(event, context):
    req_id = getattr(context, "aws_request_id", None)
    func_name = getattr(context, "function_name", None)

    # Helpful baseline log
    print(jdump({
        "msg": "greeter invoked",
        "aws_request_id": req_id,
        "function": func_name,
        "region": REGION,
        "table": TABLE_NAME,
        "sns_topic_arn": SNS_TOPIC_ARN,
        "email": EMAIL,
        "repo_url": REPO_URL,
        "event": event,
    }))

    # Validate env early
    missing = [k for k, v in {
        "TABLE_NAME": TABLE_NAME,
        "SNS_TOPIC_ARN": SNS_TOPIC_ARN,
        "EMAIL": EMAIL,
        "REPO_URL": REPO_URL,
    }.items() if not v]

    if missing:
        return {
            "statusCode": 500,
            "headers": {"content-type": "application/json"},
            "body": jdump({
                "error": "Missing required environment variables",
                "missing": missing,
                "aws_request_id": req_id,
                "region": REGION,
            })
        }

    now = int(time.time() * 1000)

    try:
        # 1) Write to DynamoDB
        table.put_item(
            Item={
                "pk": f"{EMAIL}#{now}",
                "email": EMAIL,
                "ts": now,
                "region": REGION,
            }
        )

        # 2) Publish to SNS
        payload = {
            "email": EMAIL,
            "source": "Lambda",
            "region": REGION,
            "repo": REPO_URL,
        }

        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=json.dumps(payload),
        )

        # 3) Success response
        return {
            "statusCode": 200,
            "headers": {"content-type": "application/json"},
            "body": json.dumps({"region": REGION}),
        }

    except ClientError as e:
        print(jdump({
            "msg": "AWS ClientError",
            "aws_request_id": req_id,
            "region": REGION,
            "error": e.response,
        }))
        return {
            "statusCode": 500,
            "headers": {"content-type": "application/json"},
            "body": jdump({
                "error": "AWS ClientError",
                "service_error": e.response,
                "aws_request_id": req_id,
                "region": REGION,
            })
        }

    except Exception as e:
        tb = traceback.format_exc()
        print(jdump({
            "msg": "Unhandled exception",
            "aws_request_id": req_id,
            "region": REGION,
            "error": str(e),
            "traceback": tb,
        }))
        return {
            "statusCode": 500,
            "headers": {"content-type": "application/json"},
            "body": jdump({
                "error": "Unhandled exception",
                "message": str(e),
                "traceback": tb,
                "aws_request_id": req_id,
                "region": REGION,
            })
        }