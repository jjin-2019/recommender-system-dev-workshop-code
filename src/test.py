import json
import os
import pickle

testVar = "this is empty str"
testMap = {}

def testFunc():
    global testVar
    testVar = "test func"
    global testMap
    testMap['testKey'] = "testValuefunc"

def testMapFunc():
    print(testMap['testKey'])


def init():
    global testVar

    global testMap
    testMap['testKey'] = "testValueinit"


if __name__ == "__main__":

    MANDATORY_ENV_VARS = {
        'RECALL_CONFIG': 'recall_config.pickle',

        'NEWS_ID_PROPERTY': 'news_id_news_property_dict.pickle',
        'ENTITY_ID_NEWS_IDS': 'news_entities_news_ids_dict.pickle',
        'KEYWORD_NEWS_IDS': 'news_keywords_news_ids_dict.pickle',
        'NEWS_TYPE_NEWS_IDS': 'news_type_news_ids_dict.pickle',
        'WORD_ID_NEWS_IDS': 'news_words_news_ids_dict.pickle',

        'LOCAL_DATA_FOLDER': '/tmp/rs-data/',

        'RECALL_PER_NEWS_ID': 10,
        'SIMILAR_ENTITY_THRESHOLD': 20,
        'RECALL_THRESHOLD': 2.0,
        'RECALL_MERGE_NUMBER': 20,

        'REDIS_HOST': 'localhost',
        'REDIS_PORT': 6379,

        'PORTRAIT_SERVICE_ENDPOINT': 'http://portrait:5300'
    }

    init()
    testMapFunc()
    testFunc()
    testMapFunc()



