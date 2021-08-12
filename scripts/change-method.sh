#!/usr/bin/env bash
set -e

curr_dir=$(pwd)

METHOD=$1

if [[ -z $METHOD ]];then
  METHOD='customer'
fi

Stage=$2

if [[ -z $Stage ]];then
  Stage='dev-workshop'
fi

SCENARIO=$3

if [[ -z $SCENARIO ]];then
  SCENARIO='news'
fi

if [[ -z $REGION ]];then
  REGION='ap-northeast-1'
fi

echo "METHOD: ${METHOD}"
echo "Stage: ${Stage}"
echo "SCENARIO: ${SCENARIO}"
echo "REGION: ${REGION}"

AWS_CMD="aws"
if [[ -n $PROFILE ]]; then
  AWS_CMD="aws --profile $PROFILE"
fi

AWS_ACCOUNT_ID=$($AWS_CMD sts get-caller-identity  --o text | awk '{print $1}')

if [[ $? -ne 0 ]]; then
  echo "error!!! can not get your AWS_ACCOUNT_ID"
  exit 1
fi

echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"

BUCKET_BUILD=aws-gcr-rs-sol-${Stage}-${REGION}-${AWS_ACCOUNT_ID}
PREFIX=sample-data-${SCENARIO}

#need to change name
if [ $METHOD = "ps-complete" ]
then
    solution_name="UserPersonalizeSolution"
    campaign_name="gcr-rs-${Stage}-${SCENARIO}-UserPersonalize-campaign"
    campaign_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:campaign/${campaign_name}"
    solution_version_arn=$(aws personalize describe-campaign --campaign-arn ${campaign_arn} | jq '.campaign.solutionVersionArn' -r)
elif [ $METHOD = "ps-rank" ]
then
    solution_name="rankingSolution"
    campaign_name="gcr-rs-${Stage}-${SCENARIO}-ranking-campaign"
    campaign_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:campaign/${campaign_name}"
    solution_version_arn=$(aws personalize describe-campaign --campaign-arn ${campaign_arn} | jq '.campaign.solutionVersionArn' -r)
elif [ $METHOD = "ps-sims" ]
then
    solution_name="simsSolution"
    campaign_name="gcr-rs-${Stage}-${SCENARIO}-sims-campaign"
    campaign_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:campaign/${campaign_name}"
    solution_version_arn=$(aws personalize describe-campaign --campaign-arn ${campaign_arn} | jq '.campaign.solutionVersionArn' -r)
fi

config_file_path=${curr_dir}/../sample-data/system/personalize-data/ps-config/ps_config.json

if [ $METHOD != "customer" ]
then 
  echo "------update ps_config.json file-------"
  old_solution_name=$(awk -F"\"" '/SolutionName/{print $4}' $config_file_path)
  echo "change old_solution_name: ${old_solution_name} to new_solution_name: ${solution_name}"
  sed -e "s@$old_solution_name@$solution_name@g" -i $config_file_path
  
  old_solution_version_arn=$(awk -F"\"" '/SolutionVersionArn/{print $4}' $config_file_path)
  echo "change old_solution_version_arn: ${old_solution_version_arn} to new_solution_version_arn: ${solution_version_arn}"
  sed -e "s@$old_solution_version_arn@$solution_version_arn@g" -i $config_file_path
  
  old_campaign_name=$(awk -F"\"" '/CampaignName/{print $4}' $config_file_path)
  echo "change old_campaign_name: ${old_campaign_name} to new_campaign_name: ${campaign_name}"
  sed -e "s@$old_campaign_name@$campaign_name@g" -i $config_file_path
  
  old_campaign_arn=$(awk -F"\"" '/CampaignArn/{print $4}' $config_file_path)
  echo "change old_campaign_arn: ${old_campaign_arn} to new_campaign_arn: ${campaign_arn}"
  sed -e "s@$old_campaign_arn@$campaign_arn@g" -i $config_file_path
  
  echo "------sync ps_config.json to s3-------"
  aws s3 cp ${config_file_path} s3://${BUCKET_BUILD}/${PREFIX}/system/personalize-data/ps-config/ps_config.json
  aws s3 cp ${config_file_path} s3://${BUCKET_BUILD}/${PREFIX}/notification/ps-result/ps_config.json
  
  echo "------notice online part-------"
  dns_name=$(kubectl get svc istio-ingressgateway-news-dev -n istio-system -o=jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  curl -X POST -d '{"message": {"file_type": "ps-result","file_path": "sample-data-news/notification/ps-result/","file_name": ["ps_config.json"]}}' -H "Content-Type:application/json" http://${dns_name}/loader/notice
            
fi


echo "------update config.yaml file------"
env_config_path=${curr_dir}/../manifests/envs/news-dev/config.yaml
old_method=$(awk -F "\"" '/method/{print $2}' $env_config_path)
echo "change old method: ${old_method} to new method: ${METHOD}"
sed -e "s@$old_method@$METHOD@g" -i $env_config_path


echo "------push code to github-------"
git pull
git add ${config_file_path}
git add ${env_config_path}
git commit -m "change method to ${METHOD}"
git push

echo "-------change method successfully-------"



