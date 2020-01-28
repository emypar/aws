# EKS GPU Node Patch

## Summary

Provide an update patch for EKS GPU nodes which addresses the issue of stdin being closed in containers started with `-i` option. This problem affects all pods that need stdin binary streaming, including `kubectl cp` command.

## How To Check For The Issue

Start an a GPU instance type, e.g. `p2.xlarge`, using one the official [amazon-eks-gpu-node-1.1[234]-v20191213](https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2#Images:visibility=public-images;search=%5Eamazon-eks-gpu-node-1.1%5B234%5D-v20191213;sort=name) AMIs and run on it:
```
echo "loopback from stdin" | sudo docker run --rm -i busybox cat
```
The expected output is `loopback from stdin` but the actual output is ` ` (empty) because inside the container stdin is closed.

##  The Patch

`patch-amazon-eks-gpu-node.bash` will re-install up-to-date versions of `docker-ce` and `nvidia-docker2` on an instance started from the EKS AMIs above.

`docker-cleanup.bash` will remove containers and docker volumes prior to creating new AMI images.

## Testing The New AMIs

Start a GPU node in the EKS cluster using the patched AMI and run on it:
```
kubectl run -i --image=tensorflow/tensorflow:latest-gpu-py3 --restart=Never tf python < tf_test_gpu.py
```
using the `tf_test_gpu.py` scriptlet. The expected output should end
with `True`.

This will check both the fact that stdin is now properly streamed and that GPU is available within the container.

Cleanup the pod at the end:
```
kubectl delete pod tf
```

## Pre-patched AMIs

Public AMIs for `us-west-2` can be found [here](https://us-west-2.console.aws.amazon.com/ec2/v2/home?region=us-west-2#Images:visibility=public-images;name=%5Ebgp-amazon-eks-gpu-node-.*-stdin-patch;sort=name)
