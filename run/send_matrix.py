#!/usr/bin/env python3
import sys
import time
from matrix_client.errors import MatrixHttpLibError
from matrix_client.client import MatrixClient
from matrix_client.api import MatrixHttpApi

if len(sys.argv) != 6:
    sys.stderr.write('usage: %s HOMESERVER_URL USERNAME PASSWORD ROOM_ID MESSAGE_TEXT\n' % sys.argv[0])
    sys.exit(-1)

(homeserver, username, password, room_id, message) = sys.argv[1:6]

if homeserver.endswith('/'):
    homeserver = homeserver[:-1]

if username.startswith('@'):
    username = username[1:]

if username.find(':') > 0:
    username = username.split(':')[0]

matrix = None

for retry in range(0, 4):
    try:
        client = MatrixClient(homeserver)
        token = client.login(username, password)
        matrix = MatrixHttpApi(homeserver, token)
        break
    except MatrixHttpLibError:
        sys.stderr.write('Connection failed, retrying...\n')
        time.sleep(0.25)

if matrix == None:
    sys.stderr.write('Could not connect to homeserver. Message not sent.\n')
    sys.exit(-2)

try:
    client.rooms[room_id].send_text(message)
except:
    sys.stderr.write('Failed to send message to room.\n')
    sys.exit(-3)
