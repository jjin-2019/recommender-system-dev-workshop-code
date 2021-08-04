import json
import os
import boto3

print('Loading function')


def init():
    print('init() enter')
    my_config = json.loads(os.environ['botoConfig'])
    from botocore import config
    config = config.Config(**my_config)

    global personalize
    personalize = boto3.client('personalize', config=config)


def lambda_handler(event, context):
    init()
    try:
        print("Received event: " + json.dumps(event, indent=2))
        return do_handler(event, context)
    except Exception as e:
        print(e)
        raise e


def do_handler(event, context):
    update_solution_version = event['updateSolutionVersion']
    solution_version_arn = update_solution_version['body']['solution_version_arn']
    describe_solution_version_response = personalize.describe_solution_version(
        solutionVersionArn=solution_version_arn
    )
    status = describe_solution_version_response["solutionVersion"]["status"]
    print("Solution Version Status: {}".format(status))

    return success_response(json.dumps({
        "solution_version_status": status,
        "solution_version_arn": solution_version_arn
    }))


def success_response(message):
    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": message
    }


def error_response(message):
    return {
        "statusCode": 400,
        "headers": {
            "Content-Type": "application/json"
        },
        "body": message
    }
