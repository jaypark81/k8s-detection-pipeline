import os
import logging
import redis

logger = logging.getLogger(__name__)
r = redis.Redis(host=os.getenv('REDIS_HOST', 'redis.hitchhiker.svc.cluster.local'), port=6379, db=0)
