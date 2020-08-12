#! /usr/bin/env python
import datetime
import sys
import click
from pyhdf.SD import SD


@click.command()
@click.argument(
    "inputhdfile",
    type=click.Path(dir_okay=False, file_okay=True,),
)
def main(inputhdfile):
    hdf = SD(inputhdfile, 1)
    sensing_time = hdf.SENSING_TIME
    hdf.end()
    datedttimepattern = "%Y-%m-%dT%H:%M:%S"
    scene_time = datetime.datetime.strptime(
        sensing_time.split(".")[0], datedttimepattern)
    hms = "%s%s%s" % (str(scene_time.hour).zfill(2),
                      str(scene_time.minute).zfill(2),
                      str(scene_time.second).zfill(2))
    sys.stdout.write(hms)

if __name__ == '__main__':
    main()
