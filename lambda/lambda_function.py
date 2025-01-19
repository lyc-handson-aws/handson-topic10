import boto3
import os
import json

def lambda_handler(event, context):
    # Boto3 clients for DynamoDB and CloudWatch Logs
    dynamodb = boto3.client('dynamodb')
    logs_client = boto3.client('logs')

    query_params = event.get("queryStringParameters", {})
    type_param = query_params.get("type")
    target_param = query_params.get("target")
    
    if not type_param or not target_param:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "Both 'type' and 'target' query parameters are required."}),
            "headers": {"Content-Type": "application/json"}
        }

    try:
        if type_param == "log":
            # Read logs from the provided log group
            return get_logs(logs_client, target_param)
        elif type_param == "dynamo":
            # Retrieve all items from provided DynamoDB
            return get_dynamo_items(dynamodb, target_param)
        else:
            return {
                "statusCode": 400,
                "body": json.dumps({"error": "Invalid 'type' parameter. Use 'log' or 'dynamo'."}),
                "headers": {"Content-Type": "application/json"}
            }

    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
            "headers": {"Content-Type": "application/json"}
        }


def get_logs(logs_client, log_group_name):
    """Retrieve and process logs directly from the log group."""
    try:
        # Fetch log events directly from the log group
        paginator = logs_client.get_paginator('filter_log_events')
        page_iterator = paginator.paginate(
            logGroupName=log_group_name,
            startTime=0  # Adjust based on the time range if needed
        )

        logs_list = []

        # Iterate through all fetched log events
        for page in page_iterator:
            events = page.get("events", [])
            for event in events:
                logs_list.append({
                    "stream_name": event["logStreamName"],
                    "timestamp": event["timestamp"],
                    "message": event["message"]
                })

        # Sort logs by their creation time
        sorted_logs = sorted(logs_list, key=lambda x: x["timestamp"])

        # Transform into the desired structure: a list of objects where each
        # object has the log stream name as the key and log content as the value.
        response = []
        for log in sorted_logs:
            response.append({log["stream_name"]: log["message"]})

        return {
            "statusCode": 200,
            "body": json.dumps(response, indent=2),
            "headers": {"Content-Type": "application/json"}
        }

    except logs_client.exceptions.ResourceNotFoundException:
        return {
            "statusCode": 404,
            "body": json.dumps({"error": f"Log group '{log_group_name}' not found."}),
            "headers": {"Content-Type": "application/json"}
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps
        }


def get_dynamo_items(dynamodb, table_name):
    """Retrieve all items from a DynamoDB table."""
    try:
        paginator = dynamodb.get_paginator('scan')
        page_iterator = paginator.paginate(TableName=table_name)

        item_list = []

        # Iterate through each item in the table
        for page in page_iterator:
            for item in page['Items']:
                # Construct a dictionary where key is `id` and value is `message`
                item_list.append({
                    item['id']['S']: item['message']['S']
                })

        return {
            "statusCode": 200,
            "body": json.dumps(item_list, indent=2),
            "headers": {"Content-Type": "application/json"}
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)}),
            "headers": {"Content-Type": "application/json"}
        }
