import redis
import logging
import pickle



class RedisCache:

    news_type_news_ids = 'news_type_news_ids_dict'
    ps_config_file = 'ps_config_file'

    def __init__(self, host='localhost', port=6379, db=0):
        logging.info('Initial RedisCache ...')
        # Initial connection to Redis
        logging.info('Connect to Redis %s:%s ...', host, port)
        self.rCon = redis.Redis(host=host, port=port, db=db)



    def connection_status(self):
        return self.rCon.client_list()

    def load_data_into_hash(self, field, key, data):
        return self.rCon.hset(field, key, data)

    def get_data_from_hash(self, field, key):
        return self.rCon.hget(field, key)

    def read_stream_message_block(self, stream_name):
        return self.rCon.xread({stream_name: '$'}, None, 0)

    def read_stream_message(self, stream_name):
        return self.rCon.xread({stream_name: 0})




