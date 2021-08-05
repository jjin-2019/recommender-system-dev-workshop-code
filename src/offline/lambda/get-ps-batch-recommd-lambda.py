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
    ps_config = event['ps_config']
    ps_config_json = json.loads(ps_config)
    solution_name = ps_config_json['solutionName']



    personalize.create_batch_inference_job(
        solutionVersionArn="Solution version ARN",
        jobName="Batch job name",
        roleArn="IAM service role ARN",
        batchInferenceJobConfig={
            # optional USER_PERSONALIZATION recipe hyperparameters
            "itemExplorationConfig": {
                "explorationWeight": "0.3",
                "explorationItemAgeCutOff": "30"
            }
        },
        jobInput=
        {"s3DataSource": {"path": "S3 input path"}},
        jobOutput=
        {"s3DataDestination": {"path": "S3 output path"}}
    )