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
    dataset_group_name = ps_config_json['datasetGroupName']
    solution_name = ps_config_json['solutionName']
    campaign_name = ps_config_json['campaignName']
    body = json.loads(event['updateSolutionVersion']['Payload']['body'])
    solution_version_arn = body['solution_version_arn']

    dataset_group_arn = get_dataset_group_arn(dataset_group_name)
    print("dataset_group_arn:{}".format(dataset_group_arn))

    solution_arn = get_solution_arn(dataset_group_arn, solution_name)
    print("solution_arn:{}".format(solution_arn))

    campaign_arn = get_campaign_arn(solution_arn, campaign_name)
    print("campaign_arn:{}".format(campaign_arn))

    response = personalize.update_campaign(
        campaignArn=campaign_arn,
        solutionVersionArn=solution_version_arn,
        minProvisionedTPS=10
    )

    campaign_arn = response['campaignArn']
    print("campaign_arn:{}".format(campaign_arn))

    return {
        "statusCode": 200,
        "campaign_arn": campaign_arn
    }


def get_solution_arn(dataset_group_arn, solution_name):
    response = personalize.list_solutions(
        datasetGroupArn=dataset_group_arn
    )
    for solution in response["solutions"]:
        if solution["name"] == solution_name:
            return solution["solutionArn"]


def get_dataset_group_arn(dataset_group_name):
    response = personalize.list_dataset_groups()
    for dataset_group in response["datasetGroups"]:
        if dataset_group["name"] == dataset_group_name:
            return dataset_group["datasetGroupArn"]


def get_campaign_arn(solution_arn, campaign_name):
    response = personalize.list_campaigns(
        solutionArn=solution_arn
    )
    for campaign in response["campaigns"]:
        if campaign["name"] == campaign_name:
            return campaign["campaignArn"]

