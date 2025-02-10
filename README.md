## hls-landsat-tile
This repository contains the Dockerfiles for running the HLS Landsat tile code on ECS.

The `hls-landsat-tile` image uses [espa/external-c2](https://github.com/NASA-IMPACT/espa-dockerfiles/) as base image.

## Development
You will require an AWS profile which has ECR pull permissions for the base image.

```shell
$ docker build --no-cache -t hls-landsat-tile .
```

## CI
The repository contains two CI workflows.  When PRs are created against the `dev` branch a new image is built and pushed with a tag corresponding to the PR number.

When a new `release` is created from `master` a new image is built and pushed to ECR with the release version as a tag.
