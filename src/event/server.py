import json
import logging
import os
import uuid
from datetime import datetime
from threading import Thread
from typing import List, Dict, Any, Optional
import time
import boto3
import redis
import requests
import cache
import uvicorn as uvicorn
from fastapi import FastAPI, Header, HTTPException, APIRouter, Depends
from fastapi.exceptions import RequestValidationError
from pydantic import BaseModel
from starlette.requests import Request
from starlette.responses import JSONResponse

app = FastAPI()
api_router = APIRouter()

s3client = boto3.client('s3')

step_funcs = None
account_id = ''
ps_config = {}
ps_result = 'ps-result'
sleep_interval = 10  # second

MANDATORY_ENV_VARS = {
    'REDIS_HOST': 'localhost',
    'REDIS_PORT': 6379,
    'EVENT_PORT': '5100',
    'PORTRAIT_HOST': 'portrait',
    'PORTRAIT_PORT': '5300',
    'RECALL_HOST': 'recall',
    'RECALL_PORT': '5500',
    'FILTER_HOST': 'filter',
    'FILTER_PORT': 5200,
    'AWS_REGION': 'ap-southeast-1',
    'S3_BUCKET': 'aws-gcr-rs-sol-demo-ap-southeast-1-522244679887',
    'S3_PREFIX': 'sample-data',
    'POD_NAMESPACE': 'default',
    'TEST': 'False',
    'METHOD': 'ps-complete',
    'PS_CONFIG': 'ps_config.json'
}


def xasync(f):
    def wrapper(*args, **kwargs):
        thr = Thread(target=f, args=args, kwargs=kwargs)
        thr.start()

    return wrapper


async def log_json(request: Request):
    try:
        logging.info("log request JSON: {}".format(await request.json()))
    except Exception:
        pass


class RSHTTPException(HTTPException):
    def __init__(self, status_code: int, message: str):
        super().__init__(status_code, message)


class RSAWSServiceException(Exception):
    def __init__(self, message: str):
        super().__init__(message)


@app.exception_handler(HTTPException)
async def rs_exception_handler(request, rs_exec: HTTPException):
    return JSONResponse(
        status_code=rs_exec.status_code,
        content={
            "message": rs_exec.detail
        }
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc):
    print("exception_handler error >>> {}".format(exc))
    return JSONResponse(
        status_code=405,
        content={
            "message": str(exc)
        }
    )


@app.exception_handler(RSAWSServiceException)
async def rs_exception_handler(request: Request, rs_exc: RSAWSServiceException):
    return JSONResponse(
        status_code=400,
        content={
            "message": str(rs_exc)
        }
    )


def send_post_request(url, data):
    logging.info("send POST request to {}".format(url))
    logging.info("data: {}".format(data))
    if MANDATORY_ENV_VARS['TEST'] == 'True':
        return "[TEST] sent data to {}".format(url)

    headers = {'Content-type': 'application/json'}
    r = requests.post(url, data=json.dumps(data), headers=headers)
    logging.info("status_code: {}".format(r.status_code))

    if r.status_code == 200:
        return "OK"
    else:
        if len(r.text) > 100:
            logging.error(r.text[100:300])
        else:
            logging.error(r.text)
        raise RSHTTPException(status_code=r.status_code,
                              message="error POST request {}".format(url))


def get_data_request(url, func=None):
    logging.info("GET request from :" + url)
    if MANDATORY_ENV_VARS['TEST'] == 'True':
        return {
            "test": "data from {}".format(url)
        }

    r = requests.get(url)
    logging.info("get response status_code:{}".format(r.status_code))
    if r.status_code == 200:
        if func:
            return func(r.json())
        else:
            return r.json()['data']
    else:
        if len(r.text) > 100:
            logging.error(r.text[100:300])
        else:
            logging.error(r.text)
        raise RSHTTPException(status_code=r.status_code,
                              message="error GET request {}".format(url))


class Item(BaseModel):
    id: str
    # subtype: str


class ClickedItem(BaseModel):
    clicked_item: Item


class ClickedItemList(BaseModel):
    clicked_item_list: List[Item]


class Metadata(BaseModel):
    type: str


class PortraitResponse(BaseModel):
    version: int = 1
    metadata: Metadata
    content: Dict[str, Any]


class TrainRequest(BaseModel):
    change_type: str


class SimpleResponse(BaseModel):
    version: int = 1
    metadata: Metadata
    message: str


class StateMachineStatus(BaseModel):
    # 'RUNNING'|'SUCCEEDED'|'FAILED'|'TIMED_OUT'|'ABORTED',
    status: Optional[str]
    startDate: datetime
    stopDate: Optional[datetime]


class StateMachineStatusResponse(BaseModel):
    version: int = 1
    metadata: Metadata
    status: StateMachineStatus
    detailUrl: str
    executionArn: str


class UserEntity(BaseModel):
    user_id: str
    user_sex: str


def gen_simple_response(message):
    res = SimpleResponse(
        message=message, metadata=Metadata(type='SimpleResponse'))
    return res


@app.get('/ping', tags=["monitoring"])
def ping():
    logging.info('Processing default request...')
    return {'result': 'ping'}


@api_router.get('/api/v1/event/portrait/{user_id}', response_model=PortraitResponse, tags=["event"])
def portrait_get(user_id: str, regionId=Header("1")):
    host = MANDATORY_ENV_VARS['PORTRAIT_HOST']
    port = MANDATORY_ENV_VARS['PORTRAIT_PORT']
    get_portrait_svc_url = "http://{}:{}/portrait/userid/{}".format(
        host, port, user_id)
    result_json = get_data_request(
        get_portrait_svc_url, lambda data: data['results'])
    return PortraitResponse(content=result_json, metadata=Metadata(type='PortraitResponse'))


@api_router.post('/api/v1/event/portrait/{user_id}', response_model=SimpleResponse, tags=["event"])
def portrait_post(user_id: str, clickItem: ClickedItem):
    host = MANDATORY_ENV_VARS['PORTRAIT_HOST']
    port = MANDATORY_ENV_VARS['PORTRAIT_PORT']
    portrait_svc_url = "http://{}:{}/portrait/process".format(host, port)
    data = {
        'user_id': user_id,
        'clicked_item_ids': [clickItem.clicked_item.id]
    }
    message = send_post_request(portrait_svc_url, data)
    res = gen_simple_response(message)
    return res


@api_router.post('/api/v1/event/recall/{user_id}', response_model=SimpleResponse, tags=["event"])
def online_inference(user_id: str, clickItemList: ClickedItemList):
    data = {
        'user_id': user_id,
        'clicked_item_ids': [item.id for item in clickItemList.clicked_item_list]
    }

    if MANDATORY_ENV_VARS['METHOD'] == "ps-complete":
        logging.info("send click info to personalize service ...")
        message = send_event_to_personalize(data)
    elif MANDATORY_ENV_VARS['METHOD'] in ["ps-rank", "ps-sims"]:
        logging.info("send click info to personalize service and default process ...")
        ps_message = send_event_to_personalize(data)
        default_message = send_event_to_default(data)
        message = "send message to personalize result:{}; send message to default process result:{}" \
            .format(ps_message, default_message)
    else:
        logging.info("send click info to default process ...")
        message = send_event_to_default(data)

    res = gen_simple_response(message)
    return res


@api_router.post('/api/v1/event/start_train', response_model=StateMachineStatusResponse, tags=["event"])
def start_train_post(trainReq: TrainRequest):
    if trainReq.change_type not in ['MODEL', 'CONTENT', 'ACTION']:
        raise HTTPException(status_code=405, detail="invalid change_type")
    res = start_step_funcs(trainReq)
    return res


@api_router.post('/api/v1/event/start_update', response_model=StateMachineStatusResponse, tags=["event"])
def start_update_post(trainReq: TrainRequest):
    if trainReq.change_type not in ['MODEL', 'CONTENT', 'ACTION']:
        raise HTTPException(status_code=405, detail="invalid change_type")
    res = start_step_funcs(trainReq)
    return res


@api_router.get('/api/v1/event/offline_status/{exec_arn}', response_model=StateMachineStatusResponse, tags=["event"])
def offline_status_get(exec_arn: str):
    logging.info("stepfuncs_exec_status_get: exec_arn='{}'".format(exec_arn))
    res = step_funcs.describe_execution(
        executionArn=exec_arn
    )
    aws_region = MANDATORY_ENV_VARS['AWS_REGION']
    aws_console_url = f"https://{aws_region}.console.aws.amazon.com/states/home?region={aws_region}" \
                      f"#/executions/details/{exec_arn}"
    res = StateMachineStatusResponse(metadata=Metadata(type='StateMachineStatusResponse'),
                                     detailUrl=aws_console_url,
                                     executionArn=exec_arn,
                                     status=StateMachineStatus(
                                         status=res.get('status', None),
                                         startDate=res['startDate'],
                                         stopDate=res.get('stopDate', None))
                                     )
    return res


@api_router.post('/api/v1/event/add_user/{user_id}', response_model=SimpleResponse, tags=["event"])
def add_new_user(userEntity: UserEntity):
    logging.info("Add new user to AWS Personalize Service...")
    user_id = userEntity.user_id
    user_sex = userEntity.user_sex
    personalize_events.put_users(
        datasetArn=ps_config["UserDatasetArn"],
        users=[
            {
                "userId": user_id,
                "properties": json.dumps({
                    "gender": user_sex
                })
            },
        ]
    )
    return gen_simple_response('OK')


def send_event_to_default(data):
    host = MANDATORY_ENV_VARS['RECALL_HOST']
    port = MANDATORY_ENV_VARS['RECALL_PORT']
    recall_svc_url = "http://{}:{}/recall/process".format(host, port)
    return send_post_request(recall_svc_url, data)


def send_event_to_personalize(data):
    try:
        for item_id in data['clicked_item_ids']:
            personalize_events.put_events(
                trackingId=ps_config['EventTrackerId'],
                userId=data['user_id'],
                sessionId=data['user_id'],
                eventList=[{
                    'sentAt': int(time.time()),
                    'itemId': item_id,
                    'eventType': ps_config['EventType']
                }]
            )
    except Exception as e:
        logging.error(repr(e))
        raise RSAWSServiceException(repr(e))
    host = MANDATORY_ENV_VARS['FILTER_HOST']
    port = MANDATORY_ENV_VARS['FILTER_PORT']
    filter_svc_url = "http://{}:{}/filter/ps_process".format(host, port)
    return send_post_request(filter_svc_url, data)


def start_step_funcs(trainReq):
    aws_region = MANDATORY_ENV_VARS['AWS_REGION']
    step_funcs_name = get_step_funcs_name()
    bucket = MANDATORY_ENV_VARS['S3_BUCKET']
    key_prefix = MANDATORY_ENV_VARS['S3_PREFIX']

    stateMachineArn = f"arn:aws:states:{aws_region}:{account_id}:stateMachine:{step_funcs_name}"
    logging.info("start_step_funcs: {}, trainReq={}".format(
        stateMachineArn, trainReq))

    # ps_file_path = "system/personalize-data/ps-config/ps_config.json"
    # ps_config = load_config(ps_file_path)
    ps_config_str = json.dumps(ps_config)

    try:
        res = step_funcs.start_execution(
            stateMachineArn=stateMachineArn,
            name="{}-{}".format(trainReq.change_type[0].lower(), uuid.uuid1()),
            input=json.dumps({
                'change_type': trainReq.change_type,
                'Bucket': bucket,
                'S3Prefix': key_prefix,
                'Method': MANDATORY_ENV_VARS['METHOD'],
                'ps_config': ps_config_str
            })
        )
    except Exception as e:
        logging.error(repr(e))
        raise RSAWSServiceException(repr(e))

    exec_arn = res['executionArn']
    logging.info("exec_arn: {}".format(exec_arn))

    aws_console_url = f"https://{aws_region}.console.aws.amazon.com/states/home?region={aws_region}" \
                      f"#/executions/details/{exec_arn}"

    res = StateMachineStatusResponse(metadata=Metadata(type='StateMachineStatusResponse'),
                                     detailUrl=aws_console_url,
                                     executionArn=exec_arn,
                                     status=StateMachineStatus(
                                         status=None,
                                         startDate=res['startDate'],
                                         stopDate=None)
                                     )
    return res


def load_config(file_path):
    s3_bucket = MANDATORY_ENV_VARS['S3_BUCKET']
    s3_prefix = MANDATORY_ENV_VARS['S3_PREFIX']
    file_key = '{}/{}'.format(s3_prefix, file_path)
    s3 = boto3.resource('s3')
    try:
        object_str = s3.Object(s3_bucket, file_key).get()[
            'Body'].read().decode('utf-8')
    except Exception as ex:
        logging.info("get {} failed, error:{}".format(file_key, ex))
        object_str = "{}"
    config_json = json.loads(object_str)
    return config_json


@xasync
def read_ps_config_message():
    logging.info('read_ps_message start')
    # Read existed stream message
    stream_message = rCache.read_stream_message(ps_result)
    if stream_message:
        logging.info("Handle existed stream ps-result message")
        handle_stream_message(stream_message)
    while True:
        logging.info('wait for reading ps-result message')
        localtime = time.asctime(time.localtime(time.time()))
        logging.info('start read stream: time: {}'.format(localtime))
        try:
            stream_message = rCache.read_stream_message_block(ps_result)
            if stream_message:
                handle_stream_message(stream_message)
        except redis.ConnectionError:
            localtime = time.asctime(time.localtime(time.time()))
            logging.info('get ConnectionError, time: {}'.format(localtime))
        time.sleep(sleep_interval)


def handle_stream_message(stream_message):
    logging.info('get stream message from {}'.format(stream_message))
    file_type, file_path, file_list = parse_stream_message(stream_message)
    logging.info('start reload data process in handle_stream_message')
    logging.info('file_type {}'.format(file_type))
    logging.info('file_path {}'.format(file_path))
    logging.info('file_list {}'.format(file_list))

    global ps_config
    for file_name in file_list:
        if MANDATORY_ENV_VARS['PS_CONFIG'] in file_name:
            logging.info("reload config file: {}".format(file_name))
            ps_config = load_config(file_name)


def parse_stream_message(stream_message):
    for stream_name, message in stream_message:
        for message_id, value in message:
            decode_value = convert(value)
            file_type = decode_value['file_type']
            file_path = decode_value['file_path']
            file_list = decode_value['file_list']
            return file_type, file_path, file_list


# convert stream data to str
def convert(data):
    if isinstance(data, bytes):
        return data.decode('ascii')
    elif isinstance(data, dict):
        return dict(map(convert, data.items()))
    elif isinstance(data, tuple):
        return map(convert, data)
    else:
        return data


app.include_router(api_router, dependencies=[Depends(log_json)])


def init():
    # Check out environments
    for var in MANDATORY_ENV_VARS:
        if var not in os.environ:
            logging.warning("Mandatory variable {%s} is not set, using default value {%s}.", var,
                            MANDATORY_ENV_VARS[var])
        else:
            MANDATORY_ENV_VARS[var] = str(os.environ.get(var))
        aws_region = MANDATORY_ENV_VARS['AWS_REGION']
        global step_funcs
        step_funcs = boto3.client('stepfunctions', aws_region)
        global account_id
        account_id = boto3.client(
            'sts', aws_region).get_caller_identity()['Account']

    global rCache
    rCache = cache.RedisCache(host=MANDATORY_ENV_VARS['REDIS_HOST'], port=MANDATORY_ENV_VARS['REDIS_PORT'])
    logging.info('redis status is {}'.format(rCache.connection_status()))

    global ps_config
    ps_file_path = "system/personalize-data/ps-config/ps_config.json"
    ps_config = load_config(ps_file_path)

    global personalize_events
    personalize_events = boto3.client(service_name='personalize-events', region_name=MANDATORY_ENV_VARS['AWS_REGION'])


def get_step_funcs_name():
    # if MANDATORY_ENV_VARS['MODEL'] == 'ps-complete':
    #     step_funcs_name = "rs-dev-workshop-News-OverallStepFunc-Personalize"
    # else:
    #     step_funcs_name = "rs-dev-workshop-News-OverallStepFunc"
    # return step_funcs_name

    namespace = MANDATORY_ENV_VARS['POD_NAMESPACE']
    # known_mappings = {
    #     'rs-news-dev-ns': 'rs-dev-News-OverallStepFunc',
    #     'rs-movie-dev-ns': 'rs-dev-Movie-OverallStepFunc',
    #     'rs-news-demo-ns': 'rs-demo-News-OverallStepFunc',
    #     'rs-movie-demo-ns': 'rs-demo-Movie-OverallStepFunc',
    #     'rs-beta': 'rsdemo-News-OverallStepFunc'
    # }
    # step_funcs_name = known_mappings.get(namespace, 'rsdemo-News-OverallStepFunc')
    #
    # change for dev-workshop
    s3bucket = MANDATORY_ENV_VARS['S3_BUCKET']
    if '-dev-workshop-' in s3bucket and namespace == 'rs-news-dev-ns':
        step_funcs_name = 'rs-dev-workshop-News-OverallStepFunc'

    # # change for personalize plugin
    # if MANDATORY_ENV_VARS['USE_PERSONALIZE_PLUGIN'] == "True":
    #     step_funcs_name = "rs-dev-workshop-News-OverallStepFunc-Personalize"
    #
    logging.info("get_step_funcs_name return: namespace: {}, step funcs name: {}".format(namespace, step_funcs_name))
    return step_funcs_name


if __name__ == "__main__":
    logging.basicConfig(format='%(asctime)s,%(msecs)d %(levelname)-8s [%(filename)s:%(lineno)d] %(message)s',
                        datefmt='%Y-%m-%d:%H:%M:%S',
                        level=logging.INFO)
    logging.info(json.dumps(s3client.list_buckets(), default=str))
    # aws_region = boto3.Session().region_name
    # logging.info("boto3.Session aws_region: {}".format(aws_region))

    init()
    logging.info(MANDATORY_ENV_VARS)
    uvicorn.run(app, host="0.0.0.0", port=int(
        MANDATORY_ENV_VARS['EVENT_PORT']))
