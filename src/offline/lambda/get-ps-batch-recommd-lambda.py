import json
import os
import boto3
import time

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
    solution_version_arn = ps_config_json['SolutionVersionArn']

    get_caller_identity_response = sts.get_caller_identity()
    aws_account_id = get_caller_identity_response["Account"]
    print("aws_account_id:{}".format(aws_account_id))

    role_arn = "arn:aws:iam::{}:role/gcr-rs-{}-personalize-role".format(aws_account_id, stage)
    print("role_arn:{}".format(role_arn))

    solution_name = ps_config_json['SolutionName']
    if solution_name == "userPersonalizeSolution":
        file_name = "ps-complete"
    elif solution_name == "rankingSolution":
        file_name = "ps-rank"
    elif solution_name == "simsSolution":
        file_name = "ps-sims"
    else:
        return {
            "statusCode": 400,
            "error": "Invalid Solution Name!"
        }

    response = personalize.create_batch_inference_job(
        solutionVersionArn=solution_version_arn,
        jobName="get-batch-recommend-job-{}".format(int(time.time())),
        roleArn=role_arn,
        jobInput={
            "s3DataSource": {
                "path": "s3://{}/{}/system/personalize-data/batch-input/{}".format(bucket, s3_key_prefix, file_name)
            }
        },
        jobOutput={
            "s3DataDestination": {
                "path": "s3://{}/{}/feature/recommend-list/personalize/".format(bucket, s3_key_prefix)
            }
        }
    )

    batch_inference_job_arn = response['batchInferenceJobArn']

    return {
        "statusCode": 200,
        "batch_inference_job_arn": batch_inference_job_arn
    }

