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
    create_dataset_import_job = event['createDatasetImportJob']
    dataset_import_job_arn = create_dataset_import_job['body']['dataset_import_job_arn']
    describe_dataset_import_job_response = personalize.describe_dataset_import_job(
        datasetImportJobArn=dataset_import_job_arn
    )
    status = describe_dataset_import_job_response["datasetImportJob"]['status']
    print("Dataset Import Job Status: {}".format(status))

    return success_response(json.dumps({
        "dataset_import_job_status": status,
        "dataset_import_job_arn": dataset_import_job_arn
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
