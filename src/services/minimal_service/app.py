import json
import os

import boto3
from boto3.dynamodb.conditions import Key


localstack_hostname = os.environ.get("LOCALSTACK_HOSTNAME")
localstack_endpoint = (
    "http://" + localstack_hostname + ":4566" if localstack_hostname is not None else None
)
dynamodb = boto3.resource(
    "dynamodb",
    endpoint_url=localstack_endpoint,
)


table_name = os.environ.get("DYNAMODB_TABLE_NAME")
table = dynamodb.Table(table_name)


def to_result(item):
    return {
        "pk": item["pk"],
        "sk": item["sk"],
        "description": item["Description"],
    }


def lambda_handler(event, context):
    results = table.query(KeyConditionExpression=Key("pk").eq("SAMPLE_PK"))

    items = results["Items"]

    result = list(map(to_result, items))

    return {"statusCode": 200, "body": json.dumps(result)}
