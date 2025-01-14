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

#create dataset group
datasetGroupArn=$(aws personalize create-dataset-group --name GCR-RS-${SCENARIO}-Dataset-Group --output text)
echo "dataset_Group_Arn: ${datasetGroupArn}"
echo "......"

#monitor dataset group 
echo "Dataset Group Creating... It will takes no longer than 5 min..."
MAX_TIME=`expr 10 \* 60` # 10 min
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    dataset_group_status=$(aws personalize describe-dataset-group \
                --dataset-group-arn ${datasetGroupArn} | jq '.datasetGroup.status' -r)

    echo "dataset_group_status: ${dataset_group_status}"
    
    if [ "$dataset_group_status" = "CREATE FAILED" ]
    then
        echo "!!!Dataset Group Create Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [ "$dataset_group_status" = "ACTIVE" ]
    then
        echo "Dataset Group Create successfully!"
        break
    fi
    
    CURRENT_TIME=`expr ${CURRENT_TIME} + 10`
    echo "wait for 10 second..."
    sleep 10

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Dataset Group Create Time exceed 10 min, please delete import job and try again!"
    exit 8
fi


#create schema
echo "creating Schema..."
user_schema_arn=$(aws personalize create-schema \
	--name ${SCENARIO}UserSchema \
	--schema file://../sample-data/system/personalize-data/schema/${SCENARIO}UserSchema.json --output text)

item_schema_arn=$(aws personalize create-schema \
	--name ${SCENARIO}ItemSchema \
	--schema file://../sample-data/system/personalize-data/schema/${SCENARIO}ItemSchema.json --output text)

interaction_schema_arn=$(aws personalize create-schema \
	--name ${SCENARIO}InteractionSchema \
	--schema file://../sample-data/system/personalize-data/schema/${SCENARIO}InteractionSchema.json --output text)

echo "......"
sleep 30

#create dataset
echo "create dataset..."
user_dataset_arn=$(aws personalize create-dataset \
	--name ${SCENARIO}UserDataset \
	--dataset-group-arn ${datasetGroupArn} \
	--dataset-type Users \
	--schema-arn ${user_schema_arn} --output text)

item_dataset_arn=$(aws personalize create-dataset \
	--name ${SCENARIO}ItemDataset \
	--dataset-group-arn ${datasetGroupArn} \
	--dataset-type Items \
	--schema-arn ${item_schema_arn} --output text)
	
interaction_dataset_arn=$(aws personalize create-dataset \
	--name ${SCENARIO}InteractionDataset \
	--dataset-group-arn ${datasetGroupArn} \
	--dataset-type Interactions \
	--schema-arn ${interaction_schema_arn} --output text)

# #for test
# user_dataset_arn="arn:aws:personalize:ap-northeast-1:466154167985:dataset/GCR-RS-News-UserPersonalize-Dataset-Group/USERS"
# item_dataset_arn="arn:aws:personalize:ap-northeast-1:466154167985:dataset/GCR-RS-News-UserPersonalize-Dataset-Group/ITEMS"
# interaction_dataset_arn="arn:aws:personalize:ap-northeast-1:466154167985:dataset/GCR-RS-News-UserPersonalize-Dataset-Group/INTERACTIONS"

#monitor dataset 
echo "Dataset Creating... It will takes no longer than 10 min..."
MAX_TIME=`expr 10 \* 60` # 10 min
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    user_dataset_status=$(aws personalize describe-dataset \
                --dataset-arn ${user_dataset_arn} | jq '.dataset.status' -r)
    item_dataset_status=$(aws personalize describe-dataset \
                --dataset-arn ${item_dataset_arn} | jq '.dataset.status' -r)
    interaction_dataset_status=$(aws personalize describe-dataset \
                --dataset-arn ${interaction_dataset_arn} | jq '.dataset.status' -r)

    echo "user_dataset_status: ${user_dataset_status}"
    echo "item_dataset_status: ${item_dataset_status}"
    echo "interaction_dataset_status: ${interaction_dataset_status}"
    
    if [[ "$user_dataset_status" = "CREATE FAILED" || "$item_dataset_status" = "CREATE FAILED" || "$interaction_dataset_status" = "CREATE FAILED" ]]
    then
        echo "!!!Dataset Create Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [[ "$user_dataset_status" = "ACTIVE" && "$item_dataset_status" = "ACTIVE" && "$interaction_dataset_status" = "ACTIVE" ]]
    then
        echo "Dataset Create successfully!"
        break
    fi
    
    CURRENT_TIME=`expr ${CURRENT_TIME} + 10`
    echo "wait for 10 second..."
    sleep 10

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Dataset Create Time exceed 10 min, please delete import job and try again!"
    exit 8
fi


#Get Bucket Name

BUCKET_BUILD=aws-gcr-rs-sol-${Stage}-${REGION}-${AWS_ACCOUNT_ID}

echo "BUCKET_BUILD=${BUCKET_BUILD}"
echo "Create S3 Bucket: ${BUCKET_BUILD} if not exist"

PERSONALIZE_ROLE_BUILD=arn:aws:iam::${AWS_ACCOUNT_ID}:role/gcr-rs-${Stage}-personalize-role
echo "PERSONALIZE_ROLE_BUILD=${PERSONALIZE_ROLE_BUILD}"
echo "Check if your personalize role arn is equal to the PERSONALIZE_ROLE_BUILD. If not, please follow the previous step to create iam role for personalize!"



#create import job
echo "create dataset import job..."
user_dataset_import_job_arn=$(aws personalize create-dataset-import-job \
  --job-name ${SCENARIO}UserImportJob \
  --dataset-arn ${user_dataset_arn} \
  --data-source dataLocation=s3://${BUCKET_BUILD}/sample-data-news/system/personalize-data/data/personalize_user.csv \
  --role-arn ${PERSONALIZE_ROLE_BUILD} \
  --output text)
  
  
item_dataset_import_job_arn=$(aws personalize create-dataset-import-job \
  --job-name ${SCENARIO}ItemImportJob \
  --dataset-arn ${item_dataset_arn} \
  --data-source dataLocation=s3://${BUCKET_BUILD}/sample-data-news/system/personalize-data/data/personalize_item.csv \
  --role-arn ${PERSONALIZE_ROLE_BUILD} \
  --output text)
  
interaction_dataset_import_job_arn=$(aws personalize create-dataset-import-job \
  --job-name ${SCENARIO}InteractionImportJob \
  --dataset-arn ${interaction_dataset_arn} \
  --data-source dataLocation=s3://${BUCKET_BUILD}/sample-data-news/system/personalize-data/data/personalize_interactions.csv \
  --role-arn ${PERSONALIZE_ROLE_BUILD} \
  --output text)
 
echo "......"


#monitor import job
echo "Data Importing... It will takes no longer than 10 min..."
MAX_TIME=`expr 10 \* 60` # 10 min
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    user_dataset_import_job_status=$(aws personalize describe-dataset-import-job \
                --dataset-import-job-arn ${user_dataset_import_job_arn} | jq '.datasetImportJob.status' -r)
    item_dataset_import_job_status=$(aws personalize describe-dataset-import-job \
                --dataset-import-job-arn ${item_dataset_import_job_arn} | jq '.datasetImportJob.status' -r)
    interaction_dataset_import_job_status=$(aws personalize describe-dataset-import-job \
                --dataset-import-job-arn ${interaction_dataset_import_job_arn} | jq '.datasetImportJob.status' -r)

    echo "user_dataset_import_job_status: ${user_dataset_import_job_status}"
    echo "item_dataset_import_job_status: ${item_dataset_import_job_status}"
    echo "interaction_dataset_import_job_status: ${interaction_dataset_import_job_status}"
    
    if [[ "$user_dataset_import_job_status" = "CREATE FAILED" || "$item_dataset_import_job_status" = "CREATE FAILED" || "$interaction_dataset_import_job_status" = "CREATE FAILED" ]]
    then
        echo "!!!Dataset Import Job Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [[ "$user_dataset_import_job_status" = "ACTIVE" && "$item_dataset_import_job_status" = "ACTIVE" && "$interaction_dataset_import_job_status" = "ACTIVE" ]]
    then
        echo "Import Job finishing successfully!"
        break
    fi
    
    CURRENT_TIME=`expr ${CURRENT_TIME} + 60`
    echo "wait for 1 min..."
    sleep 60

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Import Job Time exceed 10 min, please delete import job and try again!"
    exit 8
fi


##final code
#solution_arn=""
#if [[ $METHOD == "UserPersonalize" ]]; then
#    solution_arn=$(aws personalize create-solution \
#          --name ${METHOD}Solution \
#          --dataset-group-arn ${datasetGroupArn} \
#          --recipe-arn arn:aws:personalize:::recipe/aws-user-personalization --output text)
#elif [[ $METHOD == "Ranking" ]]; then
#    solution_arn=$(aws personalize create-solution \
#          --name ${METHOD}Solution \
#          --dataset-group-arn ${datasetGroupArn} \
#          --recipe-arn arn:aws:personalize:::recipe/aws-personalized-ranking --output text)
#elif [[ $METHOD == "Sims" ]]; then
#    solution_arn=$(aws personalize create-solution \
#          --name ${METHOD}Solution \
#          --dataset-group-arn ${datasetGroupArn} \
#          --recipe-arn arn:aws:personalize:::recipe/aws-sims --output text)
#fi
#

#For Dev
#create solution
userPersonalize_solution_arn=$(aws personalize create-solution \
        --name UserPersonalizeSolution \
        --dataset-group-arn ${datasetGroupArn} \
        --recipe-arn arn:aws:personalize:::recipe/aws-user-personalization --output text)

ranking_solution_arn=$(aws personalize create-solution \
        --name RankingSolution \
        --dataset-group-arn ${datasetGroupArn} \
        --recipe-arn arn:aws:personalize:::recipe/aws-personalized-ranking --output text)

sims_solution_arn=$(aws personalize create-solution \
        --name SimsSolution \
        --dataset-group-arn ${datasetGroupArn} \
        --recipe-arn arn:aws:personalize:::recipe/aws-sims --output text)


#monitor solution
echo "Solution Creating... It will takes no longer than 10 min..."
MAX_TIME=`expr 10 \* 60` # 10 min
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    userPersonalize_solution_status=$(aws personalize describe-solution \
        --solution-arn ${userPersonalize_solution_arn} | jq '.solution.status' -r)
    ranking_solution_status=$(aws personalize describe-solution \
        --solution-arn ${ranking_solution_arn} | jq '.solution.status' -r)
    sims_solution_status=$(aws personalize describe-solution \
        --solution-arn ${sims_solution_arn} | jq '.solution.status' -r)
    
    echo "userPersonalize_solution_status: ${userPersonalize_solution_status}"
    echo "ranking_solution_status: ${ranking_solution_status}"
    echo "sims_solution_status: ${sims_solution_status}"

    
    if [[ "$userPersonalize_solution_status" = "CREATE FAILED" || "$ranking_solution_status" = "CREATE FAILED" || "$sims_solution_status" = "CREATE FAILED" ]]
    then
        echo "!!!Solution Create Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [[ "$userPersonalize_solution_status" = "ACTIVE" && "$ranking_solution_status" = "ACTIVE" && "$sims_solution_status" = "ACTIVE" ]]
    then
        echo "Solution  create successfully!"
        break;
    fi
    CURRENT_TIME=`expr ${CURRENT_TIME} + 60`
    echo "wait for 1 min..."
    sleep 60

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Creating Solution Time exceed 10 min, please delete Solution and try again!"
    exit 8
fi



#create solution version
userPersonalize_solution_version_arn=$(aws personalize create-solution-version \
        --solution-arn ${userPersonalize_solution_arn} --output text)
ranking_solution_version_arn=$(aws personalize create-solution-version \
        --solution-arn ${ranking_solution_arn} --output text)


#monitor solution version
echo "Solution Version Creating... It will takes no longer than 6 hours..."
MAX_TIME=`expr 6 \* 60 \* 60` # 6 hours
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    userPersonalize_solution_version_status=$(aws personalize describe-solution-version \
            --solution-version-arn ${userPersonalize_solution_version_arn} | jq '.solutionVersion.status' -r)
    ranking_solution_version_status=$(aws personalize describe-solution-version \
            --solution-version-arn ${ranking_solution_version_arn} | jq '.solutionVersion.status' -r)
             
    echo "userPersonalize_solution_version_status: ${userPersonalize_solution_version_status}"
    echo "ranking_solution_version_status: ${ranking_solution_version_status}"
    
    if [[ "$userPersonalize_solution_version_status" = "CREATE FAILED" || "$ranking_solution_version_status" = "CREATE FAILED" ]]
    then
        echo "!!!Solution Version Create Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [[ "$userPersonalize_solution_version_status" = "ACTIVE" && "$ranking_solution_version_status" = "ACTIVE" ]]
    then
        echo "Solution Version create successfully!"
        break;
    fi
    CURRENT_TIME=`expr ${CURRENT_TIME} + 60`
    echo "wait for 1 min..."
    sleep 60

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Creating UserPersonalize Solution Version Time exceed 10 min, please delete UserPersonalize Solution Version and try again!"
    exit 8
fi


# create event tracker
eventTrackerArn=$(aws personalize create-event-tracker \
    --name NewsEventTracker \
    --dataset-group-arn ${datasetGroupArn} | jq '.eventTrackerArn' -r)

trackingId=$(aws personalize describe-event-tracker \
    --event-tracker-arn ${eventTrackerArn} | jq '.eventTracker.trackingId' -r)
    
echo "eventTrackerArn: ${eventTrackerArn}"
echo "trackingId: ${trackingId}"

# # for test
# userPersonalize_solution_version_arn="arn:aws:personalize:ap-northeast-1:466154167985:solution/userPersonalizeSolutionNew/cf6b305a"

#print metrics
echo "UserPersonalize Solution Metrics:"
aws personalize get-solution-metrics --solution-version-arn ${userPersonalize_solution_version_arn}
echo "Ranking Solution Metrics:"
aws personalize get-solution-metrics --solution-version-arn ${ranking_solution_version_arn}


#create campaign
userPersonalize_campaign_arn=$(aws personalize create-campaign \
        --name gcr-rs-dev-workshop-news-UserPersonalize-campaign \
        --solution-version-arn ${userPersonalize_solution_version_arn} \
        --min-provisioned-tps 1 --output text)
ranking_campaign_arn=$(aws personalize create-campaign \
        --name gcr-rs-dev-workshop-news-ranking-campaign \
        --solution-version-arn ${ranking_solution_version_arn} \
        --min-provisioned-tps 1 --output text)


#monitor campaign
echo "Campaign Creating... It will takes no longer than 3 hours..."
MAX_TIME=`expr 3 \* 60 \* 60` # 3 hours
CURRENT_TIME=0
while(( ${CURRENT_TIME} < ${MAX_TIME} )) 
do
    userPersonalize_campaign_status=$(aws personalize describe-campaign \
            --campaign-arn ${userPersonalize_campaign_arn} | jq '.campaign.status' -r)
    ranking_campaign_status=$(aws personalize describe-campaign \
            --campaign-arn ${ranking_campaign_arn} | jq '.campaign.status' -r)
            
    echo "userPersonalize_campaign_status: ${userPersonalize_campaign_status}"
    echo "ranking_campaign_status: ${ranking_campaign_status}"

    
    if [[ "$userPersonalize_campaign_status" = "CREATE FAILED" || "$ranking_campaign_status" = "CREATE FAILED" ]]
    then
        echo "!!!Campaign Create Failed!!!"
        echo "!!!Personalize Service Create Failed!!!"
        exit 8
    elif [[ "$userPersonalize_campaign_status" = "ACTIVE" && "$ranking_campaign_status" = "ACTIVE" ]]
    then
        echo "Campaign create successfully!"
        break;
    fi
    CURRENT_TIME=`expr ${CURRENT_TIME} + 60`
    echo "wait for 1 min..."
    sleep 60

done

if [ $CURRENT_TIME -ge $MAX_TIME ]
then
    echo "Creating Campaign Time exceed 10 min, please delete UserPersonalize Campaign and try again!"
    exit 8
fi


echo "Congratulations!!! Your AWS Personalize Service Create Successfully!!!"

