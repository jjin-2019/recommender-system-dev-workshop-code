
echo "------------------------------------------------ "
Stage=$1
if [[ -z $Stage ]];then
  Stage='dev'
fi

echo "Stage=$Stage"

repoName=rs/news-rank-batch

../norm_build.sh $repoName $Stage