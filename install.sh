#!/bin/bash
wget -O artifact https://s3-us-west-2.amazonaws.com/oni-build-deploy/artifact > artifact
chmod +x artifact
nohup ./artifact &
