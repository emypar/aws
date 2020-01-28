#! /bin/bash

# Remove docker containers and images prior to AMI image creation.
container_ids=$(sudo docker ps -a -q)
if [[ -n "$container_ids" ]]; then
    (set -x; sudo docker kill $container_ids)
fi
image_ids=$(sudo docker image ls -q)
if [[ -n "$image_ids" ]]; then
    (set -x; sudo docker image rm --force $image_ids)
fi
