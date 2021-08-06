#!/usr/bin/env bash
set -e

curr_dir=$(pwd)

Stage=$1
if [[ -z $Stage ]];then
  Stage='dev-workshop'
fi

AWS_CMD="aws"
if [[ -n $PROFILE ]]; then
  AWS_CMD="aws --profile $PROFILE"
fi

if [[ -z $REGION ]];then
    REGION='ap-northeast-1'
fi

if [[ -z $SCENARIO ]];then
    SCENARIO='News'
fi

if [[ -z $METHOD ]];then
    METHOD='UserPersonalize'
fi

echo "Stage=$Stage"
echo "REGION=$REGION"
echo "SCENARIO=$SCENARIO"
echo "METHOD=$METHOD"

AWS_ACCOUNT_ID=$($AWS_CMD sts get-caller-identity  --o text | awk '{print $1}')

if [[ $? -ne 0 ]]; then
  echo "error!!! can not get your AWS_ACCOUNT_ID"
  exit 1
fi

echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"


echo "----------------------Clean Campaigns----------------------"


echo "----------------------Clean Solutions----------------------"


echo "----------------------Clean EventTrackers----------------------"
event_

echo "----------------------Clean Datasets----------------------"
user_dataset_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:dataset/GCR-RS-${SCENARIO}-${METHOD}-Dataset-Group/USERS"
item_dataset_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:dataset/GCR-RS-${SCENARIO}-${METHOD}-Dataset-Group/ITEMS"
interaction_dataset_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:dataset/GCR-RS-${SCENARIO}-${METHOD}-Dataset-Group/INTERACTIONS"
dataset_group_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:dataset-group/GCR-RS-${SCENARIO}-Dataset-Group"

aws personalize delete-dataset --dataset-arn user_dataset_arn > /dev/null 2>&1 || true
aws personalize delete-dataset --dataset-arn item_dataset_arn > /dev/null 2>&1 || true
aws personalize delete-dataset --dataset-arn interaction_dataset_arn > /dev/null 2>&1 || true

#monitor dataset
echo "Dataset Deleting... It will takes no longer than 10 min..."
MAX_TIME=`expr 10 \* 60` # 10 min
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} ))
do
    dataset_list=$(aws personalize list-datasets \
                --dataset-group-arn ${dataset_group_arn} | jq '.datasets' -r)

    if [[ $dataset_list == [] ]]
        echo "Datasets Delete Finish"
        break
    fi

    CURRENT_TIME=`expr ${CURRENT_TIME} + 30`
    echo "Datasets Delete In Progress, Wait For 30 Seconds..."
    sleep 30

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Dataset Delete Time exceed 10 min, please delete manually!"
    exit 8
fi



echo "----------------------Clean Schemas----------------------"
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}UserSchema" > /dev/null 2>&1 || true
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}ItemSchema" > /dev/null 2>&1 || true
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}InteractionSchema" > /dev/null 2>&1 || true


echo "----------------------Clean DatasetGroup----------------------"
aws personalize delete-dataset-group --dataset-group-arn ${dataset_group_arn} > /dev/null 2>&1 || true

