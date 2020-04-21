## hls-landsat-tile
This repository contains the Dockerfiles for running the HLS Landsat tile code on ECS.

The `hls-landsat-tile` image uses [hls-base](https://github.com/NASA-IMPACT/hls-base/) as base image.

After building your base dependencies image and pushing it to ECR you can build the `hls-landsat-tile` processing image with:

```shell
$ docker build --no-cache --build-arg AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID}" -t hls-landsat-tile .
```

Note: The command above assumes you have exported an environment variable `AWS_ACCOUNT_ID` which references the AWS account where the hls-base reference image is stored.

You can then tag this `hls-landsat-tile` image as `<AWS_ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com/hls-landsat-tile` and push it to ECR.

```shell
$ docker tag hls-landsat-tile "${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/hls-landsat-tile"
```

```shell
$ docker push "${AWS_ACCOUNT_ID}.dkr.ecr.us-west-2.amazonaws.com/hls-landsat-tile"
```
