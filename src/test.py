import json
import pickle


if __name__ == "__main__":
    file = "/Users/jilizm/recommender-system-dev-workshop-code/sample-data/feature/content/inverted-list/news_id_news_property_dict.pickle"
    infile = open(file, 'rb')
    dict = pickle.load(infile)
    infile.close()
    print(json.dumps(dict, indent= 2))
    #
    # json_file ={
    #         "DatasetGroupName": "GCR-RS-News-Dataset-Group",
    #         "UserDatasetName": "NewsUserDataset",
    #         "ItemDatasetName": "NewsItemDataset",
    #         "InteractionDatasetName": "NewsInteractionDataset",
    #         "EventTrackerName": "NewsEventTracker",
    #         "SolutionName": "userPersonalizeSolution",
    #         "SolutionVersionArn": "arn:aws:personalize:ap-northeast-1:466154167985:solution/userPersonalizeSolutionNew/5286e329",
    #         "CampaignName": "gcr-rs-dev-workshop-news-UserPersonalize-campaign",
    #         "UserFileName": "personalize_user.csv",
    #         "ItemFileName": "personalize_item.csv",
    #         "InteractionFileName": "personalize_interaction.csv",
    #         "TrainingMode": "UPDATE"
    # }
    # print(json_file.__str__())
    # string = json.dumps(json_file)
    # print(str(string))
    # test = json.loads(string)
    # print(test)
    # print(test['SolutionVersionArn'])