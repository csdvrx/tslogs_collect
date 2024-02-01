# tslogs_collect

Collect tslogs from a BSD boot into a sqlite database

# Why

[Profiling boot time](https://www.daemonology.net/papers/bootprofiling.pdf) is important.

Optimizing boot time requires iterative measurements.

Existing solutions such as [Colin Percival scripts](https://github.com/cperciva/freebsd-boot-profiling) are good for one shots, but while I was trying to replicate iMil fast boot on NetBSD, I have observed a large variance when the boot time become very small.

Therefore, tslogs_collect will log everything into a sqlite database, so you can measure the variance across a large sample of boots without having to remember to collect the data.

# What

The simplest way to achieve that is a shell script, but instead of creating a directory full of files, the data is stored in a sqlite database.

This way, it should be possible to easily check during boot if and when the current boot-time is an outlier, which could act as a warning that the current hardware state is unusual (or that the last optimization you tried is a great one!)

I believe it's also easier to put into one single file all the releveant measurements, as it lets you trace performance regressions or improvements ex-post-facto: just let the database accumulate measurements when everything is working normally, so when you have a problem, you can have the data you need to do fancy things like a multivariable regression or computing 95% confidence interval.

# When

The script should be run as late as possible if you want to measure the userland processes like systemd-analyze would, so /etc/rc.local is a good place.

If you are doing kernel development, /etc/rc will do. In case you are using a qemu boot loop to collect a lot of data quickly, I have added an automatic fsck to make sure the disk image doesn't get corrupted by accident (which would bias the measurements)

# How

Add the script to your bootscripts, place the sqlite3 binary in the PATH.

I included a cosmopolitan APE, which should run on any amd64 BSD. If you also need an [aarch64 binary, get the fat APE](https://cosmo.zip/pub/cosmos/bin/sqlite3) 

# Where

I put sqlite3 in /bin. It may be dirty but I don't care.

The sqlite file is in /, and you may care as it's very visible.
 You can use arguments if you don't want the file there as `/tslogs.sqlite`, but you should make sure the path you select will be writable.

Likewise, if you prefer to preserve the individual tslog files that are put in `/tmp` with a unique timestamped filename, you can specify a directory like /var/log

# WIP

For now, this is only tested on NetBSD, but it should work on FreeBSD with minor modifications. I may eventually test it better on FreeBSD.

If you are not using an amd64 CPU, @cperciva [noted in mkflame.sh that aarch64 needs sysctl -n "kern.timecounter.tc.ARM MPCore Timecounter.frequency"](https://github.com/cperciva/freebsd-boot-profiling/blob/master/mkflame.sh#L15)

# TODO

I plan to integrate the creation of flame graphs as a perl script reading from the sqlite file, so I've added an all-in-one perl APE (small-perl) to bring in the extra motivation.

It would be nice to annotate the graphs with the quartiles or other easy-to-understand statistical measurements (mean, median, stddev, ICs) to have something similar to 

However, the resulting tool could be easily made better by adding a nice visual representation of the variance in the measurements such as a traditional box-and-whiskers plot, but adapted to the flamegraph format.
