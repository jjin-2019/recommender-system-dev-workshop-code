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

echo "Stage=$Stage"
echo "REGION=$REGION"
echo "SCENARIO=$SCENARIO"

AWS_ACCOUNT_ID=$($AWS_CMD sts get-caller-identity  --o text | awk '{print $1}')

if [[ $? -ne 0 ]]; then
  echo "error!!! can not get your AWS_ACCOUNT_ID"
  exit 1
fi

echo "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"

dataset_group_arn="arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:dataset-group/GCR-RS-${SCENARIO}-Dataset-Group"
echo "dataset_group_arn:$dataset_group_arn"

echo "----------------------Clean Campaigns----------------------"
solution_arns=$(aws personalize list-solutions --dataset-group-arn ${dataset_group_arn} | jq '.[][]' | jq '.solutionArn' -r)
if [ ${solution_arns} != "" ]; then
  for solution_arn in $(echo ${solution_arns}); do
    campaign_arns=$(aws personalize list-campaigns --solution-arn ${solution_arn} | jq '.[][]' | jq '.campaignArn' -r)
    if [ ${campaign_arns} != "" ]; then
      for campaigns_arn in $(echo ${campaign_arns}); do
        aws personalize delete-campaign --campaign-arn ${campaigns_arn}
      done
    fi

    echo "Campaigns for ${solution_arn} Deleting... It will takes no longer than 10 min..."
    MAX_TIME=`expr 10 \* 60` # 10 min
    CURRENT_TIME=0
    while(( ${CURRENT_TIME} < ${MAX_TIME} ))
    do
        campaign_list=$(aws personalize list-campaigns \
                    --solution-arn ${solution_arn} | jq '.campaigns' -r)

        if [[ $campaign_list == [] ]]
            echo "Campaigns for ${solution_arn} Delete Finish"
            break
        fi

        CURRENT_TIME=`expr ${CURRENT_TIME} + 30`
        echo "Campaigns for ${solution_arn} Delete In Progress, Wait For 30 Seconds..."
        sleep 30

    done

    if [ $CURRENT_TIME -ge $MAX_TIME ]
    then
        echo "Campaigns for ${solution_arn} Delete Time exceed 10 min, please delete manually!"
        exit 8
    fi
  done
fi


echo "----------------------Clean Solutions----------------------"
if [ ${solution_arns} != "" ]; then
  for solution_arn in $(echo ${solution_arns}); do
    aws personalize delete-solution --solution-arn ${solution_arn}
  done

  echo "Solution Deleting... It will takes no longer than 10 min..."
  MAX_TIME=`expr 10 \* 60` # 10 min
  CURRENT_TIME=0
  while(( ${CURRENT_TIME} < ${MAX_TIME} ))
  do
      solution_list=$(aws personalize list-solutions \
                  --dataset-group-arn ${dataset_group_arn} | jq '.solutions' -r)

      if [[ $solution_list == [] ]]
          echo "Solution Delete Finish"
          break
      fi

      CURRENT_TIME=`expr ${CURRENT_TIME} + 30`
      echo "Solution Delete In Progress, Wait For 30 Seconds..."
      sleep 30

  done

  if [ $CURRENT_TIME -ge $MAX_TIME ]
  then
      echo "Solution Delete Time exceed 10 min, please delete manually!"
      exit 8
  fi
fi



echo "----------------------Clean EventTrackers----------------------"
event_tracker_arns=$(aws personalize list-event-trackers --dataset-group-arn ${dataset_group_arn} | jq '.[][]' | jq '.eventTrackerArn' -r)
if [ ${event_tracker_arns} != "" ]; then
  for event_tracker_arn in $(echo ${event_tracker_arns}); do
    aws personalize delete-event-tracker --event-tracker-arn ${event_tracker_arn}
  done

  echo "EventTracker Deleting... It will takes no longer than 10 min..."
  MAX_TIME=`expr 10 \* 60` # 10 min
  CURRENT_TIME=0
  while(( ${CURRENT_TIME} < ${MAX_TIME} ))
  do
      event_tracker_list=$(aws personalize list-event-trackers \
                  --dataset-group-arn ${dataset_group_arn} | jq '.eventTrackers' -r)

      if [[ $event_tracker_list == [] ]]
          echo "EventTracker Delete Finish"
          break
      fi

      CURRENT_TIME=`expr ${CURRENT_TIME} + 30`
      echo "EventTracker Delete In Progress, Wait For 30 Seconds..."
      sleep 30

  done

  if [ $CURRENT_TIME -ge $MAX_TIME ]
  then
      echo "EventTracker Delete Time exceed 10 min, please delete manually!"
      exit 8
  fi
fi


echo "----------------------Clean Datasets----------------------"
dataset_arns=$(aws personalize list-datasets --dataset-group-arn ${dataset_group_arn} | jq '.[][]' | jq '.datasetArn' -r)
if [ ${dataset_arns} != "" ]; then
  for dataset_arn in $(echo ${dataset_arns}); do
    aws personalize delete-dataset --dataset-arn ${dataset_arn}
  done

  echo "Datasets Deleting... It will takes no longer than 20 min..."
  MAX_TIME=`expr 20 \* 60` # 10 min
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
      echo "Datasets Delete Time exceed 20 min, please delete manually!"
      exit 8
  fi
fi


echo "----------------------Clean Schemas----------------------"
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}UserSchema" > /dev/null 2>&1 || true
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}ItemSchema" > /dev/null 2>&1 || true
aws personalize delete-schema --schema-arn "arn:aws:personalize:${REGION}:${AWS_ACCOUNT_ID}:schema/${SCENARIO}InteractionSchema" > /dev/null 2>&1 || true


echo "----------------------Clean DatasetGroup----------------------"
aws personalize delete-dataset-group --dataset-group-arn ${dataset_group_arn} > /dev/null 2>&1 || true

