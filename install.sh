#!/bin/bash
wget -O artifact https://s3-us-west-2.amazonaws.com/${bucket}/${key} > ${key}
chmod +x ${key}
nohup ./${key} &
