# disk_benchmark

disk_benchmark.sh run and parse ioping and fio results.

## Warning !

Do not use this script on disk that have data !

Data will be damanged as the script writes data directly to the device !

## Prerequisite packages
* bc
* ioping
* fio
* tee

## Summary

It has been developed for internal use at Aqua Ray to test various SSDs, but it works with HDD as well.

It will run ioping and fio for every given disk. By default it will only display some quick information about results, but when --export is used, it will write a CSV file for each disk with much more informations.

```
Usage: bash disk_benchmark.sh [-h] [-v] [--ioping-count <count>] [--export <folder>] -d <disk1> [-d <disk2> ...]
```

Many options for fio can be changed (see variables at the beginning of the script).

The CSV will contain the following values (for each tested disk) :
- disk model (string)
- disk_size (integer)
- disk_size_unit (string)
- disk_firmware_version (string)
- fio io_direct (0 or 1)
- fio io_sync (0 or 1)
- fio nb_jobs (integer)
- fio block size (string)
- fio ioengine (string)
- fio iodepth (integer)
- fio rw (string)
- fio iops
- fio bandwidth (in B/s)
- fio runtime (in seconds)
- ioping time (in us)
- ioping iops
- ioping bandwidth (in B/s)
- ioping min latency (in us)
- ioping avg latency (in us)
- ioping max latency (in us)
- ioping mdev latency (in us)
