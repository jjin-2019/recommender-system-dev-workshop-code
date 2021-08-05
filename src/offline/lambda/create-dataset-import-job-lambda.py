import json
import os
import time
import boto3

print('Loading function')


def init():
    print('init() enter')
    my_config = json.loads(os.environ['botoConfig'])
    from botocore import config
    config = config.Config(**my_config)

    global personalize
    global sts
    personalize = boto3.client('personalize', config=config)
    sts = boto3.client('sts', config=config)


def lambda_handler(event, context):
    init()
    try:
        print("Received event: " + json.dumps(event, indent=2))
        return do_handler(event, context)
    except Exception as e:
        print(e)
        raise e


stage = "dev"


def do_handler(event, context):
    global stage
    stage = os.environ.get('Stage', 'dev')

    bucket = event['bucket']
    s3_key_prefix = event['prefix']
    ps_config = event['ps_config']
    ps_config_json = json.loads(ps_config)
    dataset_group_name = ps_config_json['DatasetGroupName']
    dataset_type = event['datasetType']

    if dataset_type == "USER":
        dataset_name = ps_config_json['UserDatasetName']
        file_name = ps_config_json['UserFileName']
    elif dataset_type == "ITEM":
        dataset_name = ps_config_json['ItemDatasetName']
        file_name = ps_config_json['ItemFileName']
    elif dataset_type == "INTERACTION":
        dataset_name = ps_config_json['InteractionDatasetName']
        file_name = ps_config_json['InteractionFileName']
    else:
        return {
            "statusCode": 400,
            "error": "Invalid Dataset Type!"
        }

    dataset_group_arn = get_dataset_group_arn(dataset_group_name)
    print("dataset_group_arn:{}".format(dataset_group_arn))

    dataset_arn = get_dataset_arn(dataset_group_arn, dataset_name)
    print("dataset_arn:{}".format(dataset_arn))

    get_caller_identity_response = sts.get_caller_identity()
    aws_account_id = get_caller_identity_response["Account"]
    print("aws_account_id:{}".format(aws_account_id))

    role_arn = "arn:aws:iam::{}:role/gcr-rs-{}-personalize-role".format(aws_account_id, stage)
    print("role_arn:{}".format(role_arn))

    create_dataset_import_job_response = personalize.create_dataset_import_job(
        jobName="dataset-import-job-{}".format(int(time.time())),
        datasetArn=dataset_arn,
        dataSource={
            "dataLocation": "s3://{}/{}/system/personalize-data/{}".format(bucket, s3_key_prefix, file_name)
        },
        roleArn=role_arn
    )

    dataset_import_job_arn = create_dataset_import_job_response['datasetImportJobArn']
    print("dataset_import_job_arn:{}".format(dataset_import_job_arn))

    return {
        "statusCode": 200,
        "dataset_import_job_arn": dataset_import_job_arn
    }


def get_dataset_group_arn(dataset_group_name):
    response = personalize.list_dataset_groups()
    for dataset_group in response["datasetGroups"]:
        if dataset_group["name"] == dataset_group_name:
            return dataset_group["datasetGroupArn"]


def get_dataset_arn(dataset_group_arn, dataset_name):
    response = personalize.list_datasets(
        datasetGroupArn=dataset_group_arn
    )
    for dataset in response["datasets"]:
        if dataset["name"] == dataset_name:
            return dataset["datasetArn"]


